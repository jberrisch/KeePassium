//  KeePassium Password Manager
//  Copyright © 2018–2020 Andrei Popleteev <info@keepassium.com>
//
//  This program is free software: you can redistribute it and/or modify it
//  under the terms of the GNU General Public License version 3 as published
//  by the Free Software Foundation: https://www.gnu.org/licenses/).
//  For commercial licensing, please contact the author.

import KeePassiumLib

struct AppIcon {
    let name: String
    let assetName: String?
}
extension AppIcon {
    static let all: [AppIcon]  = [AppIcon.defaultFree, AppIcon.defaultPro]
    
    static let defaultFree = AppIcon(
        name: "KeePassium", // don't localize
        assetName: nil)
    static let defaultPro = AppIcon(
        name: "KeePassium Pro", // don't localize
        assetName: "app-icon-pro")
}

// MARK: -

protocol AppIconPickerDelegate: class {
    func didSelectIcon(_ icon: AppIcon, in appIconPicker: AppIconPicker)
}

class AppIconPicker: UITableViewController {
    static let cellID = "IconCell"

    weak var delegate: AppIconPickerDelegate?
    
    // MARK: Data source
    override func numberOfSections(in tableView: UITableView) -> Int {
        return 1
    }
    
    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return AppIcon.all.count
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
        let appIcon = AppIcon.all[indexPath.row]
//        cell.imageView?.image = UIImage(named: appIcon.assetName)
        cell.textLabel?.text = appIcon.name
        return cell
    }
    
    // MARK: Action handlers
    
    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        let selectedIcon = AppIcon.all[indexPath.row]
        delegate?.didSelectIcon(selectedIcon, in: self)
    }
}
