//  KeePassium Password Manager
//  Copyright © 2020 Andrei Popleteev <info@keepassium.com>
//
//  This program is free software: you can redistribute it and/or modify it
//  under the terms of the GNU General Public License version 3 as published
//  by the Free Software Foundation: https://www.gnu.org/licenses/).
//  For commercial licensing, please contact the author.

import KeePassiumLib

class AppHistoryItemCell: UITableViewCell {
    fileprivate static let storyboardID = "LogItemCell"
    @IBOutlet weak var titleLabel: UILabel!
    @IBOutlet weak var detailLabel: UILabel!
}

class AppHistoryViewerVC: UITableViewController {
    /// The change log to display
    var appHistory: AppHistory?
    
    private let dateFormatter: DateFormatter = {
        let dateFormatter = DateFormatter()
        dateFormatter.dateStyle = .medium
        dateFormatter.timeStyle = .none
        return dateFormatter
    }()
    
    override func numberOfSections(in tableView: UITableView) -> Int {
        guard let appHistory = appHistory else {
            return 0
        }
        return appHistory.sections.count
    }
    
    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        guard let appHistory = appHistory else {
            return 0
        }
        return appHistory.sections[section].items.count
    }
    
    override func tableView(
        _ tableView: UITableView,
        titleForHeaderInSection section: Int)
        -> String?
    {
        guard let appHistory = appHistory else {
            return nil
        }
        let sectionInfo = appHistory.sections[section]
        let formattedDate = dateFormatter.string(from: sectionInfo.releaseDate)
        return "v\(sectionInfo.version) (\(formattedDate))"
    }
    
    override func tableView(_ tableView: UITableView, willDisplayHeaderView view: UIView, forSection section: Int) {
        // Overrides header capitalization
        if let headerView = view as? UITableViewHeaderFooterView {
            headerView.textLabel?.text = self.tableView(tableView, titleForHeaderInSection: section)
        }
    }
    override func tableView(
        _ tableView: UITableView,
        cellForRowAt indexPath: IndexPath)
        -> UITableViewCell
    {
        let cell = tableView.dequeueReusableCell(withIdentifier: AppHistoryItemCell.storyboardID)
            as! AppHistoryItemCell
        if let appHistory = appHistory {
            let item = appHistory.sections[indexPath.section].items[indexPath.row]
            setupCell(cell, item: item)
        }
        return cell
    }
    
    private func setupCell(_ cell: AppHistoryItemCell, item: AppHistory.Item) {
        cell.titleLabel.text = item.title
        switch item.type {
        case .none:
            cell.detailLabel.text = ""
            cell.accessoryView = nil
        case .free:
            cell.detailLabel.text = "Free" //TODO: localize
            cell.accessoryView = nil
        case .premium:
            cell.detailLabel.text = ""
            cell.accessoryView = PremiumBadgeAccessory()
        }
    }
}

private class PremiumBadgeAccessory: UIImageView {
    required init() {
        super.init(frame: CGRect(x: 0, y: 0, width: 25, height: 25))
        image = UIImage(asset: .premiumFeatureBadge)
        contentMode = .scaleAspectFill
        accessibilityLabel = "Premium"
    }
    required init?(coder aDecoder: NSCoder) {
        fatalError("Not implemented")
    }
}
