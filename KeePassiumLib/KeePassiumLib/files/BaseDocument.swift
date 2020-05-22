//  KeePassium Password Manager
//  Copyright © 2020 Andrei Popleteev <info@keepassium.com>
// 
//  This program is free software: you can redistribute it and/or modify it
//  under the terms of the GNU General Public License version 3 as published
//  by the Free Software Foundation: https://www.gnu.org/licenses/).
//  For commercial licensing, please contact the author.

import UIKit

/// Generic document to access external files.
public class BaseDocument: UIDocument {
    public typealias OpenCallback = (Result<ByteArray, FileAccessError>) -> Void
    
    public internal(set) var data = ByteArray()
    public private(set) var error: FileAccessError?
    public var hasError: Bool { return error != nil }
    
    public func open(_ callback: @escaping OpenCallback) {
        // TODO: add a timeout to this
        super.open {
            [weak self] (success) in
            guard let self = self else { return }
            if success {
                self.error = nil
                callback(.success(self.data))
            } else {
                guard let error = self.error else {
                    // This should not happen, but might. So we'll gracefully throw
                    // a generic error instead of crashing on force-unwrap.
                    assertionFailure()
                    callback(.failure(.internalError))
                    return
                }
                callback(.failure(error))
            }
        }
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
