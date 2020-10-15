//  KeePassium Password Manager
//  Copyright © 2018–2019 Andrei Popleteev <info@keepassium.com>
// 
//  This program is free software: you can redistribute it and/or modify it
//  under the terms of the GNU General Public License version 3 as published
//  by the Free Software Foundation: https://www.gnu.org/licenses/).
//  For commercial licensing, please contact the author.

import Foundation

public class EntryField: Eraseable {
    public static let title    = "Title"
    public static let userName = "UserName"
    public static let password = "Password"
    public static let url      = "URL"
    public static let notes    = "Notes"
    public static let standardNames = [title, userName, password, url, notes]
    
    /// Common name for the "virtual" (generated) one-time-password field
    public static let totp = "TOTP"

    public var name: String
    public var value: String {
        didSet {
            resolvedValueInternal = nil
        }
    }
    public var isProtected: Bool
    
    /// Cached resolved value.
    /// `nil`until resolved.
    /// Equals to `value` if there are not references.
    internal var resolvedValueInternal: String?
    
    /// Resolved value of the field (if resolved; otherwise just a copy of `value`)
    public var resolvedValue: String {
        guard resolvedValueInternal != nil else {
            assertionFailure()
            return value
        }
        return resolvedValueInternal!
    }
    
    private(set) public var resolveStatus = EntryFieldReference.ResolveStatus.noReferences
    
    /// Indicates whether the field includes any references to other fields (resolvable or not).
    public var hasReferences: Bool {
        return resolveStatus != .noReferences
    }

    public var decoratedValue: String {
        guard hasReferences else {
            return resolvedValue
        }
        return "→ " + resolvedValue

    }
    
    /// True if field's name is one of the fixed/standard KP2 fields.
    public var isStandardField: Bool {
        return EntryField.isStandardName(name: self.name)
    }
    public static func isStandardName(name: String) -> Bool {
        return standardNames.contains(name)
    }
    
    public convenience init(name: String, value: String, isProtected: Bool) {
        self.init(
            name: name,
            value: value,
            isProtected: isProtected,
            resolvedValue: value,  // assume the raw value, until we explicitly go through resolving
            resolveStatus: .noReferences
        )
    }
    
    internal init(
        name: String,
        value: String,
        isProtected: Bool,
        resolvedValue: String?,
        resolveStatus: EntryFieldReference.ResolveStatus
    ) {
        self.name = name
        self.value = value
        self.isProtected = isProtected
        self.resolvedValueInternal = resolvedValue
        self.resolveStatus = resolveStatus
    }
    
    deinit {
        erase()
    }
    
    public func clone() -> EntryField {
        let clone = EntryField(
            name: name,
            value: value,
            isProtected: isProtected,
            resolvedValue: resolvedValue,
            resolveStatus: resolveStatus
        )
        return clone
    }
    
    public func erase() {
        name.erase()
        value.erase()
        isProtected = false

        resolvedValueInternal?.erase()
        resolvedValueInternal = nil
        resolveStatus = .noReferences
    }
    
    /// Checks if the field name/value contains given `text`.
    public func contains(
        word: Substring,
        includeFieldNames: Bool,
        includeProtectedValues: Bool,
        options: String.CompareOptions
    ) -> Bool {
        guard name != EntryField.password else { return false } // don't search in passwords
        
        if includeFieldNames
            && !isStandardField
            && name.localizedContains(word, options: options)
        {
            return true
        }
        
        let includeFieldValue = !isProtected || includeProtectedValues
        if includeFieldValue {
            return resolvedValue.localizedContains(word, options: options)
        }
        return false
    }
    
    /// Resolves field's references in relation to the given references,
    /// and updates the `resolvedValue` property.
    /// - Parameters:
    ///   - entries: other entries in the database
    ///   - maxDepth: maximum permitted depth of chained references
    /// - Returns: resolved value
    @discardableResult
    public func resolveReferences<T>(entries: T, maxDepth: Int = 3) -> String
        where T: Collection, T.Element: Entry
    {
        guard resolvedValueInternal == nil else {
            return resolvedValueInternal!
        }
        
        var _resolvedValue = value
        let status = EntryFieldReference.resolveReferences(
            in: value,
            entries: entries,
            maxDepth: maxDepth,
            resolvedValue: &_resolvedValue
        )
        resolveStatus = status
        resolvedValueInternal = _resolvedValue
        return _resolvedValue
    }
    
    /// Resets the cached resolved value, so it needs to be resolved again.
    public func unresolveReferences() {
        resolvedValueInternal = nil
        resolveStatus = .noReferences
    }
}

public class Entry: DatabaseItem, Eraseable {
    public static let defaultIconID = IconID.key
    
    public weak var database: Database?
    public var uuid: UUID
    public var iconID: IconID

    public var fields: [EntryField]
    public var isSupportsExtraFields: Bool { get { return false } }
    public var isSupportsMultipleAttachments: Bool { return false }

    public var title: String {
        get{ return getField(with: EntryField.title)?.value ?? "" }
        set { setField(name: EntryField.title, value: newValue) }
    }
    public var resolvedTitle: String {
        get{ return getField(with: EntryField.title)?.resolvedValue ?? "" }
    }
    
    public var userName: String {
        get{ return getField(with: EntryField.userName)?.value ?? "" }
        set { setField(name: EntryField.userName, value: newValue) }
    }
    public var resolvedUserName: String {
        get{ return getField(with: EntryField.userName)?.resolvedValue ?? "" }
    }
    
    public var password: String {
        get{ return getField(with: EntryField.password)?.value ?? "" }
        set { setField(name: EntryField.password, value: newValue) }
    }
    public var resolvedPassword: String {
        get{ return getField(with: EntryField.password)?.resolvedValue ?? "" }
    }
    
    public var url: String {
        get{ return getField(with: EntryField.url)?.value ?? "" }
        set { setField(name: EntryField.url, value: newValue) }
    }
    public var resolvedURL: String {
        get{ return getField(with: EntryField.url)?.resolvedValue ?? "" }
    }

    public var notes: String {
        get{ return getField(with: EntryField.notes)?.value ?? "" }
        set { setField(name: EntryField.notes, value: newValue) }
    }
    public var resolvedNotes: String {
        get{ return getField(with: EntryField.notes)?.resolvedValue ?? "" }
    }
    
    public internal(set) var creationTime: Date
    public internal(set) var lastModificationTime: Date
    public internal(set) var lastAccessTime: Date
    public var expiryTime: Date
    /// Is this entry expirable? (`false` by default)
    /// This property is overriden by all subclasses.
    public var canExpire: Bool {
        get { return false }
        set { /* ignored */ }
    }
    public var isExpired: Bool { return canExpire && (Date() > expiryTime) }
    /// True if the entry is in Recycle Bin
    public var isDeleted: Bool
    
    /// Attachments of this entry
    public var attachments: Array<Attachment>
    
    public var description: String { return "Entry[\(title)]" }
    
    init(database: Database?) {
        self.database = database
        attachments = []
        fields = []

        uuid = UUID.ZERO
        iconID = Entry.defaultIconID
        isDeleted = false
        
        let now = Date()
        creationTime = now
        lastModificationTime = now
        lastAccessTime = now
        expiryTime = now
        
        super.init()
        
        canExpire = false
        populateStandardFields()
    }
    
    deinit {
        erase()
    }
    
    public func erase() {
        attachments.erase()
        fields.erase()
        populateStandardFields()
        
        uuid = UUID.ZERO
        iconID = Entry.defaultIconID
        isDeleted = false
        canExpire = false

        parent = nil

        let now = Date()
        creationTime = now
        lastModificationTime = now
        lastAccessTime = now
        expiryTime = now
    }
    
    /// Builds an appropriate child instance of `EntryField`.
    func makeEntryField(name: String, value: String, isProtected: Bool) -> EntryField {
        return EntryField(
            name: name,
            value: value,
            isProtected: isProtected,
            resolvedValue: value, // assume the raw value, until we explicitly go through resolving
            resolveStatus: .noReferences)
    }
    
    /// Sets standard/fixed fields to empty values.
    public func populateStandardFields() {
        setField(name: EntryField.title, value: "")
        setField(name: EntryField.userName, value: "")
        setField(name: EntryField.password, value: "", isProtected: true)
        setField(name: EntryField.url, value: "")
        setField(name: EntryField.notes, value: "")
    }
    
    /// Adds a named field (updates if `name` already exists).
    /// When `isProtected` is `nil`, it will not be updated (when adding, defaults to `false`)
    public func setField(name: String, value: String, isProtected: Bool? = nil) {
        for field in fields {
            if field.name == name {
                field.value = value
                if let isProtected = isProtected {
                    field.isProtected = isProtected
                } else {
                    // isProtected should remain unchanged
                }
                return
            }
        }
        // If undefined, memory protection defaults to `false`, because:
        // - for standard fields it will be updated according to DB Meta protection flags (on save)
        // - for other fields, it will be changed by some other method.
        fields.append(makeEntryField(name: name, value: value, isProtected: isProtected ?? false))
    }

    /// - Returns: first field with given name
    public func getField<T: StringProtocol>(with name: T) -> EntryField? {
        return fields.first(where: {
            $0.name.compare(name) == .orderedSame
        })
    }
    
    /// Deletes field with the given name (ignores errors) without making backup.
    public func removeField(_ field: EntryField) {
        if let index = fields.firstIndex(where: {$0 === field}) {
            fields.remove(at: index)
        }
    }

    /// Returns a new entry instance with the same property values.
    /// (A pure virtual method, must be overriden)
    public func clone(makeNewUUID: Bool) -> Entry {
        fatalError("Pure virtual method")
    }
    
    /// Copies properties of this entry to the `target`.
    /// Complex properties are cloned.
    /// Does not affect group membership.
    public func apply(to target: Entry, makeNewUUID: Bool) {
        // target.database and target.parent are not changed
        if makeNewUUID {
            target.uuid = UUID()
        } else {
            target.uuid = uuid
        }
        target.iconID = iconID
        target.isDeleted = isDeleted
        target.lastModificationTime = lastModificationTime
        target.creationTime = creationTime
        target.lastAccessTime = lastAccessTime
        target.expiryTime = expiryTime
        target.canExpire = canExpire
        
        target.attachments.removeAll()
        for att in attachments {
            target.attachments.append(att.clone())
        }
        target.fields.removeAll()
        for field in fields {
            target.fields.append(field.clone())
        }
    }
    
    /// Makes a backup copy of the current values/state of the entry.
    /// Actual behavior is DB version specific.
    /// (A pure virtual method, must be overriden)
    public func backupState() {
        fatalError("Pure virtual method")
    }
    
    /// Update last access time (and optionally the modification time) of the entry.
    /// - Parameter mode: defines which timestamps should be updated
    /// - Parameter updateParents: also touch containing groups.
    override public func touch(_ mode: DatabaseItem.TouchMode, updateParents: Bool = true) {
        lastAccessTime = Date.now
        if mode == .modified {
            lastModificationTime = Date.now
        }
        if updateParents {
            parent?.touch(mode, updateParents: true)
        }
    }
    
    /// Removes the entry from the parent group. Does NOT make a copy in Backup/Recycle Bin.
    public func deleteWithoutBackup() {
        parent?.remove(entry: self)
    }
    
    public func move(to newGroup: Group) {
        guard newGroup !== parent else { return }
        parent?.remove(entry: self)
        newGroup.add(entry: self)
    }
    
    /// Returns the names of the groups this entry is in, much like a file system path.
    public func getGroupPath() -> String {
        var groupNames = Array<String>()
        var parentGroup = self.parent
        while parentGroup != nil {
            let parentGroupUnwrapped = parentGroup! // safe to force-unwrap
            groupNames.append(parentGroupUnwrapped.name)
            parentGroup = parentGroupUnwrapped.parent
        }
        return groupNames.reversed().joined(separator: "/")
    }
    
    /// Checks if the entry matches given search `query`.
    /// (That is, each query word is present in at least one of the fields
    /// [title, user name, url, notes, attachment names].)
    public func matches(query: SearchQuery) -> Bool {
        for word in query.textWords {
            var wordFound = false
            for field in fields {
                wordFound = field.contains(
                    word: word,
                    includeFieldNames: query.includeFieldNames,
                    includeProtectedValues: query.includeProtectedValues,
                    options: query.compareOptions)
                if wordFound {
                    break
                }
            }
            if wordFound {
                continue
            }

            for att in attachments {
                if att.name.localizedContains(word, options: query.compareOptions) {
                    wordFound = true
                    break
                }
            }
            if !wordFound {
                return false
            }
        }
        return true
    }
}


extension Array where Element == Entry {
    mutating func remove(_ entry: Entry) {
        if let index = firstIndex(where: {$0 === entry}) {
            remove(at: index)
        }
    }
}

