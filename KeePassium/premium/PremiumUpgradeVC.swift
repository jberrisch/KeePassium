//  KeePassium Password Manager
//  Copyright © 2018–2020 Andrei Popleteev <info@keepassium.com>
//
//  This program is free software: you can redistribute it and/or modify it
//  under the terms of the GNU General Public License version 3 as published
//  by the Free Software Foundation: https://www.gnu.org/licenses/).
//  For commercial licensing, please contact the author.

import KeePassiumLib
import StoreKit

protocol PremiumUpgradeDelegate: class {
    func getAvailableProducts() -> [SKProduct]
    func didPressCancel(in viewController: PremiumUpgradeVC)
    func didPressRestorePurchases(in viewController: PremiumUpgradeVC)
    func didPressBuy(product: SKProduct, in viewController: PremiumUpgradeVC)
}

class PremiumUpgradeVC: UIViewController {
    fileprivate let termsAndConditionsURL = URL(string: "https://keepassium.com/terms/app")!
    fileprivate let privacyPolicyURL = URL(string: "https://keepassium.com/privacy/app")!

    @IBOutlet weak var activityIndcator: UIActivityIndicatorView!
    @IBOutlet weak var statusLabel: UILabel!
    @IBOutlet weak var restorePurchasesButton: UIButton!
    @IBOutlet weak var termsButton: UIButton!
    @IBOutlet weak var privacyPolicyButton: UIButton!

    
    weak var delegate: PremiumUpgradeDelegate?
    
    var allowRestorePurchases: Bool = true {
        didSet {
            guard isViewLoaded else { return }
            restorePurchasesButton.isHidden = !allowRestorePurchases
        }
    }
    public static func create(
        delegate: PremiumDelegate? = nil
    ) -> PremiumVC
    {
        let vc = PremiumVC.instantiateFromStoryboard()
        vc.delegate = delegate
        return vc
    }
    
    // MARK: - VC life cycle
    
    public func refresh(animated: Bool) {
        guard let products = delegate?.getAvailableProducts(),
            !products.isEmpty
            else { return }
        setAvailableProducts(products, animated: animated)
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
        //TODO
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

// MARK: - PricingPlanCollectionLayout

/// Provides page-like scrolling and centering on each cell
class PricingPlanCollectionLayout: UICollectionViewFlowLayout {
    private var previousOffset: CGFloat = 0
    private var currentPage: Int = 0
    
    required init?(coder: NSCoder) {
        super.init(coder: coder)
        scrollDirection = .horizontal
        collectionView?.decelerationRate = .fast
    }
    
    override func targetContentOffset(
        forProposedContentOffset proposedContentOffset: CGPoint,
        withScrollingVelocity velocity: CGPoint)
        -> CGPoint
    {
        guard let collectionView = collectionView else {
            return super.targetContentOffset(
                forProposedContentOffset: proposedContentOffset,
                withScrollingVelocity: velocity)
        }
        
        let bounds = collectionView.bounds
        let targetRect = CGRect(
            x: proposedContentOffset.x,
            y: 0,
            width: bounds.width,
            height: bounds.height)
        let horizontalCenter = proposedContentOffset.x + (bounds.width / 2.0)
        
        var offsetAdjustment = CGFloat.greatestFiniteMagnitude
        super.layoutAttributesForElements(in: targetRect)?.forEach { layoutAtributes in
            let itemHorizontalCenter = layoutAtributes.center.x;
            if (abs(itemHorizontalCenter - horizontalCenter) < abs(offsetAdjustment)) {
                offsetAdjustment = itemHorizontalCenter - horizontalCenter
            }
        }
        return CGPoint(x: proposedContentOffset.x + offsetAdjustment, y: proposedContentOffset.y);
    }
}

