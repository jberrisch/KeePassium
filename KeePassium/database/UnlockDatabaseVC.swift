//  KeePassium Password Manager
//  Copyright © 2018–2019 Andrei Popleteev <info@keepassium.com>
// 
//  This program is free software: you can redistribute it and/or modify it
//  under the terms of the GNU General Public License version 3 as published
//  by the Free Software Foundation: https://www.gnu.org/licenses/).
//  For commercial licensing, please contact the author.

import UIKit
import KeePassiumLib

class UnlockDatabaseVC: UIViewController, Refreshable {
    @IBOutlet private weak var databaseNameLabel: UILabel!
    @IBOutlet private weak var inputPanel: UIView!
    @IBOutlet private weak var passwordField: UITextField!
    @IBOutlet private weak var keyFileField: KeyFileTextField!
    @IBOutlet private weak var keyboardAdjView: UIView!
    @IBOutlet private weak var errorMessagePanel: UIView!
    @IBOutlet private weak var errorLabel: UILabel!
    @IBOutlet private weak var errorDetailButton: UIButton!
    @IBOutlet private weak var watchdogTimeoutLabel: UILabel!
    @IBOutlet private weak var databaseIconImage: UIImageView!
    @IBOutlet weak var masterKeyKnownLabel: UILabel!
    @IBOutlet weak var lockDatabaseButton: UIButton!
    @IBOutlet weak var getPremiumButton: UIButton!
    @IBOutlet weak var announcementButton: UIButton!
    
    public var databaseRef: URLReference! {
        didSet {
            guard isViewLoaded else { return }
            hideErrorMessage(animated: false)
            refresh()
        }
    }
    
    private var keyFileRef: URLReference?
    private var yubiKey: YubiKey?
    private var fileKeeperNotifications: FileKeeperNotifications!
    
    var isJustLaunched = false // limits auto-unlock on iPad to the initial launch only
    var isAutoUnlockEnabled = true
    fileprivate var isAutomaticUnlock = false

    static func make(databaseRef: URLReference) -> UnlockDatabaseVC {
        let vc = UnlockDatabaseVC.instantiateFromStoryboard()
        vc.databaseRef = databaseRef
        return vc
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        passwordField.delegate = self
        keyFileField.delegate = self
        
        fileKeeperNotifications = FileKeeperNotifications(observer: self)
        // listen for
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(refreshPremiumStatus),
            name: PremiumManager.statusUpdateNotification,
            object: nil)

        // make background image
        view.backgroundColor = UIColor(patternImage: UIImage(asset: .backgroundPattern))
        view.layer.isOpaque = false

        // hide the hidden labels
        watchdogTimeoutLabel.alpha = 0.0
        errorMessagePanel.alpha = 0.0
        errorMessagePanel.isHidden = true
        
        // setup Yubikey button
        keyFileField.yubikeyHandler = {
            [weak self] (field) in
            guard let self = self else { return }
            let popoverAnchor = PopoverAnchor(
                sourceView: self.keyFileField,
                sourceRect: self.keyFileField.bounds)
            self.showHardwareKeyPicker(at: popoverAnchor)
        }

        // Fix UIKeyboardAssistantBar constraints warnings for secure input field
        passwordField.inputAssistantItem.leadingBarButtonGroups = []
        passwordField.inputAssistantItem.trailingBarButtonGroups = []
        
        // Back button to return to this VC (that is, to be shown in ViewGroupVC)
        let lockDatabaseButton = UIBarButtonItem(
            title: LString.actionCloseDatabase,
            style: .plain,
            target: nil,
            action: nil)
        navigationItem.backBarButtonItem = lockDatabaseButton
        
        refreshNews()
    }
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        refreshPremiumStatus()
        refresh()
        if isMovingToParent && canAutoUnlock() {
            // prepare UI for auto-unlocking
            showProgressOverlay(animated: false)
        }
    }
    
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        fileKeeperNotifications.startObserving()
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(onAppDidBecomeActive),
            name: UIApplication.didBecomeActiveNotification,
            object: nil)
        onAppDidBecomeActive()
        
        if isMovingToParent && canAutoUnlock() {
            // Cannot do this in viewWillAppear: causes weird NavController state and crashes
            DispatchQueue.main.async { [weak self] in
                self?.tryToUnlockDatabase(isAutomaticUnlock: true)
            }
        } else {
            // On launch, the database can be locked by watchdog
            // between viewWillAppear() and viewDidAppear() calls.
            // So we ensure the overlay does not remain hovering above the UI.
            hideProgressOverlay(quickly: true)
            refreshInputMode()
        }

        if FileKeeper.shared.hasPendingFileOperations {
            processPendingFileOperations()
        }
        
        maybeFocusOnPassword()
    }
    
    @objc func onAppDidBecomeActive() {
        if Watchdog.shared.isDatabaseTimeoutExpired {
            showWatchdogTimeoutMessage()
        } else {
            hideWatchdogTimeoutMessage(animated: false)
        }
        refreshInputMode()
    }
    
    override func viewWillDisappear(_ animated: Bool) {
        NotificationCenter.default.removeObserver(
            self,
            name: UIApplication.didBecomeActiveNotification,
            object: nil)
        fileKeeperNotifications.stopObserving()
        super.viewWillDisappear(animated)
    }
    
    override func didReceiveMemoryWarning() {
        Diag.error("Received a memory warning")
        DatabaseManager.shared.progress.cancel(reason: .lowMemoryWarning)
    }
    
    func refresh() {
        guard isViewLoaded else { return }
        
        databaseIconImage.image = databaseRef.getIcon(fileType: .database)
        databaseNameLabel.text = databaseRef.visibleFileName
        if databaseRef.hasError {
            let text = databaseRef.error?.localizedDescription
            if databaseRef.hasPermissionError257 {
                showErrorMessage(text, suggestion: LString.tryToReAddFile)
            } else {
                showErrorMessage(text)
            }
        }
        
        let dbSettings = DatabaseSettingsManager.shared.getSettings(for: databaseRef)
        if let associatedKeyFileRef = dbSettings?.associatedKeyFile {
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
        if let associatedYubiKey = dbSettings?.associatedYubiKey {
            setYubiKey(associatedYubiKey)
        }
        refreshNews()
        refreshInputMode()
    }
    
    @objc private func refreshPremiumStatus() {
        switch PremiumManager.shared.status {
        case .initialGracePeriod,
             .freeLightUse,
             .freeHeavyUse:
            getPremiumButton.isHidden = false
        case .subscribed,
             .lapsed:
            getPremiumButton.isHidden = true
        }
    }
    
    /// Switch the UI depending on whether the master key is already known.
    private func refreshInputMode() {
        let dbSettings = DatabaseSettingsManager.shared.getSettings(for: databaseRef)
        let isDatabaseKeyStored = dbSettings?.hasMasterKey ?? false
        Diag.verbose("isDatabaseKeyStored: \(isDatabaseKeyStored)")
        
        let shouldInputMasterKey = !isDatabaseKeyStored
        masterKeyKnownLabel.isHidden = shouldInputMasterKey
        lockDatabaseButton.isHidden = masterKeyKnownLabel.isHidden
        inputPanel.isHidden = !shouldInputMasterKey
    }

    /// Makes password field the first responder, if visible
    private func maybeFocusOnPassword() {
        if !inputPanel.isHidden {
            passwordField.becomeFirstResponder()
        }
    }
    
    private func clearPasswordField() {
        passwordField.text = ""
    }
    
    // MARK: - Yubikey stuff
    
    func showHardwareKeyPicker(at popoverAnchor: PopoverAnchor) {
        let hardwareKeyPicker = HardwareKeyPicker.create(delegate: self)
        hardwareKeyPicker.modalPresentationStyle = .popover
        if let popover = hardwareKeyPicker.popoverPresentationController {
            popoverAnchor.apply(to: popover)
            popover.delegate = hardwareKeyPicker.dismissablePopoverDelegate
        }
        hardwareKeyPicker.key = yubiKey
        present(hardwareKeyPicker, animated: true, completion: nil)
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

    @IBAction func didPressAnouncementButton(_ sender: Any) {
        newsItem?.show(in: self)
    }
    
    // MARK: - Showing/hiding various messagess

    /// Shows an error message about database loading.
    func showErrorMessage(
        _ text: String?,
        details: String?=nil,
        suggestion: String?=nil,
        haptics: HapticFeedback.Kind?=nil
    ) {
        guard let text = text else { return }
        let message = [text, details, suggestion]
            .compactMap{ return $0 }
            .joined(separator: "\n")
        errorLabel.text = message
        Diag.error(message)
        UIAccessibility.post(notification: .layoutChanged, argument: errorLabel)
        
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
                self?.errorMessagePanel.isHidden = false
                self?.errorMessagePanel.alpha = 1.0
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
    
    /// Hides the previously shown error message, if any.
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
                    self?.errorLabel.text = nil
                }
            )
        } else {
            errorMessagePanel.isHidden = true
            errorLabel.text = nil
        }
    }
    
    func showWatchdogTimeoutMessage() {
        UIView.animate(
            withDuration: 0.5,
            delay: 0.0,
            options: .curveEaseOut,
            animations: {
                [weak self] in
                self?.watchdogTimeoutLabel.alpha = 1.0
            },
            completion: nil)
    }
    
    func hideWatchdogTimeoutMessage(animated: Bool) {
        if animated {
            UIView.animate(
                withDuration: 0.5,
                delay: 0.0,
                options: .curveEaseOut,
                animations: {
                    [weak self] in
                    self?.watchdogTimeoutLabel.alpha = 0.0
                },
                completion: nil)
        } else {
            watchdogTimeoutLabel.alpha = 0.0
        }
    }

    // MARK: - Progress tracking
    private var progressOverlay: ProgressOverlay?
    fileprivate func showProgressOverlay(animated: Bool) {
        guard progressOverlay == nil else { return }
        progressOverlay = ProgressOverlay.addTo(
            keyboardAdjView,
            title: LString.databaseStatusLoading,
            animated: animated)
        progressOverlay?.isCancellable = true
        progressOverlay?.unresponsiveCancelHandler = { [weak self] in
            guard let self = self else { return }
            let diagInfoVC = ViewDiagnosticsVC.make()
            self.present(diagInfoVC, animated: true, completion: nil)
        }
        
        // Disable navigation so the user won't switch to another DB while unlocking.
        if let leftNavController = splitViewController?.viewControllers.first as? UINavigationController,
            let chooseDatabaseVC = leftNavController.topViewController as? ChooseDatabaseVC {
                chooseDatabaseVC.isEnabled = false
        }
        navigationItem.hidesBackButton = true
    }
    
    fileprivate func hideProgressOverlay(quickly: Bool) {
        UIView.animateKeyframes(
            withDuration: quickly ? 0.2 : 0.6,
            delay: quickly ? 0.0 : 0.6,
            options: [.beginFromCurrentState],
            animations: {
                [weak self] in
                self?.progressOverlay?.alpha = 0.0
            },
            completion: {
                [weak self] finished in
                guard let _self = self else { return }
                _self.progressOverlay?.removeFromSuperview()
                _self.progressOverlay = nil
            }
        )
        // Enable navigation
        navigationItem.hidesBackButton = false
        if let leftNavController = splitViewController?.viewControllers.first as? UINavigationController,
            let chooseDatabaseVC = leftNavController.topViewController as? ChooseDatabaseVC {
            chooseDatabaseVC.isEnabled = true
        }

        let p = DatabaseManager.shared.progress
        Diag.verbose("Final progress: \(p.completedUnitCount) of \(p.totalUnitCount)")
    }

    // MARK: - Key file selection
    
    func selectKeyFileAction(_ sender: Any) {
        Diag.verbose("Selecting key file")
        hideErrorMessage(animated: true)
        let keyFileChooser = ChooseKeyFileVC.make(popoverSourceView: keyFileField, delegate: self)
        present(keyFileChooser, animated: true, completion: nil)
    }
    
    // MARK: - Actions
    
    @IBAction func didPressErrorDetails(_ sender: Any) {
        let diagInfoVC = ViewDiagnosticsVC.make()
        present(diagInfoVC, animated: true, completion: nil)
    }
    
    @IBAction func didPressUnlock(_ sender: Any) {
        tryToUnlockDatabase(isAutomaticUnlock: false)
    }
    
    @IBAction func didPressLockDatabase(_ sender: Any) {
        DatabaseSettingsManager.shared.updateSettings(for: databaseRef) {
            $0.clearMasterKey()
        }
        refreshInputMode()
    }
    
    private var premiumCoordinator: PremiumCoordinator?
    @IBAction func didPressUpgradeToPremium(_ sender: Any) {
        assert(premiumCoordinator == nil)
        premiumCoordinator = PremiumCoordinator(presentingViewController: self)
        premiumCoordinator?.delegate = self
        premiumCoordinator?.start()
    }
    
    // MARK: - DB unlocking
    
    func canAutoUnlock() -> Bool {
        guard isAutoUnlockEnabled && Settings.current.isAutoUnlockStartupDatabase else {
            return false
        }
        guard let splitVC = splitViewController, splitVC.isCollapsed else { return isJustLaunched }
        
        let dbSettings = DatabaseSettingsManager.shared.getSettings(for: databaseRef)
        let hasKey = dbSettings?.hasMasterKey ?? false
        Diag.verbose("canAutoUnlock: \(hasKey)")
        return hasKey
    }
    
    func tryToUnlockDatabase(isAutomaticUnlock: Bool) {
        Diag.clear()
        Diag.verbose("Will try to unlock database [automatically: \(isAutomaticUnlock)]")
        self.isAutomaticUnlock = isAutomaticUnlock
        let password = passwordField.text ?? ""
        passwordField.resignFirstResponder()
        hideWatchdogTimeoutMessage(animated: true)
        DatabaseManager.shared.addObserver(self)
        
        let _challengeHandler = ChallengeResponseManager.makeHandler(for: yubiKey)
        let dbSettings = DatabaseSettingsManager.shared.getSettings(for: databaseRef)
        if let databaseKey = dbSettings?.masterKey {
            // try to unlock automatically
            databaseKey.challengeHandler = _challengeHandler
            DatabaseManager.shared.startLoadingDatabase(
                database: databaseRef,
                compositeKey: databaseKey)
        } else {
            guard !isAutomaticUnlock else {
                // Automatic unlock, but there is no master key?
                // This means the key was just cleared by the watchdog.
                // So let's abort auto-unlock and pretend this never happened.
                Diag.debug("Aborting auto-unlock, there is no stored key")
                refreshInputMode()
                hideProgressOverlay(quickly: true)
                return
            }
            DatabaseManager.shared.startLoadingDatabase(
                database: databaseRef,
                password: password,
                keyFile: keyFileRef,
                challengeHandler: _challengeHandler)
        }
    }
    
    /// Called when the DB is successfully loaded, shows it in ViewGroupVC
    func showDatabaseRoot(loadingWarnings: DatabaseLoadingWarnings) {
        guard let database = DatabaseManager.shared.database else {
            assertionFailure()
            return
        }
        let viewGroupVC = ViewGroupVC.make(group: database.root, loadingWarnings: loadingWarnings)
        guard let leftNavController =
            splitViewController?.viewControllers.first as? UINavigationController else
        {
            fatalError("No leftNavController?!")
        }
        if leftNavController.topViewController is UnlockDatabaseVC {
            // compact mode: replace DB unlocker with the group viewer
            var viewControllers = leftNavController.viewControllers
            viewControllers[viewControllers.count - 1] = viewGroupVC
            leftNavController.setViewControllers(viewControllers, animated: true)
        } else {
            // wide mode: stack group viewer on top of DB list
            leftNavController.show(viewGroupVC, sender: self)
        }
    }
}

extension UnlockDatabaseVC: HardwareKeyPickerDelegate {
    func didDismiss(_ picker: HardwareKeyPicker) {
        // ignored
    }
    
    func didSelectKey(yubiKey: YubiKey?, in picker: HardwareKeyPicker) {
        setYubiKey(yubiKey)
    }
    
    func setYubiKey(_ yubiKey: YubiKey?) {
        self.yubiKey = yubiKey
        keyFileField.isYubiKeyActive = (yubiKey != nil)

        DatabaseSettingsManager.shared.updateSettings(for: databaseRef) { (dbSettings) in
            dbSettings.maybeSetAssociatedYubiKey(yubiKey)
        }
        if let _yubiKey = yubiKey {
            Diag.info("Hardware key selected [key: \(_yubiKey)]")
        } else {
            Diag.info("No hardware key selected")
        }
    }
}

extension UnlockDatabaseVC: KeyFileChooserDelegate {
    func setKeyFile(urlRef: URLReference?) {
        // can be nil, can have error, can be ok
        self.keyFileRef = urlRef
        DatabaseSettingsManager.shared.updateSettings(for: databaseRef) { (dbSettings) in
            dbSettings.maybeSetAssociatedKeyFile(keyFileRef)
        }

        guard let keyFileRef = keyFileRef else {
            Diag.debug("No key file selected")
            keyFileField.text = ""
            return
        }
        if let errorDetails = keyFileRef.error?.localizedDescription {
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
            keyFileField.text = keyFileRef.visibleFileName
        }
    }
    
    func onKeyFileSelected(urlRef: URLReference?) {
        setKeyFile(urlRef: urlRef)
    }
}

extension UnlockDatabaseVC: UITextFieldDelegate {
    func textFieldShouldReturn(_ textField: UITextField) -> Bool {
        if textField == self.passwordField {
            tryToUnlockDatabase(isAutomaticUnlock: false)
        }
        return true
    }
    
    func textField(
        _ textField: UITextField,
        shouldChangeCharactersIn range: NSRange,
        replacementString string: String) -> Bool
    {
        hideErrorMessage(animated: true)
        hideWatchdogTimeoutMessage(animated: true)
        return true
    }
    
    func textFieldShouldBeginEditing(_ textField: UITextField) -> Bool {
        if textField === keyFileField {
            //textField.endEditing(true) //TODO: does not work
            passwordField.becomeFirstResponder()
            selectKeyFileAction(textField)
            return false
        }
        return true
    }
    
    func textFieldDidBeginEditing(_ textField: UITextField) {
    }
}


// MARK: - DatabaseManagerObserver
extension UnlockDatabaseVC: DatabaseManagerObserver {
    func databaseManager(willLoadDatabase urlRef: URLReference) {
        showProgressOverlay(animated: true)
    }
    
    func databaseManager(database urlRef: URLReference, isCancelled: Bool) {
        DatabaseManager.shared.removeObserver(self)
        DatabaseSettingsManager.shared.updateSettings(for: urlRef) { (dbSettings) in
            dbSettings.clearMasterKey()
        }
        
        refresh()
        clearPasswordField()
        hideProgressOverlay(quickly: true)
        // cancelled by the user, no errors to show
        maybeFocusOnPassword()
    }
    
    func databaseManager(progressDidChange progress: ProgressEx) {
        progressOverlay?.update(with: progress)
    }
    
    func databaseManager(database urlRef: URLReference, invalidMasterKey message: String) {
        DatabaseManager.shared.removeObserver(self)
        DatabaseSettingsManager.shared.updateSettings(for: urlRef) { (dbSettings) in
            dbSettings.clearMasterKey()
        }
        refresh()
        // Keep the entered password intact
        hideProgressOverlay(quickly: true)
        
        showErrorMessage(message, haptics: .wrongPassword)
        maybeFocusOnPassword()
    }
    
    func databaseManager(didLoadDatabase urlRef: URLReference, warnings: DatabaseLoadingWarnings) {
        DatabaseManager.shared.removeObserver(self)
        
//        Watchdog.shared.restart()
        HapticFeedback.play(.databaseUnlocked)
        
        if Settings.current.isRememberDatabaseKey {
            do {
                try DatabaseManager.shared.rememberDatabaseKey() // throws KeychainError
            } catch {
                Diag.error("Failed to remember database key [message: \(error.localizedDescription)]")
            }
        }
        clearPasswordField()
        hideProgressOverlay(quickly: false)
        showDatabaseRoot(loadingWarnings: warnings)
    }

    func databaseManager(database urlRef: URLReference, loadingError message: String, reason: String?) {
        DatabaseManager.shared.removeObserver(self)
        refresh()
        // Keep the entered password intact
        hideProgressOverlay(quickly: true)
        
        isAutoUnlockEnabled = false
        showErrorMessage(message, details: reason, haptics: .error)
        maybeFocusOnPassword()
    }
}

// MARK: - FileKeeperObserver
extension UnlockDatabaseVC: FileKeeperObserver {
    func fileKeeper(didAddFile urlRef: URLReference, fileType: FileType) {
        if fileType == .database {
            // (compact view only) show DB list to demonstrate that one has been added
            navigationController?.popViewController(animated: true)
        }
    }

    func fileKeeperHasPendingOperation() {
        processPendingFileOperations()
    }

    /// Adds pending files, if any
    private func processPendingFileOperations() {
        FileKeeper.shared.processPendingOperations(
            success: nil,
            error: {
                [weak self] (error) in
                guard let _self = self else { return }
                let alert = UIAlertController.make(
                    title: LString.titleError,
                    message: error.localizedDescription)
                _self.present(alert, animated: true, completion: nil)
            }
        )
    }
}

// MARK: - PremiumCoordinatorDelegate
extension UnlockDatabaseVC: PremiumCoordinatorDelegate {
    func didUpgradeToPremium(in premiumCoordinator: PremiumCoordinator) {
        refresh()
    }
    
    func didFinish(_ premiumCoordinator: PremiumCoordinator) {
        // it has already removed its modal VC
        self.premiumCoordinator = nil
    }
}
