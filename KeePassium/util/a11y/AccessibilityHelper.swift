//  KeePassium Password Manager
//  Copyright © 2018–2019 Andrei Popleteev <info@keepassium.com>
//
//  This program is free software: you can redistribute it and/or modify it
//  under the terms of the GNU General Public License version 3 as published
//  by the Free Software Foundation: https://www.gnu.org/licenses/).
//  For commercial licensing, please contact the author.

import Foundation

class AccessibilityHelper {
    
    /// Generates an accessibilityLabel for features that can be marked as premium
    /// - Parameter name: name of the premium feature (or text in the premium-only UI control)
    /// - Parameter isEnabled: true if premium feature is already enabled; false if it should be named as premium feature.
    /// - Returns: the original feature name, adding ", Premium Feature" if `isEnabled` is false.
    public static func decorateAccessibilityLabel(
        premiumFeature name: String?,
        isEnabled: Bool
    ) -> String? {
        guard let premiumFeatureName = name else {
            return nil
        }
        if isEnabled {
            return premiumFeatureName
        } else {
            return String.localizedStringWithFormat(
                "%@ (%@)",
                premiumFeatureName,
                LString.premiumFeatureGenericTitle)
        }
    }
}
