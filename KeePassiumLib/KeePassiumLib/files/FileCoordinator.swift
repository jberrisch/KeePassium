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
    fileprivate let backgroundQueue = DispatchQueue(
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
        execute(
            withTimeout: timeout,
            on: backgroundQueue,
            slowAsyncOperation: {
                [weak self] (_ notifyAndCheckIfCanProceed: @escaping ()->Bool) -> () in
                // `coordinate()` might take forever
                self?.coordinate(
                    with: [.readingIntent(with: url, options: options)],
                    queue: FileCoordinator.operationQueue)
                {
                    (error) in
                    // Notify the timeout trigger that we've done with the slow part.
                    // It returns `false` if timeout has already happened.
                    guard notifyAndCheckIfCanProceed() else {
                        // already timed out
                        return
                    }
                    if let error = error {
                        callback(.accessError(error))
                    } else {
                        callback(nil)
                    }
                }
                
            }, onSuccess: {
                // Yay, we've got into the coordinated read before timeout!
                // Nothing else to do, everything will be done in the callback above.
            }, onTimeout: {
                callback(.timeout)
            }
        )
    }
}
