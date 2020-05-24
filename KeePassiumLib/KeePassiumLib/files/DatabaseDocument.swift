//  KeePassium Password Manager
//  Copyright © 2018–2019 Andrei Popleteev <info@keepassium.com>
// 
//  This program is free software: you can redistribute it and/or modify it
//  under the terms of the GNU General Public License version 3 as published
//  by the Free Software Foundation: https://www.gnu.org/licenses/).
//  For commercial licensing, please contact the author.

import UIKit

public class DatabaseDocument: BaseDocument {
    var database: Database?

    var encryptedData: ByteArray {
        get { return data }
        set { data = newValue }
    }
    
    public func open(successHandler: @escaping(() -> Void), errorHandler: @escaping((String?)->Void)) {
        super.open(completionHandler: { success in
            if success {
                self.errorMessage = nil
                successHandler()
            } else {
                errorHandler(self.errorMessage)
            }
        })
    }
                successHandler()
            } else {
                errorHandler(self.errorMessage)
            }
        }
    }
}
