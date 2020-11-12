//  KeePassium Password Manager
//  Copyright © 2018–2019 Andrei Popleteev <info@keepassium.com>
// 
//  This program is free software: you can redistribute it and/or modify it
//  under the terms of the GNU General Public License version 3 as published
//  by the Free Software Foundation: https://www.gnu.org/licenses/).
//  For commercial licensing, please contact the author.

import Foundation

public class KeyHelper {
    public static let compositeKeyLength = 32
    internal let keyFileKeyLength = 32
    
    /// Combines given key components into a format-specific key.
    /// Both can be empty simultaneously, but then there should be a challenge-response handler (defined separately)
    /// (Pure virtual method, must be overriden)
    ///
    /// - Parameter: passwordData - password data (possibly empty)
    /// - Parameter: keyFileData - key file data (possibly empty)
    /// - Returns: composite key (possibly empty)
    public func combineComponents(passwordData: SecureByteArray, keyFileData: ByteArray) -> SecureByteArray {
        fatalError("Pure virtual method")
    }
    
    public func getKey(fromCombinedComponents combinedComponents: SecureByteArray) -> SecureByteArray {
        fatalError("Pure virtual method")
    }
    
    /// Converts the password string to its raw-bytes representation, according to DB version rules.
    public func getPasswordData(password: String) -> SecureByteArray {
        fatalError("Pure virtual method")
    }
    
    /// Extracts key from a key file
    public func processKeyFile(keyFileData: ByteArray) -> SecureByteArray {
        assert(!keyFileData.isEmpty, "keyFileData cannot be empty here")

        if keyFileData.count == keyFileKeyLength {
            // assume the data is a 32-byte key
            Diag.debug("Key file format is: binary")
            return SecureByteArray(keyFileData)
        } else if keyFileData.count == 2 * keyFileKeyLength {
            // maybe it is a 64-byte hex encoded key?
            let hexString = keyFileData.toString(using: .ascii)
            if let hexString = hexString {
                if let key = ByteArray(hexString: hexString) {
                    Diag.debug("Key file format is: base64")
                    return SecureByteArray(key)
                }
            }
        }
        
        // is it an XML key file?
        if let key = processXmlKeyFile(keyFileData: keyFileData) {
            Diag.debug("Key file format is: XML")
            return key
        }
        
        // it is something else, just hash it
        Diag.debug("Key file format is: other")
        return SecureByteArray(keyFileData.sha256)
    }
    
    /// Tries to extract key from XML key file.
    /// (To be subclassed for format-dependent processing)
    /// - Returns: extracted key, or nil if failed to extract.
    public func processXmlKeyFile(keyFileData: ByteArray) -> SecureByteArray? {
        return nil
    }
}


