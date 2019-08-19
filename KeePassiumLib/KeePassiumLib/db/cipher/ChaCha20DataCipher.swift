//  KeePassium Password Manager
//  Copyright © 2018–2019 Andrei Popleteev <info@keepassium.com>
// 
//  This program is free software: you can redistribute it and/or modify it
//  under the terms of the GNU General Public License version 3 as published
//  by the Free Software Foundation: https://www.gnu.org/licenses/).
//  For commercial licensing, please contact the author.

import Foundation

final class ChaCha20DataCipher: DataCipher {
    private let _uuid = UUID(uuid:
        (0xD6,0x03,0x8A,0x2B,0x8B,0x6F,0x4C,0xB5,0xA5,0x24,0x33,0x9A,0x31,0xDB,0xB5,0x9A))
    var uuid: UUID { return _uuid }
    var name: String { return "ChaCha20" }
    
    var initialVectorSize: Int { return 12 } // 96 bits
    var keySize: Int { return 32 }
    private var progress = ProgressEx()

    init() {
        // left empty
    }
    
    func initProgress() -> ProgressEx {
        progress = ProgressEx()
        return progress
    }
    
    /// - Throws: `ProgressInterruption`
    func encrypt(plainText: ByteArray, key: ByteArray, iv: ByteArray) throws -> ByteArray {
        progress.localizedDescription = NSLocalizedString(
            "[Cipher/Progress] Encrypting",
            value: "Encrypting",
            comment: "Progress status")
        
        let chacha20 = ChaCha20(key: key, iv: iv)
        return try chacha20.encrypt(data: plainText, progress: progress) // throws ProgressInterruption
    }
    
    /// - Throws: `ProgressInterruption`
    func decrypt(cipherText: ByteArray, key: ByteArray, iv: ByteArray) throws -> ByteArray {
        progress.localizedDescription = NSLocalizedString(
            "[Cipher/Progress] Decrypting",
            value: "Decrypting",
            comment: "Progress status")
        
        let chacha20 = ChaCha20(key: key, iv: iv)
        return try chacha20.decrypt(data: cipherText, progress: progress) // throws ProgressInterruption
    }
}
