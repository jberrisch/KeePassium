//  KeePassium Password Manager
//  Copyright © 2018–2019 Andrei Popleteev <info@keepassium.com>
// 
//  This program is free software: you can redistribute it and/or modify it
//  under the terms of the GNU General Public License version 3 as published
//  by the Free Software Foundation: https://www.gnu.org/licenses/).
//  For commercial licensing, please contact the author.

import Foundation

/// KP1 database
public class Database1: Database {
    /// An issue with database format: chechsum mismatch, etc
    public enum FormatError: LocalizedError {
        /// File is too short
        case prematureDataEnd
        /// Field size or content does not match expected format
        case corruptedField(fieldName: String?)
        /// An entry with non-existent groupID
        case orphanedEntry
        public var errorDescription: String? {
            switch self {
            case .prematureDataEnd:
                return NSLocalizedString(
                    "[Database1/FormatError] Unexpected end of file. Corrupted database file?",
                    bundle: Bundle.framework,
                    value: "Unexpected end of file. Corrupted database file?",
                    comment: "Error message")
            case .corruptedField(let fieldName):
                if fieldName != nil {
                    return String.localizedStringWithFormat(
                        NSLocalizedString(
                            "[Database1/FormatError] Error parsing field %@. Corrupted database file?",
                            bundle: Bundle.framework,
                            value: "Error parsing field %@. Corrupted database file?",
                            comment: "Error message [fieldName: String]"),
                        fieldName!)
                } else {
                    return NSLocalizedString(
                        "[Database1/FormatError] Database file is corrupted.",
                        bundle: Bundle.framework,
                        value: "Database file is corrupted.",
                        comment: "Error message")
                }
            case .orphanedEntry:
                return NSLocalizedString(
                    "[Database1/FormatError] Found an entry outside any group. Corrupted DB file?",
                    bundle: Bundle.framework,
                    value: "Found an entry outside any group. Corrupted DB file?",
                    comment: "Error message")
            }
        }
    }
    
    private enum ProgressSteps {
        static let all: Int64 = 100
        static let keyDerivation: Int64 = 60
        static let resolvingReferences: Int64 = 5
        
        static let decryption: Int64 = 25
        static let parsing: Int64 = 10

        static let encryption: Int64 = 25
        static let packing: Int64 = 10
    }
    
    override public var keyHelper: KeyHelper { return _keyHelper }
    private let _keyHelper = KeyHelper1()
    
    private(set) var header: Header1!
    private(set) var masterKey = SecureByteArray()
    private(set) var backupGroup: Group1?
    private var metaStreamEntries = ContiguousArray<Entry1>()

    override public init() {
        super.init()
        header = Header1(database: self)
    }
    deinit {
        erase()
    }
    override public func erase() {
        header.erase()
        compositeKey.erase()
        masterKey.erase()
        backupGroup?.erase()
        backupGroup = nil
        for metaEntry in metaStreamEntries {
            metaEntry.erase()
        }
        metaStreamEntries.removeAll()
        Diag.debug("Database erased")
    }

    /// Generates a new group ID (guaranteed to be unique in this DB)
    func createNewGroupID() -> Group1ID {
        var groups = Array<Group>()
        var entries = Array<Entry>()
        if let root = root {
            root.collectAllChildren(groups: &groups, entries: &entries)
        } else {
            Diag.warning("Creating a new Group1ID for an empty database")
            assertionFailure("Creating new Group1ID for an empty database")
            // and continue with groups and entries empty
        }
        
        var takenIDs = ContiguousArray<Int32>()
        takenIDs.reserveCapacity(groups.count)
        var maxID: Int32 = 0
        for group in groups {
            let id = (group as! Group1).id
            if id > maxID { maxID = id}
            takenIDs.append(id)
        }
        groups.removeAll()
        entries.removeAll()
        
        var newID = maxID + 1
        while takenIDs.contains(newID) {
            newID = newID &+ 1 // &+ allows for potential Int32 overflow
        }
        return newID
    }
    
    /// Returns the Backup group of this database
    /// (or creates one, if `createIfMissing` is true).
    override public func getBackupGroup(createIfMissing: Bool) -> Group? {
        guard let root = root else {
            Diag.warning("Tried to get Backup group without the root one")
            assertionFailure()
            return nil
        }
        
        if backupGroup == nil && createIfMissing {
            // There's no backup group, let's make one
            let newBackupGroup = root.createGroup() as! Group1
            newBackupGroup.name = Group1.backupGroupName
            newBackupGroup.iconID = Group1.backupGroupIconID
            newBackupGroup.isDeleted = true
            backupGroup = newBackupGroup
        }
        return backupGroup
    }

    /// Checks if given data starts with compatible KP2 signature.
    override public class func isSignatureMatches(data: ByteArray) -> Bool {
        return Header1.isSignatureMatches(data: data)
    }

    /// Changes DB's composite key to the provided one.
    /// Don't forget to call `deriveMasterKey` before saving.
    ///
    /// - Parameter newKey: new composite key.
    override public func changeCompositeKey(to newKey: CompositeKey) {
        compositeKey = newKey
    }
    
    /// Decrypts DB data using the given compositeKey.
    /// - Throws: `DatabaseError.loadError`, `DatabaseError.invalidKey`, `ProgressInterruption`
    override public func load(
        dbFileName: String,
        dbFileData: ByteArray,
        compositeKey: CompositeKey,
        warnings: DatabaseLoadingWarnings
    ) throws {
        Diag.info("Loading KP1 database")
        progress.completedUnitCount = 0
        progress.totalUnitCount = ProgressSteps.all
        do {
            try header.read(data: dbFileData) // throws Header1.Error
            Diag.debug("Header read OK")
            
            try deriveMasterKey(compositeKey: compositeKey, canUseFinalKey: true)
                // throws CryptoError, ChallengeResponseError, ProgressInterruption
            Diag.debug("Key derivation OK")
            
            // Decrypt data
            let dbWithoutHeader = dbFileData.suffix(from: header.count)
            let decryptedData = try decrypt(data: dbWithoutHeader)
                // throws CryptoError, ProgressInterruption
            Diag.debug("Decryption OK")
            guard decryptedData.sha256 == header.contentHash else {
                Diag.error("Header hash mismatch - invalid master key?")
                throw DatabaseError.invalidKey
            }
            
            /// Reading and parsing data
            try loadContent(data: decryptedData, dbFileName: dbFileName)
                // throws FormatError, ProgressInterruption
            Diag.debug("Content loaded OK")

            // all good, so remember combinedKey for eventual saving
            self.compositeKey = compositeKey
        } catch let error as Header1.Error {
            Diag.error("Header error [reason: \(error.localizedDescription)]")
            throw DatabaseError.loadError(reason: error.localizedDescription)
        } catch let error as CryptoError {
            Diag.error("Crypto error [reason: \(error.localizedDescription)]")
            throw DatabaseError.loadError(reason: error.localizedDescription)
        } catch let error as ChallengeResponseError {
            Diag.error("Challenge-response error [reason: \(error.localizedDescription)]")
            throw DatabaseError.loadError(reason: error.localizedDescription)
        } catch let error as FormatError {
            Diag.error("Format error [reason: \(error.localizedDescription)]")
            throw DatabaseError.loadError(reason: error.localizedDescription)
        } // ProgressInterruption is passed further out
    }
    
    /// - Throws: `CryptoError`, `ChallengeResponseError`, `ProgressInterruption`
    func deriveMasterKey(compositeKey: CompositeKey, canUseFinalKey: Bool) throws {
        Diag.debug("Start key derivation")
        
        guard compositeKey.challengeHandler == nil else {
            throw ChallengeResponseError.notSupportedByDatabaseFormat
        }
        
        if canUseFinalKey,
           compositeKey.state == .final,
           let _masterKey = compositeKey.finalKey
        {
            // Already have the final key, can skip derivation
            self.masterKey = _masterKey
            progress.completedUnitCount += ProgressSteps.keyDerivation
            return
        }
        
        let kdf = AESKDF()
        progress.addChild(kdf.initProgress(), withPendingUnitCount: ProgressSteps.keyDerivation)
        let kdfParams = kdf.defaultParams
        kdfParams.setValue(
            key: AESKDF.transformSeedParam,
            value: VarDict.TypedValue(value: header.transformSeed))
        kdfParams.setValue(
            key: AESKDF.transformRoundsParam,
            value: VarDict.TypedValue(value: UInt64(header.transformRounds)))
        
        let combinedComponents: SecureByteArray
        if compositeKey.state == .processedComponents {
            combinedComponents = keyHelper.combineComponents(
                passwordData: compositeKey.passwordData!, // might be empty, but not nil
                keyFileData: compositeKey.keyFileData!    // might be empty, but not nil
            )
            compositeKey.setCombinedStaticComponents(combinedComponents)
        } else if compositeKey.state >= .combinedComponents {
            combinedComponents = compositeKey.combinedStaticComponents! // not nil in this state
        } else {
            preconditionFailure("Unexpected key state")
        }
        
        let keyToTransform = keyHelper.getKey(fromCombinedComponents: combinedComponents)
        let transformedKey = try kdf.transform(key: keyToTransform, params: kdfParams)
            // throws CryptoError, ProgressInterruption
        let secureMasterSeed = SecureByteArray(header.masterSeed)
        masterKey = SecureByteArray.concat(secureMasterSeed, transformedKey).sha256
        compositeKey.setFinalKeys(masterKey, nil)
    }
    
    /// Reads groups and entries from plain-text `data`
    /// and arranges them into a hierarchy.
    /// - Throws: `Database1.FormatError`, `ProgressInterruption`
    private func loadContent(data: ByteArray, dbFileName: String) throws {
        let stream = data.asInputStream()
        stream.open()
        defer { stream.close() }
        
        let loadProgress = ProgressEx()
        loadProgress.totalUnitCount = Int64(header.groupCount + header.entryCount)
        loadProgress.localizedDescription = LString.Progress.database1ParsingContent
        self.progress.addChild(loadProgress, withPendingUnitCount: ProgressSteps.parsing)
        
        // load all groups
        Diag.debug("Loading groups")
        var groups = ContiguousArray<Group1>()
        var groupByID = [Group1ID : Group1]() // will need these for restoring the hierarchy
        var maxLevel = 0                      // of groups and entries
        for _ in 0..<header.groupCount {
            loadProgress.completedUnitCount += 1
            let group = Group1(database: self)
            try group.load(from: stream) // throws FormatError
            if group.isDeleted {
                backupGroup = group
            }
            if group.level > maxLevel {
                maxLevel = Int(group.level)
            }
            groupByID[group.id] = group
            groups.append(group)
        }

        // load all entries
        Diag.debug("Loading entries")
        var entries = ContiguousArray<Entry1>()
        for _ in 0..<header.entryCount {
            let entry = Entry1(database: self)
            try entry.load(from: stream) // throws FormatError
            entries.append(entry)
            loadProgress.completedUnitCount += 1
            if loadProgress.isCancelled {
                throw ProgressInterruption.cancelled(reason: loadProgress.cancellationReason)
            }
        }
        Diag.info("Loaded \(groups.count) groups and \(entries.count) entries")
        
        // create root group
        let _root = Group1(database: self)
        _root.level = -1 // because its children should have level 0
        _root.iconID = Group.defaultIconID // created subgroups will use this icon
        _root.name = dbFileName
        self.root = _root
        
        // restore group hierarchy
        var parentGroup = _root
        for level in 0...maxLevel {
            let prevLevel = level - 1
            for group in groups {
                if group.level == level {
                    parentGroup.add(group: group)
                } else if group.level == prevLevel {
                    parentGroup = group
                }
            }
        }
        
        // put entries to their groups
        Diag.debug("Moving entries to their groups")
        for entry in entries {
            if entry.isMetaStream {
                // meta streams are kept in a separate list, invisible for the user
                metaStreamEntries.append(entry);
            } else {
                guard let group = groupByID[entry.groupID] else { throw FormatError.orphanedEntry }
                entry.isDeleted = group.isDeleted
                group.add(entry: entry)
            }
        }
        // Mark everything inside the backup group as deleted
        backupGroup?.deepSetDeleted(true)
        
        // Resolve references in loaded content
        resolveReferences(
            allEntries: entries,
            parentProgress: progress,
            pendingProgressUnits: ProgressSteps.resolvingReferences
        )
    }
    
    /// Decrypts DB data using current master key.
    /// - Throws: CryptoError, ProgressInterruption
    func decrypt(data: ByteArray) throws -> ByteArray {
        switch header.algorithm {
        case .aes:
            Diag.debug("Decrypting AES cipher")
            let cipher = AESDataCipher()
            progress.addChild(cipher.initProgress(), withPendingUnitCount: ProgressSteps.decryption)
            let decrypted = try cipher.decrypt(cipherText: data, key: masterKey, iv: header.initialVector)
                // throws CryptoError, ProgressInterruption
            return decrypted
        case .twofish:
            Diag.debug("Decrypting Twofish cipher")
            let cipher = TwofishDataCipher(isPaddingLikelyMessedUp: false)
            progress.addChild(cipher.initProgress(), withPendingUnitCount: ProgressSteps.decryption)
            let decrypted = try cipher.decrypt(cipherText: data, key: masterKey, iv: header.initialVector)
                // throws CryptoError, ProgressInterruption
            return decrypted
        }
    }
    
    /// Encrypts the DB and returns the result as byte array.
    /// Progress, errors and outcomes are reported to status delegate.
    ///
    /// - Throws: `DatabaseError.saveError`, `ProgressInterruption`
    /// - Returns: encrypted DB bytes.
    override public func save() throws -> ByteArray {
        Diag.info("Saving KP1 database")
        let contentStream = ByteArray.makeOutputStream()
        contentStream.open()
        guard let root = root else { fatalError("Tried to save without root group") }
        
        progress.completedUnitCount = 0
        progress.totalUnitCount = ProgressSteps.all
        do {
            var groups = Array<Group>()
            var entries = Array<Entry>()
            root.collectAllChildren(groups: &groups, entries: &entries)

            // Refresh references to reflect the modified content.
            // This does not affect the output file, just its displayed version.
            resolveReferences(
                allEntries: entries,
                parentProgress: progress,
                pendingProgressUnits: ProgressSteps.resolvingReferences
            )

            Diag.info("Saving \(groups.count) groups and \(entries.count)+\(metaStreamEntries.count) entries")
            let packingProgress = ProgressEx()
            packingProgress.totalUnitCount = Int64(groups.count + entries.count + metaStreamEntries.count)
            packingProgress.localizedDescription = LString.Progress.database1PackingContent
            progress.addChild(packingProgress, withPendingUnitCount: ProgressSteps.packing)
            Diag.debug("Packing the content")
            // write groups and entries in a buffer
            for group in groups {
                (group as! Group1).write(to: contentStream)
                packingProgress.completedUnitCount += 1
            }
            for entry in entries {
                (entry as! Entry1).write(to: contentStream)
                packingProgress.completedUnitCount += 1
                if packingProgress.isCancelled {
                    throw ProgressInterruption.cancelled(reason: packingProgress.cancellationReason)
                }
            }
            Diag.debug("Writing meta-stream entries")
            // also write the meta-stream entries (which are not included in the above list)
            for metaEntry in metaStreamEntries {
                metaEntry.write(to: contentStream)
                print("Wrote a meta-stream entry: \(metaEntry.rawNotes)")
                packingProgress.completedUnitCount += 1
                if packingProgress.isCancelled {
                    throw ProgressInterruption.cancelled(reason: packingProgress.cancellationReason)
                }
            }
            contentStream.close()
            guard let contentData = contentStream.data else { fatalError() }
        
            // update the header
            Diag.debug("Updating the header")
            header.groupCount = groups.count
            header.entryCount = entries.count + metaStreamEntries.count
            header.contentHash = contentData.sha256
        
            // update encryption seeds and transform the keys
            try header.randomizeSeeds() // throws CryptoError
            try deriveMasterKey(compositeKey: self.compositeKey, canUseFinalKey: false)
                // throws CryptoError, ChallengeResponseError, ProgressInterruption
            Diag.debug("Key derivation OK")
            
            // encrypt the content
            let encryptedContent = try encrypt(data: contentData)
                // throws CryptoError, ProgressInterruption
            Diag.debug("Content encryption OK")
            
            // actually write everything out
            let outStream = ByteArray.makeOutputStream()
            outStream.open()
            defer { outStream.close() }
            header.write(to: outStream)
            outStream.write(data: encryptedContent)
            return outStream.data!
        } catch let error as CryptoError {
            Diag.error("Crypto error [reason: \(error.localizedDescription)]")
            throw DatabaseError.saveError(reason: error.localizedDescription)
        } catch let error as ChallengeResponseError {
            Diag.error("Challenge-response error [reason: \(error.localizedDescription)]")
            throw DatabaseError.saveError(reason: error.localizedDescription)
        } // ProgressInterruption is passed further up
    }
    
    /// Encrypts DB data using current master key.
    /// - Throws: CryptoError, ProgressInterruption
    func encrypt(data: ByteArray) throws -> ByteArray {
        switch header.algorithm {
        case .aes:
            Diag.debug("Encrypting AES")
            let cipher = AESDataCipher()
            progress.addChild(cipher.initProgress(), withPendingUnitCount: ProgressSteps.encryption)
            return try cipher.encrypt(
                plainText: data,
                key: masterKey,
                iv: header.initialVector) // throws CryptoError, ProgressInterruption
        case .twofish:
            Diag.debug("Encrypting Twofish")
            let cipher = TwofishDataCipher(isPaddingLikelyMessedUp: false)
            progress.addChild(cipher.initProgress(), withPendingUnitCount: ProgressSteps.encryption)
            return try cipher.encrypt(
                plainText: data,
                key: masterKey,
                iv: header.initialVector) // throws CryptoError, ProgressInterruption
        }
    }
    
    // MARK: - Group/entry management routines
    
    /// Deletes given `group` (to Backup group, when appropriate; otherwise permanently).
    override public func delete(group: Group) {
        guard let group = group as? Group1 else { fatalError() }
        guard let parentGroup = group.parent else {
            Diag.warning("Cannot delete group: no parent group")
            return
        }
        
        // Ensure backup group exists
        guard let backupGroup = getBackupGroup(createIfMissing: true) else {
            Diag.warning("Cannot delete group: no backup group")
            return
        }
        
        // detach this branch from the parent group
        parentGroup.remove(group: group)
        
        var subEntries = [Entry]()
        group.collectAllEntries(to: &subEntries)
        
        // kp1 does not backup subgroups, so move only entries
        subEntries.forEach { (entry) in
            entry.move(to: backupGroup)
            entry.touch(.accessed, updateParents: false)
        }
        Diag.debug("Delete group OK")
    }
    
    /// Deletes given `entry` (or moves it to the Backup group, when possible).
    override public func delete(entry: Entry) {
        if entry.isDeleted {
            // already in Backup, so delete permanently
            entry.parent?.remove(entry: entry)
            return
        }
        
        guard let backupGroup = getBackupGroup(createIfMissing: true) else {
            Diag.warning("Failed to get or create backup group")
            return
        }
        
        entry.move(to: backupGroup)
        entry.touch(.accessed, updateParents: false)
        Diag.info("Delete entry OK")
    }
    
    /// Creates an attachment suitable for this database's entries.
    ///
    /// - Parameters:
    ///   - name: attachment name (name of the original file)
    ///   - data: uncompressed content
    /// - Returns: version-appropriate instance of `Attachment`, possibly with compressed data.
    override public func makeAttachment(name: String, data: ByteArray) -> Attachment {
        return Attachment(name: name, isCompressed: false, data: data)
    }
}
