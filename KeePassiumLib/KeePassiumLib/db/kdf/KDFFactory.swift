//  KeePassium Password Manager
//  Copyright © 2018–2019 Andrei Popleteev <info@keepassium.com>
// 
//  This program is free software: you can redistribute it and/or modify it
//  under the terms of the GNU General Public License version 3 as published
//  by the Free Software Foundation: https://www.gnu.org/licenses/).
//  For commercial licensing, please contact the author.

import Foundation

/// Protocol for key derivation functions
protocol KeyDerivationFunction {
    /// Predefined UUID of this KDF
    var uuid: UUID { get }
    /// Human-readable KDF name
    var name: String { get }
    /// A `KDFParams` instance prefilled with some reasonable default values
    var defaultParams: KDFParams { get }
    
    /// Returns a fresh instance of key derivation progress
    func initProgress() -> ProgressEx

    init()
    
    /// Performs key transformation using given params.
    /// - Throws: CryptoError, ProgressInterruption
    /// - Returns: resulting key
    func transform(key: SecureByteArray, params: KDFParams) throws -> SecureByteArray
    
    /// Returns the parameter that should be used for challenge-response.
    /// Throws `CryptoError.invalidKDFParam`
    func getChallenge(_ params: KDFParams) throws -> ByteArray
    
    /// Randomize KDF parameters (before saving the DB)
    /// - Throws: CryptoError.rngError
    func randomize(params: inout KDFParams) throws
}

/// Creates a KDF instance by its UUID.
final class KDFFactory {
    private static let argon2kdf = Argon2KDF()
    private static let aeskdf = AESKDF()

    private init() {
        // nothing to do here
    }
    
    /// - Returns: a suitable KDF instance, or `nil` for unknown UUID.
    public static func createFor(uuid: UUID) -> KeyDerivationFunction? {
        switch uuid {
        case argon2kdf.uuid:
            Diag.info("Creating Argon2 KDF")
            return Argon2KDF()
        case aeskdf.uuid:
            Diag.info("Creating AES KDF")
            return AESKDF()
        default:
            Diag.warning("Unrecognized KDF UUID")
            return nil
        }
    }
}
