//  KeePassium Password Manager
//  Copyright © 2020 Andrei Popleteev <info@keepassium.com>
//
//  This program is free software: you can redistribute it and/or modify it
//  under the terms of the GNU General Public License version 3 as published
//  by the Free Software Foundation: https://www.gnu.org/licenses/).
//  For commercial licensing, please contact the author.

public class EntryFieldReference {
    public enum Status {
        case parsed
        case targetMissing
        case resolved
    }
    private(set) public var status: Status
    
    enum FieldType {
        case uuid
        case named(_ name: String)
        case otherNamed
        
        public static func fromCode(_ code: Character) -> Self? {
            switch code {
            case "T": return .named(EntryField.title)
            case "U": return .named(EntryField.userName)
            case "P": return .named(EntryField.password)
            case "A": return .named(EntryField.url)
            case "N": return .named(EntryField.notes)
            case "I": return .uuid
            case "O": return .otherNamed
            default:
                return nil
            }
        }
    }
    
    private static let refPrefix = "{REF:"
    private static let regexp = try! NSRegularExpression(
        pattern: #"{REF:([TUPANI])@([TUPANIO]):(.+)}"#,
        options: []
    )
    
    /// Range of this reference in the source string
    private var range: NSRange?
    private var targetFieldType: FieldType
    private var searchFieldType: FieldType
    private var searchValue: Substring

    /// The referenced field, if resolved.
    /// (Also `nil` if the target field is UUID. In this case, `status` is `.resolved`, but `target` is `nil`.
    private(set) public var targetField: Weak<EntryField>?
   
    
    private init(
        range: NSRange,
        targetFieldType: FieldType,
        searchFieldType: FieldType,
        searchValue: Substring)
    {
        self.targetFieldType = targetFieldType
        self.searchFieldType = searchFieldType
        self.searchValue = searchValue
        self.status = .parsed
    }
    
    // MARK: Parsing
    
    /// Tries parsing the given string.
    /// - Parameter string: string to parse. Valid references should have format
    ///     `{REF:<WantedField>@<SearchIn>:<Text>}`.
    ///     The string can contain serveral references.
    /// - Returns: Initialized references with a suitable status
    public static func parse(_ string: String) -> [EntryFieldReference] {
        guard string.contains(refPrefix) else {
            // fast check: there are no refs
            return []
        }
        
        var references = [EntryFieldReference]()
        let fullRange = NSRange(string.startIndex..<string.endIndex, in: string)
        let matches = regexp.matches(in: string, options: [], range: fullRange)
        for match in matches {
            guard match.numberOfRanges == 3,
                  let targetFieldCodeRange = Range(match.range(at: 1), in: string),
                  let searchFieldCodeRange = Range(match.range(at: 2), in: string),
                  let searchValueRange =  Range(match.range(at: 3), in: string) else
            {
                // malformed reference, go to the next one
                continue
            }
            
            guard let targetFieldCode = string[targetFieldCodeRange].first,
                  let targetFieldType = FieldType.fromCode(targetFieldCode) else
            {
                // failed to parse this ref, go to the next one
                Diag.debug("Unrecognized target field")
                continue
            }
            
            guard let searchFieldCode = string[searchFieldCodeRange].first,
                  let searchFieldType = FieldType.fromCode(searchFieldCode) else
            {
                // failed to parse this ref, go to the next one
                Diag.debug("Unrecognized search field")
                continue
            }
            
            let searchValue = string[searchValueRange]
            guard !searchValue.isEmpty else {
                // failed to parse this ref, go to the next one
                Diag.debug("Empty search criterion")
                continue
            }
            let ref = EntryFieldReference(
                range: match.range,
                targetFieldType: targetFieldType,
                searchFieldType: searchFieldType,
                searchValue: searchValue)
            references.append(ref)
        }
        return references
    }
    
    // MARK: Resolving
    
    /// Finds the target field of this reference.
    /// - Parameter entries: entries to search among (e.g. all the DB entries)
    /// - Returns: `true` if resolved successfully
    public func resolve(entries: [Entry]) -> Bool {
        assert(status == .parsed)
        guard let entry = findEntry(in: entries, field: searchFieldType, value: searchValue) else {
            targetField = nil
            status = .targetMissing
            return false
        }
        
        switch targetFieldType {
        case .uuid:
            // UUID is not an EntryField, which makes it rather difficult to reference.
            // Most likely, nobody will use it as a target field anyway.
            // We'll recognize UUID target by the combination (resolved, but target field is nil).
            targetField = nil
            status = .resolved
        case .named(let name):
            if let _targetField = entry.getField(with: name) {
                self.targetField = Weak(_targetField)
                status = .resolved
            } else {
                self.targetField = nil
                status = .targetMissing
            }
        case .otherNamed:
            if let _targetField = entry.getField(with: searchValue) {
                self.targetField = Weak(_targetField)
                status = .resolved
            } else {
                self.targetField = nil
                status = .targetMissing
            }
        }
        return status == .resolved
    }
    
    func findEntry(in entries: [Entry], field: FieldType, value: Substring) -> Entry? {
        let result: Entry?
        switch field {
        case .uuid:
            // The UUID string can be a simple hex string (most likely)
            // or a formatted UUID string with dashes.
            let _uuid: UUID?
            if let uuidBytes = ByteArray(hexString: value) {
                _uuid = UUID(data: uuidBytes)
            } else {
                _uuid = UUID(uuidString: String(value)) // this constructor accepts only String
            }
            guard let uuid = _uuid else {
                Diag.debug("Malformed UUID: \(value)")
                return nil
            }
            result = entries.first(where: { $0.uuid == uuid })
        case .named(let name):
            result = entries.first(where: { entry in
                let field = entry.getField(with: name)
                return field?.value.compare(value) == .some(.orderedSame)
            })
        case .otherNamed:
            // For custom fields, KeePass searches by field name
            result = entries.first(where: { entry in
                let field = entry.getField(with: value)
                return field != nil
            })
        }
        return result
    }
    
    public func getValue(maxDepth: Int) -> String {
        if maxDepth == 0 {
            return "{REF: ???}" //TODO: localize this
        }
        
        switch status {
        case .parsed:
            assertionFailure("The reference should be resolved by now")
            return "{REF: unresolved}"
        case .targetMissing:
            return "{REF: ?}"
        case .resolved:
            let field = targetField?.value
            return field?.getResolvedValue(maxDepth: maxDepth - 1)
        }
    }
}

