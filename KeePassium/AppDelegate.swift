//  KeePassium Password Manager
//  Copyright © 2018–2019 Andrei Popleteev <info@keepassium.com>
// 
//  This program is free software: you can redistribute it and/or modify it
//  under the terms of the GNU General Public License version 3 as published
//  by the Free Software Foundation: https://www.gnu.org/licenses/).
//  For commercial licensing, please contact the author.

import UIKit
import KeePassiumLib
import LocalAuthentication

//@UIApplicationMain - replaced by main.swift to subclass UIApplication
class AppDelegate: UIResponder, UIApplicationDelegate {

    var window: UIWindow?
    fileprivate var watchdog: Watchdog
    fileprivate var appCoverWindow: UIWindow?
    fileprivate var appLockWindow: UIWindow?
    fileprivate var biometricsBackgroundWindow: UIWindow?
    fileprivate var isBiometricAuthShown = false
    
    // Repeated biometric requests are considered successful for a brief time.
    fileprivate let biometricAuthReuseDuration = TimeInterval(1.5)
    fileprivate var lastSuccessfulBiometricAuthTime: Date = .distantPast
    
    
    override init() {
        watchdog = Watchdog.shared // init
        super.init()
        watchdog.delegate = self
    }
    
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
        ) -> Bool
    {
        #if PREPAID_VERSION
        BusinessModel.type = .prepaid
        #else
        BusinessModel.type = .freemium
        #endif
        AppGroup.applicationShared = application
        SettingsMigrator.processAppLaunch(with: Settings.current)
        SystemIssueDetector.scanForIssues()
        Diag.info(AppInfo.description)
        PremiumManager.shared.startObservingTransactions()
        
        if #available(iOS 13, *) {
            let args = ProcessInfo.processInfo.arguments
            if args.contains("darkMode") {
                window?.overrideUserInterfaceStyle = .dark
            }
        }

        // Make sure that FileKeeper can ask user for confirmations
        let rootVC = window?.rootViewController as? FileKeeperDelegate
        assert(rootVC != nil, "FileKeeper needs a delegate")
        FileKeeper.shared.delegate = rootVC

        // First thing first, cover the app to avoid flashing any content.
        // The cover will be hidden by Watchdog, if appropriate.
        showAppCoverScreen()
        return true
    }
    
    func applicationWillTerminate(_ application: UIApplication) {
        PremiumManager.shared.finishObservingTransactions()
    }
    
    func application(
        _ application: UIApplication,
        open inputURL: URL,
        options: [UIApplication.OpenURLOptionsKey : Any] = [:]
        ) -> Bool
    {
        AppGroup.applicationShared = application
        let isOpenInPlace = (options[.openInPlace] as? Bool) ?? false

        Diag.info("Opened with URL: \(inputURL.redacted) [inPlace: \(isOpenInPlace)]")
        
        if inputURL.scheme != AppGroup.appURLScheme {
            // By now, we might not have the UI to show import progress or errors.
            // So defer the operation until there is UI.
            FileKeeper.shared.prepareToAddFile(
                url: inputURL,
                mode: isOpenInPlace ? .openInPlace : .import)
        }
        
        DatabaseManager.shared.closeDatabase(
            clearStoredKey: false,
            ignoreErrors: true,
            completion: nil)
        return true
    }
}

// MARK: - WatchdogDelegate
extension AppDelegate: WatchdogDelegate {
    var isAppCoverVisible: Bool {
        return appCoverWindow != nil
    }
    var isAppLockVisible: Bool {
        return appLockWindow != nil || isBiometricAuthShown
    }
    func showAppCover(_ sender: Watchdog) {
        showAppCoverScreen()
    }
    func hideAppCover(_ sender: Watchdog) {
        hideAppCoverScreen()
    }
    func showAppLock(_ sender: Watchdog) {
        showAppLockScreen()
    }
    func hideAppLock(_ sender: Watchdog) {
        hideAppLockScreen()
    }
    
    private func showAppCoverScreen()  {
        guard appCoverWindow == nil else { return }
        
        let _appCoverWindow = UIWindow(frame: UIScreen.main.bounds)
        _appCoverWindow.screen = UIScreen.main
        _appCoverWindow.windowLevel = UIWindow.Level.alert
        let coverVC = AppCoverVC.make()
        
        UIView.performWithoutAnimation {
            _appCoverWindow.rootViewController = coverVC
            _appCoverWindow.makeKeyAndVisible()
        }
        self.appCoverWindow = _appCoverWindow
        print("App cover shown")
        
        coverVC.view.snapshotView(afterScreenUpdates: true)
    }
    
    private func hideAppCoverScreen() {
        guard let appCoverWindow = appCoverWindow else { return }
        appCoverWindow.isHidden = true
        self.appCoverWindow = nil
        print("App cover hidden")
    }
    
    private var canUseBiometrics: Bool {
        return isBiometricsAvailable() && Settings.current.premiumIsBiometricAppLockEnabled
    }
    
    /// Shows the lock screen.
    private func showAppLockScreen() {
        guard !isAppLockVisible else { return }
        if canUseBiometrics {
            performBiometricUnlock()
        } else {
            showPasscodeRequest()
        }
    }
    
    private func hideAppLockScreen() {
        guard isAppLockVisible else { return }
        appLockWindow?.resignKey()
        appLockWindow?.isHidden = true
        appLockWindow = nil
        print("appLockWindow hidden")
    }
    
    private func showPasscodeRequest() {
        let passcodeInputVC = PasscodeInputVC.instantiateFromStoryboard()
        passcodeInputVC.delegate = self
        passcodeInputVC.mode = .verification
        passcodeInputVC.isCancelAllowed = false // for the main app
        passcodeInputVC.isBiometricsAllowed = canUseBiometrics
        
        let _appLockWindow = UIWindow(frame: UIScreen.main.bounds)
        _appLockWindow.screen = UIScreen.main
        _appLockWindow.windowLevel = UIWindow.Level.alert
        UIView.performWithoutAnimation {
            _appLockWindow.rootViewController = passcodeInputVC
            _appLockWindow.makeKeyAndVisible()
        }
        passcodeInputVC.view.snapshotView(afterScreenUpdates: true)
        
        self.appLockWindow = _appLockWindow
        print("passcode request shown")
    }
    
    /// True if hardware provides biometric authentication.
    private func isBiometricsAvailable() -> Bool {
        let context = LAContext()
        let policy = LAPolicy.deviceOwnerAuthenticationWithBiometrics
        return context.canEvaluatePolicy(policy, error: nil)
    }
    
    /// Shows biometric auth.
    private func performBiometricUnlock() {
        assert(isBiometricsAvailable())
        guard Settings.current.premiumIsBiometricAppLockEnabled else { return }
        guard !isBiometricAuthShown else { return }
        
        // After a successful biometric auth, consider repeated requests successful.
        // Basically, this is a custom implementation of
        // `touchIDAuthenticationAllowableReuseDuration` that does not seem to work properly.
        let timeSinceLastSuccess = abs(Date.now.timeIntervalSince(lastSuccessfulBiometricAuthTime))
        if timeSinceLastSuccess < biometricAuthReuseDuration {
            print("Skipping repeated biometric prompt")
            watchdog.unlockApp()
            return
        }
        
        let context = LAContext()
        let policy = LAPolicy.deviceOwnerAuthenticationWithBiometrics
        context.localizedFallbackTitle = "" // hide "Enter (System) Password" fallback; nil won't work
        context.localizedCancelTitle = LString.actionUsePasscode
        print("Showing biometrics request")
        
        showBiometricsBackground()
        lastSuccessfulBiometricAuthTime = .distantPast
        context.evaluatePolicy(policy, localizedReason: LString.titleTouchID) {
            [weak self] (authSuccessful, authError) in
            DispatchQueue.main.async { [weak self] in
                if authSuccessful {
                    self?.lastSuccessfulBiometricAuthTime = Date.now
                    self?.watchdog.unlockApp()
                } else {
                    Diag.warning("TouchID failed [message: \(authError?.localizedDescription ?? "nil")]")
                    self?.lastSuccessfulBiometricAuthTime = .distantPast
                    self?.showPasscodeRequest()
                }
                self?.hideBiometricsBackground()
                self?.isBiometricAuthShown = false
            }
        }
        isBiometricAuthShown = true
    }
    
    private func showBiometricsBackground()  {
        guard biometricsBackgroundWindow == nil else { return }
        
        let window = UIWindow(frame: UIScreen.main.bounds)
        window.screen = UIScreen.main
        window.windowLevel = UIWindow.Level.alert + 1 // to be above any AppCover
        let coverVC = AppCoverVC.make()
        
        UIView.performWithoutAnimation {
            window.rootViewController = coverVC
            window.makeKeyAndVisible()
        }
        print("Biometrics background shown")
        self.biometricsBackgroundWindow = window
        
        coverVC.view.snapshotView(afterScreenUpdates: true)
    }
    
    private func hideBiometricsBackground() {
        guard let window = biometricsBackgroundWindow else { return }
        window.isHidden = true
        self.biometricsBackgroundWindow = nil
        print("Biometrics background hidden")
    }
    
}

// MARK: - PasscodeInputDelegate
extension AppDelegate: PasscodeInputDelegate {
    func passcodeInput(_ sender: PasscodeInputVC, didEnterPasscode passcode: String) {
        do {
            if try Keychain.shared.isAppPasscodeMatch(passcode) { // throws KeychainError
                HapticFeedback.play(.appUnlocked)
                watchdog.unlockApp()
            } else {
                HapticFeedback.play(.wrongPassword)
                sender.animateWrongPassccode()
                if Settings.current.isLockAllDatabasesOnFailedPasscode {
                    DatabaseSettingsManager.shared.eraseAllMasterKeys()
                    DatabaseManager.shared.closeDatabase(
                        clearStoredKey: true,
                        ignoreErrors: true,
                        completion: nil)
                }
            }
        } catch {
            let alert = UIAlertController.make(
                title: LString.titleKeychainError,
                message: error.localizedDescription)
            sender.present(alert, animated: true, completion: nil)
        }
    }
    
    func passcodeInputDidRequestBiometrics(_ sender: PasscodeInputVC) {
        assert(canUseBiometrics)
        performBiometricUnlock()
    }
}
