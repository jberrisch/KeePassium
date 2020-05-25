//  KeePassium Password Manager
//  Copyright © 2018–2019 Andrei Popleteev <info@keepassium.com>
// 
//  This program is free software: you can redistribute it and/or modify it
//  under the terms of the GNU General Public License version 3 as published
//  by the Free Software Foundation: https://www.gnu.org/licenses/).
//  For commercial licensing, please contact the author.

import Foundation

public extension Bool {
    /// Correctly parses mixed-case "TRuE"/"FaLsE" strings, everything else means `nil`
    init?(optString value: String?) {
        guard let value = value else {
            return nil
        }
        
        switch value.lowercased() {
        case "true":
            self = true
        case "false":
            self = false
        default:
            return nil
        }
    }
    /// Correctly parses mixed-case "true", any other string means `false`.
    init(string: String) {
        if string.lowercased() == "true" {
            self = true
        } else {
            self = false
        }
    }
    /// Correctly parses mixed-case "true", any other string or `nil` means `false`.
    init(string: String?) {
        self.init(string: string ?? "")
    }
}
