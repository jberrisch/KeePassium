//  KeePassium Password Manager
//  Copyright © 2018–2019 Andrei Popleteev <info@keepassium.com>
// 
//  This program is free software: you can redistribute it and/or modify it
//  under the terms of the GNU General Public License version 3 as published
//  by the Free Software Foundation: https://www.gnu.org/licenses/).
//  For commercial licensing, please contact the author.

import UIKit
import KeePassiumLib
import StoreKit

protocol PremiumCoordinatorDelegate: class {
    /// The coordinator has finished work (called regardless the outcome).
    func didFinish(_ premiumCoordinator: PremiumCoordinator)
}

class PremiumCoordinator: NSObject {
    
    weak var delegate: PremiumCoordinatorDelegate?
    
    /// Parent VC which will present our modal form
    let presentingViewController: UIViewController
    
    private let premiumManager: PremiumManager
    private let navigationController: UINavigationController
    private let planPicker: PricingPlanPickerVC
    
    private var availablePricingPlans = [PricingPlan]()
    private var isProductsRefreshed: Bool = false
    
    init(presentingViewController: UIViewController) {
        self.premiumManager = PremiumManager.shared
        self.presentingViewController = presentingViewController
        planPicker = PricingPlanPickerVC.create()
        navigationController = UINavigationController(rootViewController: planPicker)
        super.init()

        navigationController.modalPresentationStyle = .formSheet
        navigationController.presentationController?.delegate = self

        planPicker.delegate = self
    }
    
    func start(tryRestoringPurchasesFirst: Bool=false) {
        premiumManager.delegate = self
        self.presentingViewController.present(navigationController, animated: true, completion: nil)
        
        // fetch available purchase options from AppStore
        UIApplication.shared.isNetworkActivityIndicatorVisible = true
        
        // disable manual "Restore Purchases" while loading products,
        // because this might interfere with the workflow.
        planPicker.isPurchaseEnabled = false
        
        if tryRestoringPurchasesFirst {
            restorePurchases()
        } else {
            refreshAvailableProducts()
        }
    }
    
    fileprivate func restorePurchases() {
        premiumManager.restorePurchases()
    }
    
    fileprivate func refreshAvailableProducts() {
        premiumManager.requestAvailableProducts() {
            [weak self] (products, error) in
            UIApplication.shared.isNetworkActivityIndicatorVisible = false
            guard let self = self else { return }
            
            // we're done, can restore purchases now
            self.planPicker.isPurchaseEnabled = true
            
            guard error == nil else {
                self.planPicker.showMessage(error!.localizedDescription)
                return
            }
            
            guard let products = products, products.count > 0 else {
                let message = LString.errorNoPurchasesAvailable
                self.planPicker.showMessage(message)
                return
            }
            var availablePlans = products.compactMap { (product) in
                return PricingPlanFactory.make(for: product)
            }
            availablePlans.append(FreePricingPlan()) // free tier is always available
            self.isProductsRefreshed = true
            self.availablePricingPlans = availablePlans
            self.planPicker.refresh(animated: true)
            self.planPicker.scrollToDefaultPlan(animated: false)
        }
    }
    
    func setPurchasing(_ isPurchasing: Bool) {
        planPicker.setPurchasing(isPurchasing)
    }
    
    func finish(animated: Bool, completion: (() -> Void)?) {
        navigationController.dismiss(animated: animated) { [weak self] in
            guard let self = self else { return }
            self.delegate?.didFinish(self)
        }
    }
}

// MARK: - PricingPlanPickerDelegate
extension PremiumCoordinator: PricingPlanPickerDelegate {
    func getAvailablePlans() -> [PricingPlan] {
        return availablePricingPlans
    }

    func didPressBuy(product: SKProduct, in viewController: PricingPlanPickerVC) {
        setPurchasing(true)
        premiumManager.purchase(product)
    }
    
    func didPressCancel(in viewController: PricingPlanPickerVC) {
        premiumManager.delegate = nil
        finish(animated: true, completion: nil)
    }
    
    func didPressRestorePurchases(in viewController: PricingPlanPickerVC) {
        setPurchasing(true)
        restorePurchases()
    }
}

// MARK: - PremiumManagerDelegate
extension PremiumCoordinator: PremiumManagerDelegate {
    func purchaseStarted(in premiumManager: PremiumManager) {
        planPicker.showMessage(LString.statusPurchasing)
        setPurchasing(true)
    }
    
    func purchaseSucceeded(_ product: InAppProduct, in premiumManager: PremiumManager) {
        setPurchasing(false)
        SKStoreReviewController.requestReview()
    }
    
    func purchaseDeferred(in premiumManager: PremiumManager) {
        setPurchasing(false)
        planPicker.showMessage(LString.statusDeferredPurchase)
    }
    
    func purchaseFailed(with error: Error, in premiumManager: PremiumManager) {
        planPicker.showErrorAlert(error)
        setPurchasing(false)
    }
    
    func purchaseCancelledByUser(in premiumManager: PremiumManager) {
        setPurchasing(false)
        // keep planPicker on screen, otherwise might look like something crashed
    }
    
    func purchaseRestoringFinished(in premiumManager: PremiumManager) {
        setPurchasing(false)
        switch premiumManager.status {
        case .subscribed:
            // successfully restored
            let successAlert = UIAlertController(
                title: LString.titlePurchaseRestored,
                message: LString.purchaseRestored,
                preferredStyle: .alert)
            let okAction = UIAlertAction(title: LString.actionOK, style: .default) {
                [weak self] _ in
                self?.finish(animated: true, completion: nil)
            }
            successAlert.addAction(okAction)
            planPicker.present(successAlert, animated: true, completion: nil)
        default:
            // sorry, no previous purchase could be restored
            if !isProductsRefreshed {
                // start fetching available products while showing a "Sorry" alert
                refreshAvailableProducts()
            }
            let notRestoredAlert = UIAlertController.make(
                title: LString.titleRestorePurchaseError,
                message: LString.errorNoPreviousPurchaseToRestore,
                cancelButtonTitle: LString.actionOK)
            planPicker.present(notRestoredAlert, animated: true, completion: nil)
            // keep premiumVC on screen for eventual purchase
        }
    }
}

// MARK: - UIAdaptivePresentationControllerDelegate
extension PremiumCoordinator: UIAdaptivePresentationControllerDelegate {
    func presentationControllerDidDismiss(_ presentationController: UIPresentationController) {
        didPressCancel(in: planPicker)
    }
}
