//  KeePassium Password Manager
//  Copyright © 2018–2020 Andrei Popleteev <info@keepassium.com>
//
//  This program is free software: you can redistribute it and/or modify it
//  under the terms of the GNU General Public License version 3 as published
//  by the Free Software Foundation: https://www.gnu.org/licenses/).
//  For commercial licensing, please contact the author.

import KeePassiumLib

class HelpViewerCoordinator: NSObject, Coordinator {
    var childCoordinators = [Coordinator]()
    
    typealias DismissHandler = (HelpViewerCoordinator) -> Void
    var dismissHandler: DismissHandler?
    
    fileprivate var navigationRouter: NavigationRouter
    private let helpViewerVC: HelpViewerVC
    
    static func create(at popoverAnchor: PopoverAnchor) -> HelpViewerCoordinator {
        let navVC = UINavigationController()
        let navigationRouter = NavigationRouter(navVC)
        let coordinator = HelpViewerCoordinator(navigationRouter: navigationRouter)
        
        navVC.modalPresentationStyle = .popover
        navVC.presentationController?.delegate = coordinator
        if let popover = navVC.popoverPresentationController {
            popoverAnchor.apply(to: popover)
            popover.delegate = coordinator
        }
        return coordinator
    }
    
    init(navigationRouter: NavigationRouter) {
        self.navigationRouter = navigationRouter
        
        helpViewerVC = HelpViewerVC.create()
        super.init()
        
        helpViewerVC.delegate = self
    }
    
    func start() {
        fatalError("use start(in:) instead")
    }
    
    func start(in parent: UIViewController) {
        helpViewerVC.content = HelpArticle.perpetualFallbackLicense
        navigationRouter.push(helpViewerVC, animated: true, onPop: {
            [weak self] (viewController) in
            guard let self = self else { return }
            assert(viewController == self.helpViewerVC)
            self.dismissHandler?(self)
        })
        parent.present(navigationRouter.navigationController, animated: true, completion: nil)
    }
}

extension HelpViewerCoordinator: HelpViewerDelegate {
    func didPressCancel(in viewController: HelpViewerVC) {
        navigationRouter.pop(animated: true)
    }
}

extension HelpViewerCoordinator: UIPopoverPresentationControllerDelegate {

    func presentationController(
        _ controller: UIPresentationController,
        viewControllerForAdaptivePresentationStyle style: UIModalPresentationStyle
        ) -> UIViewController?
    {
        return nil // "keep existing"
    }
}

// MARK: UIAdaptivePresentationControllerDelegate

extension HelpViewerCoordinator: UIAdaptivePresentationControllerDelegate {
    func presentationControllerDidDismiss(_ presentationController: UIPresentationController) {
        didPressCancel(in: helpViewerVC)
    }
}
