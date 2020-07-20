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

    
    /// Starts executing a slow asynchronous operation (`slowAsyncOperation`) on a background queue (`queue`)..
    /// Once the slow operation reaches its completion block, the latter must call `notifyAndCheckIfCanProceed` parameter.
    /// It cancels the timeout (since the slow operation has largely completed), and returns `true` if the slow completion block can
    /// continue its work. (or `false`, if the slow operation has already timed out).
    ///
    /// If the timeout has been cancelled, the `onSuccess` callback is called.
    /// If the timeout occured while waiting for the slow operation, the `onTimeout` callback is called.
    /// - Parameters:
    ///   - timeout: time interval to wait for the slow operation to complete.
    ///   - queue: background queue to wait for the timeout
    ///   - slowAsyncOperation: starts a slow asynchronous operation. (That is, `slowAsyncOperation`
    ///       can return quickly, but its completion block might be arbitrarily delayed). Has one parameter,
    ///       a `notifyAndCheckIfCanProceed` callback that should be called asap in the slow operation's completion block.
    ///       This callback will cancel the timeout (if not happened already), and return `true` if slow operation can proceed.
    ///       (Or `false` if it has already timed out and should be abandoned.)
    ///   - onSuccess: called if the slow operation sent a notification before the timeout
    ///   - onTimeout: called if the slow operation has timed out
    func execute(
        withTimeout timeout: TimeInterval,
        on queue: OperationQueue,
        slowAsyncOperation: @escaping (_ notifyAndCheckIfCanProceed: @escaping ()->Bool)->(),
        onSuccess: @escaping ()->(),
        onTimeout: @escaping ()->())
    {
        assert(timeout >= TimeInterval.zero)
        queue.addOperation { [self] in // strong self
            assert(!Thread.isMainThread)
            
            let semaphore = DispatchSemaphore(value: 0)
            
            var isCancelled = false
            var isFinished = false
            slowAsyncOperation { [weak self] in
                // Got a notification call from the slow operation's callback
                guard let self = self else {
                    return false // abort the slow operation, there's nobody left
                }
                semaphore.signal()
                self.synchronized {
                    if !isCancelled {
                        isFinished = true
                    }
                }
                return isFinished // can proceed if was not cancelled
            }
            
            if semaphore.wait(timeout: .now() + timeout) == .timedOut {
                self.synchronized {
                    if !isFinished {
                        isCancelled = true
                    }
                }
            }
            
            if isFinished {
                onSuccess()
            } else {
                onTimeout()
            }
        }
    }
}
