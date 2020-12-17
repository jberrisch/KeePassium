//  KeePassium Password Manager
//  Copyright © 2018–2019 Andrei Popleteev <info@keepassium.com>
// 
//  This program is free software: you can redistribute it and/or modify it
//  under the terms of the GNU General Public License version 3 as published
//  by the Free Software Foundation: https://www.gnu.org/licenses/).
//  For commercial licensing, please contact the author.

import Foundation

class KeyHelper1: KeyHelper {
    override init() {
        super.init()
    }
    
    /// Converts the password string to its raw-bytes representation, according to DB version rules.
    override func getPasswordData(password: String) -> SecureByteArray {
        guard let data = password.data(using: .isoLatin1, allowLossyConversion: true) else {
            fatalError("getPasswordData(KP1): Failed lossy conversion to ISO Latin 1")
        }
        return SecureByteArray(data: data)
    }
    
    /// - Throws: `KeyFileError`
    override func combineComponents(
        passwordData: SecureByteArray,
        keyFileData: ByteArray
    ) throws -> SecureByteArray {
        let hasPassword = !passwordData.isEmpty
        let hasKeyFile = !keyFileData.isEmpty
        
        if hasPassword && hasKeyFile {
            Diag.info("Using password and key file")
            let preKey = SecureByteArray.concat(
                passwordData.sha256,
                try processKeyFile(keyFileData: keyFileData)) // throws KeyFileError
            return preKey.sha256
        } else if hasPassword {
            Diag.info("Using password")
            return passwordData.sha256
        } else if hasKeyFile {
            Diag.info("Using key file")
            // in KP1, XML files are returned as is (in KP2 undergoes another sha256)
            return try processKeyFile(keyFileData: keyFileData) // throws KeyFileError
        } else {
            // The caller must ensure that some other key component
            // (challenge-response handler) is not empty.
            Diag.warning("Both password and key file are empty after being checked.")
            return SecureByteArray().sha256
        }
    }
    
    override func getKey(fromCombinedComponents combinedComponents: SecureByteArray) -> SecureByteArray {
        return combinedComponents // they are already hashed
    }
    
    /// - Throws: `KeyFileError`
    override func processXmlKeyFile(keyFileData: ByteArray) throws -> SecureByteArray? {
        // By design, KP1 does not handle XML key files in any special manner.
        return nil
    }
}
