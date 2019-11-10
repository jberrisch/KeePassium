//  KeePassium Password Manager
//  Copyright © 2018–2019 Andrei Popleteev <info@keepassium.com>
// 
//  This program is free software: you can redistribute it and/or modify it
//  under the terms of the GNU General Public License version 3 as published
//  by the Free Software Foundation: https://www.gnu.org/licenses/).
//  For commercial licensing, please contact the author.

import KeePassiumLib

protocol DatabaseUnlockerDelegate: class {
    /// Called when the user presses "Unlock"
    func databaseUnlockerShouldUnlock(
        _ sender: DatabaseUnlockerVC,
        database: URLReference,
        password: String,
        keyFile: URLReference?)
    func didPressNewsItem(in databaseUnlocker: DatabaseUnlockerVC, newsItem: NewsItem)
}

class DatabaseUnlockerVC: UIViewController, Refreshable {

    @IBOutlet weak var errorMessagePanel: UIView!
    @IBOutlet weak var errorMessageLabel: UILabel!
    @IBOutlet weak var errorDetailsButton: UIButton!
    @IBOutlet weak var databaseLocationIconImage: UIImageView!
    @IBOutlet weak var databaseFileNameLabel: UILabel!
    @IBOutlet weak var inputPanel: UIView!
    @IBOutlet weak var passwordField: ProtectedTextField!
    @IBOutlet weak var keyFileField: UITextField!
    @IBOutlet weak var announcementButton: UIButton!
    @IBOutlet weak var unlockButton: UIButton!
    
    weak var coordinator: MainCoordinator?
    weak var delegate: DatabaseUnlockerDelegate?
    var shouldAutofocus = false
    var databaseRef: URLReference? {
        didSet { refresh() }
    }
    private(set) var keyFileRef: URLReference?
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        // make background image
        view.backgroundColor = UIColor(patternImage: UIImage(asset: .backgroundPattern))
        view.layer.isOpaque = false
        unlockButton.titleLabel?.adjustsFontForContentSizeCategory = true
        
        errorMessagePanel.alpha = 0.0
        errorMessagePanel.isHidden = true
        
        refresh()
        
        keyFileField.delegate = self
        passwordField.delegate = self
    }
    
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        navigationController?.setToolbarHidden(true, animated: true)
        if shouldAutofocus {
            DispatchQueue.main.async { [weak self] in
                self?.passwordField?.becomeFirstResponder()
            }
        }
    }
    
    func showErrorMessage(
        _ text: String,
        reason: String?=nil,
        suggestion: String?=nil,
        haptics: HapticFeedback.Kind?=nil
    ) {
        let text = [text, reason, suggestion]
            .compactMap { return $0 } // drop empty
            .joined(separator: "\n")
        errorMessageLabel.text = text
        Diag.error(text)
        UIAccessibility.post(notification: .announcement, argument: text)
        
        // In a stack view, visibility calls are accumulated
        // (https://stackoverflow.com/a/45599835)
        // so we avoid re-showing the panel.
        guard errorMessagePanel.isHidden else { return }

        UIView.animate(
            withDuration: 0.3,
            delay: 0.0,
            options: .curveEaseIn,
            animations: {
                [weak self] in
                self?.errorMessagePanel.alpha = 1.0
                self?.errorMessagePanel.isHidden = false
            },
            completion: {
                [weak self] (finished) in
                self?.errorMessagePanel.shake()
                if let hapticsKind = haptics {
                    HapticFeedback.play(hapticsKind)
                }
            }
        )
    }
    
    func hideErrorMessage(animated: Bool) {
        // In a stack view, visibility calls are accumulated
        // (https://stackoverflow.com/a/45599835)
        // so we avoid re-hiding the panel.
        guard !errorMessagePanel.isHidden else { return }

        if animated {
            UIView.animate(
                withDuration: 0.3,
                delay: 0.0,
                options: .curveEaseOut,
                animations: {
                    [weak self] in
                    self?.errorMessagePanel.alpha = 0.0
                    self?.errorMessagePanel.isHidden = true
                },
                completion: {
                    [weak self] (finished) in
                    self?.errorMessageLabel.text = " "
                }
            )
        } else {
            errorMessagePanel.alpha = 0.0
            errorMessagePanel.isHidden = true
            errorMessageLabel.text = " "
        }
    }

    func showMasterKeyInvalid(message: String) {
        showErrorMessage(message, haptics: .wrongPassword)
    }
    
    func refresh() {
        guard isViewLoaded else { return }
        refreshNews()
        
        guard let dbRef = databaseRef else {
            databaseLocationIconImage.image = nil
            databaseFileNameLabel.text = ""
            return
        }
        let fileInfo = dbRef.info
        if let errorMessage = fileInfo.errorMessage {
            databaseFileNameLabel.text = errorMessage
            databaseFileNameLabel.textColor = UIColor.errorMessage
            databaseLocationIconImage.image = nil
        } else {
            databaseFileNameLabel.text = fileInfo.fileName
            databaseFileNameLabel.textColor = UIColor.primaryText
            databaseLocationIconImage.image = UIImage.databaseIcon(for: dbRef)
        }
        
        let associatedKeyFileRef = Settings.current
            .premiumGetKeyFileForDatabase(databaseRef: dbRef)
        if let associatedKeyFileRef = associatedKeyFileRef {
            // Stored reference can be from the main app (inaccessible),
            // so make sure 1) it is available, or at least 2) there is a same-name available file.
            let allAvailableKeyFiles = FileKeeper.shared
                .getAllReferences(fileType: .keyFile, includeBackup: false)
            if let availableKeyFileRef = associatedKeyFileRef
                .find(in: allAvailableKeyFiles, fallbackToNamesake: true)
            {
                setKeyFile(urlRef: availableKeyFileRef)
            }
        }
    }
    
    func setKeyFile(urlRef: URLReference?) {
        // can be nil, can have error, can be ok
        keyFileRef = urlRef
        
        hideErrorMessage(animated: false)

        guard let databaseRef = databaseRef else { return }
        Settings.current.setKeyFileForDatabase(databaseRef: databaseRef, keyFileRef: keyFileRef)
        
        guard let fileInfo = urlRef?.info else {
            Diag.debug("No key file selected")
            keyFileField.text = ""
            return
        }
        if let errorDetails = fileInfo.errorMessage {
            let errorMessage = String.localizedStringWithFormat(
                NSLocalizedString(
                    "[Database/Unlock] Key file error: %@",
                    value: "Key file error: %@",
                    comment: "Error message related to key file. [errorDetails: String]"),
                errorDetails)
            Diag.warning(errorMessage)
            showErrorMessage(errorMessage)
            keyFileField.text = ""
        } else {
            Diag.info("Key file set successfully")
            keyFileField.text = fileInfo.fileName
        }
    }
    
    // MARK: - Progress overlay
    private(set) var progressOverlay: ProgressOverlay?

    public func showProgressOverlay(animated: Bool) {
        navigationItem.hidesBackButton = true
        progressOverlay = ProgressOverlay.addTo(
            self.view,
            title: LString.databaseStatusLoading,
            animated: animated)
    }
    
    public func updateProgress(with progress: ProgressEx) {
        progressOverlay?.update(with: progress)
    }
    
    public func hideProgressOverlay() {
        navigationItem.hidesBackButton = false
        progressOverlay?.dismiss(animated: true) {
            [weak self] (finished) in
            guard finished, let _self = self else { return }
            _self.progressOverlay?.removeFromSuperview()
            _self.progressOverlay = nil
        }
    }

    
    // MARK: - In-app news announcements
    
    private var newsItem: NewsItem?
    
    /// Sets visibility and content of the announcement button
    private func refreshNews() {
        let nc = NewsCenter.shared
        if let newsItem = nc.getTopItem() {
            announcementButton.titleLabel?.numberOfLines = 0
            announcementButton.setTitle(newsItem.title, for: .normal)
            announcementButton.isHidden = false
            self.newsItem = newsItem
        } else {
            announcementButton.isHidden = true
            self.newsItem = nil
        }
    }
    
    // MARK: - Actions
    
    @IBAction func didPressErrorDetailsButton(_ sender: Any) {
        Watchdog.shared.restart()
        coordinator?.showDiagnostics()
    }
    
    @IBAction func didPressUnlock(_ sender: Any) {
        Watchdog.shared.restart()
        guard let databaseRef = databaseRef else { return }
        delegate?.databaseUnlockerShouldUnlock(
            self,
            database: databaseRef,
            password: passwordField.text ?? "",
            keyFile: keyFileRef)
        passwordField.text = "" 
    }
    
    @IBAction func didPressAnouncementButton(_ sender: Any) {
        guard let newsItem = newsItem else { return }
        delegate?.didPressNewsItem(in: self, newsItem: newsItem)
    }
}

extension DatabaseUnlockerVC: UITextFieldDelegate {
    func textFieldDidBeginEditing(_ textField: UITextField) {
        Watchdog.shared.restart()
        if textField === keyFileField {
            coordinator?.selectKeyFile()
            passwordField.becomeFirstResponder()
        }
    }
    
    func textField(
        _ textField: UITextField,
        shouldChangeCharactersIn range: NSRange,
        replacementString string: String) -> Bool
    {
        hideErrorMessage(animated: true)
        return true
    }
    
    func textFieldShouldReturn(_ textField: UITextField) -> Bool {
        if textField === passwordField {
            didPressUnlock(textField)
            return false
        }
        return true // use default behavior
    }
}
