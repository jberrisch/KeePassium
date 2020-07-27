//  KeePassium Password Manager
//  Copyright © 2018–2020 Andrei Popleteev <info@keepassium.com>
//
//  This program is free software: you can redistribute it and/or modify it
//  under the terms of the GNU General Public License version 3 as published
//  by the Free Software Foundation: https://www.gnu.org/licenses/).
//  For commercial licensing, please contact the author.

import KeePassiumLib

protocol AppIconPickerDelegate: class {
    func didSelectIcon(_ icon: AppIcon, in appIconPicker: AppIconPicker)
}

class AppIconPicker: UITableViewController {
    static let cellID = "IconCell"

    weak var delegate: AppIconPickerDelegate?
    
    private let appIcons: [AppIcon] = {
        switch BusinessModel.type {
        case .freemium:
            return [AppIcon.classicFree] + AppIcon.allCustom
        case .prepaid:
            return [AppIcon.classicPro, AppIcon.classicFree] + AppIcon.allCustom
        }
    }()
    
    // MARK: Data source
    override func numberOfSections(in tableView: UITableView) -> Int {
        return 1
    }
    
    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return appIcons.count
    }
    
    override func tableView(
        _ tableView: UITableView,
        cellForRowAt indexPath: IndexPath)
        -> UITableViewCell
    {
        let cell = tableView.dequeueReusableCell(
            withIdentifier: AppIconPicker.cellID,
            for: indexPath
        )
        let appIcon = appIcons[indexPath.row]
        cell.imageView?.image = UIImage(named: appIcon.asset)
        cell.textLabel?.text = appIcon.name
        let isCurrent = (UIApplication.shared.alternateIconName == appIcon.key)
        cell.accessoryType = isCurrent ? .checkmark : .none
        return cell
    }
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
    }
    
    // MARK: Action handlers
    
    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        let selectedIcon = appIcons[indexPath.row]
        delegate?.didSelectIcon(selectedIcon, in: self)
        tableView.reloadData()
    }
}
