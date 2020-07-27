//  KeePassium Password Manager
//  Copyright © 2018–2020 Andrei Popleteev <info@keepassium.com>
//
//  This program is free software: you can redistribute it and/or modify it
//  under the terms of the GNU General Public License version 3 as published
//  by the Free Software Foundation: https://www.gnu.org/licenses/).
//  For commercial licensing, please contact the author.

import KeePassiumLib

struct AppIcon: Equatable {
    // Human-readable name. Don't localize because the name does not matter.
    let name: String
    // Key name in Info.plist
    let key: String?
    // Key name in assets catalogue
    let asset: String
}
extension AppIcon {
    static let allCustom: [AppIcon]  = [
        AppIcon.atomWhite, AppIcon.atomBlue, AppIcon.atomBlack,
        AppIcon.calc, AppIcon.keepass, AppIcon.info, 
    ]
    
    static let classicFree = AppIcon(
        name: "KeePassium Classic",
        key: "appicon-classic-free",
        asset: "appicon-classic-free-listitem")
    static let classicPro = AppIcon(
        name: "KeePassium Pro Classic",
        key: "appicon-classic-pro",
        asset: "appicon-classic-pro-listitem")
    
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
    static let info = AppIcon(
        name: "Info",
        key: "appicon-info",
        asset: "appicon-info-listitem")
    static let keepass = AppIcon(
        name: "KeePass",
        key: "appicon-keepass",
        asset: "appicon-keepass-listitem")
    
    public static func isPremium(_ icon: AppIcon) -> Bool {
        return icon != classicFree
    }
}
