//  KeePassium Password Manager
//  Copyright © 2018–2019 Andrei Popleteev <info@keepassium.com>
//
//  This program is free software: you can redistribute it and/or modify it
//  under the terms of the GNU General Public License version 3 as published
//  by the Free Software Foundation: https://www.gnu.org/licenses/).
//  For commercial licensing, please contact the author.

import Foundation

public enum ChallengeResonseError: Error {
    /// Challenge-response feature is not supported by hardware
    case notSupportedByHardware
    /// Challenge-response feature is not supported by the database format (kdb or kdbx3)
    case notSupportedByDatabaseFormat
    
    case communicationError(message: String)
}

public typealias ChallengeHandler =
    (_ challenge: SecureByteArray, _ responseHandler: @escaping ResponseHandler) -> Void

public typealias ResponseHandler =
    (_ response: SecureByteArray, _ error: ChallengeResonseError?) -> Void
