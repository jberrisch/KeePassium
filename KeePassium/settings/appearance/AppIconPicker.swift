//  KeePassium Password Manager
//  Copyright © 2018–2020 Andrei Popleteev <info@keepassium.com>
//
//  This program is free software: you can redistribute it and/or modify it
//  under the terms of the GNU General Public License version 3 as published
//  by the Free Software Foundation: https://www.gnu.org/licenses/).
//  For commercial licensing, please contact the author.

import KeePassiumLib

struct AppIcon {
    // Human-readable name
    let name: String
    // Key name in Info.plist
    let key: String?
    // Key name in assets catalogue
    let asset: String
}
extension AppIcon {
    static let all: [AppIcon]  = [
        AppIcon.classicFree,
        AppIcon.atomWhite, AppIcon.atomBlue, AppIcon.atomBlack,
        AppIcon.elementBlue, AppIcon.elementBlack,
        AppIcon.asteriskBlue,
        AppIcon.calc, AppIcon.info, AppIcon.keepass
    ]
    
    static let classicFree = AppIcon(
        name: "KeePassium Classic", // don't localize
        key: "appicon-classic-free",
        asset: "appicon-classic-free-listitem")
    static let classicPro = AppIcon(
        name: "KeePassium Pro Classic", // don't localize
        key: "appicon-classic-pro",
        asset: "appicon-classic-pro-listitem")

    static let asteriskBlue = AppIcon(
        name: "Asterisk Blue",
        key: "appicon-asterisk-blue",
        asset: "appicon-asterisk-blue-listitem")
    static let atomBlack = AppIcon(
        name: "Atom Black",
        key: "appicon-atom-black",
        asset: "appicon-atom-black-listitem")
    static let atomBlue = AppIcon(
        name: "Atom Blue",
        key: "appicon-atom-blue",
        asset: "appicon-atom-blue-listitem")
    static let atomWhite = AppIcon(
        name: "Atom White",
        key: "appicon-atom-white",
        asset: "appicon-atom-white-listitem")
    static let calc = AppIcon(
        name: "Calculator",
        key: "appicon-calc",
        asset: "appicon-calc-listitem")
    static let elementBlue = AppIcon(
        name: "Element Blue",
        key: "appicon-element-blue",
        asset: "appicon-element-blue-listitem")
    static let elementBlack = AppIcon(
        name: "Element Black",
        key: "appicon-element-black",
        asset: "appicon-element-black-listitem")
    static let info = AppIcon(
        name: "Info",
        key: "appicon-info",
        asset: "appicon-info-listitem")
    static let keepass = AppIcon(
        name: "KeePass",
        key: "appicon-keepass",
        asset: "appicon-keepass-listitem")
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
        let selectedIcon = AppIcon.all[indexPath.row]
        delegate?.didSelectIcon(selectedIcon, in: self)
        tableView.reloadData()
    }
}
