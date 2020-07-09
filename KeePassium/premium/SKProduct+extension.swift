//  KeePassium Password Manager
//  Copyright © 2018–2019 Andrei Popleteev <info@keepassium.com>
// 
//  This program is free software: you can redistribute it and/or modify it
//  under the terms of the GNU General Public License version 3 as published
//  by the Free Software Foundation: https://www.gnu.org/licenses/).
//  For commercial licensing, please contact the author.

import StoreKit
import UIKit

extension SKProduct {
    
    /// Price of the product in local currency.
    /// In case of locale trouble, falls back to number-only result.
    var localizedPrice: String {
        let formatter = NumberFormatter()
        formatter.locale = priceLocale
        formatter.numberStyle = .currency
        return formatter.string(from: price) ?? String(format: "%.2f", price)
    }
    
    /// Number of days in the trial period (if any).)
    var trialDays: Int? {
        guard #available(iOS 11.2, *),
            let period = introductoryPrice?.subscriptionPeriod else { return nil }
        switch period.unit {
        case .day:
            return period.numberOfUnits
        case .week:
            return 7 * period.numberOfUnits
        case .month:
            return 31 * period.numberOfUnits
        case .year:
            return 365 * period.numberOfUnits
        }
    }
    
    /// Returns string describing the duration of the trial period (if any).
    /// For example: "90 days".
    var localizedTrialDuration: String? {
        guard let trialDays = self.trialDays else { return nil }
        
        var dateComponents = DateComponents()
        dateComponents.setValue(trialDays, for: .day)
        
        let timeFormatter = DateComponentsFormatter()
        timeFormatter.allowedUnits = [.day]
        timeFormatter.unitsStyle = .full
        timeFormatter.maximumUnitCount = 1
        timeFormatter.formattingContext = .middleOfSentence
        timeFormatter.zeroFormattingBehavior = .dropAll
        return timeFormatter.string(from: dateComponents)
    }
}
