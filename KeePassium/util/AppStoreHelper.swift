//  KeePassium Password Manager
//  Copyright © 2018–2019 Andrei Popleteev <info@keepassium.com>
// 
//  This program is free software: you can redistribute it and/or modify it
//  under the terms of the GNU General Public License version 3 as published
//  by the Free Software Foundation: https://www.gnu.org/licenses/).
//  For commercial licensing, please contact the author.

import UIKit

class AppStoreHelper {
    // App ID in AppStore
    static public let proVersionID = 1481781647
    static public let freemiumVersionID = 1435127111
    
    #if PREPAID_VERSION
    static private let appStoreID = AppStoreHelper.proVersionID
    #else
    static private let appStoreID = AppStoreHelper.freemiumVersionID
    #endif

    /// Opens AppStore page of the given app (by default, the current one)
    static func openInAppStore(appID: Int = appStoreID) {
        guard let url = URL(string: "itms-apps://apps.apple.com/app/id\(appID)") else {
            assertionFailure("Invalid AppStore URL")
            return
        }
        if UIApplication.shared.canOpenURL(url) {
            UIApplication.shared.open(url, options: [:], completionHandler: nil)
        }
    }

    /// Opens AppStore page for reviewing the app
    static func writeReview() {
        guard let url = URL(string: "itms-apps://apps.apple.com/app/id\(appStoreID)?action=write-review") else {
            assertionFailure("Invalid AppStore URL")
            return
        }
        if UIApplication.shared.canOpenURL(url) {
            UIApplication.shared.open(url, options: [:], completionHandler: nil)
        }
    }

    #if MAIN_APP
    static func openSubscriptionManagement() {
        guard let url = URL(string: "itms-apps://apps.apple.com/account/subscriptions") else {
            assertionFailure();
            return
        }
        let application = UIApplication.shared
        if application.canOpenURL(url) {
            // open Manage Subscriptions page in AppStore
            application.open(url, options: [:])
        }
    }
    #endif
}
