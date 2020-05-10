//  KeePassium Password Manager
//  Copyright © 2018–2019 Andrei Popleteev <info@keepassium.com>
// 
//  This program is free software: you can redistribute it and/or modify it
//  under the terms of the GNU General Public License version 3 as published
//  by the Free Software Foundation: https://www.gnu.org/licenses/).
//  For commercial licensing, please contact the author.

import Foundation

public extension Date {
    /// A readability-improving wrapper for `Date()`
    static var now: Date { return Date() }
    
    private static let iso8601DateFormatter = { () -> ISO8601DateFormatter in
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()
    
    private static let iso8601DateFormatterWithFractionalSeconds = { () -> ISO8601DateFormatter in
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions =  [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()
    
    /// Date formatter for problematic MiniKeePass-generated timestamps that have
    /// abbreviated timezone format (e.g. "2020-03-04T2:38:16 PST")
    private static let miniKeePassDateFormatter = { () -> DateFormatter in
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss z"
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        return formatter
    }()

    /// Number of seconds between 0001-01-01 00:00 and 2001-01-01 00:00,
    /// in .NET context (Swift thinks there are 2 days less)
    static internal let secondsBetweenSwiftAndDotNetReferenceDates = Int64(63113904000)

    /// Creates date from an ISO8601-formatted string.
    init?(iso8601string string: String?) {
        guard let string = string else { return nil }
        // ISO8601DateFormatter can be configured to either expect only integer seconds
        // (and return nil if they are fractional), or to expect only fractional seconds
        // (and return nil if they are integer). So we have to try both configurations.
        if let date = Date.iso8601DateFormatter.date(from: string) {
            self = date
        } else if let date = Date.iso8601DateFormatterWithFractionalSeconds.date(from: string) {
            self = date
        } else if let date = Date.miniKeePassDateFormatter.date(from: string) {
            // Some MKP timestamps have abbreviated timezones, so accept them, too.
            self = date
        } else {
            return nil
        }
    }
    
    /// Creates date from a base-64 encoded Int64 of seconds
    /// since `Date.dotNetTimeZero` (KP2v4)
    init?(base64Encoded string: String?) {
        guard let data = ByteArray(base64Encoded: string) else { return nil }
        guard let secondsSinceDotNetReferenceDate = Int64(data: data) else { return nil }
        let secondsSinceSwiftReferenceDate =
            secondsSinceDotNetReferenceDate - Date.secondsBetweenSwiftAndDotNetReferenceDates
        self = Date(timeIntervalSinceReferenceDate: Double(secondsSinceSwiftReferenceDate))
    }
    
    /// Returns the date as an ISO8601-formatted string
    func iso8601String() -> String {
        return Date.iso8601DateFormatter.string(from: self)
    }
    
    /// Returns the date as Base64-encoded UInt64 of seconds since
    /// `Date.dotNetTimeZero` (KP2v4)
    func base64EncodedString() -> String {
        let secondsSinceSwiftReferenceDate = Int64(self.timeIntervalSinceReferenceDate)
        let secondsSinceDotNetReferenceDate =
            secondsSinceSwiftReferenceDate + Date.secondsBetweenSwiftAndDotNetReferenceDates
        return secondsSinceDotNetReferenceDate.data.base64EncodedString()
    }
}
