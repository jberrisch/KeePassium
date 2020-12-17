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
    
    // Throws: `KeyFileError`
    override func combineComponents(
        passwordData: SecureByteArray,
        keyFileData: ByteArray
    ) throws -> SecureByteArray {
        let hasPassword = !passwordData.isEmpty
        let hasKeyFile = !keyFileData.isEmpty
        
        var preKey = SecureByteArray()
        if hasPassword {
            Diag.info("Using password")
            preKey = SecureByteArray.concat(preKey, passwordData.sha256)
        }
        if hasKeyFile {
            Diag.info("Using key file")
            preKey = SecureByteArray.concat(
                preKey,
                try processKeyFile(keyFileData: keyFileData) // throws KeyFileError
            )
        }
        if preKey.isEmpty {
            // The caller must ensure that some other key component
            // (e.g. challenge-response handler) is not empty.
            Diag.warning("All key components are empty after being checked.")
        }
        return preKey // not hashed yet
    }
    
    override func getKey(fromCombinedComponents combinedComponents: SecureByteArray) -> SecureByteArray {
        return combinedComponents.sha256
    }
    
    /// Tries to extract key data from KeePass v2.xx XML file.
    /// - Returns: key data, or nil in case of any issues.
    /// - Throws: KeyFileError
    internal override func processXmlKeyFile(keyFileData: ByteArray) throws -> SecureByteArray? {
        let xml = try AEXMLDocument(xml: keyFileData.asData)
        let version = xml[Xml2.keyFile][Xml2.meta][Xml2.version].value
        switch version {
        case "2.0":
            let result = try processXMLFileVersion2(xml) // throws KeyFileError
            return result
        case "1.0":
            let result = try processXMLFileVersion1(xml) // throws KeyFileError
            return result
        default:
            throw KeyFileError.unsupportedFormat
        }
    }
    
    /// - Throws: `KeyFileError`
    private func processXMLFileVersion1(_ xml: AEXMLDocument) throws -> SecureByteArray? {
        guard let base64 = xml[Xml2.keyFile][Xml2.key][Xml2.data].value else {
            Diag.warning("Empty Base64 value")
            return nil
        }
        guard let keyData = ByteArray(base64Encoded: base64) else {
            Diag.error("Invalid Base64 string")
            throw KeyFileError.keyFileCorrupted
        }
        return SecureByteArray(keyData)
    }
    
    /// - Throws: `KeyFileError`
    private func processXMLFileVersion2(_ xml: AEXMLDocument) throws -> SecureByteArray? {
        let rawHexString = xml[Xml2.keyFile][Xml2.key][Xml2.data].value
        guard let hexString = rawHexString?.filter({ !$0.isWhitespace }),
              hexString.isNotEmpty
        else {
            Diag.warning("Empty key data")
            throw KeyFileError.keyFileCorrupted
        }
        
        guard let keyData = ByteArray(hexString: hexString) else {
            Diag.error("Invalid hex string")
            throw KeyFileError.keyFileCorrupted
        }
        
        if let hashString = xml[Xml2.keyFile][Xml2.key][Xml2.data].attributes[Xml2.hash] {
            // hash present, must verify it
            guard let hashData = ByteArray(hexString: hashString) else {
                Diag.error("Invalid hash hex string")
                throw KeyFileError.keyFileCorrupted
            }
            guard keyData.sha256.prefix(4) == hashData else {
                Diag.error("Hash verification failed")
                throw KeyFileError.keyFileCorrupted
            }
        }
        return SecureByteArray(keyData)
    }
}
