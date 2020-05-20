//  KeePassium Password Manager
//  Copyright © 2020 Andrei Popleteev <info@keepassium.com>
//
//  This program is free software: you can redistribute it and/or modify it
//  under the terms of the GNU General Public License version 3 as published
//  by the Free Software Foundation: https://www.gnu.org/licenses/).
//  For commercial licensing, please contact the author.

import Foundation

/// A utiility protocol to which provides synchronized { } method.
public protocol Synchronizable {
    func synchronized<T>(_ handler: ()->(T)) -> T
}

public extension Synchronizable {
    /// Calls `handler` in a synchronized manner
    func synchronized<T>(_ handler: ()->(T)) -> T  {
        objc_sync_enter(self)
        defer { objc_sync_exit(self)}
        return handler()
    }
    
    /// Executes the `handler` on the main thread
    func dispatchMain(_ handler: @escaping ()->()) {
        if Thread.isMainThread {
            handler()
        } else {
            DispatchQueue.main.async(execute: handler)
        }
    }
}
