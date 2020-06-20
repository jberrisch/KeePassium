//  KeePassium Password Manager
//  Copyright © 2018–2019 Andrei Popleteev <info@keepassium.com>
// 
//  This program is free software: you can redistribute it and/or modify it
//  under the terms of the GNU General Public License version 3 as published
//  by the Free Software Foundation: https://www.gnu.org/licenses/).
//  For commercial licensing, please contact the author.

import Foundation

final class TwofishDataCipher: DataCipher {
    private let _uuid = UUID(uuid:
        (0xad,0x68,0xf2,0x9f,0x57,0x6f,0x4b,0xb9,0xa3,0x6a,0xd4,0x7a,0xf9,0x65,0x34,0x6c))
    var uuid: UUID { return _uuid }
    var name: String { return "Twofish" }
    
    var initialVectorSize: Int { return Twofish.blockSize }
    var keySize: Int { return 32 }
    
    internal var progress = ProgressEx()
    
    /// Twofish plugin for KeePass2 pads with garbage instead of PKCS#7.
    /// And our XML parser does not like trailing garbage...
    /// If this flag is set, we will fallback to heuristics-based padding removal
    /// (searching for the final "</KeePassFile>").
    private let isPaddingLikelyMessedUp: Bool
    
    init(isPaddingLikelyMessedUp: Bool) {
        self.isPaddingLikelyMessedUp = isPaddingLikelyMessedUp
    }

    /// Encrypts `plainText` using Twofish (automatically adding PKCS7 padding).
    /// - Parameter: data - plain text data
    /// - Parameter: key - encryption key
    /// - Parameter: iv - initial vector
    /// - Throws: `CryptoError.twofishError`, `ProgressInterruption`
    /// - Returns: encrypted data
    func encrypt(plainText data: ByteArray, key: ByteArray, iv: ByteArray) throws -> ByteArray {
        assert(key.count == self.keySize)
        assert(iv.count == self.initialVectorSize)
        
        progress.localizedDescription = NSLocalizedString(
            "[Cipher/Progress] Encrypting",
            bundle: Bundle.framework,
            value: "Encrypting",
            comment: "Progress status")
        
        let twofish = Twofish(key: key, iv: iv)
        let dataClone = data.clone() //TODO: copying is redundant here
        CryptoManager.addPadding(data: dataClone, blockSize: Twofish.blockSize)
        try twofish.encrypt(data: dataClone, progress: progress)
            // throws CryptoError.twofishError, ProgressInterruption
        return dataClone
    }
    
    /// Decrypts data with Twofish, also removing PKCS7 padding.
    /// - Parameter: key - encryption key
    /// - Parameter: iv - initial vector
    /// - Parameter: encData - encrypted data
    /// - Throws: `CryptoError.twofishError`, `ProgressInterruption`
    /// - Returns: decrypted data
    func decrypt(cipherText encData: ByteArray, key: ByteArray, iv: ByteArray) throws -> ByteArray {
        assert(key.count == self.keySize)
        assert(iv.count == self.initialVectorSize)
        progress.localizedDescription = NSLocalizedString(
            "[Cipher/Progress] Decrypting",
            bundle: Bundle.framework,
            value: "Decrypting",
            comment: "Progress status")
        
        let twofish = Twofish(key: key, iv: iv) 
        let dataClone = encData.clone() //TODO: copying is redundant here
        try twofish.decrypt(data: dataClone, progress: progress)
            // throws CryptoError.twofishError, ProgressInterruption
        
        if isPaddingLikelyMessedUp {
            // The padding can be garbage, so ignore any errors for now
            // and postpone the clean-up to pre-XML-parsing phase
            try? CryptoManager.removePadding(data: dataClone) // throws CryptoError
        } else {
            try CryptoManager.removePadding(data: dataClone) // throws CryptoError
        }
        return dataClone
    }
}
