//  KeePassium Password Manager
//  Copyright © 2018–2019 Andrei Popleteev <info@keepassium.com>
// 
//  This program is free software: you can redistribute it and/or modify it
//  under the terms of the GNU General Public License version 3 as published
//  by the Free Software Foundation: https://www.gnu.org/licenses/).
//  For commercial licensing, please contact the author.

import Foundation
//import AEXML

/// Field of a KP2 database entry
public class EntryField2: EntryField {
    
    // True if both key and value are empty strings.
    public var isEmpty: Bool {
        return name.isEmpty && value.isEmpty
    }
    override init(name: String, value: String, isProtected: Bool) {
        super.init(name: name, value: value, isProtected: isProtected)
    }
    
    override public func clone() -> EntryField {
        return EntryField2(name: self.name, value: self.value, isProtected: self.isProtected)
    }
    
    /// Sets field's in-memory protection flag to that specified in Meta.
    /// Only applies for standard fields, does nothing for the others.
    func applyProtectionFlag(from meta: Meta2) {
        let mp = meta.memoryProtection
        switch name {
        case EntryField.title:
            isProtected = mp.isProtectTitle
        case EntryField.userName:
            isProtected = mp.isProtectUserName
        case EntryField.password:
            isProtected = mp.isProtectPassword
        case EntryField.url:
            isProtected = mp.isProtectURL
        case EntryField.notes:
            isProtected = mp.isProtectNotes
        default:
            break
        }
    }
    
    /// - Throws: Xml2.ParsingError, ProgressInterruption
    func load(xml: AEXMLElement, streamCipher: StreamCipher) throws {
        assert(xml.name == Xml2.string)
        Diag.verbose("Loading XML: entry field")
        erase()
        
        // It is possible that both key and value are present, but empty.
        // (MiniKeePass seems to produce such fields).
        // In this case, the caller can check `isEmpty` and remove such fields.
        
        var key: String?
        var value: String?
        var isProtected: Bool = false
        for tag in xml.children {
            switch tag.name {
            case Xml2.key:
                key = tag.value ?? ""
            case Xml2.value:
                isProtected = Bool(string: tag.attributes[Xml2.protected])
                if isProtected {
                    // the value is encrypted, need to decrypt it first
                    if let encData = ByteArray(base64Encoded: tag.value ?? "") {
                        Diag.verbose("Decrypting field value")
                        let plainData = try streamCipher.decrypt(data: encData, progress: nil)
                            // throws ProgressInterruption
                        value = plainData.toString(using: .utf8) // nil if decrypt() failed
                    }
                } else {
                    // simple plain-text value
                    value = tag.value ?? ""
                }
            default:
                Diag.error("Unexpected XML tag in Entry/String: \(tag.name)")
                throw Xml2.ParsingError.unexpectedTag(actual: tag.name, expected: "Entry/String/*")
            }
        }
        // Problematic states to check:
        // - key or value (or both) is nil
        // - empty key with non-empty value
        guard let _key = key else {
            Diag.error("Missing Entry/String/Key")
            throw Xml2.ParsingError.malformedValue(tag: "Entry/String/Key", value: nil)
        }
        guard let _value = value else {
            Diag.error("Missing Entry/String/Value")
            throw Xml2.ParsingError.malformedValue(tag: "Entry/String/Value", value: nil)
        }
        if _key.isEmpty && _value.isNotEmpty {
            Diag.error("Missing Entry/String/Key with present Value")
            // Reportedly, this can happen with databases imported from 1Password.
            // The parent Database2 will show a warning after loading is complete.
        }
        self.name = _key
        self.value = _value
        self.isProtected = isProtected
    }
    
    
    /// Throws: ProgressInterruption
    func toXml(streamCipher: StreamCipher) throws -> AEXMLElement {
        Diag.verbose("Generating XML: entry string")
        let xmlField = AEXMLElement(name: Xml2.string)
        xmlField.addChild(name: Xml2.key, value: name)
        if isProtected {
            let openData = ByteArray(utf8String: value)
            Diag.verbose("Encrypting field value")
            let encData = try streamCipher.encrypt(data: openData, progress: nil)
                // throws ProgressInterruption
            xmlField.addChild(
                name: Xml2.value,
                value: encData.base64EncodedString(),
                attributes: [Xml2.protected: Xml2._true])
        } else {
            xmlField.addChild(name: Xml2.value, value: value)
        }
        return xmlField
    }
} // EntryField2

public class Entry2: Entry {

    /// Auto type settings of a KP2 entry
    public class AutoType: Eraseable {
        public struct Association {
            var window: String
            var keystrokeSequence: String
        }
        var isEnabled: Bool
        var obfuscationType: UInt32
        var defaultSequence: String
        var associations: [Association]
        
        /// Creates a clone of the given `AutoType` instance
        init(from original: AutoType) {
            isEnabled = original.isEnabled
            obfuscationType = original.obfuscationType
            defaultSequence = original.defaultSequence
            associations = original.associations
        }
        init() {
            isEnabled = true
            obfuscationType = 0
            defaultSequence = ""
            associations = []
        }
        deinit {
            erase()
        }
        
        public func erase() {
            isEnabled = true
            obfuscationType = 0
            defaultSequence.erase()
            associations.removeAll() //erase()
        }

        func clone() -> AutoType {
            return AutoType(from: self)
        }

        /// - Throws: Xml2.ParsingError
        func load(xml: AEXMLElement, streamCipher: StreamCipher) throws {
            assert(xml.name == Xml2.autoType)
            Diag.verbose("Loading XML: entry autotype")
            erase()
            
            for tag in xml.children {
                switch tag.name {
                case Xml2.enabled:
                    isEnabled = Bool(string: tag.value)
                case Xml2.dataTransferObfuscation:
                    obfuscationType = UInt32(tag.value) ?? 0
                case Xml2.defaultSequence:
                    defaultSequence = tag.value ?? ""
                case Xml2.association:
                    try loadAssociation(xml: tag)
                default:
                    Diag.error("Unexpected XML tag in Entry/AutoType: \(tag.name)")
                    throw Xml2.ParsingError.unexpectedTag(actual: tag.name, expected: "Entry/*")
                }
            }
        }
        
        /// - Throws: Xml2.ParsingError
        func loadAssociation(xml: AEXMLElement) throws {
            assert(xml.name == Xml2.association)
            
            var window: String?
            var sequence: String?
            for tag in xml.children {
                switch tag.name {
                case Xml2.window:
                    window = tag.value ?? ""
                case Xml2.keystrokeSequence:
                    sequence = tag.value ?? ""
                default:
                    Diag.error("Unexpected XML tag in Entry/AutoType/Association: \(tag.name)")
                    throw Xml2.ParsingError.unexpectedTag(
                        actual: tag.name,
                        expected: "Entry/AutoType/Association/*")
                }
            }
            guard window != nil else {
                Diag.error("Missing Entry/AutoType/Association/Window")
                throw Xml2.ParsingError.malformedValue(
                    tag: "Entry/AutoType/Association/Window",
                    value: window)
            }
            guard sequence != nil else {
                Diag.error("Missing Entry/AutoType/Association/Sequence")
                throw Xml2.ParsingError.malformedValue(
                    tag: "Entry/AutoType/Association/Sequence",
                    value: sequence)
            }
            associations.append(Association(window: window!, keystrokeSequence: sequence!))
        }
        
        internal func toXml() -> AEXMLElement {
            Diag.verbose("Generating XML: entry autotype")
            let xmlAutoType = AEXMLElement(name: Xml2.autoType)
            xmlAutoType.addChild(
                name: Xml2.enabled,
                value: isEnabled ? Xml2._true : Xml2._false)
            xmlAutoType.addChild(
                name: Xml2.dataTransferObfuscation,
                value: String(obfuscationType))
            
            if !defaultSequence.isEmpty {
                xmlAutoType.addChild(
                    name: Xml2.defaultSequence,
                    value: defaultSequence)
            }
            for association in associations {
                let xmlAssoc = xmlAutoType.addChild(name: Xml2.association)
                xmlAssoc.addChild(
                    name: Xml2.window,
                    value: association.window)
                xmlAssoc.addChild(
                    name: Xml2.keystrokeSequence,
                    value: association.keystrokeSequence)
            }
            return xmlAutoType
        }
    } // AutoType
    
    private var _canExpire: Bool
    override public var canExpire: Bool {
        get { return _canExpire }
        set { _canExpire = newValue }
    }
    
    override public var isSupportsExtraFields: Bool { return true }
    
    override public var isSupportsMultipleAttachments: Bool { return true }
    
    
    //MARK: Entry2 properties
    public var customIconUUID: UUID
    public var autoType: AutoType
    public var history: Array<Entry2>
    public var usageCount: UInt32
    public var locationChangedTime: Date
    public var foregroundColor: String
    public var backgroundColor: String
    public var overrideURL: String
    public var tags: String
    public var customData: CustomData2 // v4 only
    
    override init(database: Database?) {
        _canExpire = false
        customIconUUID = UUID.ZERO
        autoType = AutoType()
        history = []
        usageCount = 0
        locationChangedTime = Date.now
        foregroundColor = ""
        backgroundColor = ""
        overrideURL = ""
        tags = ""
        customData = CustomData2()
        super.init(database: database)
    }
    deinit {
        erase()
    }
    
    override public func erase() {
        _canExpire = false
        customIconUUID.erase()
        autoType.erase()
        history.erase()
        usageCount = 0
        locationChangedTime = Date.now
        foregroundColor.erase()
        backgroundColor.erase()
        overrideURL.erase()
        tags.erase()
        customData.erase()
        super.erase()
    }
    
    /// Returns a new entry instance with the same properties.
    override public func clone(makeNewUUID: Bool) -> Entry {
        let newEntry = Entry2(database: self.database)
        self.apply(to: newEntry, makeNewUUID: makeNewUUID)
        
        // The clone is not inserted in any group because
        // the clone might be needed in entry history (and thus have no parent group)
        
        return newEntry
    }

    /// Copies properties of this entry to the `target`.
    /// Complex properties are cloned.
    /// Does not affect group membership.
    func apply(to target: Entry2, makeNewUUID: Bool) {
        super.apply(to: target, makeNewUUID: makeNewUUID)
        target.customIconUUID = self.customIconUUID
        target.foregroundColor = self.foregroundColor
        target.backgroundColor = self.backgroundColor
        target.overrideURL = self.overrideURL
        target.tags = self.tags
        
        target.autoType = self.autoType.clone()
        
        target.canExpire = self.canExpire
        target.usageCount = self.usageCount
        target.locationChangedTime = self.locationChangedTime
        target.customData = self.customData.clone()

        target.history.removeAll()
        for histEntry in history {
            let histEntryClone = histEntry.clone(makeNewUUID: makeNewUUID) as! Entry2
            target.history.append(histEntryClone)
        }
    }
    
    override public func makeEntryField(
        name: String,
        value: String,
        isProtected: Bool
        ) -> EntryField
    {
        return EntryField2(name: name, value: value, isProtected: isProtected)
    }
    
    public func addToHistory(entry: Entry) {
        // most recent entries should be at the top
        history.insert(entry as! Entry2, at: 0)
    }
    
    func clearHistory() {
        history.erase()
    }
    
    /// Removes old history items, if required by Meta settings.
    func maintainHistorySize() {
        let meta: Meta2 = (self.database as! Database2).meta
        if meta.historyMaxItems >= 0 {
            // Remove history items with oldest modification date
            
            history.sort(by: { return $0.lastModificationTime < $1.lastModificationTime })
            let oldEntryCount = history.count - Int(meta.historyMaxItems)
            guard oldEntryCount > 0 else { return }
            // These entries will be gone, so erase them first
            for oldEntry in history.prefix(oldEntryCount) {
                oldEntry.erase()
            }
            history = Array(history.dropFirst(oldEntryCount))
        }
        //TODO: enforce historyMaxSize, too
    }
    
    
    /// Makes a backup copy of the current values/state of the entry.
    /// (For KP2, adds the current state to entry's history)
    ///
    /// - Returns: true if successful, false otherwise.
    override public func backupState() {
        // In KP2, historical items preserve the same UUID (unlike KP1)
        let entryClone = self.clone(makeNewUUID: false) as! Entry2
        entryClone.clearHistory()
        addToHistory(entry: entryClone)
        maintainHistorySize()
    }

    /// Update last access time and usage counter (and optionally the modification time) of the entry.
    /// - Parameter mode: defines which timestamps should be updated
    /// - Parameter updateParents: also touch containing groups.
    override public func touch(_ mode: DatabaseItem.TouchMode, updateParents: Bool = true) {
        usageCount += 1
        super.touch(mode, updateParents: updateParents)
    }
    
    override public func move(to newGroup: Group) {
        super.move(to: newGroup)
        locationChangedTime = Date.now
    }
    
    /// Loads the entry from XML.
    /// - Throws: `Xml2.ParsingError`, `ProgressInterruption`
    func load(
        xml: AEXMLElement,
        streamCipher: StreamCipher,
        warnings: DatabaseLoadingWarnings
        ) throws
    {
        assert(xml.name == Xml2.entry)
        Diag.verbose("Loading XML: entry")
        
        // All the fields will be read from XML, except for the parent group
        // so we restore the parent after erasing.
        let parent = self.parent
        erase()
        self.parent = parent
        
        for tag in xml.children {
            switch tag.name {
            case Xml2.uuid:
                self.uuid = UUID(base64Encoded: tag.value) ?? UUID.ZERO
            case Xml2.iconID:
                self.iconID = IconID(tag.value) ?? IconID.key
            case Xml2.customIconUUID:
                self.customIconUUID = UUID(base64Encoded: tag.value) ?? UUID.ZERO
            case Xml2.foregroundColor:
                self.foregroundColor = tag.value ?? ""
            case Xml2.backgroundColor:
                self.backgroundColor = tag.value ?? ""
            case Xml2.overrideURL:
                self.overrideURL = tag.value ?? ""
            case Xml2.tags:
                self.tags = tag.value ?? ""
            case Xml2.string:
                let field = makeEntryField(name: "", value: "", isProtected: true) as! EntryField2
                try field.load(xml: tag, streamCipher: streamCipher)
                    // throws Xml2.ParsingError, ProgressInterruption
                if field.isEmpty {
                    Diag.debug("Loaded empty entry field, ignoring.")
                } else if field.name.isEmpty {
                    Diag.warning("Loaded entry field with an empty name, will show a warning.")
                    // For now, just log the warning and ignore it. User-visible warnings
                    // will be generated by the caller, when done loading the DB.
                    setField(name: field.name, value: field.value, isProtected: field.isProtected)
                } else {
                    Diag.verbose("Entry field loaded OK")
                    setField(name: field.name, value: field.value, isProtected: field.isProtected)
                }
            case Xml2.binary:
                guard !tag.children.isEmpty else {
                    Diag.warning("Skipping an empty Binary tag")
                    continue
                }
                let att = try Attachment2.load(
                    xml: tag,
                    database: database as! Database2,
                    streamCipher: streamCipher)
                    // throws Xml2.ParsingError, ProgressInterruption
                attachments.append(att)
                Diag.verbose("Entry attachment loaded OK")
            case Xml2.times:
                try loadTimes(xml: tag)
                Diag.verbose("Entry times loaded OK")
            case Xml2.autoType:
                try autoType.load(xml: tag, streamCipher: streamCipher)
                Diag.verbose("Entry autotype loaded OK")
            case Xml2.customData: // v4 only
                try customData.load(xml: tag, streamCipher: streamCipher, xmlParentName: "Entry")
                Diag.verbose("Entry custom data loaded OK")
            case Xml2.history:
                try loadHistory(xml: tag, streamCipher: streamCipher, warnings: warnings)
                    // throws Xml2.ParsingError, ProgressInterruption
                Diag.verbose("Entry history loaded OK")
            default:
                Diag.error("Unexpected XML tag in Entry: \(tag.name)")
                throw Xml2.ParsingError.unexpectedTag(actual: tag.name, expected: "Entry/*")
            }
        }
    }
    
    /// Loads timestamps of the entry.
    /// - Throws: Xml2.ParsingError
    func loadTimes(xml: AEXMLElement) throws {
        assert(xml.name == Xml2.times)
        Diag.verbose("Loading XML: entry times")
        let db = database as! Database2
        
        // Some apps create empty-value expiryTime tags for non-expiring entries.
        // So we validate the expiry time below, only after parsing all times.
        var optionalExpiryTime: Date?
        for tag in xml.children {
            switch tag.name {
            case Xml2.lastModificationTime:
                guard let time = db.xmlStringToDate(tag.value) else {
                    Diag.error("Cannot parse Entry/Times/LastModificationTime as Date")
                     throw Xml2.ParsingError.malformedValue(
                        tag: "Entry/Times/LastModificationTime",
                        value: tag.value)
                }
                lastModificationTime = time
            case Xml2.creationTime:
                guard let time = db.xmlStringToDate(tag.value) else {
                    Diag.error("Cannot parse Entry/Times/CreationTime as Date")
                    throw Xml2.ParsingError.malformedValue(
                        tag: "Entry/Times/CreationTime",
                        value: tag.value)
                }
                creationTime = time
            case Xml2.lastAccessTime:
                guard let time = db.xmlStringToDate(tag.value) else {
                    Diag.error("Cannot parse Entry/Times/LastAccessTime as Date")
                    throw Xml2.ParsingError.malformedValue(
                        tag: "Entry/Times/LastAccessTime",
                        value: tag.value)
                }
                lastAccessTime = time
            case Xml2.expiryTime:
                guard let tagValue = tag.value else {
                    Diag.warning("Entry/Times/ExpiryTime is nil")
                    optionalExpiryTime = nil // acceptable if canExpire value is/will be false
                    continue
                }
                guard let time = db.xmlStringToDate(tagValue) else {
                    Diag.error("Cannot parse Entry/Times/ExpiryTime as Date")
                    throw Xml2.ParsingError.malformedValue(
                        tag: "Entry/Times/ExpiryTime",
                        value: tagValue)
                }
                optionalExpiryTime = time
            case Xml2.expires:
                self.canExpire = Bool(string: tag.value)
            case Xml2.usageCount:
                usageCount = UInt32(tag.value) ?? 0
            case Xml2.locationChanged:
                guard let time = db.xmlStringToDate(tag.value) else {
                    Diag.error("Cannot parse Entry/Times/LocationChanged as Date")
                    throw Xml2.ParsingError.malformedValue(
                        tag: "Entry/Times/LocationChanged",
                        value: tag.value)
                }
                locationChangedTime = time
            default:
                Diag.error("Unexpected XML tag in Entry/Times: \(tag.name)")
                throw Xml2.ParsingError.unexpectedTag(actual: tag.name, expected: "Entry/Times/*")
            }
        }
        
        if let expiryTime = optionalExpiryTime  {
            self.expiryTime = expiryTime
        } else {
            if canExpire {
                Diag.error("Parsed an entry that can expire, but Entry/Times/ExpiryTime is nil")
                throw Xml2.ParsingError.malformedValue(
                    tag: "Entry/Times/ExpiryTime",
                    value: nil)
            } else {
                // The entry does not expire, so just set the missing expiry date
                // to a reasonable value.
                self.expiryTime = Date.distantFuture
            }
        }
    }

    /// Loads the entry's history tag.
    /// - Throws: Xml2.ParsingError, ProgressInterruption
    func loadHistory(
        xml: AEXMLElement,
        streamCipher: StreamCipher,
        warnings: DatabaseLoadingWarnings
        ) throws
    {
        assert(xml.name == Xml2.history)
        Diag.verbose("Loading XML: entry history")
        for tag in xml.children {
            switch tag.name {
            case Xml2.entry:
                let histEntry = Entry2(database: database)
                try histEntry.load(xml: tag, streamCipher: streamCipher, warnings: warnings)
                    // throws Xml2.ParsingError, ProgressInterruption
                history.append(histEntry)
                Diag.verbose("Entry history item loaded OK")
            default:
                Diag.error("Unexpected XML tag in Entry/History: \(tag.name)")
                throw Xml2.ParsingError.unexpectedTag(actual: tag.name, expected: "Entry/History/*")
            }
        }
    }
    
    /// Throws: `ProgressInterruption`
    func toXml(streamCipher: StreamCipher) throws -> AEXMLElement {
        Diag.verbose("Generating XML: entry")
        let db2 = database as! Database2
        let meta: Meta2 = db2.meta
        
        let xmlEntry = AEXMLElement(name: Xml2.entry)
        xmlEntry.addChild(name: Xml2.uuid, value: uuid.base64EncodedString())
        xmlEntry.addChild(name: Xml2.iconID, value: String(iconID.rawValue))
        if customIconUUID != UUID.ZERO {
            xmlEntry.addChild(
                name: Xml2.customIconUUID,
                value: customIconUUID.base64EncodedString())
        }
        xmlEntry.addChild(name: Xml2.foregroundColor, value: foregroundColor)
        xmlEntry.addChild(name: Xml2.backgroundColor, value: backgroundColor)
        xmlEntry.addChild(name: Xml2.overrideURL, value: overrideURL)
        xmlEntry.addChild(name: Xml2.tags, value: tags)
        
        // times
        let xmlTimes = AEXMLElement(name: Xml2.times)
        xmlTimes.addChild(
            name: Xml2.creationTime,
            value: db2.xmlDateToString(creationTime))
        xmlTimes.addChild(
            name: Xml2.lastModificationTime,
            value: db2.xmlDateToString(lastModificationTime))
        xmlTimes.addChild(
            name: Xml2.lastAccessTime,
            value: db2.xmlDateToString(lastAccessTime))
        xmlTimes.addChild(
            name: Xml2.expiryTime,
            value: db2.xmlDateToString(expiryTime))
        xmlTimes.addChild(
            name: Xml2.expires,
            value: canExpire ? Xml2._true : Xml2._false)
        xmlTimes.addChild(
            name: Xml2.usageCount,
            value: String(usageCount))
        xmlTimes.addChild(
            name: Xml2.locationChanged,
            value: db2.xmlDateToString(locationChangedTime))
        xmlEntry.addChild(xmlTimes)
        
        // <String> fields
        for field in fields {
            let field2 = field as! EntryField2
            field2.applyProtectionFlag(from: meta)
            xmlEntry.addChild(try field2.toXml(streamCipher: streamCipher))
                // throws ProgressInterruption
        }
        // Attachments
        for att in attachments {
            xmlEntry.addChild((att as! Attachment2).toXml())
        }
        // Auto type
        xmlEntry.addChild(autoType.toXml())
        
        if db2.header.formatVersion == .v4 && !customData.isEmpty{
            xmlEntry.addChild(customData.toXml())
        }
        
        // History
        if !history.isEmpty {
            let xmlHistory = xmlEntry.addChild(name: Xml2.history)
            for histEntry in history {
                xmlHistory.addChild(try histEntry.toXml(streamCipher: streamCipher))
                    // throws ProgressInterruption
            }
        }
        return xmlEntry
    }
}
