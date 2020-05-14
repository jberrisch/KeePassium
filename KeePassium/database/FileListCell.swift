//  KeePassium Password Manager
//  Copyright © 2018–2019 Andrei Popleteev <info@keepassium.com>
// 
//  This program is free software: you can redistribute it and/or modify it
//  under the terms of the GNU General Public License version 3 as published
//  by the Free Software Foundation: https://www.gnu.org/licenses/).
//  For commercial licensing, please contact the author.

import KeePassiumLib

/// A cell in the a file list/table.
class FileListCell: UITableViewCell {
    /// Reference to the database file
    var urlRef: URLReference! {
        didSet {
            setupCell()
        }
    }
    
    private func setupCell() {
        textLabel?.text = urlRef.publicURL?.lastPathComponent ?? "?"
        
        // Here we need file info ASAP, even if outdated. We'll refresh it separately.
        urlRef.getCachedInfo { [weak self] result in
            guard let self = self else { return }

            switch result {
            case .success(let fileInfo):
                self.imageView?.image = self.getFileIcon(for: self.urlRef, hasError: false)
                if let modificationDate = fileInfo.modificationDate {
                    let dateString = DateFormatter.localizedString(
                        from: modificationDate,
                        dateStyle: .long,
                        timeStyle: .medium)
                    self.detailTextLabel?.text = dateString
                } else {
                    self.detailTextLabel?.text = nil
                }
                self.detailTextLabel?.textColor = UIColor.auxiliaryText
            case .failure(let error):
                self.detailTextLabel?.text = error.localizedDescription
                self.detailTextLabel?.textColor = UIColor.errorMessage
                self.imageView?.image = self.getFileIcon(for: self.urlRef, hasError: true)
            }
        }
    }
    
    /// Returns an appropriate icon for the target file.
    func getFileIcon(for urlRef: URLReference, hasError: Bool) -> UIImage? {
        assertionFailure("Override this")
        return nil
    }
}

/// A cell in a list of database files
class DatabaseListCell: FileListCell {
    override func getFileIcon(for urlRef: URLReference, hasError: Bool) -> UIImage? {
        guard !hasError else {
            return UIImage(asset: .databaseErrorListitem)
        }
        return UIImage.databaseIcon(for: self.urlRef)
    }
}

/// A cell if a list of key files
class KeyFileListCell: FileListCell {
    override func getFileIcon(for urlRef: URLReference, hasError: Bool) -> UIImage? {
        return nil
    }
}
