//  KeePassium Password Manager
//  Copyright © 2020 Andrei Popleteev <info@keepassium.com>
//
//  This program is free software: you can redistribute it and/or modify it
//  under the terms of the GNU General Public License version 3 as published
//  by the Free Software Foundation: https://www.gnu.org/licenses/).
//  For commercial licensing, please contact the author.

import Foundation

class FileCoordinator: NSFileCoordinator, Synchronizable {
    /// Dispatch queue for asynchronous URLReference operations
    fileprivate static let queue = DispatchQueue(
        label: "com.keepassium.FileCoordinator",
        qos: .default,
        attributes: [.concurrent])
    
    /// Queue for coordinated reads
    fileprivate static let operationQueue = OperationQueue()
    
    typealias ReadingCallback = (FileAccessError?) -> ()
    
    public func coordinateReading(
        at url: URL,
        options: NSFileCoordinator.ReadingOptions,
        timeout: TimeInterval,
        callback: @escaping ReadingCallback)
    {
        FileCoordinator.queue.async { [self] in
            self.coordinateReadingInternal(
                at: url,
                options: options,
                timeout: timeout,
                callback: callback
            )
        }
    }
    
    private func coordinateReadingInternal(
        at url: URL,
        options: NSFileCoordinator.ReadingOptions,
        timeout: TimeInterval,
        callback: @escaping ReadingCallback)
    {
        assert(!Thread.isMainThread)
        
        let waitSemaphore = DispatchSemaphore(value: 0)
        var hasTimedOut = false
        
        // start the slow stuff in background
        coordinate(
            with: [.readingIntent(with: url, options: options)],
            queue: FileCoordinator.operationQueue)
        {
            (error) in // strong self
            waitSemaphore.signal()
            guard !hasTimedOut else { return }
            
            if let error = error {
                callback(.accessError(error)) // wrapped error
            } else {
                callback(nil) // all good
            }
        }
        
        guard waitSemaphore.wait(timeout: DispatchTime.now() + timeout) != .timedOut else {
            hasTimedOut = true
            DispatchQueue.main.async {
                callback(.timeout)
            }
            return
        }
    }
}
