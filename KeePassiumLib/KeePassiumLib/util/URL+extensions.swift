//  KeePassium Password Manager
//  Copyright © 2018–2019 Andrei Popleteev <info@keepassium.com>
// 
//  This program is free software: you can redistribute it and/or modify it
//  under the terms of the GNU General Public License version 3 as published
//  by the Free Software Foundation: https://www.gnu.org/licenses/).
//  For commercial licensing, please contact the author.

import Foundation

public extension URL {
    
    /// Second-level domain name, if any.
    /// (For example, for "auth.private.example.com" returns "example")
    /// Will not work with IP addresses (e.g. "127.0.0.1" -> "0")
    var domain2: String? {
        guard let names = host?.split(separator: ".") else { return nil }
        let nameCount = names.count
        if nameCount >= 2 {
            return String(names[nameCount - 2])
        }
        return nil
    }
    
    /// Last modiifcation date of a file URL.
    var fileModificationDate: Date? {
        guard let attr = try? FileManager.default
            .attributesOfItem(atPath: self.path) else { return nil }
        return attr[FileAttributeKey.modificationDate] as? Date
    }

    /// Creation date of a file URL.
    var fileCreationDate: Date? {
        guard let attr = try? FileManager.default
            .attributesOfItem(atPath: self.path) else { return nil }
        return attr[FileAttributeKey.creationDate] as? Date
    }
    
    /// Size of the file at this URL.
    var fileSize: Int64? {
        guard let attr = try? FileManager.default
            .attributesOfItem(atPath: self.path) else { return nil}
        return attr[FileAttributeKey.size] as? Int64
    }
    
    /// True for directories.
    var isDirectory: Bool {
        let res = try? resourceValues(forKeys: [.isDirectoryKey])
        return res?.isDirectory ?? false
    }
    
    /// Whether the file is marked as excluded from iTunes/iCloud backup
    var isExcludedFromBackup: Bool? {
        let res = try? resourceValues(forKeys: [.isExcludedFromBackupKey])
        return res?.isExcludedFromBackup
    }
    
    /// Changes the "excluded from backup" attribute.
    /// - Returns: `true` if successful, `false` in case of error
    @discardableResult
    mutating func setExcludedFromBackup(_ isExcluded: Bool) -> Bool {
        var values = URLResourceValues()
        values.isExcludedFromBackup = isExcluded
        do {
            try setResourceValues(values)
            // Verify that the change was actually applied
            if isExcludedFromBackup != nil && isExcludedFromBackup! == isExcluded {
                return true
            }
            Diag.warning("Failed to change backup attribute: the modification did not last.")
            return false
        } catch {
            Diag.warning("Failed to change backup attribute [reason: \(error.localizedDescription)]")
            return false
        }
    }
    
    /// Same URL with last component name replaced with "_redacted_"
    var redacted: URL {
        let isDirectory = self.isDirectory
        return self.deletingLastPathComponent().appendingPathComponent("_redacted_", isDirectory: isDirectory)
//        return self //TODO debug stuff, remove in production
    }
}
