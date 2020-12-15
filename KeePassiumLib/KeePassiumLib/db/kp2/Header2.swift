//  KeePassium Password Manager
//  Copyright © 2018–2019 Andrei Popleteev <info@keepassium.com>
// 
//  This program is free software: you can redistribute it and/or modify it
//  under the terms of the GNU General Public License version 3 as published
//  by the Free Software Foundation: https://www.gnu.org/licenses/).
//  For commercial licensing, please contact the author.

import Foundation

/// KP2 file header
final class Header2: Eraseable {
    private static let signature1: UInt32 = 0x9AA2D903
    private static let signature2: UInt32 = 0xB54BFB67
    private static let fileVersion3: UInt32 = 0x00030001
    private static let fileVersion4: UInt32 = 0x00040000
    private static let versionMask: UInt32 = 0xFFFF0000

    enum HeaderError: LocalizedError {
        case readingError
        case wrongSignature
        case unsupportedFileVersion(actualVersion: String)
        case unsupportedDataCipher(uuidHexString: String)
        case unsupportedStreamCipher(id: UInt32)
        case unsupportedKDF(uuid: UUID)
        case unknownCompressionAlgorithm
        case binaryUncompressionError(reason: String)
        case hashMismatch // header's hash does not match its after-header copy
        case hmacMismatch // header's HMAC does not match its after-header copy
        case corruptedField(fieldName: String)
        
        public var errorDescription: String? {
            switch self {
            case .readingError:
                return NSLocalizedString(
                    "[Database2/Header2/Error] Header reading error. DB file corrupt?",
                    bundle: Bundle.framework,
                    value: "Header reading error. DB file corrupt?",
                    comment: "Error message when reading database header")
            case .wrongSignature:
                return NSLocalizedString(
                    "[Database2/Header2/Error] Wrong file signature. Not a KeePass database?",
                    bundle: Bundle.framework,
                    value: "Wrong file signature. Not a KeePass database?",
                    comment: "Error message when opening a database")
            case .unsupportedFileVersion(let version):
                return String.localizedStringWithFormat(
                    NSLocalizedString(
                        "[Database2/Header2/Error] Unsupported database format version: %@.",
                        bundle: Bundle.framework,
                        value: "Unsupported database format version: %@.",
                        comment: "Error message when opening a database. [version: String]"),
                    version)
            case .unsupportedDataCipher(let uuidHexString):
                return String.localizedStringWithFormat(
                    NSLocalizedString(
                        "[Database2/Header2/Error] Unsupported data cipher: %@",
                        bundle: Bundle.framework,
                        value: "Unsupported data cipher: %@",
                        comment: "Error message. [uuidHexString: String]"),
                    uuidHexString.prefix(32).localizedUppercase)
            case .unsupportedStreamCipher(let id):
                return String.localizedStringWithFormat(
                    NSLocalizedString(
                        "[Database2/Header2/Error] Unsupported inner stream cipher (ID %d)",
                        bundle: Bundle.framework,
                        value: "Unsupported inner stream cipher (ID %d)",
                        comment: "Error message when opening a database. [id: UInt32]"),
                    id)
            case .unsupportedKDF(let uuid):
                return String.localizedStringWithFormat(
                    NSLocalizedString(
                        "[Database2/Header2/Error] Unsupported KDF: %@",
                        bundle: Bundle.framework,
                        value: "Unsupported KDF: %@",
                        comment: "Error message about Key Derivation Function. [uuidString: String]"),
                    uuid.uuidString)
            case .unknownCompressionAlgorithm:
                return NSLocalizedString(
                    "[Database2/Header2/Error] Unknown compression algorithm.",
                    bundle: Bundle.framework,
                    value: "Unknown compression algorithm.",
                    comment: "Error message when opening a database")
            case .binaryUncompressionError(let reason):
                return String.localizedStringWithFormat(
                    NSLocalizedString(
                        "[Database2/Header2/Error] Failed to uncompress attachment data: %@",
                        bundle: Bundle.framework,
                        value: "Failed to uncompress attachment data: %@",
                        comment: "Error message when saving a database. [reason: String]"),
                    reason)
            case .corruptedField(let fieldName):
                return String.localizedStringWithFormat(
                    NSLocalizedString(
                        "[Database2/Header2/Error] Header field %@ is corrupted.",
                        bundle: Bundle.framework,
                        value: "Header field %@ is corrupted.",
                        comment: "Error message, with the name of problematic field. [fieldName: String]"),
                    fieldName)
            case .hashMismatch:
                return NSLocalizedString(
                    "[Database2/Header2/Error] Header hash mismatch. DB file corrupt?",
                    bundle: Bundle.framework,
                    value: "Header hash mismatch. DB file corrupt?",
                    comment: "Error message")
            case .hmacMismatch:
                return NSLocalizedString(
                    "[Database2/Header2/Error] Header HMAC mismatch. DB file corrupt?",
                    bundle: Bundle.framework,
                    value: "Header HMAC mismatch. DB file corrupt?",
                    comment: "Error message. HMAC = https://en.wikipedia.org/wiki/HMAC")
            }
        }
    }

    enum FieldID: UInt8 {
        case end                 = 0
        case comment             = 1
        case cipherID            = 2
        case compressionFlags    = 3
        case masterSeed          = 4
        case transformSeed       = 5 // v3 only
        case transformRounds     = 6 // v3 only
        case encryptionIV        = 7
        case protectedStreamKey  = 8 // v3 only
        case streamStartBytes    = 9 // v3 only
        case innerRandomStreamID = 10 // v3 only
        case kdfParameters       = 11 // v4
        case publicCustomData    = 12 // v4
        public var name: String {
            switch self {
            case .end:      return "End"
            case .comment:  return "Comment"
            case .cipherID: return "CipherID"
            case .compressionFlags: return "CompressionFlags"
            case .masterSeed:       return "MasterSeed"
            case .transformSeed:    return "TransformSeed"
            case .transformRounds:  return "TransformRounds"
            case .encryptionIV:     return "EncryptionIV"
            case .protectedStreamKey:  return "ProtectedStreamKey"
            case .streamStartBytes:    return "StreamStartBytes"
            case .innerRandomStreamID: return "RandomStreamID"
            case .kdfParameters:       return "KDFParameters"
            case .publicCustomData:    return "PublicCustomData"
            }
        }
    }

    /// Inner header field in v4
    enum InnerFieldID: UInt8 {
        case end                  = 0
        case innerRandomStreamID  = 1
        case innerRandomStreamKey = 2
        case binary               = 3
        public var name: String {
            switch self {
            case .end: return "Inner/End"
            case .innerRandomStreamID:  return "Inner/RandomStreamID"
            case .innerRandomStreamKey: return "Inner/RandomStreamKey"
            case .binary: return "Inner/Binary"
            }
        }
    }
    
    enum CompressionAlgorithm: UInt8 {
        case noCompression = 0
        case gzipCompression = 1
    }
    
    private unowned let database: Database2
    private var initialized: Bool
    private var data: ByteArray // raw header data
    
    private(set) var formatVersion: Database2.FormatVersion
    internal var size: Int { return data.count }
    private(set) var fields: [FieldID: ByteArray]
    private(set) var hash: ByteArray
    private(set) var dataCipher: DataCipher
    private(set) var kdf: KeyDerivationFunction
    private(set) var kdfParams: KDFParams
    private(set) var streamCipher: StreamCipher
    private(set) var publicCustomData: VarDict // v4 only
    
    // v3-only fields
    var masterSeed: ByteArray { return fields[.masterSeed]! }
    var streamStartBytes: ByteArray? { return fields[.streamStartBytes] }
    
    // v3/v4 fields
//    var cipherUUID: UUID? { return UUID(data: fields[.cipherID]) } // replaced by dataCipher
    var initialVector:  ByteArray { return fields[.encryptionIV]! }
    var isCompressed: Bool {
        guard let fieldData = fields[.compressionFlags],
              let compressionValue = UInt32(data: fieldData) else {
            assertionFailure()
            return false
        }
        return compressionValue != CompressionAlgorithm.noCompression.rawValue
    }
    
    // outer(v3)/inner(v4) fields
    var protectedStreamKey: SecureByteArray?
    var innerStreamAlgorithm: ProtectedStreamAlgorithm
    
    /// Checks if `data` starts with a compatible KP2 DB signature.
    class func isSignatureMatches(data: ByteArray) -> Bool {
        let ins = data.asInputStream()
        ins.open()
        defer { ins.close() }
        guard let sign1: UInt32 = ins.readUInt32(),
            let sign2: UInt32 = ins.readUInt32() else {
                return false
        }
        return (sign1 == Header2.signature1) && (sign2 == Header2.signature2)
    }
    
    init(database: Database2) {
        self.database = database
        initialized = false
        formatVersion = .v4
        data = ByteArray()
        fields = [:]
        dataCipher = AESDataCipher()
        hash = ByteArray()
        kdf = AESKDF()
        kdfParams = kdf.defaultParams
        innerStreamAlgorithm = .Null
        streamCipher = UselessStreamCipher()
        publicCustomData = VarDict()
    }
    deinit {
        erase()
    }
    
    func erase() {
        initialized = false
        formatVersion = .v4
        data.erase()
        hash.erase()
        for (_, field) in fields { field.erase() }
        fields.removeAll()
        dataCipher = AESDataCipher()
        kdf = AESKDF()
        kdfParams = kdf.defaultParams
        innerStreamAlgorithm = .Null
        streamCipher.erase()
        publicCustomData.erase()
    }
    
    /// Configures header for a new kp2v4 database.
    func loadDefaultValuesV4() {
        formatVersion = .v4

        dataCipher = ChaCha20DataCipher()
        fields[.cipherID] = dataCipher.uuid.data
        
        kdf = Argon2dKDF()
        kdfParams = kdf.defaultParams
        // refine the default KDF params
        let iterations: UInt64 = 100
        let memory: UInt64 = 1*1024*1024
        let parallelism: UInt32 = 2
        kdfParams.setValue(
            key: AbstractArgon2KDF.iterationsParam,
            value: VarDict.TypedValue(value: iterations))
        kdfParams.setValue(
            key: AbstractArgon2KDF.memoryParam,
            value: VarDict.TypedValue(value: memory))
        kdfParams.setValue(
            key: AbstractArgon2KDF.parallelismParam,
            value: VarDict.TypedValue(value: parallelism))
        fields[.kdfParameters] = kdfParams.data!
        
        let compressionFlags = UInt32(exactly: CompressionAlgorithm.gzipCompression.rawValue)!
        fields[.compressionFlags] = compressionFlags.data

        innerStreamAlgorithm = .ChaCha20

        fields[.publicCustomData] = ByteArray()
        
        // setup .masterSeed, .encryptionIV, .protectedStreamKey and streamCipher
        // Done in randomizeSeeds(), will be called before saving.
        //try randomizeSeeds() // throws `CryptoError.rngError`
        
        initialized = true
    }
    
    /// Reads and parses main(v3)/outer(v4) header data
    /// - Throws: HeaderError
    func read(data inputData: ByteArray) throws {
        assert(!initialized, "Tried to read already initialized header")
        
        Diag.verbose("Will read header")
        var headerSize = 0 // header data size, to be calculated
        let stream = inputData.asInputStream()
        stream.open()
        defer { stream.close() }
        
        guard let sign1: UInt32 = stream.readUInt32(),
            let sign2: UInt32 = stream.readUInt32(),
            let fileVer: UInt32 = stream.readUInt32() else {
                Diag.error("Signature is too short")
                throw HeaderError.readingError
        }
        headerSize += sign1.byteWidth + sign2.byteWidth + fileVer.byteWidth
        guard sign1 == Header2.signature1 else {
            Diag.error("Wrong signature #1")
            throw HeaderError.wrongSignature
        }
        guard sign2 == Header2.signature2 else {
            Diag.error("Wrong signature #2")
            throw HeaderError.wrongSignature
        }
        
        if (fileVer & Header2.versionMask) == (Header2.fileVersion3 & Header2.versionMask) {
            Diag.verbose("Database format: v3")
            formatVersion = .v3
        } else if (fileVer & Header2.versionMask) == (Header2.fileVersion4 & Header2.versionMask) {
            Diag.verbose("Database format: v4")
            formatVersion = .v4
        } else {
            Diag.error("Unsupported file version [version: \(fileVer.asHexString)]")
            throw HeaderError.unsupportedFileVersion(actualVersion: fileVer.asHexString)
        }
        Diag.verbose("Header signatures OK")
        
        // read header fields
        while (true) {
            guard let rawFieldID: UInt8 = stream.readUInt8() else { throw HeaderError.readingError }
            headerSize += rawFieldID.byteWidth
            
            let fieldSize: Int
            switch formatVersion {
            case .v3:
                guard let fSize = stream.readUInt16() else { throw HeaderError.readingError }
                fieldSize = Int(fSize)
                headerSize += MemoryLayout.size(ofValue: fSize) + fieldSize
            case .v4:
                guard let fSize = stream.readUInt32() else { throw HeaderError.readingError }
                fieldSize = Int(fSize)
                headerSize += MemoryLayout.size(ofValue: fSize) + fieldSize
            }
            
            guard let fieldID: FieldID = FieldID(rawValue: rawFieldID) else {
                Diag.warning("Unknown field ID, skipping [fieldID: \(rawFieldID)]")
                continue
            }
            
            guard let fieldValueData = stream.read(count: fieldSize) else {
                throw HeaderError.readingError
            }
            
            // in KeePass 2.38, the end field contains data, so we read/preserve it above
            if fieldID == .end {
                self.initialized = true
                fields.updateValue(fieldValueData, forKey: fieldID)
                break // the endless while loop
            }

            // Most of field values are saved as-is in a `fields` dictionary (below),
            // therefore most of switch cases only verify these values make sense.
            // (But some fields are also stored to dedicated class members.)
            switch fieldID {
            case .end:
                Diag.verbose("\(fieldID.name) read OK")
                break // .end already handled above
            case .comment:
                Diag.verbose("\(fieldID.name) read OK")
                // header comments are ignored even in original KeePass v2
                break
            case .cipherID:
                guard let _cipherUUID = UUID(data: fieldValueData) else {
                    Diag.error("Cipher UUID is misformatted")
                    throw HeaderError.corruptedField(fieldName: fieldID.name)
                }
                guard let _dataCipher = DataCipherFactory.instance.createFor(uuid: _cipherUUID) else {
                    Diag.error("Unsupported cipher ID: \(fieldValueData.asHexString)")
                    throw HeaderError.unsupportedDataCipher(
                        uuidHexString: fieldValueData.asHexString)
                }
                self.dataCipher = _dataCipher
                Diag.verbose("\(fieldID.name) read OK [name: \(dataCipher.name)]")
            case .compressionFlags:
                // only verify convertibility
                guard let compressionFlags32 = UInt32(data: fieldValueData) else {
                    throw HeaderError.readingError
                }
                guard let compressionFlags8 = UInt8(exactly: compressionFlags32) else {
                    Diag.error("Unknown compression algorithm [compressionFlags32: \(compressionFlags32)]")
                    throw HeaderError.unknownCompressionAlgorithm
                }
                guard CompressionAlgorithm(rawValue: compressionFlags8) != nil else {
                    Diag.error("Unknown compression algorithm [compressionFlags8: \(compressionFlags8)]")
                    throw HeaderError.unknownCompressionAlgorithm
                }
                Diag.verbose("\(fieldID.name) read OK")
            case .masterSeed:
                guard fieldSize == SHA256_SIZE else {
                    Diag.error("Unexpected \(fieldID.name) field size [\(fieldSize) bytes]")
                    throw HeaderError.corruptedField(fieldName: fieldID.name)
                }
                Diag.verbose("\(fieldID.name) read OK")
            case .transformSeed: // v3 only
                guard formatVersion == .v3 else {
                    Diag.error("Found \(fieldID.name) in non-V3 header. Database corrupted?")
                    throw HeaderError.corruptedField(fieldName: fieldID.name)
                }
                guard fieldSize == SHA256_SIZE else {
                    Diag.error("Unexpected \(fieldID.name) field size [\(fieldSize) bytes]")
                    throw HeaderError.corruptedField(fieldName: fieldID.name)
                }
                let aesKDF = AESKDF()
                if kdf.uuid != aesKDF.uuid {
                    kdf = aesKDF
                    kdfParams = aesKDF.defaultParams
                    Diag.warning("Replaced KDF with AES-KDF [original KDF UUID: \(kdf.uuid)]")
                }
                kdfParams.setValue(key: AESKDF.transformSeedParam,
                                   value: VarDict.TypedValue(value: fieldValueData))
                Diag.verbose("\(fieldID.name) read OK")
            case .transformRounds: // v3 only
                guard formatVersion == .v3 else {
                    Diag.error("Found \(fieldID.name) in non-V3 header. Database corrupted?")
                    throw HeaderError.corruptedField(fieldName: fieldID.name)
                }
                guard let nRounds: UInt64 = UInt64(data: fieldValueData) else {
                    throw HeaderError.readingError
                }
                let aesKDF = AESKDF()
                if kdf.uuid != aesKDF.uuid {
                    kdf = aesKDF
                    kdfParams = aesKDF.defaultParams
                    Diag.warning("Replaced KDF with AES-KDF [original KDF UUID: \(kdf.uuid)]")
                }
                kdfParams.setValue(key: AESKDF.transformRoundsParam,
                                   value: VarDict.TypedValue(value: nRounds))
                Diag.verbose("\(fieldID.name) read OK")
            case .encryptionIV:
                // IV validation depends on KDF, which might not yet have been loaded.
                // So we postpone IV validation to verifyImportantFields() below.
                Diag.verbose("\(fieldID.name) read OK")
                break
            case .protectedStreamKey: // v3 only
                guard formatVersion == .v3 else {
                    Diag.error("Found \(fieldID.name) in non-V3 header. Database corrupted?")
                    throw HeaderError.corruptedField(fieldName: fieldID.name)
                }
                guard fieldSize == SHA256_SIZE else {
                    Diag.error("Unexpected \(fieldID.name) field size [\(fieldSize) bytes]")
                    throw HeaderError.corruptedField(fieldName: fieldID.name)
                }
                self.protectedStreamKey = SecureByteArray(fieldValueData)
                Diag.verbose("\(fieldID.name) read OK")
            case .streamStartBytes: // v3 only
                guard formatVersion == .v3 else {
                    Diag.error("Found \(fieldID.name) in non-V3 header. Database corrupted?")
                    throw HeaderError.corruptedField(fieldName: fieldID.name)
                }
                // no special checks required, any size will do
                Diag.verbose("\(fieldID.name) read OK")
                break
            case .innerRandomStreamID: // v3 only
                guard formatVersion == .v3 else {
                    Diag.error("Found \(fieldID.name) in non-V3 header. Database corrupted?")
                    throw HeaderError.corruptedField(fieldName: fieldID.name)
                }
                guard let rawID = UInt32(data: fieldValueData) else {
                    Diag.error("innerRandomStreamID is not a UInt32")
                    throw HeaderError.corruptedField(fieldName: fieldID.name)
                }
                guard let protectedStreamAlgorithm = ProtectedStreamAlgorithm(rawValue: rawID) else {
                    Diag.error("Unrecognized innerRandomStreamID [rawID: \(rawID)]")
                    throw HeaderError.unsupportedStreamCipher(id: rawID)
                }
                self.innerStreamAlgorithm = protectedStreamAlgorithm
                Diag.verbose("\(fieldID.name) read OK [name: \(innerStreamAlgorithm.name)]")
            case .kdfParameters: // v4 only
                guard formatVersion == .v4 else {
                    Diag.error("Found \(fieldID.name) in non-V4 header. Database corrupted?")
                    throw HeaderError.corruptedField(fieldName: fieldID.name)
                }
                guard let kdfParams = KDFParams(data: fieldValueData) else {
                    Diag.error("Cannot parse KDF params. Database corrupted?")
                    throw HeaderError.corruptedField(fieldName: fieldID.name)
                }
                self.kdfParams = kdfParams
                // also init the KDF specified by kdfParams
                guard let _kdf = KDFFactory.createFor(uuid: kdfParams.kdfUUID) else {
                    Diag.error("Unrecognized KDF requested [UUID: \(kdfParams.kdfUUID)]")
                    throw HeaderError.unsupportedKDF(uuid: kdfParams.kdfUUID)
                }
                self.kdf = _kdf
                Diag.verbose("\(fieldID.name) read OK")
            case .publicCustomData:
                guard formatVersion == .v4 else {
                    Diag.error("Found \(fieldID.name) in non-V4 header. Database corrupted?")
                    throw HeaderError.corruptedField(fieldName: fieldID.name)
                }
                guard let publicCustomData = VarDict(data: fieldValueData) else {
                    Diag.error("Cannot parse public custom data. Database corrupted?")
                    throw HeaderError.corruptedField(fieldName: fieldID.name)
                }
                self.publicCustomData = publicCustomData
                Diag.verbose("\(fieldID.name) read OK")
            }
            // print("Field \(fieldID): \(fieldValueData.asHexString)")
            fields.updateValue(fieldValueData, forKey: fieldID)
        }
        
        self.data = inputData.prefix(headerSize)
        self.hash = self.data.sha256
        
        try verifyImportantFields()
        Diag.verbose("All important fields are in place")
        
        if formatVersion == .v3 { // for v4 this is done after reading inner header
            initStreamCipher()
            Diag.verbose("V3 stream cipher init OK")
        }
    }
    
    /// Checks if there is some data in each of the critically important fields.
    /// - Throws: HeaderError.corruptedField, CryptoError
    private func verifyImportantFields() throws {
        Diag.verbose("Will check all important fields are present")
        var importantFields: [FieldID]
        switch formatVersion {
        case .v3:
            importantFields = [
                .cipherID, .compressionFlags, .masterSeed, .transformSeed,
                .transformRounds, .encryptionIV, .streamStartBytes,
                .protectedStreamKey, .innerRandomStreamID]
        case .v4:
            importantFields =
                [.cipherID, .compressionFlags, .masterSeed, .encryptionIV, .kdfParameters]
        }
        for fieldID in importantFields {
            guard let fieldData = fields[fieldID] else {
                Diag.error("\(fieldID.name) is missing")
                throw HeaderError.corruptedField(fieldName: fieldID.name)
            }
            if fieldData.isEmpty {
                Diag.error("\(fieldID.name) is present, but empty")
                throw HeaderError.corruptedField(fieldName: fieldID.name)
            }
        }
        // By here, all importantFields are present and initialized.
        // Now let's check if they play well together.
        Diag.verbose("All important fields are OK")
        
        // Verify that IV is appropriate for the current dataCipher
        guard initialVector.count == dataCipher.initialVectorSize else {
            Diag.error("Initial vector size is inappropritate for the cipher [size: \(initialVector.count), cipher UUID: \(dataCipher.uuid)]")
            throw HeaderError.corruptedField(fieldName: FieldID.encryptionIV.name)
        }
    }
    
    /// Instantiates protected stream cipher (Salsa20/ChaCha20) using current `protectedStreamKey`,
    /// for reading/writing protected values.
    internal func initStreamCipher() {
        guard let protectedStreamKey = protectedStreamKey else {
            // This should not happen, because the presence of `protectedStreamKey`
            // should have been checked in `verifyImportantFields()`
            fatalError()
        }
        self.streamCipher = StreamCipherFactory.create(
            algorithm: innerStreamAlgorithm,
            key: protectedStreamKey)
    }
    
    /// Calculates HMAC SHA256 of the raw header data
    /// - Parameter: key - 64-byte key
    func getHMAC(key: ByteArray) -> ByteArray {
        assert(!self.data.isEmpty)
        assert(key.count == CC_SHA256_BLOCK_BYTES)
        
        let blockKey = CryptoManager.getHMACKey64(key: key, blockIndex: UInt64.max)
        return CryptoManager.hmacSHA256(data: data, key: blockKey)
    }
    
//    /// Prints fields' content for debug
//    func printDebugInfo() {
//        for (fieldID, fieldData) in fields {
//            print("Field \(fieldID): \(fieldData.asHexString)")
//        }
//        print("Header hash: \(hash.asHexString)")
//        print("Header size: \(size)")
//        kdfParams.debugPrint()
//    }
    
    
    /// Reads inner header of KP2 v4 files
    /// - Parameter: data - plain-text DB file content
    /// - Throws: HeaderError
    /// - Returns: inner header size in bytes
    func readInner(data: ByteArray) throws -> Int {
        let stream = data.asInputStream()
        stream.open()
        defer { stream.close() }
        
        Diag.verbose("Will read inner header")
        var size: Int = 0
        while true {
            guard let rawFieldID = stream.readUInt8() else {
                throw HeaderError.readingError
            }
            guard let fieldID = InnerFieldID(rawValue: rawFieldID) else {
                throw HeaderError.readingError
            }
            guard let fieldSize: Int32 = stream.readInt32() else {
                throw HeaderError.corruptedField(fieldName: fieldID.name)
            }
            guard fieldSize >= 0 else {
                throw HeaderError.readingError
            }
            guard let fieldData = stream.read(count: Int(fieldSize)) else {
                throw HeaderError.corruptedField(fieldName: fieldID.name)
            }
            size += MemoryLayout.size(ofValue: rawFieldID)
                + MemoryLayout.size(ofValue: fieldSize)
                + fieldData.count
            
            switch fieldID {
            case .innerRandomStreamID:
                guard let rawID = UInt32(data: fieldData) else {
                    throw HeaderError.corruptedField(fieldName: fieldID.name)
                }
                guard let protectedStreamAlgorithm = ProtectedStreamAlgorithm(rawValue: rawID) else {
                    Diag.error("Unrecognized protected stream algorithm [rawID: \(rawID)]")
                    throw HeaderError.unsupportedStreamCipher(id: rawID)
                }
                self.innerStreamAlgorithm = protectedStreamAlgorithm
                Diag.verbose("\(fieldID.name) read OK [name: \(innerStreamAlgorithm.name)]")
            case .innerRandomStreamKey:
                guard fieldData.count > 0 else {
                    throw HeaderError.corruptedField(fieldName: fieldID.name)
                }
                self.protectedStreamKey = SecureByteArray(fieldData)
                Diag.verbose("\(fieldID.name) read OK")
            case .binary:
                let isProtected = (fieldData[0] & 0x01 != 0)
                let newBinaryID = database.binaries.count
                let binary = Binary2(
                    id: newBinaryID,
                    data: fieldData.suffix(from: 1), // fieldData is in plain text
                    isCompressed: false,
                    isProtected: isProtected) // just a recommendation, not a call for decryption
                database.binaries[newBinaryID] = binary
                Diag.verbose("\(fieldID.name) read OK [size: \(fieldData.count) bytes]")
            case .end:
                initStreamCipher()
                Diag.verbose("Stream cipher init OK")
                Diag.verbose("Inner header read OK [size: \(size) bytes]")
                return size
            }
        }
    }
    
    /// Changes `formatVersion` field, if required by other encryption settings.
    /// (E.g. upgrades v3 to v4, if Argon2 KDF is used)
    func maybeUpdateFormatVersion() {
        // TODO someday implement this; for now we'll save the same format as read.
        // Things to change (only if necessary):
        // - self.dataCipher
        // - streamCipher
        // - self.kdf & kdfParam
        // - protectedStreamCipher
    }
    
    /// Writes header data to the given stream.
    /// Implicitly updates header's hash value, and *possibly DB format version*.
    func write(to outStream: ByteArray.OutputStream) {
        Diag.verbose("Will write header")
        // Need a dedicated buffer to calculate header hash
        let headerStream = ByteArray.makeOutputStream()
        headerStream.open()
        defer { headerStream.close() }
        
        headerStream.write(value: Header2.signature1)
        headerStream.write(value: Header2.signature2)
        switch formatVersion {
        case .v3:
            headerStream.write(value: Header2.fileVersion3)
            writeV3(stream: headerStream)
            Diag.verbose("KP2v3 header written OK")
        case .v4:
            headerStream.write(value: Header2.fileVersion4)
            writeV4(stream: headerStream)
            Diag.verbose("KP2v4 header written OK")
        }
        
        // update header hash
        let headerData = headerStream.data!
        self.data = headerData
        self.hash = headerData.sha256
        outStream.write(data: headerData)
    }
  
    /// Writes KP2v3 header data (sans signatures & file version) to the stream
    private func writeV3(stream: ByteArray.OutputStream) {
        func writeField(to stream: ByteArray.OutputStream, fieldID: FieldID) {
            stream.write(value: UInt8(fieldID.rawValue))
            let fieldData = fields[fieldID] ?? ByteArray()
            stream.write(value: UInt16(fieldData.count))
            stream.write(data: fieldData)
        }

        guard let transformSeedData = kdfParams.getValue(key: AESKDF.transformSeedParam)?.data
            else { fatalError("Missing transform seed data") }
        guard let transformRoundsData = kdfParams.getValue(key: AESKDF.transformRoundsParam)?.data
            else { fatalError("Missing transform rounds data") }
        
        fields[.cipherID] = self.dataCipher.uuid.data
        fields[.transformSeed] = transformSeedData
        fields[.transformRounds] = transformRoundsData
        fields[.protectedStreamKey] = protectedStreamKey
        fields[.innerRandomStreamID] = innerStreamAlgorithm.rawValue.data

        writeField(to: stream, fieldID: .cipherID)
        writeField(to: stream, fieldID: .compressionFlags)
        writeField(to: stream, fieldID: .masterSeed)
        writeField(to: stream, fieldID: .transformSeed)
        writeField(to: stream, fieldID: .transformRounds)
        writeField(to: stream, fieldID: .encryptionIV)
        writeField(to: stream, fieldID: .protectedStreamKey)
        writeField(to: stream, fieldID: .streamStartBytes)
        writeField(to: stream, fieldID: .innerRandomStreamID)
        writeField(to: stream, fieldID: .end)
    }
    
    /// Writes KP2v4 header data (sans signatures & file version) to the stream
    private func writeV4(stream: ByteArray.OutputStream) {
        func writeField(to stream: ByteArray.OutputStream, fieldID: FieldID) {
            stream.write(value: UInt8(fieldID.rawValue))
            let fieldData = fields[fieldID] ?? ByteArray()
            stream.write(value: UInt32(fieldData.count))
            stream.write(data: fieldData)
        }
        // Some things parameters could have changed, so update serialized data
        fields[.cipherID] = self.dataCipher.uuid.data
        fields[.kdfParameters] = kdfParams.data

        writeField(to: stream, fieldID: .cipherID)
        writeField(to: stream, fieldID: .compressionFlags)
        writeField(to: stream, fieldID: .masterSeed)
        writeField(to: stream, fieldID: .kdfParameters)
        writeField(to: stream, fieldID: .encryptionIV)
        if !publicCustomData.isEmpty {
            fields[.publicCustomData] = publicCustomData.data
            writeField(to: stream, fieldID: .publicCustomData)
        }
        writeField(to: stream, fieldID: .end)
    }
    
    /// Writes KP2 v4 inner header
    /// Throws: ProgressInterruption, HeaderError.binaryUncompressionError
    func writeInner(to stream: ByteArray.OutputStream) throws {
        assert(formatVersion == .v4)
        guard let protectedStreamKey = protectedStreamKey else { fatalError() }
        
        Diag.verbose("Writing KP2v4 inner header")
        stream.write(value: InnerFieldID.innerRandomStreamID.rawValue) // fieldID: UInt8
        stream.write(value: UInt32(MemoryLayout.size(ofValue: innerStreamAlgorithm.rawValue))) // fieldSize: UInt32
        stream.write(value: innerStreamAlgorithm.rawValue) // data
        
        stream.write(value: InnerFieldID.innerRandomStreamKey.rawValue) // fieldID: UInt8
        stream.write(value: UInt32(protectedStreamKey.count)) // fieldSize: UInt32
        stream.write(data: protectedStreamKey)
        print("  streamCipherKey: \(protectedStreamKey.asHexString)")
        
        // Inner header binaries should be ordered (since their order is their ID)
        for binaryID in database.binaries.keys.sorted() {
            Diag.verbose("Writing a binary")
            let binary = database.binaries[binaryID]! // guaranteed to exist
            
            let data: ByteArray
            if binary.isCompressed {
                do {
                    data = try binary.data.gunzipped() // throws `GzipError`
                } catch {
                    Diag.error("Failed to uncompress attachment data [message: \(error.localizedDescription)]")
                    throw HeaderError.binaryUncompressionError(reason: error.localizedDescription)
                }
            } else {
                data = binary.data
            }
            stream.write(value: InnerFieldID.binary.rawValue) // fieldID: UInt8
            stream.write(value: UInt32(1 + data.count)) // (+1 for flag) fieldSize: UInt32,
            stream.write(value: UInt8(binary.flags))
            stream.write(data: data) // in plain text; protected flag is just a recommendation
            print("  binary: \(data.count + 1) bytes")
        }
        stream.write(value: InnerFieldID.end.rawValue) // terminator fieldID: UInt8
        stream.write(value: UInt32(0)) // terminator fieldSize: UInt32
        Diag.verbose("Inner header written OK")
    }
    
    /// Randomizes encryption seeds.
    /// - Throws: CryptoError.rngError
    internal func randomizeSeeds() throws {
        Diag.verbose("Randomizing the seeds")
        fields[.masterSeed] = try CryptoManager.getRandomBytes(count: SHA256_SIZE)
        fields[.encryptionIV] = try CryptoManager.getRandomBytes(count: dataCipher.initialVectorSize)
        try kdf.randomize(params: &kdfParams) // throws CryptoError.rngError
        switch formatVersion {
        case .v3:
            protectedStreamKey = SecureByteArray(try CryptoManager.getRandomBytes(count: 32)) // for Salsa20
            fields[.streamStartBytes] = try CryptoManager.getRandomBytes(count: SHA256_SIZE)
        case .v4:
            protectedStreamKey = SecureByteArray(try CryptoManager.getRandomBytes(count: 64)) // for ChaCha20
        }
        // make streamCipher use the new key
        initStreamCipher()
    }
}
