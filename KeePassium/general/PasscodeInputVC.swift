//  KeePassium Password Manager
//  Copyright © 2018–2019 Andrei Popleteev <info@keepassium.com>
// 
//  This program is free software: you can redistribute it and/or modify it
//  under the terms of the GNU General Public License version 3 as published
//  by the Free Software Foundation: https://www.gnu.org/licenses/).
//  For commercial licensing, please contact the author.

import KeePassiumLib
import LocalAuthentication

protocol PasscodeInputDelegate: class {
    /// Called when the user presses "Cancel"
    func passcodeInputDidCancel(_ sender: PasscodeInputVC)
    
    /// Defines whether the given passcode has acceptable length/complexity.
    func passcodeInput(_sender: PasscodeInputVC, canAcceptPasscode passcode: String) -> Bool
    
    /// Called when the user presses "Unlock" / "Done" (depending on the mode)
    func passcodeInput(_ sender: PasscodeInputVC, didEnterPasscode passcode: String)
    
    /// Called when the user presses "Touch ID / Face ID" button.
    func passcodeInputDidRequestBiometrics(_ sender: PasscodeInputVC)
}

extension PasscodeInputDelegate {
    // Empty method stubs, to make their implementation optional for delegates.
    func passcodeInputDidCancel(_ sender: PasscodeInputVC) {}
    func passcodeInput(_sender: PasscodeInputVC, canAcceptPasscode passcode: String) -> Bool {
        return passcode.count > 0
    }
    func passcodeInput(_ sender: PasscodeInputVC, didEnterPasscode: String) {}
    func passcodeInputDidRequestBiometrics(_ sender: PasscodeInputVC) {}
}

class PasscodeInputVC: UIViewController {

    /// Defines whether the dialog verifies the passcode, or kindly asks to setup one.
    public enum Mode {
        /// Setup passcode: the main button is called "Done".
        case setup
        /// Verification mode: the main button is called "Unlock".
        case verification
    }
    
    @IBOutlet weak var cancelButton: UIButton!
    @IBOutlet weak var passcodeTextField: ProtectedTextField!
    @IBOutlet weak var mainButton: UIButton!
    @IBOutlet weak var switchKeyboardButton: UIButton!
    @IBOutlet weak var useBiometricsButton: UIButton!
    @IBOutlet weak var keyboardLayoutConstraint: KeyboardLayoutConstraint!
    
    /// Defines whether the VC is kindly asking for or strictly checking the passcode.
    public var mode: Mode = .setup
    /// Automatically show up keyboard after appearing (true by default).
    /// Disable this if passcode input is immedaitely followed by biometrics auth UI.
    public var shouldActivateKeyboard = true
    /// Whether to show the Cancel button (by default is `true`).
    public var isCancelAllowed = true
    /// Whether to show the "Touch ID / Face ID" button (false by default)
    public var isBiometricsAllowed = false {
        didSet { refreshBiometricsButton() }
    }
    
    weak var delegate: PasscodeInputDelegate?
    private var nextKeyboardType = Settings.PasscodeKeyboardType.alphanumeric
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        // make background image
        view.backgroundColor = UIColor(patternImage: UIImage(asset: .backgroundPattern))
        view.layer.isOpaque = false
        
        mainButton.titleLabel?.font = UIFont.preferredFont(forTextStyle: .body)
        mainButton.titleLabel?.textAlignment = .center
        mainButton.titleLabel?.adjustsFontForContentSizeCategory = true
        
        self.presentationController?.delegate = self
        
        passcodeTextField.delegate = self
        passcodeTextField.validityDelegate = self
        passcodeTextField.isWatchdogAware = (mode != .verification) // unlocking is not an activity

        let cancelButton = UIBarButtonItem(
            barButtonSystemItem: .cancel,
            target: self,
            action: #selector(didPressCancelButton))
        navigationItem.leftBarButtonItem = cancelButton
        
        if UIDevice.current.userInterfaceIdiom == .pad {
            // Keyboard is always the same on iPad, cannot switch.
            switchKeyboardButton.isHidden = true
        }
        setKeyboardType(Settings.current.passcodeKeyboardType)
    }
    
    override func viewWillAppear(_ animated: Bool) {
        switch mode {
        case .setup:
            mainButton.setTitle(LString.actionDone, for: .normal)
        case .verification:
            mainButton.setTitle(LString.actionUnlock, for: .normal)
        }
        cancelButton.isHidden = !isCancelAllowed
        mainButton.isEnabled = passcodeTextField.isValid
        refreshBiometricsButton()
        
        if shouldActivateKeyboard {
            DispatchQueue.main.async { [self] in
                self.passcodeTextField.becomeFirstResponder()
            }
        }
        super.viewWillAppear(animated)
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        updateKeyboardLayoutConstraints()
        if shouldActivateKeyboard {
            DispatchQueue.main.async { [self] in
                self.passcodeTextField.becomeFirstResponder()
            }
        }
    }
    
    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        DispatchQueue.main.async {
            self.updateKeyboardLayoutConstraints()
        }
    }
    
    private func refreshBiometricsButton() {
        guard isViewLoaded else { return }
        useBiometricsButton.isHidden = !isBiometricsAllowed
        
        // biometrics icon should correspond to hardware capabilities
        let biometryType = LAContext.getBiometryType()
        useBiometricsButton.setImage(biometryType.icon, for: .normal)
    }
    
    private func updateKeyboardLayoutConstraints() {
        if let window = view.window {
            let viewTop = view.convert(view.frame.origin, to: window).y
            let viewHeight = view.frame.height
            let windowHeight = window.frame.height
            let viewBottomOffset = windowHeight - (viewTop + viewHeight)
            keyboardLayoutConstraint.viewOffset = viewBottomOffset
        }
    }
    
    override var canBecomeFirstResponder: Bool {
        return passcodeTextField.canBecomeFirstResponder
    }
    
    @discardableResult
    func showKeyboard() -> Bool {
        let result = passcodeTextField.becomeFirstResponder()
        return result
    }
    
    private func setKeyboardType(_ type: Settings.PasscodeKeyboardType) {
        Settings.current.passcodeKeyboardType = type
        let nextKeyboardTitle: String
        switch type {
        case .numeric:
            passcodeTextField.keyboardType = .numberPad
            nextKeyboardType = .alphanumeric
            nextKeyboardTitle = NSLocalizedString(
                "[AppLock/Passcode/KeyboardType/switchAction] 123→ABC",
                value: "123→ABC",
                comment: "Action: change keyboard type to enter alphanumeric passphrases")
        case .alphanumeric:
            passcodeTextField.keyboardType = .asciiCapable
            nextKeyboardType = .numeric
            nextKeyboardTitle = NSLocalizedString(
                "[AppLock/Passcode/KeyboardType/switchAction] ABC→123",
                value: "ABC→123",
                comment: "Action: change keyboard type to enter PIN numbers")
        }
        passcodeTextField.reloadInputViews()
        switchKeyboardButton.setTitle(nextKeyboardTitle, for: .normal)
    }
    
    /// Animates the VC to show that the entered passcode was wrong.
    public func animateWrongPassccode() {
        passcodeTextField.shake()
        passcodeTextField.selectAll(nil)
    }
    
    // MARK: - Actions
    
    @IBAction func didPressCancelButton(_ sender: Any) {
        delegate?.passcodeInputDidCancel(self)
    }
    
    @IBAction func didPressMainButton(_ sender: Any) {
        let passcode = passcodeTextField.text ?? ""
        delegate?.passcodeInput(self, didEnterPasscode: passcode)
    }
    
    @IBAction func didPressSwitchKeyboard(_ sender: Any) {
        setKeyboardType(nextKeyboardType)
    }
    
    @IBAction func didPressUseBiometricsButton(_ sender: Any) {
        delegate?.passcodeInputDidRequestBiometrics(self)
    }
}

extension PasscodeInputVC: UITextFieldDelegate, ValidatingTextFieldDelegate {
    func textFieldShouldReturn(_ textField: UITextField) -> Bool {
        didPressMainButton(textField)
        return false
    }
    
    func validatingTextFieldShouldValidate(_ sender: ValidatingTextField) -> Bool {
        let passcode = passcodeTextField.text ?? ""
        let isAcceptable = delegate?
            .passcodeInput(_sender: self, canAcceptPasscode: passcode) ?? false
        mainButton.isEnabled = isAcceptable
        return isAcceptable
    }
}

// MARK: - UIAdaptivePresentationControllerDelegate

extension PasscodeInputVC: UIAdaptivePresentationControllerDelegate {
    
    func presentationControllerDidDismiss(_ presentationController: UIPresentationController) {
        didPressCancelButton(self)
    }
}
