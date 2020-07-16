//  KeePassium Password Manager
//  Copyright © 2018–2020 Andrei Popleteev <info@keepassium.com>
//
//  This program is free software: you can redistribute it and/or modify it
//  under the terms of the GNU General Public License version 3 as published
//  by the Free Software Foundation: https://www.gnu.org/licenses/).
//  For commercial licensing, please contact the author.

import TPInAppReceipt

fileprivate let dateFormatter: DateFormatter = {
    let dateFormatter = DateFormatter()
    dateFormatter.locale = Locale(identifier: "en_US_POSIX") // set locale to reliable US_POSIX
    dateFormatter.dateFormat = "yyyy-MM-dd"
    return dateFormatter
}()

class ReceiptAnalyzer {
    /// Intervals that are `adjacentIntervalsTolerance` apart will be considered continuous.
    let adjacentIntervalsTolerance = 7 * DateInterval.day
    
    // MARK: Internal classes
    
    struct DateInterval: CustomDebugStringConvertible {
        static let day = TimeInterval(24 * 60 * 60)
        static let year = 365 * DateInterval.day

        var from: Date
        var to: Date
        
        var duration: TimeInterval {
            return to.timeIntervalSince(from)
        }
            
        init?(fromSubscription subscription: InAppPurchase) {
            assert(subscription.isRenewableSubscription)
            guard let expiryDate = subscription.subscriptionExpirationDate else {
                assertionFailure()
                Diag.warning("Subscription with an empty expiration date?")
                return nil
            }
            self.from = subscription.purchaseDate
            self.to = expiryDate
        }
        
        /// Checks whether this interval can be extended (to left) with the given `interval`,
        /// - Returns: `true` if the intervals overlap or are within the `tolerance` interval apart.
        func canExtendLeft(with interval: DateInterval, tolerance: TimeInterval) -> Bool {
            guard interval.to <= self.to else {
                // `interval` ends later that `self`
                return false
            }
            guard interval.to > self.from.addingTimeInterval(-tolerance) else {
                // `interval` ends too early
                return false
            }
            // all good, can extend
            return true
        }
        
        var debugDescription: String {
            return "{ \(dateFormatter.string(from: from)) to \(dateFormatter.string(from: to)) }"
        }
    }
    
    
    // MARK: - Properties
    
    /// Whether the receipt includes a trial-period subscription
    var containsTrial = false
    
    /// Whether the receipt includes a .forever or .forever2 product
    var containsLifetimePurchase = false
    
    /// Perpetual fallback date, if any
    var fallbackDate: Date? = nil
    
    
    // MARK: - Methods
    
    static func logPurchaseHistory() {
        do {
            let receipt = try InAppReceipt.localReceipt()
            guard receipt.hasPurchases else {
                Diag.debug("No previous purchases found.")
                return
            }
            
            Diag.debug("Purchase history:")
            receipt.purchases.forEach { purchase in
                var flags = [String]()
                if purchase.cancellationDateString != nil {
                    flags.append("cancelled")
                }
                if purchase.subscriptionTrialPeriod || purchase.subscriptionIntroductoryPricePeriod {
                    flags.append("trial")
                }
                Diag.debug(
                    """
                    \(purchase.productIdentifier) - \(purchase.purchaseDateString) \
                    to \(purchase.subscriptionExpirationDateString ?? "nil") \
                    \(flags.joined())
                    """
                )
            }
        } catch {
            Diag.error(error.localizedDescription)
        }
    }
    
    func loadReceipt() {
        do {
            let receipt = try InAppReceipt.localReceipt()
            guard receipt.hasPurchases else {
                return
            }
            // No verification, to keep things simple
            
            containsTrial = receipt.autoRenewablePurchases.reduce(false) {
                (result, purchase) -> Bool in
                return result
                    || purchase.subscriptionTrialPeriod
                    || purchase.subscriptionIntroductoryPricePeriod
            }
            
            let sortedSubscriptions = receipt.autoRenewablePurchases
                .filter { $0.cancellationDateString == nil } // ignore cancelled transactions
                .sorted { $0.purchaseDate > $1.purchaseDate } // recent purchases first

            analyzeSubscriptions(sortedSubscriptions)
            
            containsLifetimePurchase =
                receipt.containsPurchase(ofProductIdentifier: InAppProduct.forever.rawValue) ||
                receipt.containsPurchase(ofProductIdentifier: InAppProduct.forever2.rawValue)
            if containsLifetimePurchase {
                fallbackDate = .distantFuture
            }
        } catch {
            Diag.error(error.localizedDescription)
        }
    }
        
    private func analyzeSubscriptions(_ sortedSubscriptions: [InAppPurchase]) {
        var subscriptionIterator = sortedSubscriptions.makeIterator()
        guard let latestSubscription = subscriptionIterator.next() else {
            // there are no subscriptions
            return
        }
        
        guard var continuousInterval = DateInterval(fromSubscription: latestSubscription) else {
            assertionFailure()
            return // there's nothing to work with
        }
        
        while true {
            let duration = continuousInterval.duration
            if duration >= DateInterval.year {
                // Found a long enough subscription interval.
                // Fall back a year and we're done.
                fallbackDate = continuousInterval.to.addingTimeInterval(-DateInterval.year)
                break
            }

            guard let nextSubscription = subscriptionIterator.next() else {
                break
            }
            guard let interval = DateInterval(fromSubscription: nextSubscription) else {
                assertionFailure()
                break // let's pretend we did not see it
            }
            
            let canExtend = continuousInterval.canExtendLeft(with: interval, tolerance: adjacentIntervalsTolerance)
            if canExtend {
                continuousInterval.from = interval.from
            } else {
                // interval cannot be extended, restart the search
                continuousInterval = interval
            }
        }
        if let fallbackDate = fallbackDate {
            Diag.info("Subscription fallback date: \(dateFormatter.string(from: fallbackDate))")
        }
    }
}
