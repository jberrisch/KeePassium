//  KeePassium Password Manager
//  Copyright © 2020 Andrei Popleteev <info@keepassium.com>
// 
//  This program is free software: you can redistribute it and/or modify it
//  under the terms of the GNU General Public License version 3 as published
//  by the Free Software Foundation: https://www.gnu.org/licenses/).
//  For commercial licensing, please contact the author.

import UIKit

/// Generic document to access external files.
public class BaseDocument: UIDocument, Synchronizable {
    public static let timeout = URLReference.defaultTimeout
    
    public typealias OpenCallback = (Result<ByteArray, FileAccessError>) -> Void
    
    public internal(set) var data = ByteArray()
    public internal(set) var error: FileAccessError?
    public var hasError: Bool { return error != nil }
    
    private let backgroundQueue = DispatchQueue(
        label: "com.keepassium.Document",
        qos: .default,
        attributes: [.concurrent])
    
    public func open(_ callback: @escaping OpenCallback) {
        self.open(withTimeout: BaseDocument.timeout, callback)
    }
    
    public func open(withTimeout timeout: TimeInterval, _ callback: @escaping OpenCallback) {
        execute(
            withTimeout: BaseDocument.timeout,
            on: backgroundQueue,
            slowAsyncOperation: {
                [weak self] (_ notifyAndCheckIfCanProceed: @escaping ()->Bool) -> () in
                // `superOpen()` might take forever
                self?.superOpen {
                    [weak self] (success) in
                    guard let self = self else { return }

                    // Notify the timeout trigger that we've done with the slow part.
                    // It returns `false` if timeout has already happened.
                    guard notifyAndCheckIfCanProceed() else {
                        // already timed out -> close the document, we won't need it
                        self.close(completionHandler: nil)
                        return
                    }
                    if let error = self.error {
                        callback(.failure(error))
                    } else {
                        callback(.success(self.data))
                    }
                }
                
            }, onSuccess: {
                // Yay, we've opened the document before the timeout!
                // Nothing else to do, everything will be done in the callback above.
            }, onTimeout: {
                self.error = .timeout
                callback(.failure(.timeout))
            }
        )
    }

    // Workaround for `super.` being unavailable in a callback.
    private func superOpen(_ callback: @escaping (_ success: Bool)->()) {
        super.open(completionHandler: callback)
    }
    
    override public func contents(forType typeName: String) throws -> Any {
        error = nil
        return data.asData
    }
    
    override public func load(fromContents contents: Any, ofType typeName: String?) throws {
        assert(contents is Data)
        error = nil
        if let contents = contents as? Data {
            data = ByteArray(data: contents)
        } else {
            data = ByteArray()
        }
    }
    
    override public func handleError(_ error: Error, userInteractionPermitted: Bool) {
        self.error = .accessError(error)
        super.handleError(error, userInteractionPermitted: userInteractionPermitted)
    }
}
