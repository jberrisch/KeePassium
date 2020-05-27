//  KeePassium Password Manager
//  Copyright © 2018–2019 Andrei Popleteev <info@keepassium.com>
//
//  This program is free software: you can redistribute it and/or modify it
//  under the terms of the GNU General Public License version 3 as published
//  by the Free Software Foundation: https://www.gnu.org/licenses/).
//  For commercial licensing, please contact the author.

import Foundation

/// Createssuitable TOTP generators for entries.
public class TOTPGeneratorFactory {
    
    /// Checks if the entry contains TOTP parameter field(s),
    /// and uses them to return a configured `TOTPGenerator` instance.
    public static func makeGenerator(for entry: Entry) -> TOTPGenerator? {
        return makeGenerator(from: entry.fields)
    }
    
    private static func find(_ name: String, in fields: [EntryField]) -> EntryField? {
        return fields.first(where: { $0.name == name })
    }
    
    /// Checks if `entry` contains TOTP parameter field(s),
    /// and uses them to return a configured `TOTPGenerator` instance.
    public static func makeGenerator(from fields: [EntryField]) -> TOTPGenerator? {
        if let totpField = find(SingleFieldFormat.fieldName, in: fields) {
            return parseSingleFieldFormat(totpField.value)
        } else {
            guard let seedField = find(SplitFieldFormat.seedFieldName, in: fields),
                let settingsField = find(SplitFieldFormat.settingsFieldName, in: fields)
                else { return nil }
            return SplitFieldFormat.parse(
                seedString: seedField.value,
                settingsString: settingsField.value)
        }
    }
    
    private static func parseSingleFieldFormat(_ paramString: String) -> TOTPGenerator? {
        guard let uriComponents = URLComponents(string: paramString) else {
            Diag.warning("Unexpected OTP field format")
            return nil
        }
        
        if GAuthFormat.isMatching(scheme: uriComponents.scheme, host: uriComponents.host) {
            return GAuthFormat.parse(uriComponents)
        }
        if KeeOtpFormat.isMatching(scheme: uriComponents.scheme, host: uriComponents.host) {
            return KeeOtpFormat.parse(paramString)
        }
        Diag.warning("Unrecognized OTP field format")
        return nil
    }
}


// MARK: - Format definitions

/// Single-field TOTP parameters format
fileprivate class SingleFieldFormat {
    static let fieldName = "otp"
}

/// Google Auth URI format
fileprivate class GAuthFormat: SingleFieldFormat {
    static let scheme = "otpauth"
    static let host = "totp"
    
    static let seedParam = "secret"
    static let timeStepParam = "period"
    static let lengthParam = "digits"
    static let algorithmParam = "algorithm"
    static let issuerParam = "issuer"
    static let encoderParam = "encoder" // KeePassXC custom param for Steam
    
    static let defaultTimeStep = 30
    static let defaultLength = 6
    static let defaultAlgorithm = TOTPHashAlgorithm.sha1
    
    /// Returns true iff given URI components match this format.
    static func isMatching(scheme: String?, host: String?) -> Bool {
        return scheme == GAuthFormat.scheme
    }
    
    /// Parses given TOTP parameters and returns a configured `TOTPGenerator` instance.
    ///
    /// - Parameters:
    ///   - parameters: TOTP parameters in Google Auth URI format, pre-parsed as `URLComponents`
    ///         (https://github.com/google/google-authenticator/wiki/Key-Uri-Format)
    /// - Returns: initialized `TOTPGenerator` instance
    static func parse(_ uriComponents: URLComponents) -> TOTPGenerator? {
        // otpauth://totp/ACME%20Co:john.doe@email.com?secret=HXDMVJECJJWSRB3HWIZR4IFUGFTMXBOZ&issuer=ACME%20Co&algorithm=SHA1&digits=6&period=30
        guard uriComponents.scheme == scheme,
            uriComponents.host == host,
            let queryItems = uriComponents.queryItems else
        {
            Diag.warning("OTP URI has unexpected format")
            return nil
        }
        
        let params = queryItems.reduce(into: [String: String]()) { (result, item) in
            result[item.name] = item.value
        }
        
        // The only required parameter is secret
        guard let seedString = params[seedParam],
            let seedData = base32DecodeToData(seedString),
            !seedData.isEmpty else
        {
            Diag.warning("OTP parameter cannot be parsed [parameter: \(seedParam)]")
            return nil
        }
        
        // timeStep must be either a valid int or missing
        guard let timeStep = Int(params[timeStepParam] ?? "\(defaultTimeStep)") else {
            Diag.warning("OTP parameter cannot be parsed [parameter: \(timeStepParam)]")
            return nil
        }
        
        let isSteam = uriComponents.path.starts(with: "/Steam:") ||
            (params[issuerParam] == "Steam") ||
            (params[encoderParam] == "steam")
        if isSteam {
            return TOTPGeneratorSteam(seed: ByteArray(data: seedData), timeStep: timeStep)
        }
        
        // algorithm, if defined, must be a supported one
        var algorithm: TOTPHashAlgorithm?
        if let algorithmString = params[algorithmParam] {
            guard let _algorithm = TOTPHashAlgorithm.fromString(algorithmString) else {
                Diag.warning("OTP algorithm is not supported [algorithm: \(algorithmString)]")
                return nil
            }
            algorithm = _algorithm
        }
        
        // length must be either a valid int or missing
        guard let length = Int(params[lengthParam] ?? "\(defaultLength)") else {
            Diag.warning("OTP parameter cannot be parsed [parameter: \(lengthParam)]")
            return nil
        }
        
        return TOTPGeneratorRFC6238(
            seed: ByteArray(data: seedData),
            timeStep: timeStep,
            length: length,
            hashAlgorithm: algorithm ?? defaultAlgorithm)
    }
}

/// KeeOtp query-string style format.
/// Example: {totp} = {key=BASE32KEY&step=30&size=8&type=TOTP&otpHashMode=SHA256}
fileprivate class KeeOtpFormat: SingleFieldFormat {
    static let seedParam = "key"
    static let timeStepParam = "step"
    static let lengthParam = "size"
    static let typeParam = "type"
    static let algorithmParam = "otpHashMode"
    
    static let defaultTimeStep = 30
    static let defaultLength = 6
    static let defaultAlgorithm = TOTPHashAlgorithm.sha1
    static let supportedType = "totp"
    
    /// Returns true iff given URI components match this format.
    static func isMatching(scheme: String?, host: String?) -> Bool {
        return (scheme == nil) && (host == nil)
    }

    /// Parses given KeeOtp-formatted parameter string,
    /// returns a configured `TOTPGenerator` instance.
    ///
    /// - Parameter paramString: parameter string
    ///         (for example, "key=BASE32KEY&step=30&size=8&type=TOTP&otpHashMode=SHA256")
    /// - Returns: configured TOTPGenerator instance.
    static func parse(_ paramString: String) -> TOTPGenerator? {
        // convert paramString to a dictionary, using URLComponents for heavy lifting
        guard let uriComponents = URLComponents(string: "fakeScheme://fakeHost?" + paramString),
            let queryItems = uriComponents.queryItems
            else { return nil }
        let params = queryItems.reduce(into: [String: String]()) { (result, item) in
            result[item.name] = item.value
        }
        
        // The only required parameter is secret
        guard let seedString = params[seedParam],
            let seedData = base32DecodeToData(seedString),
            !seedData.isEmpty else
        {
            Diag.warning("OTP parameter cannot be parsed [parameter: \(seedParam)]")
            return nil
        }
        
        // type must be either "totp" or missing
        if let type = params[typeParam],
            type.caseInsensitiveCompare(supportedType) != .orderedSame
        {
            Diag.warning("OTP type is not suppoorted [type: \(type)]")
            return nil
        }
        
        // algorithm, if defined, must be a supported one
        var algorithm: TOTPHashAlgorithm?
        if let algorithmString = params[algorithmParam] {
            guard let _algorithm = TOTPHashAlgorithm.fromString(algorithmString) else {
                Diag.warning("OTP algorithm is not supported [algorithm: \(algorithmString)]")
                return nil
            }
            algorithm = _algorithm
        }
        
        // timeStep must be either a valid int or missing
        guard let timeStep = Int(params[timeStepParam] ?? "\(defaultTimeStep)") else {
            Diag.warning("OTP parameter cannot be parsed [parameter: \(timeStepParam)]")
            return nil
        }
        
        // length must be either a valid int or missing
        guard let length = Int(params[lengthParam] ?? "\(defaultLength)") else {
            Diag.warning("OTP parameter cannot be parsed [parameter: \(lengthParam)]")
            return nil
        }
        
        return TOTPGeneratorRFC6238(
            seed: ByteArray(data: seedData),
            timeStep: timeStep,
            length: length,
            hashAlgorithm: algorithm ?? defaultAlgorithm)
    }
}

/// Split TOTP parameters format (KeePassXC, TrayTOTP)
fileprivate class SplitFieldFormat {
    static let seedFieldName = "TOTP Seed"
    static let settingsFieldName = "TOTP Settings"
    
    /// Parses given TOTP parameters and returns a configured TOTP generator.
    /// - Parameters:
    ///   - seedString: string with TOTP secret/seed
    ///   - settingsString: other TOTP settings, such as time step and number of digits
    /// - Returns: `TOTPGenerator` instance defined by the settings.
    static func parse(seedString: String, settingsString: String) -> TOTPGenerator? {
        guard let seed = parseSeedString(seedString) else {
            Diag.warning("Unrecognized TOTP seed format")
            return nil
        }
        
        let settings = settingsString.split(separator: ";")
        if settings.count > 2 {
            Diag.verbose("Found redundant TOTP settings, ignoring [expected: 2, got: \(settings.count)]")
        } else if settings.count < 2 {
            Diag.warning("Insufficient TOTP settings number [expected: 2, got: \(settings.count)]")
            return nil
        }
        guard let timeStep = Int(settings[0]) else {
            Diag.warning("Failed to parse TOTP time step as Int")
            return nil
        }
        guard timeStep > 0 else {
            Diag.warning("Invalid TOTP time step value: \(timeStep)")
            return nil
        }
        
        if let length = Int(settings[1]) {
            return TOTPGeneratorRFC6238(
                seed: seed,
                timeStep: timeStep,
                length: length,
                hashAlgorithm: .sha1
            )
        } else if settings[1] == TOTPGeneratorSteam.typeSymbol {
            return TOTPGeneratorSteam(seed: seed, timeStep: timeStep)
        } else {
            Diag.warning("Unexpected TOTP size or type: '\(settings[1])'")
            return nil
        }
    }
    
    static func parseSeedString(_ seedString: String) -> ByteArray? {
        let cleanedSeedString = seedString
            .replacingOccurrences(of: " ", with: "")
            .replacingOccurrences(of: "=", with: "")
        if let seedData = base32DecodeToData(cleanedSeedString) {
            return ByteArray(data: seedData)
        }
        if let seedData = base32HexDecodeToData(cleanedSeedString) {
            return ByteArray(data: seedData)
        }
        if let seedData = Data(base64Encoded: cleanedSeedString) {
            return ByteArray(data: seedData)
        }
        return nil
    }
}
