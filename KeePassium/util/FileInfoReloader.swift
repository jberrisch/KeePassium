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
        for urlRef in refs {
            refreshQueue.async {
                urlRef.refreshInfo(timeout: FileInfoReloader.timeout) { result in
                    switch result {
                    case .success(let fileInfo):
                        updateHandler(urlRef, fileInfo)
                    case .failure(let error):
                        Diag.warning("Failed to get file info [reason: \(error.localizedDescription)]")
                        updateHandler(urlRef, nil)
                    }
                }
            }
        }
        refreshQueue.asyncAfter(deadline: .now(), qos: .background, flags: .barrier) {
            DispatchQueue.main.async {
                completion()
            }
        }
    }
}
