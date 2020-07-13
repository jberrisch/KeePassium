//  KeePassium Password Manager
//  Copyright © 2020 Andrei Popleteev <info@keepassium.com>
//
//  This program is free software: you can redistribute it and/or modify it
//  under the terms of the GNU General Public License version 3 as published
//  by the Free Software Foundation: https://www.gnu.org/licenses/).
//  For commercial licensing, please contact the author.

import Foundation

/// Errors while accessing a local or remote file; including timeout.
public enum FileAccessError: LocalizedError {
    /// Operation timed out
    case timeout(fileProvider: FileProvider?)
    
    /// There is no cached file info, and caller asked not to refresh it.
    case noInfoAvailable
    
    /// Raised when there is an internal inconsistency in the code.
    /// In particular, when both result and error params of a callback are nil.
    case internalError
    
    case fileProviderDoesNotRespond(fileProvider: FileProvider?)
    
    /// Wrapper for an underlying error
    case systemError(_ originalError: Error?)
    
    public var errorDescription: String? {
        switch self {
        case .timeout(let fileProvider):
            if let fileProvider = fileProvider {
                return String.localizedStringWithFormat(
                    NSLocalizedString(
                        "[FileAccessError/Timeout/knownFileProvider]",
                        bundle: Bundle.framework,
                        value: "%@ does not respond.",
                        comment: "Error message: file provider does not respond to requests (quickly enough). For example: `Google Drive does not respond`"),
                    fileProvider.localizedName
                )
            } else {
                return NSLocalizedString(
                    "[FileAccessError/Timeout/genericFileProvider]",
                    bundle: Bundle.framework,
                    value: "Storage provider does not respond.",
                    comment: "Error message: storage provider app (e.g. Google Drive) does not respond to requests (quickly enough).")
            }
        case .noInfoAvailable:
            assertionFailure("Should not be shown to the user")
            return nil
        case .internalError:
            return NSLocalizedString(
                "[FileAccessError/internalError]",
                bundle: Bundle.framework,
                value: "Internal KeePassium error, please tell us about it.",
                comment: "Error message shown when there's internal inconsistency in KeePassium.")
        case .fileProviderDoesNotRespond(let fileProvider):
            if let fileProvider = fileProvider {
                return String.localizedStringWithFormat(
                    NSLocalizedString(
                        "[FileAccessError/NoResponse/knownFileProvider]",
                        bundle: Bundle.framework,
                        value: "%@ does not respond.",
                        comment: "Error message: file provider does not respond to requests. For example: `Google Drive does not respond.`"),
                    fileProvider.localizedName
                )
            } else {
                return NSLocalizedString(
                    "[FileAccessError/NoResponse/genericFileProvider]",
                    bundle: Bundle.framework,
                    value: "Storage provider does not respond.",
                    comment: "Error message: storage provider app (e.g. Google Drive) does not respond to requests.")
            }
        case .systemError(let originalError):
            return originalError?.localizedDescription
        }
    }
    
    /// Processes a generic system error and returns a suitable case of `FileAccessError`,
    /// initialized with necessary details.
    public static func make(from originalError: Error, fileProvider: FileProvider?) -> FileAccessError {
        let nsError = originalError as NSError
        // Since we don't know anything about the error, it is useful to log some debug info about it.
        Diag.error("""
            Failed to access the file \
            [fileProvider: \(fileProvider?.id ?? "nil"), systemError: \(nsError.debugDescription)]
            """)
        switch (nsError.domain, nsError.code) {
        // "Could not communicate with the helper app" - Google Drive offline
        case ("NSCocoaErrorDomain", 4101):
            fallthrough
            
        // "Could not communicate with the helper app" - Sync.com offline after device restart
        case ("NSCocoaErrorDomain", 4097): fallthrough
        case ("NSCocoaErrorDomain", 4099):
            return .fileProviderDoesNotRespond(fileProvider: fileProvider)
        default:
            // Generic catch-all error
            return .systemError(originalError)
        }
    }
}
