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
    
    // MARK: VC life cycle
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        collectionView.dataSource = self
        collectionView.delegate = self
        collectionView.decelerationRate = .fast
        
        statusLabel.text = LString.statusContactingAppStore
        activityIndcator.isHidden = false
    }
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        refresh(animated: animated)
    }
    
    override func viewWillLayoutSubviews() {
        super.viewWillLayoutSubviews()
        collectionView?.collectionViewLayout.invalidateLayout()
    }
    
    public func refresh(animated: Bool) {
        guard isViewLoaded else { return }
        restorePurchasesButton.isEnabled = isPurchaseEnabled
        
        if let unsortedPlans = delegate?.getAvailablePlans(), unsortedPlans.count > 0 {
            // show expensive first
            let sortedPlans = unsortedPlans.sorted {
                (plan1, plan2) -> Bool in
                let isP1BeforeP2 = plan1.price.doubleValue < plan2.price.doubleValue
                return isP1BeforeP2
            }
            self.pricingPlans = sortedPlans
            hideMessage()
        }

        collectionView.reloadData()
    }
    
    // MARK: Error message routines
    
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
    
    // MARK: Purchasing
    
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
    
    // MARK: Actions
    
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

// MARK: - UICollectionViewDelegateFlowLayout
extension PricingPlanPickerVC: UICollectionViewDelegateFlowLayout {
    func collectionView(
        _ collectionView: UICollectionView,
        layout collectionViewLayout: UICollectionViewLayout,
        sizeForItemAt indexPath: IndexPath)
        -> CGSize
    {
        let desiredAspectRatio = CGFloat(1.69)
        let frameWidth = collectionView.frame.width
        let width = min(
            max(350, frameWidth * 0.6), // fill a narrow screen, but only a fraction of a wide screen
            frameWidth - 32) // leave some margins to see adjacent cells
                             // 32 = (2 * purchase button margin)
                             //     These margins hide the purchase buttons in adjacent cells.
        
        let height = min(
            max(width * desiredAspectRatio, collectionView.frame.height * 0.6),
            collectionView.frame.height - 30)
            // 0.6 — so that there is only one row on the screen
        return CGSize(width: width, height: height)
    }
    
    func collectionView(
        _ collectionView: UICollectionView,
        layout collectionViewLayout: UICollectionViewLayout,
        referenceSizeForHeaderInSection section: Int)
        -> CGSize
    {
        let cellSize = self.collectionView(
            collectionView,
            layout: collectionViewLayout,
            sizeForItemAt: IndexPath(item: 0, section: section)
        )
        // Left offset of the first cell
        let headerSize = (collectionView.frame.width - cellSize.width) / 2
        return CGSize(width: headerSize, height: 0)
    }
    
    func collectionView(
        _ collectionView: UICollectionView,
        layout collectionViewLayout: UICollectionViewLayout,
        referenceSizeForFooterInSection section: Int)
        -> CGSize
    {
        let cellSize = self.collectionView(
            collectionView,
            layout: collectionViewLayout,
            sizeForItemAt: IndexPath(item: 0, section: section)
        )
        // Right offset of the last cell
        let footerSize = (collectionView.frame.width - cellSize.width) / 2
        return CGSize(width: footerSize, height: 0)
    }
    
    func collectionView(
        _ collectionView: UICollectionView,
        layout collectionViewLayout: UICollectionViewLayout,
        minimumInteritemSpacingForSectionAt section: Int)
        -> CGFloat
    {
        return 0
    }
    
    func collectionView(
        _ collectionView: UICollectionView,
        layout collectionViewLayout: UICollectionViewLayout,
        minimumLineSpacingForSectionAt section: Int)
        -> CGFloat
    {
        let headerSize = self.collectionView(
            collectionView,
            layout: collectionViewLayout,
            referenceSizeForHeaderInSection: section
        )
        return 0.5 * headerSize.width
    }
}

// MARK: - UICollectionViewDataSource
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
