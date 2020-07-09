//  KeePassium Password Manager
//  Copyright © 2018–2020 Andrei Popleteev <info@keepassium.com>
//
//  This program is free software: you can redistribute it and/or modify it
//  under the terms of the GNU General Public License version 3 as published
//  by the Free Software Foundation: https://www.gnu.org/licenses/).
//  For commercial licensing, please contact the author.

import KeePassiumLib
import StoreKit

protocol PricingPlanPickerDelegate: class {
    func getAvailablePlans() -> [PricingPlan]
    func didPressCancel(in viewController: PricingPlanPickerVC)
    func didPressRestorePurchases(in viewController: PricingPlanPickerVC)
    func didPressBuy(product: SKProduct, in viewController: PricingPlanPickerVC)
}

class PricingPlanPickerVC: UIViewController {
    fileprivate let termsAndConditionsURL = URL(string: "https://keepassium.com/terms/app")!
    fileprivate let privacyPolicyURL = URL(string: "https://keepassium.com/privacy/app")!

    @IBOutlet weak var activityIndcator: UIActivityIndicatorView!
    @IBOutlet weak var statusLabel: UILabel!
    @IBOutlet weak var collectionView: UICollectionView!
    @IBOutlet weak var restorePurchasesButton: UIButton!
    @IBOutlet weak var termsButton: UIButton!
    @IBOutlet weak var privacyPolicyButton: UIButton!

    weak var delegate: PricingPlanPickerDelegate?
    
    private var pricingPlans = [PricingPlan]()
    
    /// Disables purchase buttons during operations with App Store
    var isPurchaseEnabled = false {
        didSet {
            refresh(animated: false)
        }
    }
    
    public static func create(delegate: PricingPlanPickerDelegate? = nil) -> PricingPlanPickerVC {
        let vc = PricingPlanPickerVC.instantiateFromStoryboard()
        vc.delegate = delegate
        return vc
    }
    
    // MARK: - VC life cycle
    
    public func refresh(animated: Bool) {
        restorePurchasesButton.isEnabled = isPurchaseEnabled
        
        if let unsortedPlans = delegate?.getAvailablePlans() {
            hideMessage()
            // show expensive first
            let sortedPlans = unsortedPlans.sorted {
                (plan1, plan2) -> Bool in
                let isP1BeforeP2 = plan1.price.doubleValue < plan2.price.doubleValue
                return isP1BeforeP2
            }
            self.pricingPlans = sortedPlans
        }
        
        if animated {
            collectionView.reloadSections([0])
        } else {
            collectionView.reloadData()
        }
    }
    
    // MARK: - Error message routines
    
    public func showMessage(_ message: String) {
        statusLabel.text = message
        activityIndcator.isHidden = true
        UIView.animate(withDuration: 0.3) {
            self.statusLabel.isHidden = false
        }
    }
    
    public func hideMessage() {
        UIView.animate(withDuration: 0.3) {
            self.activityIndcator.isHidden = true
            self.statusLabel.isHidden = true
        }
    }
    
    // MARK: - Purchasing
    
    /// Locks/unlocks user interaction during purchase communication with AppStore.
    ///
    /// - Parameter isPurchasing: true when purchasing, false once done.
    public func setPurchasing(_ isPurchasing: Bool) {
        isPurchaseEnabled = !isPurchasing
        if isPurchasing {
            showMessage(LString.statusContactingAppStore)
            UIView.animate(withDuration: 0.3) {
                self.activityIndcator.isHidden = false
            }
        } else {
            hideMessage()
            UIView.animate(withDuration: 0.3) {
                self.activityIndcator.isHidden = true
            }
        }
    }
    
    // MARK: - Actions
    
    @IBAction func didPressCancel(_ sender: Any) {
        delegate?.didPressCancel(in: self)
    }
    
    @IBAction func didPressRestorePurchases(_ sender: Any) {
        delegate?.didPressRestorePurchases(in: self)
    }
        
    @IBAction func didPressTerms(_ sender: Any) {
        AppGroup.applicationShared?.open(termsAndConditionsURL, options: [:])
    }
    @IBAction func didPressPrivacyPolicy(_ sender: Any) {
        AppGroup.applicationShared?.open(privacyPolicyURL, options: [:])
    }
}

// MARK: UICollectionViewDataSource
extension PricingPlanPickerVC: UICollectionViewDataSource {
    func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
        return pricingPlans.count
    }
    
    func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        let cell = collectionView
            .dequeueReusableCell(
                withReuseIdentifier: PricingPlanCollectionCell.storyboardID,
                for: indexPath)
            as! PricingPlanCollectionCell
        cell.clipsToBounds = false
        cell.layer.masksToBounds = false
        cell.layer.shadowColor = UIColor.black.cgColor
        cell.layer.shadowRadius = 5
        cell.layer.shadowOpacity = 0.5
        cell.layer.shadowOffset = CGSize(width: 0.0, height: 3.0)
        
        cell.isPurchaseEnabled = self.isPurchaseEnabled
        cell.pricingPlan = pricingPlans[indexPath.item]
        cell.delegate = self
        return cell
    }
}

// MARK: - PricingPlanCollectionCellDelegate
extension PricingPlanPickerVC: PricingPlanCollectionCellDelegate {
    func didPressPurchaseButton(in cell: PricingPlanCollectionCell, with pricingPlan: PricingPlan) {
        guard let realPricingPlan = pricingPlan as? RealPricingPlan else {
            assert(pricingPlan.isFree)
            delegate?.didPressCancel(in: self)
            return
        }
        delegate?.didPressBuy(product: realPricingPlan.product, in: self)
    }
    
    func didPressPerpetualFallbackDetail(
        in cell: PricingPlanCollectionCell,
        with pricingPlan: PricingPlan)
    {
        //TODO
    }
}
