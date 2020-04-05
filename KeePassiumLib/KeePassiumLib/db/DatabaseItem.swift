//  KeePassium Password Manager
//  Copyright © 2018–2019 Andrei Popleteev <info@keepassium.com>
//
//  This program is free software: you can redistribute it and/or modify it
//  under the terms of the GNU General Public License version 3 as published
//  by the Free Software Foundation: https://www.gnu.org/licenses/).
//  For commercial licensing, please contact the author.


/// A common parent for groups and entries
open class DatabaseItem {
    public enum TouchMode {
        /// The item has been merely accessed (viewed)
        case accessed
        /// The item has been accessed and modified
        case modified
    }
    
    public weak var parent: Group?
    
    /// True iff this item is a parent (at any level) of the given `item`.
    public func isAncestor(of item: DatabaseItem) -> Bool {
        var parent = item.parent
        while parent != nil {
            if self === parent {
                return true
            }
            parent = parent?.parent
        }
        return false
    }
    
    /// Update last access time (and optionally the modification time) of the entry.
    /// - Parameter mode: defines which timestamps should be updated
    /// - Parameter updateParents: also touch containing groups.
    public func touch(_ mode: TouchMode, updateParents: Bool = true) {
        fatalError("Pure abstract method")
    }
}
