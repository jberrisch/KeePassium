//  KeePassium Password Manager
//  Copyright © 2018–2019 Andrei Popleteev <info@keepassium.com>
// 
//  This program is free software: you can redistribute it and/or modify it
//  under the terms of the GNU General Public License version 3 as published
//  by the Free Software Foundation: https://www.gnu.org/licenses/).
//  For commercial licensing, please contact the author.

import Foundation
import KeePassiumLib

/// Helper class to manage reloading of `URLReference` attributes.
class FileInfoReloader {
    /// wait time before giving up on a reference
    static let timeout = URLReference.defaultTimeout
    
    private let refreshQueue = DispatchQueue(
        label: "com.keepassium.FileInfoReloader",
        qos: .background,
        attributes: .concurrent)
    private var dispatchGroup: DispatchGroup?
    
    /// True while not all the references have been refreshed
    public var isRefreshing: Bool {
        return dispatchGroup != nil
    }
    
    private var processedRefs = [URLReference]()
    
    /// Returns true iff the given reference has already been processed.
    public func isProcessed(_ urlRef: URLReference) -> Bool {
        return processedRefs.contains(urlRef)
    }
    
    /// Called once info for the`ref` reference has been reloaded.
    /// If successful, `fileInfo` contains the new info.
    /// Otherwise, `fileInfo` will be `nil` and `ref.error` will contain the error information.
    typealias UpdateHandler = (_ ref: URLReference, _ fileInfo: FileInfo?) -> ()
    
    /// The caller is responsible for avoiding excessive calls.
    public func getInfo(
        for refs: [URLReference],
        update updateHandler: @escaping UpdateHandler,
        completion: @escaping ()->())
    {
        guard dispatchGroup == nil else {
            assertionFailure("A refresh is already ongoing")
            completion()
            return
        }
        processedRefs.removeAll(keepingCapacity: true)
        let dispatchGroup = DispatchGroup()
        self.dispatchGroup = dispatchGroup
        for urlRef in refs {
            let workItem = DispatchWorkItem {
                let semaphore = DispatchSemaphore(value: 0)
                urlRef.refreshInfo(timeout: FileInfoReloader.timeout) { [self] (result) in // strong self
                    self.processedRefs.append(urlRef)
                    switch result {
                    case .success(let fileInfo):
                        updateHandler(urlRef, fileInfo)
                    case .failure(let error):
                        Diag.warning("Failed to get file info [reason: \(error.localizedDescription)]")
                        updateHandler(urlRef, nil)
                    }
                    semaphore.signal()
                }
                // stay in the dispatch group until refreshInfo() completes
                semaphore.wait()
            }
            refreshQueue.async(group: dispatchGroup, execute: workItem)
        }
        dispatchGroup.notify(queue: refreshQueue) { [self] in // strong self
            // all the refs have been refreshed, so we can call the completion handler.
            self.dispatchGroup = nil
            DispatchQueue.main.async {
                completion()
            }
        }
    }
}
