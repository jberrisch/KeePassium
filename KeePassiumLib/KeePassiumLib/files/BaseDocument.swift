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
    public var errorMessage: String? { error?.localizedDescription }
    public var hasError: Bool { return error != nil }
    
    private let backgroundQueue = DispatchQueue(
        label: "com.keepassium.Document",
        qos: .default,
        attributes: [.concurrent])
    
    /// Attempts to open the document with a default timeout (`BaseDocument.timeout`).
    /// - Parameter callback: called with the result of opening (either document data or a `FileAccessError`)
    public func open(_ callback: @escaping OpenCallback) {
        self.open(withTimeout: BaseDocument.timeout, callback)
    }
    
    /// Attempts to open the document within the specified timeout.
    /// - Parameters:
    ///   - timeout: timeout for the operation.
    ///   - callback: called once the document opens or fails to open (due to an error or timeout)
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
    
    public func save(_ completion: @escaping((Result<Void, FileAccessError>) -> Void)) {
        super.save(to: fileURL, for: .forOverwriting, completionHandler: {
            [weak self] (success) in // strong self
            guard let self = self else { return }
            if success {
                self.error = nil
                completion(.success)
            } else {
                if let error = self.error {
                    completion(.failure(error))
                } else {
                    Diag.error("Saving unsuccessful, but without error info.")
                    completion(.failure(.internalError))
                }
            }
        })
    }
    
    public func close(_ completion: @escaping ((Result<Void, FileAccessError>) -> Void)) {
        super.close(completionHandler: {
            [weak self] (success) in
            guard let self = self else { return }
            if success {
                self.error = nil
                completion(.success)
            } else {
                if let error = self.error {
                    completion(.failure(error))
                } else {
                    Diag.error("Closing unsuccessful, but without error info.")
                    completion(.failure(.internalError))
                }
            }
        })
    }
    
    override public func handleError(_ error: Error, userInteractionPermitted: Bool) {
        self.error = .accessError(error)
        super.handleError(error, userInteractionPermitted: userInteractionPermitted)
    }
}
