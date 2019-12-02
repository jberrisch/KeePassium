//  KeePassium Password Manager
//  Copyright © 2018–2019 Andrei Popleteev <info@keepassium.com>
// 
//  This program is free software: you can redistribute it and/or modify it
//  under the terms of the GNU General Public License version 3 as published
//  by the Free Software Foundation: https://www.gnu.org/licenses/).
//  For commercial licensing, please contact the author.

import Foundation
//import AEXML

final class KeyHelper2: KeyHelper {
    
    override init() {
        super.init()
    }
    
    /// Converts the password string to its raw-bytes representation, according to DB version rules.
    override func getPasswordData(password: String) -> SecureByteArray {
        return SecureByteArray(data: Data(password.utf8))
    }
    
    override func makeCompositeKey(
        passwordData: SecureByteArray,
        keyFileData: ByteArray
    ) -> SecureByteArray {
        let hasPassword = !passwordData.isEmpty
        let hasKeyFile = !keyFileData.isEmpty

        precondition(hasPassword || hasKeyFile)
        
        let preKey: SecureByteArray
        if hasPassword && hasKeyFile {
            Diag.info("Using password and key file")
            preKey = SecureByteArray.concat(
                passwordData.sha256,
                processKeyFile(keyFileData: keyFileData))
        } else if hasPassword {
            Diag.info("Using password only")
            preKey = passwordData.sha256
        } else if hasKeyFile {
            Diag.info("Using key file only")
            preKey = processKeyFile(keyFileData: keyFileData)
            // in KP2, preKey is kept for another sha256 (in KP1, is returned as is)
        } else {
            // Nothing is provided. This should have already been checked above.
            fatalError("Both password and key file are empty after being checked.")
        }
        return preKey.sha256
    }
    
    /// Tries to extract key data from KeePass v2.xx XML file.
    /// - Returns: key data, or nil in case of any issues.
    internal override func processXmlKeyFile(keyFileData: ByteArray) -> SecureByteArray? {
        do {
            let xml = try AEXMLDocument(xml: keyFileData.asData)
            // version = xml[Xml2.keyFile][Xml2.meta][Xml2.version].value // unused
            let base64 = xml[Xml2.keyFile][Xml2.key][Xml2.data].value
            guard let out = ByteArray(base64Encoded: base64) else {
                return nil
            }
            return SecureByteArray(out)
        } catch {
            return nil
        }
    }
}
