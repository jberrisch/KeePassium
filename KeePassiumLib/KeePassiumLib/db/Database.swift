//  KeePassium Password Manager
//  Copyright © 2018–2019 Andrei Popleteev <info@keepassium.com>
// 
//  This program is free software: you can redistribute it and/or modify it
//  under the terms of the GNU General Public License version 3 as published
//  by the Free Software Foundation: https://www.gnu.org/licenses/).
//  For commercial licensing, please contact the author.

import Foundation

public enum DatabaseError: LocalizedError {
    /// Error while loading database
    case loadError(reason: String)
    /// Provided master key is invalid
    case invalidKey
    /// Error while saving database
    case saveError(reason: String)
    
    public var errorDescription: String? {
        switch self {
        case .loadError:
            return NSLocalizedString(
                "[DatabaseError] Cannot open database",
                bundle: Bundle.framework,
                value: "Cannot open database",
                comment: "Error message while opening a database")
        case .invalidKey:
            return NSLocalizedString(
                "[DatabaseError] Invalid password or key file",
                bundle: Bundle.framework,
                value: "Invalid password or key file",
                comment: "Error message: user provided a wrong master key for decryption.")
        case .saveError:
            return NSLocalizedString(
                "[DatabaseError] Cannot save database",
                bundle: Bundle.framework,
                value: "Cannot save database",
                comment: "Error message while saving a database")
        }
    }
    public var failureReason: String? {
        switch self {
        case .loadError(let reason):
            return reason
        case .saveError(let reason):
            return reason
        default:
            return nil
        }
    }
}

public struct SearchQuery {
    public let includeSubgroups: Bool
    public let includeDeleted: Bool
    public let includeFieldNames: Bool
    public let includeProtectedValues: Bool
    public let compareOptions: String.CompareOptions
    
    public let text: String
    public let textWords: Array<Substring>
    
    public init(
        includeSubgroups: Bool,
        includeDeleted: Bool,
        includeFieldNames: Bool,
        includeProtectedValues: Bool,
        compareOptions: String.CompareOptions,
        text: String,
        textWords: Array<Substring>)
    {
        self.includeSubgroups = includeSubgroups
        self.includeDeleted = includeDeleted
        self.includeFieldNames = includeFieldNames
        self.includeProtectedValues = includeProtectedValues
        self.compareOptions = compareOptions
        self.text = text
        self.textWords = text.split(separator: " ")
    }
}

public class DatabaseLoadingWarnings {
    /// Name of the app that has written the database file
    public internal(set) var databaseGenerator: String?
    /// Human-readable warning messages, if any
    public internal(set) var messages: [String]
    
    public var isEmpty: Bool { return messages.isEmpty }
    
    internal init() {
        databaseGenerator = nil
        messages = []
    }
}

open class Database: Eraseable {
    /// File system path to the database file
    var filePath: String?
    
    /// Root group
    public internal(set) var root: Group?

    /// Progress of load/save operations
    public internal(set) var progress = ProgressEx()

    /// Composite key of the database, before derivation
    internal var compositeKey = CompositeKey.empty
    
    /// Returns a fresh instance of progress for load/save operations
    public func initProgress() -> ProgressEx {
        progress = ProgressEx()
        return progress
    }
    
    /// DB version specific helper for key processing.
    /// (Pure virtual, must be overriden)
    public var keyHelper: KeyHelper {
        fatalError("Pure virtual method")
    }
    
    internal init() {
        // left empty
    }
    
    deinit {
        erase()
    }
    
    /// Erases and removes any loaded DB elements.
    public func erase() {
        root?.erase()
        root = nil
        filePath?.erase()
        compositeKey.erase()
    }

    /// Checks if given data starts with compatible KeePass signature.
    /// (Pure virtual method, must be overriden)
    public class func isSignatureMatches(data: ByteArray) -> Bool {
        fatalError("Pure virtual method")
    }
    
    /// Tries to decrypt the given DB with the given composite master key.
    ///
    /// - Parameters:
    ///   - dbFileName: name of the database file (without path)
    ///   - dbFileData: content of the database file
    ///   - compositeKey: composite key
    ///   - warnings: will contain messages about database issues, that are not-blocking
    ///               (loading can continue), but might lead to loss of data.
    ///               For example, orphaned attachments in KP2 binary pool.
    /// - Throws: `DatabaseError`, `ProgressInterruption`
    public func load(
        dbFileName: String,
        dbFileData: ByteArray,
        compositeKey: CompositeKey,
        warnings: DatabaseLoadingWarnings
    ) throws {
        fatalError("Pure virtual method")
    }
    
    /// Encrypts the DB and returns the result as byte array.
    /// Progress, errors and outcomes are reported to status delegate.
    ///
    /// (Pure virtual method, must be overriden)
    ///
    /// - Throws: `DatabaseError.saveError`, `ProgressInterruption`
    /// - Returns: encrypted DB bytes.
    public func save() throws -> ByteArray {
        fatalError("Pure virtual method")
    }
    
    /// Changes DB's composite key to the provided one.
    /// Don't forget to call `deriveMasterKey` before saving.
    ///
    /// (Pure virtual method, must be overriden)
    ///
    /// - Parameter newKey: new composite key.
    public func changeCompositeKey(to newKey: CompositeKey) {
        fatalError("Pure virtual method")
    }
    
    /// Returns the Backup group of this DB.
    ///
    /// (Pure virtual method, must be overriden)
    ///
    /// - Parameter createIfMissing: create the Backup group if it does not exist.
    ///        This parameter is ignored (assumed false) if backup is disabled at DB level.
    /// - Returns: pre-existing or newly created Backup group
    public func getBackupGroup(createIfMissing: Bool) -> Group? {
        fatalError("Pure virtual method")
    }
    
    /// Returns the number of all groups and/or entries in this DB.
    public func count(includeGroups: Bool = true, includeEntries: Bool = true) -> Int {
        // TODO: can make this more efficient
        var result = 0
        if let root = self.root {
            var groups = Array<Group>()
            var entries = Array<Entry>()
            root.collectAllChildren(groups: &groups, entries: &entries)
            result += includeGroups ? groups.count : 0
            result += includeEntries ? entries.count : 0
        }
        return result
    }
    
    /// Searches for entries that match given search `query`.
    /// - Returns: number of found entries.
    public func search(query: SearchQuery, result: inout Array<Entry>) -> Int {
        result.removeAll()
        root?.filterEntries(query: query, result: &result)
        return result.count
    }
    
    /// Deletes given `group` (to Backup group, when appropriate; otherwise permanently).
    public func delete(group: Group) {
        fatalError("Pure virtual method")
    }
    
    /// Deletes given `entry` (or moves it to the Backup group, when possible).
    public func delete(entry: Entry) {
        fatalError("Pure virtual method")
    }

    /// Creates an attachment suitable for this database's entries.
    ///
    /// - Parameters:
    ///   - name: attachment name (name of the original file)
    ///   - data: uncompressed content
    /// - Returns: version-appropriate instance of `Attachment`, possibly with compressed data.
    public func makeAttachment(name: String, data: ByteArray) -> Attachment {
        fatalError("Pure virtual method")
    }
    
    /// Resolves all field references in all entries.
    /// - Parameters:
    ///   - allEntries: all entries of the database
    ///   - parentProgress: DB's loading progress; the resolving progress will be added to it as a child.
    ///   - pendingProgressUnits: parent progress units designated for the resolving phase.
    internal func resolveReferences<T>(
        allEntries: T,
        parentProgress: ProgressEx,
        pendingProgressUnits: Int64)
        where T: Collection, T.Element: Entry
    {
        Diag.debug("Resolving references")
        
        let resolvingProgress = ProgressEx()
        resolvingProgress.totalUnitCount = Int64(allEntries.count)
        resolvingProgress.localizedDescription = LString.Progress.resolvingFieldReferences
        progress.addChild(resolvingProgress, withPendingUnitCount: pendingProgressUnits)
        
        // First of all, erase any cached resolved values
        allEntries.forEach { entry in
            entry.fields.forEach { field in
                field.unresolveReferences()
            }
        }
        
        var entriesProcessed = 0
        // And now, resolve them anew
        allEntries.forEach { entry in
            entry.fields.forEach { field in
                field.resolveReferences(entries: allEntries)
            }
            entriesProcessed += 1
            if entriesProcessed % 100 == 0 {
                resolvingProgress.completedUnitCount = Int64(entriesProcessed)
            }
        }
        resolvingProgress.completedUnitCount = resolvingProgress.totalUnitCount // ensure 100%
        Diag.debug("References resolved OK")
    }
}

