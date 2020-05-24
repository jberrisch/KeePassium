//  KeePassium Password Manager
//  Copyright © 2018–2019 Andrei Popleteev <info@keepassium.com>
// 
//  This program is free software: you can redistribute it and/or modify it
//  under the terms of the GNU General Public License version 3 as published
//  by the Free Software Foundation: https://www.gnu.org/licenses/).
//  For commercial licensing, please contact the author.

import Foundation

final class AESDataCipher: DataCipher {
    private let _uuid = UUID(uuid:
        (0x31,0xC1,0xF2,0xE6,0xBF,0x71,0x43,0x50,0xBE,0x58,0x05,0x21,0x6A,0xFC,0x5A,0xFF))
    var uuid: UUID { return _uuid }
    var name: String { return "AES" }
    
    var initialVectorSize: Int { return kCCBlockSizeAES128 }
    var keySize: Int { return kCCKeySizeAES256 }

    internal var progress = ProgressEx()

    init() {
        // left empty
    }
    
    /// Encrypts `plainText` using AES in CBC mode (automatically adding PKCS7 padding).
    /// - Parameter: data - plain text data
    /// - Parameter: key - encryption key (32 bytes)
    /// - Parameter: iv - initial vector (16 bytes)
    /// - Throws: `CryptoError.aesEncryptError`, `ProgressInterruption`
    /// - Returns: encrypted data
    func encrypt(plainText data: ByteArray, key: ByteArray, iv: ByteArray) throws -> ByteArray {
        assert(key.count == kCCKeySizeAES256)
        assert(iv.count == kCCBlockSizeAES128)
        progress.localizedDescription = NSLocalizedString(
            "[Cipher/Progress] Encrypting",
            bundle: Bundle.framework,
            value: "Encrypting",
            comment: "Progress status")
        
        let operation: CCOperation = UInt32(kCCEncrypt)
        let algoritm: CCAlgorithm = UInt32(kCCAlgorithmAES)
        let options: CCOptions = UInt32(kCCOptionPKCS7Padding)
        
        progress.completedUnitCount = 0
        progress.totalUnitCount = Int64(data.count)
        // out buffer needs additional space for padding
        let out = ByteArray(count: data.count + kCCBlockSizeAES128)
        var numBytesEncrypted: size_t = 0
        let status = data.withBytes { dataBytes in
            return key.withBytes{ keyBytes in
                return iv.withBytes{ ivBytes in
                    return out.withMutableBytes { (outBytes: inout [UInt8]) in
                        return CCCrypt(
                            operation, algoritm, options,
                            keyBytes, keyBytes.count,
                            ivBytes,
                            dataBytes, dataBytes.count,
                            &outBytes, outBytes.count,
                            &numBytesEncrypted
                        )
                    }
                }
            }
        }
        //TODO: check if need fine-grained progress tracking here
        progress.completedUnitCount = Int64(data.count)
        if progress.isCancelled {
            throw ProgressInterruption.cancelled(reason: progress.cancellationReason)
        }
        
        debugPrint("encrypted size: \(numBytesEncrypted) bytes")
        guard status == UInt32(kCCSuccess) else {
            throw CryptoError.aesEncryptError(code: Int(status))
        }
        out.trim(toCount: numBytesEncrypted)
        return out
    }
    
    /// Decrypts data with AES in CBC mode, also removing PKCS7 padding.
    /// - Parameter: key - 32 bytes
    /// - Parameter: iv - initial vector (16 bytes)
    /// - Parameter: encData - encrypted data, size must be a multiple of 16.
    /// - Throws: `CryptoError.aesDecryptError`, `ProgressInterruption`
    /// - Returns: decrypted data
    func decrypt(cipherText encData: ByteArray, key: ByteArray, iv: ByteArray) throws -> ByteArray {
        assert(key.count == kCCKeySizeAES256)
        assert(iv.count == kCCBlockSizeAES128)
        assert(encData.count % kCCBlockSizeAES128 == 0)
        
        progress.localizedDescription = NSLocalizedString(
            "[Cipher/Progress] Decrypting",
            bundle: Bundle.framework,
            value: "Decrypting",
            comment: "Progress status")
        
        let operation: CCOperation = UInt32(kCCDecrypt)
        let algoritm: CCAlgorithm = UInt32(kCCAlgorithmAES)
        let options: CCOptions = UInt32(kCCOptionPKCS7Padding)
        
        progress.completedUnitCount = 0
        progress.totalUnitCount = Int64(encData.count)
        var numBytesDecrypted: size_t = 0
        let out = ByteArray(count: encData.count)
        let status = encData.withBytes { encDataBytes in
            return key.withBytes{ keyBytes in
                return iv.withBytes{ ivBytes in
                    return out.withMutableBytes { (outBytes: inout [UInt8]) in
                        return CCCrypt(
                            operation, algoritm, options,
                            keyBytes, keyBytes.count,
                            ivBytes,
                            encDataBytes, encDataBytes.count,
                            &outBytes, outBytes.count,
                            &numBytesDecrypted
                        )
                    }
                }
            }
        }
        //TODO: check if need fine-grained progress tracking here
        progress.completedUnitCount = Int64(encData.count)
        if progress.isCancelled {
            throw ProgressInterruption.cancelled(reason: progress.cancellationReason)
        }
        
        debugPrint("decrypted \(numBytesDecrypted) bytes")
        guard status == UInt32(kCCSuccess) else {
            throw CryptoError.aesDecryptError(code: Int(status))
        }
        out.trim(toCount: numBytesDecrypted)
//        print("key: \(key.asHexString)")
//        print("iv: \(iv.asHexString)")
//        print("encData (16): \(encData.prefix(16).asHexString)")
//        print("outData (-16): \(plainText.suffix(16).asHexString)")
//        print("outData size: \(numBytesDecrypted)")
        return out
    }
}
