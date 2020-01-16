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
        .canUseBiometricAppLock, // enforced
        .canUseLongDatabaseTimeouts, // enforced
        .canPreviewAttachments, // enforced
        .canUseHardwareKeys
    ]
    
    /// Can unlock any added database (otherwise only one, with olders modification date)
    case canUseMultipleDatabases = 0

    /// Can enable biometric AppLock in settings (otherwise passcode-only)
    case canUseBiometricAppLock = 1
    
    /// Can set Database Timeout to values over 2 hours (otherwise only short delays)
    case canUseLongDatabaseTimeouts = 2
    
    /// Can preview attached files by one tap (otherwise, opens a Share sheet)
    case canPreviewAttachments = 3
    
    /// Can open databases protected with hardware keys
    case canUseHardwareKeys = 4
    
    /// Defines whether this premium feature may be used with given premium status.
    ///
    /// - Parameter status: status to check availability against
    /// - Returns: true iff the feature can be used
    public func isAvailable(in status: PremiumManager.Status) -> Bool {
        switch self {
        case .canUseMultipleDatabases:
            return status == .subscribed || status == .lapsed
        case .canUseBiometricAppLock:
            return status != .freeHeavyUse
        case .canUseLongDatabaseTimeouts:
            return status == .subscribed || status == .lapsed
        case .canPreviewAttachments:
            return status != .freeHeavyUse
        case .canUseHardwareKeys:
            return status == .subscribed || status == .lapsed
        }
    }
}
