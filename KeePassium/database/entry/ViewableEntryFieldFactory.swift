//  KeePassium Password Manager
//  Copyright © 2018–2019 Andrei Popleteev <info@keepassium.com>
// 
//  This program is free software: you can redistribute it and/or modify it
//  under the terms of the GNU General Public License version 3 as published
//  by the Free Software Foundation: https://www.gnu.org/licenses/).
//  For commercial licensing, please contact the author.

import UIKit
import KeePassiumLib

/// Internal names of the fields that should be displayed in one line.
/// (Other - custom - fields are always multi-line)
fileprivate let singlelineFields: [String] =
    [EntryField.title, EntryField.userName, EntryField.password, EntryField.url]

/// Entry field as shown
protocol ViewableField: class {
    var field: EntryField? { get set }

    var internalName: String { get }
    var visibleName: String { get }
    
    var value: String? { get }
    var isProtected: Bool { get }
    
    /// Can this field be edited?
    var isEditable: Bool { get }

    var isMultiline: Bool { get }

    /// True for standard fields that cannot be moved around.
    var isFixed: Bool { get }
    
    /// Valid only for protected fields: is the value currently hidden?
    var isValueHidden: Bool { get set }

    /// Should the field height be limited when showing?
    var isHeightConstrained: Bool { get set }
}

extension ViewableField {
    var isMultiline: Bool {
        return !singlelineFields.contains(internalName)
    }
    
    var visibleName: String {
        switch internalName {
        case EntryField.title: return LString.fieldTitle
        case EntryField.userName: return LString.fieldUserName
        case EntryField.password: return LString.fieldPassword
        case EntryField.url: return LString.fieldURL
        case EntryField.notes: return LString.fieldNotes
        default:
            return internalName
        }
    }
}

class BasicViewableField: ViewableField {
    weak var field: EntryField?
    
    var internalName: String { return field?.name ?? "" }
    var value: String? { return field?.value }
    var isProtected: Bool { return field?.isProtected ?? false }
    /// True for standard fields that cannot be moved around.
    var isFixed: Bool { return field?.isStandardField ?? false }

    /// Valid only for protected fields: is the value currently hidden?
    var isValueHidden: Bool
    
    /// Should the field height be limited when showing?
    var isHeightConstrained: Bool
    
    /// Can this field be edited?
    var isEditable: Bool { return true }
    
    // Existing entry field for external interface
    convenience init(field: EntryField, isValueHidden: Bool) {
        self.init(fieldOrNil: field, isValueHidden: isValueHidden)
    }
    
    // Possibly nil entry field for internal use
    init(fieldOrNil field: EntryField?, isValueHidden: Bool) {
        self.field = field
        self.isValueHidden = isValueHidden
        self.isHeightConstrained = true
    }
}

/// A `ViewableField` whose value is calculated (and/or is referencing other fields).
class DynamicViewableField: BasicViewableField, Refreshable {

    /// Entry fields needed to calculate `value`.
    internal var fields: [Weak<EntryField>]

    init(field: EntryField?, fields: [EntryField], isValueHidden: Bool) {
        self.fields = Weak.wrapped(fields)
        super.init(fieldOrNil: field, isValueHidden: isValueHidden)
    }
    
    /// Recalculates field value
    public func refresh() {
        //TODO: check if `value` is a reference, and fetch its value
    }
}

class TOTPViewableField: DynamicViewableField {
    var totpGenerator: TOTPGenerator?
    
    override var internalName: String { return EntryField.totp }
    override var isEditable: Bool { return false }
    
    override var value: String {
        return totpGenerator?.generate() ?? ""
    }
    var elapsedTimeFraction: Float? {
        return totpGenerator?.elapsedTimeFraction
    }
    
    init(fields: [EntryField]) {
        super.init(field: nil, fields: fields, isValueHidden: false)
        refresh()
    }
    
    override func refresh() {
        let _fields = Weak.unwrapped(self.fields)
        self.totpGenerator = TOTPGeneratorFactory.makeGenerator(from: _fields) // might return nil
    }
}

class ViewableEntryFieldFactory {
    enum ExcludedFields {
        /// Do not include the title field
        case title
        /// Do not include fields with empty values
        case emptyValues
        /// Do not include fields that cannot be edited (such as TOTP)
        case nonEditable
    }
    
    static func makeAll(
        from entry: Entry,
        in database: Database,
        excluding excludedFields: [ExcludedFields]
    ) -> [ViewableField] {
        var result = [ViewableField]()
        let excludeTitle = excludedFields.contains(.title)
        let excludeEmptyValues = excludedFields.contains(.emptyValues)
        let excludeNonEditable = excludedFields.contains(.nonEditable)
        for field in entry.fields {
            if excludeTitle && field.name == EntryField.title {
                continue
            }
            if excludeEmptyValues && field.value.isEmpty {
                continue
            }
            
            // in KP1, all fields are not protected, but we still need to hide the password
            let isHidden = field.isProtected || field.name == EntryField.password
            let viewableField = BasicViewableField(field: field, isValueHidden: isHidden)
            result.append(viewableField)
        }
        
        // do the fields have (sufficient) TOTP parameters?
        if let _ = TOTPGeneratorFactory.makeGenerator(for: entry),
            !excludeNonEditable
        {
            result.append(TOTPViewableField(fields: entry.fields))
        }
        
        return result
    }
}

