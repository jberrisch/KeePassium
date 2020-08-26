//  KeePassium Password Manager
//  Copyright © 2018–2019 Andrei Popleteev <info@keepassium.com>
// 
//  This program is free software: you can redistribute it and/or modify it
//  under the terms of the GNU General Public License version 3 as published
//  by the Free Software Foundation: https://www.gnu.org/licenses/).
//  For commercial licensing, please contact the author.

/// Features reserved for the premium version.
public enum PremiumFeature: Int {
    public static let all: [PremiumFeature] = [
        .canUseMultipleDatabases, // enforced
        .canUseLongDatabaseTimeouts, // enforced
        .canPreviewAttachments, // enforced
        .canUseHardwareKeys,    // enforced
        .canKeepMasterKeyOnDatabaseTimeout, // enforced
        .canChangeAppIcon,
    ]
    
    /// Can unlock any added database (otherwise only one, with olders modification date)
    case canUseMultipleDatabases = 0

    /// Can set Database Timeout to values over 2 hours (otherwise only short delays)
    case canUseLongDatabaseTimeouts = 2
    
    /// Can preview attached files by one tap (otherwise, opens a Share sheet)
    case canPreviewAttachments = 3
    
    /// Can open databases protected with hardware keys
    case canUseHardwareKeys = 4
    
    /// Can keep stored master keys on database timeout
    case canKeepMasterKeyOnDatabaseTimeout = 5
    
    case canChangeAppIcon = 6
    
    /// Defines whether this premium feature may be used with given premium status.
    ///
    /// - Parameter status: status to check availability against
    /// - Returns: true iff the feature can be used
    public func isAvailable(in status: PremiumManager.Status, fallbackDate: Date?) -> Bool {
        let isEntitled = status == .subscribed ||
            status == .lapsed ||
            wasAvailable(before: fallbackDate)
        
        switch self {
        case .canUseMultipleDatabases,
             .canUseLongDatabaseTimeouts,
             .canUseHardwareKeys,
             .canKeepMasterKeyOnDatabaseTimeout,
             .canChangeAppIcon:
            return isEntitled
        case .canPreviewAttachments:
            return isEntitled || (status != .freeHeavyUse)
        }
    }
    
    /// Returns `true` if the premium feature was available before the given fallback date.
    /// If there is no fallback date, always return false.
    private func wasAvailable(before fallbackDate: Date?) -> Bool {
        guard let date = fallbackDate else {
            return false
        }
        switch self {
        case .canUseMultipleDatabases:
            return date > Date(iso8601string: "2019-07-31T00:00:00Z")!
        case .canUseLongDatabaseTimeouts:
            return date > Date(iso8601string: "2019-07-31T00:00:00Z")!
        case .canPreviewAttachments:
            return date > Date(iso8601string: "2019-07-31T00:00:00Z")!
        case .canUseHardwareKeys:
            return date > Date(iso8601string: "2020-01-14T00:00:00Z")!
        case .canKeepMasterKeyOnDatabaseTimeout:
            return date > Date(iso8601string: "2020-07-14T00:00:00Z")!
        case .canChangeAppIcon:
            return date > Date(iso8601string: "2020-08-04T00:00:00Z")!
        }
    }
}
