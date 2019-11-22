//  KeePassium Password Manager
//  Copyright © 2018–2019 Andrei Popleteev <info@keepassium.com>
//
//  This program is free software: you can redistribute it and/or modify it
//  under the terms of the GNU General Public License version 3 as published
//  by the Free Software Foundation: https://www.gnu.org/licenses/).
//  For commercial licensing, please contact the author.

import Foundation
import KeePassiumLib
import LocalAuthentication

/// Contains flags that enable/disable workarounds for specific iOS issues.
class SystemIssueDetector {
    public enum Issue {
        static let allValues: [Issue] = [.autoFillFaceIDLoop_iOS_13_2_3]
        
        /// Repetetive Face ID prompts in AutoFill on iOS 13.2.3 (and maybe higher)
        /// (https://github.com/keepassium/KeePassium/issues/74)
        /// Workaround: converts immediate AppLock timeouts to a 3-second one.
        case autoFillFaceIDLoop_iOS_13_2_3
    }
    
    private static var activeIssues = [Issue]()
    
    /// Returns `true` iff the current code is potentially affected by the given `issue`.
    public static func isAffectedBy(_ issue: Issue) -> Bool {
        return activeIssues.contains(issue)
    }
    
    /// Identifies the known iOS issues/bugs, to allow for runtime workarounds.
    /// Should be run at app launch.
    public static func scanForIssues() {
        assert(activeIssues.isEmpty)
        for issue in Issue.allValues {
            switch issue {
            case .autoFillFaceIDLoop_iOS_13_2_3:
                if isAffectedByAutoFillFaceIDLoop_iOS_13_2_3() {
                    Diag.warning("Detected a known system issue: \(issue)")
                    Settings.current.isAffectedByAutoFillFaceIDLoop_iOS_13_2_3 = true
                    activeIssues.append(.autoFillFaceIDLoop_iOS_13_2_3)
                }
            }
        }
    }
    
    private static func isAffectedByAutoFillFaceIDLoop_iOS_13_2_3() -> Bool {
        #if AUTOFILL_EXT
            // Affected is only AutoFill, on Face ID devices, on iOS 13.2.3 (and maybe higher)
            guard #available(iOS 13.2.3, *) else { return false }
            guard LAContext.getBiometryType() == .faceID else { return false }
            return true
        #else
            //main app is not affected
            return false
        #endif
    }
}
