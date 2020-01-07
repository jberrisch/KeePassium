//  KeePassium Password Manager
//  Copyright © 2018–2019 Andrei Popleteev <info@keepassium.com>
// 
//  This program is free software: you can redistribute it and/or modify it
//  under the terms of the GNU General Public License version 3 as published
//  by the Free Software Foundation: https://www.gnu.org/licenses/).
//  For commercial licensing, please contact the author.

import Foundation

public class Group: DatabaseItem, Eraseable {
    public static let defaultIconID = IconID.folder
    public static let defaultOpenIconID = IconID.folderOpen
    
    // "up" refs are weak, refs to children are strong
    public weak var database: Database?
    public var uuid: UUID
    public var iconID: IconID
    public var name: String
    public var notes: String
    public internal(set) var creationTime: Date
    public internal(set) var lastModificationTime: Date
    public internal(set) var lastAccessTime: Date
    public var expiryTime: Date
    public var canExpire: Bool
    /// Returns true if the group has expired.
    public var isExpired: Bool {
        return canExpire && Date() > expiryTime
    }
    /// True if the group is in Recycle Bin
    public var isDeleted: Bool
    
    private var isChildrenModified: Bool
    public var groups = [Group]()
    public var entries = [Entry]()
    
    public var isRoot: Bool { return database?.root === self }

    /// Checks if a group name is reserved for internal use and cannot be assigned by the user.
    public func isNameReserved(name: String) -> Bool {
        return false
    }

    init(database: Database?) {
        self.database = database
        
        uuid = UUID.ZERO
        iconID = Group.defaultIconID
        name = ""
        notes = ""
        isChildrenModified = true
        canExpire = false
        isDeleted = false
        groups = []
        entries = []

        let now = Date()
        creationTime = now
        lastModificationTime = now
        lastAccessTime = now
        expiryTime = now
        
        super.init()
    }
    deinit {
        erase()
    }
    public func erase() {
        entries.removeAll() //erase()
        groups.removeAll() //erase()

        uuid = UUID.ZERO
        iconID = Group.defaultIconID
        name.erase()
        notes.erase()
        isChildrenModified = true
        canExpire = false
        isDeleted = false
        
        parent = nil
        // database = nil  -- database reference does not change on erase

        let now = Date()
        creationTime = now
        lastModificationTime = now
        lastAccessTime = now
        expiryTime = now
    }
    
    /// Creates a shallow copy of this group with the same properties, but no children items.
    /// Subclasses must override and return an instance of a version-appropriate Group subclass.
    public func clone() -> Group {
        fatalError("Pure virtual method")
    }
    
    /// Copies properties of this group to `target`. Complex properties are cloned.
    /// Does not affect children items, parent group or parent database.
    public func apply(to target: Group) {
        target.uuid = uuid
        target.iconID = iconID
        target.name = name
        target.notes = notes
        target.canExpire = canExpire
        target.isDeleted = isDeleted
        
        // parent - not changed
        // database - not changed
        
        target.creationTime = creationTime
        target.lastModificationTime = lastModificationTime
        target.lastAccessTime = lastAccessTime
        target.expiryTime = expiryTime
    }
    
    /// Returns the number of immediate children of this group
    public func count(includeGroups: Bool = true, includeEntries: Bool = true) {
        var result = 0
        if includeGroups {
            result += groups.count
        }
        if includeEntries {
            result += entries.count
        }
    }
    
    public func add(group: Group) {
        group.parent = self
        groups.append(group)
        group.deepSetDeleted(self.isDeleted)
        isChildrenModified = true
    }
    
    /// Sets the `isDeleted` flag of this group and all its children.
    public func deepSetDeleted(_ isDeleted: Bool) {
        self.isDeleted = isDeleted
        groups.forEach { $0.deepSetDeleted(isDeleted) }
        entries.forEach { $0.isDeleted = isDeleted }
    }
    
    public func remove(group: Group) {
        guard group.parent === self else {
            return
        }
        groups.remove(group)
        group.parent = nil
        isChildrenModified = true
    }
    
    public func add(entry: Entry) {
        entry.parent = self
        entry.isDeleted = self.isDeleted
        entries.append(entry)
        isChildrenModified = true
    }
    
    public func remove(entry: Entry) {
        guard entry.parent === self else {
            return
        }
        entries.remove(entry)
        entry.parent = nil
        isChildrenModified = true
    }
    
    /// Moves this group to another parent group.
    public func move(to newGroup: Group) {
        guard parent !== newGroup else { return }
        parent?.remove(group: self)
        newGroup.add(group: self)
    }

    /// Finds (sub)group with the given UUID (searching the full tree).
    /// - Returns: the first subgroup with the given UUID, or nil if none found.
    public func findGroup(byUUID uuid: UUID) -> Group? {
        if self.uuid == uuid {
            return self
        }
        for group in groups {
            if let result = group.findGroup(byUUID: uuid) {
                return result
            }
        }
        return nil
    }

    /// Creates an entry in this group.
    /// Subclasses must override and return an instance of a version-appropriate Entry subclass.
    /// - Returns: created entry
    public func createEntry() -> Entry {
        fatalError("Pure virtual method")
    }
    
    /// Creates a group inside this group.
    /// Subclasses must override and return an instance of a version-appropriate Group subclass.
    /// - Returns: created group
    public func createGroup() -> Group {
        fatalError("Pure virtual method")
    }
    
    /// Updates last access timestamp to current time
    public func accessed() {
        lastAccessTime = Date.now
    }
    /// Updates modification timestamp to current time
    public func modified() {
        accessed()
        lastModificationTime = Date.now
    }

    /// Recursively iterates through all the children groups and entries of this group
    /// and adds them to the given lists. The group itself is excluded.
    public func collectAllChildren(groups: inout Array<Group>, entries: inout Array<Entry>) {
        for group in self.groups {
            groups.append(group)
            group.collectAllChildren(groups: &groups, entries: &entries)
        }
        entries.append(contentsOf: self.entries)
    }
    
    /// Recursively collects all entries from this group and its subgroups.
    public func collectAllEntries(to entries: inout Array<Entry>) {
        for group in self.groups {
            group.collectAllEntries(to: &entries)
        }
        entries.append(contentsOf: self.entries)
    }
    
    /// Finds entries which match the query, and adds them to the `result`.
    public func filterEntries(query: SearchQuery, result: inout Array<Entry>) {
        if self.isDeleted && !query.includeDeleted {
            return
        }
        
        if query.includeSubgroups {
            for group in groups {
                group.filterEntries(query: query, result: &result)
            }
        }
        
        for entry in entries {
            if entry.matches(query: query) {
                result.append(entry)
            }
        }
    }
}

extension Array where Element == Group {
    mutating func remove(_ group: Group) {
        if let index = index(where: {$0 === group}) {
            remove(at: index)
        }
    }
}


