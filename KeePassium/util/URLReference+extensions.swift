//  KeePassium Password Manager
//  Copyright © 2018–2019 Andrei Popleteev <info@keepassium.com>
//
//  This program is free software: you can redistribute it and/or modify it
//  under the terms of the GNU General Public License version 3 as published
//  by the Free Software Foundation: https://www.gnu.org/licenses/).
//  For commercial licensing, please contact the author.

import KeePassiumLib

extension URLReference {
    
    /// Returns an icon suitable for this reference (+ its location + its type)
    func getIcon(fileType: FileType) -> UIImage? {
        switch fileType {
        case .database:
            return getDatabaseIcon()
        case .keyFile:
            return UIImage(asset: .keyFileListitem)
        }
    }
    
    /// Icon for database with the given reference (depends on location and error state).
    private func getDatabaseIcon() -> UIImage {
        switch self.location {
        case .external:
            return fileProvider?.icon ?? UIImage(asset: .fileProviderGenericListitem)
        case .internalDocuments, .internalInbox:
            if UIDevice.current.userInterfaceIdiom == .pad {
                return UIImage.init(asset: .fileProviderOnMyIPadListitem)
            } else {
                return UIImage.init(asset: .fileProviderOnMyIPhoneListitem)
            }
        case .internalBackup:
            return UIImage(asset: .databaseBackupListitem)
        }
    }
}
