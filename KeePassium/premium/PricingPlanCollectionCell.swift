//  KeePassium Password Manager
//  Copyright © 2018–2020 Andrei Popleteev <info@keepassium.com>
//
//  This program is free software: you can redistribute it and/or modify it
//  under the terms of the GNU General Public License version 3 as published
//  by the Free Software Foundation: https://www.gnu.org/licenses/).
//  For commercial licensing, please contact the author.

import KeePassiumLib
import StoreKit


// MARK: - Custom table cells

class PricingPlanTitleCell: UITableViewCell {
    static let storyboardID = "TitleCell"
    
    @IBOutlet weak var titleLabel: UILabel!
    @IBOutlet weak var priceLabel: UILabel!
    @IBOutlet weak var priceNoteLabel: UILabel!
}

protocol PricingPlanConditionCellDelegate: class {
    func didPressDetailButton(in cell: PricingPlanConditionCell)
}
class PricingPlanConditionCell: UITableViewCell {
    static let storyboardID = "ConditionCell"
    weak var delegate: PricingPlanConditionCellDelegate?
    
    @IBOutlet weak var checkmarkImage: UIImageView!
    @IBOutlet weak var titleLabel: UILabel!
    @IBOutlet weak var detailButton: UIButton!
    
    @IBAction func didPressDetailButton(_ sender: UIButton) {
        delegate?.didPressDetailButton(in: self)
    }
}

class PricingPlanBenefitCell: UITableViewCell {
    static let storyboardID = "BenefitCell"
    
    @IBOutlet weak var iconView: UIImageView!
    @IBOutlet weak var titleLabel: UILabel!
    @IBOutlet weak var subtitleLabel: UILabel!
}

// MARK: - PricingPlanCollectionCell

protocol PricingPlanCollectionCellDelegate: class {
    func didPressPurchaseButton(in cell: PricingPlanCollectionCell, with pricePlan: PricePlan)
    func didPressPerpetualFallbackDetail(in cell: PricingPlanCollectionCell, with pricePlan: PricePlan)
}

/// Represents one page/tile in the price plan picker
class PricingPlanCollectionCell: UICollectionViewCell {
    static let storyboardID = "PricingPlanCollectionCell"
    private enum Section: Int {
        static let allValues = [Section]([.title, .conditions, .premiumFeatures])
        case title = 0
        case conditions = 1
        case benefits = 2
    }
    
    @IBOutlet weak var tableView: UITableView!
    @IBOutlet weak var purchaseButton: UIButton!
    @IBOutlet weak var footerLabel: UILabel!
    
    weak var delegate: PricingPlanCollectionCellDelegate?
    /// Enables/disables the purchase button
    var isPurchaseEnabled: Bool {
        didSet {
            refresh()
        }
    }
    var pricePlan: PricePlan! {
        didSet { refresh() }
    }
    
    // MARK: VC life cycle
    
    override func awakeFromNib() {
        super.awakeFromNib()
        
        tableView.delegate = self
        tableView.rowHeight = UITableView.automaticDimension
        tableView.estimatedRowHeight = 44
    }
    
    func refresh() {
        guard pricePlan != nil else { return }
        if pricePlan.isFree {
            purchaseButton.borderColor = .actionTint
            purchaseButton.borderWidth = 1
            purchaseButton.backgroundColor = .actionText
            purchaseButton.tintColor = .actionTint
        } else {
            purchaseButton.borderColor = .actionTint
            purchaseButton.borderWidth = 1
            purchaseButton.backgroundColor = .actionTint
            purchaseButton.tintColor = .actionText
        }
        purchaseButton.setTitle(pricePlan.callForAction, for: .normal)
        purchaseButton.isEnabled = isPurchaseEnabled
        footerLabel.text = pricePlan.cfaSubtitle
        tableView.dataSource = self
        tableView.reloadData()
    }
    
    // MARK: Actions
    
    @IBAction func didPressPurchaseButton(_ sender: Any) {
        delegate?.didPressPurchaseButton(in: self, with: pricePlan)
    }
}

// MARK: UITableViewDelegate

extension PricingPlanCollectionCell: UITableViewDelegate {
    func tableView(_ tableView: UITableView, heightForHeaderInSection section: Int) -> CGFloat {
        switch Section(rawValue: section)! {
        case .title:
            return 0.1 // no header
        case .conditions:
            return 0.1 // no header
        case .benefits:
            return UITableView.automaticDimension
        }
    }
    func tableView(_ tableView: UITableView, heightForFooterInSection section: Int) -> CGFloat {
        switch Section(rawValue: section)! {
        case .title:
            return 0.1 // no footer
        case .conditions:
            return 8 // just a small gap
        case .benefits:
            return UITableView.automaticDimension
        }
    }
}

// MARK: UITableViewDataSource

extension PricingPlanCollectionCell: UITableViewDataSource {
    func numberOfSections(in tableView: UITableView) -> Int {
        return Section.allValues.count
    }
    
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        switch Section(rawValue: section)! {
        case .title:
            return 1
        case .conditions:
            return pricePlan.conditions.count
        case .benefits:
            return pricePlan.benefits.count
        }
    }
    
    func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        guard Section(rawValue: section)! == .benefits else {
            return nil
        }
        
        if pricePlan.isFree {
            return LString.premiumWhatYouMiss
        } else {
            return LString.premiumWhatYouGet
        }
    }
    
    func tableView(_ tableView: UITableView, titleForFooterInSection section: Int) -> String? {
        guard Section(rawValue: section)! == .benefits else {
            return nil
        }
        return pricePlan.smallPrint
    }
    
    // MARK: Cell setup
    
    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        switch Section(rawValue: indexPath.section)! {
        case .title:
            return dequeueTitleCell(tableView, cellForRowAt: indexPath)
        case .conditions:
            return dequeueConditionCell(tableView, cellForRowAt: indexPath)
        case .benefits:
            return dequeueBenefitCell(tableView, cellForRowAt: indexPath)
        }
    }
    
    func dequeueTitleCell(
        _ tableView: UITableView,
        cellForRowAt indexPath: IndexPath)
        -> PricingPlanTitleCell
    {
        let cell = tableView
            .dequeueReusableCell(withIdentifier: PricingPlanTitleCell.storyboardID, for: indexPath)
            as! PricingPlanTitleCell
        cell.titleLabel?.text = nil //pricePlan?.title
        cell.priceLabel?.text = pricePlan?.priceString
        cell.priceNoteLabel?.text = pricePlan.pricePeriodString
        return cell
    }
    
    func dequeueConditionCell(
        _ tableView: UITableView,
        cellForRowAt indexPath: IndexPath)
        -> PricingPlanConditionCell
    {
        let condition = pricePlan.conditions[indexPath.row]
        let cell = tableView
            .dequeueReusableCell(withIdentifier: PricingPlanConditionCell.storyboardID, for: indexPath)
            as! PricingPlanConditionCell
        cell.delegate = self
        cell.titleLabel?.text = condition.localizedTitle
        if condition.isIncluded {
            cell.checkmarkImage?.image = UIImage(asset: .premiumConditionCheckedListitem)
            cell.checkmarkImage?.tintColor = .primaryText
            cell.titleLabel.textColor = .primaryText
        } else {
            cell.checkmarkImage?.image = UIImage(asset: .premiumConditionUncheckedListitem)
            cell.checkmarkImage?.tintColor = .disabledText
            cell.titleLabel.textColor = .disabledText
        }
        
        switch condition.moreInfo {
        case .none:
            cell.detailButton.isHidden = true
        case .perpetualFallback:
            cell.detailButton.isHidden = false
        }
        return cell
    }
    
    func dequeueBenefitCell(
        _ tableView: UITableView,
        cellForRowAt indexPath: IndexPath)
        -> PricingPlanBenefitCell
    {
        let feature = pricePlan.benefits[indexPath.row]
        let cell = tableView
            .dequeueReusableCell(withIdentifier: PricingPlanBenefitCell.storyboardID, for: indexPath)
            as! PricingPlanBenefitCell
        cell.titleLabel?.text = feature.title
        cell.subtitleLabel?.text = feature.description
        if let imageAsset = feature.image {
            cell.iconView?.image = UIImage(asset: imageAsset)
        } else {
            cell.iconView.image = nil
        }

        if pricePlan.isFree {
            cell.titleLabel.textColor = .disabledText
            cell.iconView?.tintColor = .disabledText
        } else {
            cell.titleLabel.textColor = .primaryText
            cell.iconView?.tintColor = .actionTint
        }
        return cell
    }
}

// MARK: PricingPlanConditionCellDelegate
extension PricingPlanCollectionCell: PricingPlanConditionCellDelegate {
    func didPressDetailButton(in cell: PricingPlanConditionCell) {
        delegate?.didPressPerpetualFallbackDetail(in: self, with: pricePlan)
    }
}
