//  KeePassium Password Manager
//  Copyright © 2018–2019 Andrei Popleteev <info@keepassium.com>
// 
//  This program is free software: you can redistribute it and/or modify it
//  under the terms of the GNU General Public License version 3 as published
//  by the Free Software Foundation: https://www.gnu.org/licenses/).
//  For commercial licensing, please contact the author.

import UIKit

//protocol ValidatingTextViewDelegate {
//    func isTextViewValid(sender: ValidatingTextView) -> Bool
//    func textViewValidityDidChange(sender: ValidatingTextView, isValid: Bool)
//}
protocol ValidatingTextViewDelegate {
    /// Called whenever the user changes the text, immediately before validation
    func validatingTextView(_ sender: ValidatingTextView, textDidChange text: String)
    /// Should return `true` if the text is valid, `false` otherwise
    func validatingTextViewShouldValidate(_ sender: ValidatingTextView) -> Bool
    /// Called after text view validity changes.
    func validatingTextView(_ sender: ValidatingTextView, validityDidChange: Bool)
}

extension ValidatingTextViewDelegate {
    // Empty method stubs, to make their implementation optional for delegates.
    func validatingTextView(_ sender: ValidatingTextView, textDidChange text: String) {}
    func validatingTextViewShouldValidate(_ sender: ValidatingTextView) -> Bool { return true }
    func validatingTextView(_ sender: ValidatingTextView, validityDidChange: Bool) {}
}

class ValidatingTextView: WatchdogAwareTextView {
    
    var validityDelegate: ValidatingTextViewDelegate?
    var isValid: Bool {
        get { return validityDelegate?.validatingTextViewShouldValidate(self) ?? true }
    }
    
    override var text: String? {
        didSet { validate() }
    }
    
    private var wasValid: Bool?
    required init?(coder aDecoder: NSCoder) {
        super.init(coder: aDecoder)
    }
    
    @objc
    override func onTextChanged() {
        super.onTextChanged()
        validityDelegate?.validatingTextView(self, textDidChange: self.text ?? "")
        validate()
    }
    
    func validate() {
        let isValid = validityDelegate?.validatingTextViewShouldValidate(self) ?? true
        if isValid {
            backgroundColor = UIColor.clear
        } else if (wasValid ?? true) { // just became invalid
            backgroundColor = UIColor.red.withAlphaComponent(0.2)
        }
        if isValid != wasValid {
            validityDelegate?.validatingTextView(self, validityDidChange: isValid)
        }
        wasValid = isValid
    }
}
