//  KeePassium Password Manager
//  Copyright © 2020 Andrei Popleteev <info@keepassium.com>
//
//  This program is free software: you can redistribute it and/or modify it
//  under the terms of the GNU General Public License version 3 as published
//  by the Free Software Foundation: https://www.gnu.org/licenses/).
//  For commercial licensing, please contact the author.

import Foundation

/// A utiility protocol to which provides synchronized { } method.
public protocol Synchronizable: class {
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
    
    /// Executes and waits for the `slowOperation` on background queue (`queue`).
    /// If the operation completes before timeout, calls `onSuccess`.
    /// Otherwise, calls `onTimeout`.
    /// - Parameters:
    ///   - timeout: max allocated time for the `slowOperation` to complete
    ///   - queue: background queue to block while waiting for the completion/timeout
    ///   - slowOperation: some blocking operation that can take forever to complete.
    ///       Usually one atomic operation without side effects, like resolving a URL bookmark.
    ///   - onSuccess: called when the operation completes before the timeout
    ///   - onTimeout: called if the operation did not complete before the timeout
    func execute<SlowResultType>(
        withTimeout timeout: TimeInterval,
        on queue: DispatchQueue,
        slowSyncOperation: @escaping ()->(SlowResultType),
        onSuccess: @escaping (SlowResultType)->(),
        onTimeout: @escaping ()->())
    {
        assert(timeout >= TimeInterval.zero)
        queue.async { [self] in // strong self
            let semaphore = DispatchSemaphore(value: 0)
            let slowBlockQueue = DispatchQueue.init(label: "", qos: queue.qos, attributes: []) // serial
            
            var result: SlowResultType?
            var isCancelled = false
            var isFinished = false
            slowBlockQueue.async { [weak self] in
                result = slowSyncOperation()
                
                // do we still exist?
                guard let self = self else { return }
                defer { semaphore.signal() }
                self.synchronized {
                    if !isCancelled {
                        isFinished = true
                    }
                }
            }
            
            if semaphore.wait(timeout: .now() + timeout) == .timedOut {
                self.synchronized {
                    if !isFinished {
                        isCancelled = true
                    }
                }
            }
            
            if isFinished {
                onSuccess(result!)
            } else {
                onTimeout()
            }
        }
    }
}
