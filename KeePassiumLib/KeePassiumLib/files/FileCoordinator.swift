//  KeePassium Password Manager
//  Copyright © 2020 Andrei Popleteev <info@keepassium.com>
//
//  This program is free software: you can redistribute it and/or modify it
//  under the terms of the GNU General Public License version 3 as published
//  by the Free Software Foundation: https://www.gnu.org/licenses/).
//  For commercial licensing, please contact the author.

import Foundation

class FileCoordinator: NSFileCoordinator, Synchronizable {
    /// Queue for asynchronous URLReference operations
    fileprivate static let backgroundQueue: OperationQueue = {
        let queue = OperationQueue()
        queue.name = "com.keepassium.FileCoordinator"
        queue.qualityOfService = .default
        queue.maxConcurrentOperationCount = 8
        return queue
    }()
    
    /// Queue for coordinated reads
    fileprivate static let coordinationQueue = OperationQueue()
    
    typealias ReadingCallback = (FileAccessError?) -> ()
    
    public func coordinateReading(
        at url: URL,
        fileProvider: FileProvider?,
        options: NSFileCoordinator.ReadingOptions,
        timeout: TimeInterval,
        callback: @escaping ReadingCallback)
    {
        execute(
            withTimeout: timeout,
            on: FileCoordinator.backgroundQueue,
            slowAsyncOperation: {
                [weak self] (_ notifyAndCheckIfCanProceed: @escaping ()->Bool) -> () in
                // `coordinate()` might take forever
                self?.coordinate(
                    with: [.readingIntent(with: url, options: options)],
                    queue: FileCoordinator.coordinationQueue)
                {
                    (error) in
                    // Notify the timeout trigger that we've done with the slow part.
                    // It returns `false` if timeout has already happened.
                    guard notifyAndCheckIfCanProceed() else {
                        // already timed out
                        return
                    }
                    if let error = error {
                        callback(FileAccessError.make(from: error, fileProvider: fileProvider))
                    } else {
                        callback(nil)
                    }
                }
                
            }, onSuccess: {
                // Yay, we've got into the coordinated read before timeout!
                // Nothing else to do, everything will be done in the callback above.
            }, onTimeout: {
                callback(.timeout(fileProvider: fileProvider))
            }
        )
    }
}
