//  KeePassium Password Manager
//  Copyright © 2018–2020 Andrei Popleteev <info@keepassium.com>
//
//  This program is free software: you can redistribute it and/or modify it
//  under the terms of the GNU General Public License version 3 as published
//  by the Free Software Foundation: https://www.gnu.org/licenses/).
//  For commercial licensing, please contact the author.

import KeePassiumLib

class AppIconSwitcherCoordinator: Coordinator {
    var childCoordinators = [Coordinator]()
    
    typealias DismissHandler = (AppIconSwitcherCoordinator) -> Void
    var dismissHandler: DismissHandler?
    
    private let router: NavigationRouter
    private let picker: AppIconPicker
    
    init(router: NavigationRouter) {
        self.router = router
        picker = AppIconPicker.instantiateFromStoryboard()
        picker.delegate = self
    }
    
    func start() {
        router.push(picker, animated: true, onPop: { [self] (viewController) in // strong self
            self.dismissHandler?(self)
        })
    }
}

// MARK: AppIconPickerDelegate
extension AppIconSwitcherCoordinator: AppIconPickerDelegate {
    func didSelectIcon(_ icon: AppIcon, in appIconPicker: AppIconPicker) {
        UIApplication.shared.setAlternateIconName(icon.assetName) { error in
            if let error = error {
                Diag.error("Failed to switch app icon [message: \(error.localizedDescription)")
            } else {
                Diag.info("App icon switched successfully")
            }
        }
    }
}
