//  KeePassium Password Manager
//  Copyright © 2018–2019 Andrei Popleteev <info@keepassium.com>
//
//  This program is free software: you can redistribute it and/or modify it
//  under the terms of the GNU General Public License version 3 as published
//  by the Free Software Foundation: https://www.gnu.org/licenses/).
//  For commercial licensing, please contact the author.


/// A common parent for groups and entries
open class DatabaseItem {
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
}
