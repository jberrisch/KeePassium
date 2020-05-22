//  KeePassium Password Manager
//  Copyright © 2018–2019 Andrei Popleteev <info@keepassium.com>
// 
//  This program is free software: you can redistribute it and/or modify it
//  under the terms of the GNU General Public License version 3 as published
//  by the Free Software Foundation: https://www.gnu.org/licenses/).
//  For commercial licensing, please contact the author.

import KeePassiumLib

class FileListCellFactory {
    fileprivate static let databaseFileIconProvider = DatabaseListCellIconProvider()
    fileprivate static let keyFileIconProvider = KeyFileListCellIconProvider()
    
    public static func dequeueReusableCell(
        from tableView: UITableView,
        withIdentifier identifier: String,
        for indexPath: IndexPath,
        for fileType: FileType
    ) -> FileListCell {
        let cell = tableView
            .dequeueReusableCell(withIdentifier: identifier, for: indexPath)
            as! FileListCell
        
        switch fileType {
        case .database:
            cell.iconProvider = FileListCellFactory.databaseFileIconProvider
        case .keyFile:
            cell.iconProvider = FileListCellFactory.keyFileIconProvider
        }
        return cell
    }
}

fileprivate protocol FileListCellIconProvider: class {
    func getFileIcon(for urlRef: URLReference, hasError: Bool) -> UIImage?
}

/// Accessory button for `FileListCell`
class FileInfoAccessoryButton: UIButton {
    required init() {
        super.init(frame: CGRect(x: 0, y: 0, width: 25, height: 25))
        setImage(UIImage(asset: .fileInfoCellAccessory), for: .normal)
        contentMode = .scaleAspectFill
    }
    required init?(coder aDecoder: NSCoder) {
        fatalError("Not implemented")
    }
}


/// A cell in the a file list/table.
class FileListCell: UITableViewCell {
    @IBOutlet weak var fileIconView: UIImageView!
    @IBOutlet weak var fileNameLabel: UILabel!
    @IBOutlet weak var fileDetailLabel: UILabel!
    @IBOutlet weak var spinner: UIActivityIndicatorView!
    var accessoryTapHandler: ((FileListCell)->())? // strong ref
    
    fileprivate var iconProvider: FileListCellIconProvider?
    
    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupCell()
    }
    override func awakeFromNib() {
        super.awakeFromNib()
        setupCell()
    }
    
    private func setupCell() {
        let fileInfoButton = FileInfoAccessoryButton()
        accessoryView = fileInfoButton
        accessoryType = .detailButton
        fileInfoButton.addTarget(
            self,
            action: #selector(didPressAccessoryButton(button:)),
            for: .touchUpInside)
    }
    
    @objc
    private func didPressAccessoryButton(button: UIButton) {
        accessoryTapHandler?(self)
    }
    
    public func showInfo(from urlRef: URLReference) {
        fileNameLabel?.text = urlRef.visibleFileName
        
        urlRef.getCachedInfo(canFetch: false) { [weak self] result in
            guard let self = self else { return }

            switch result {
            case .success(let fileInfo):
                self.fileIconView?.image = self.getFileIcon(for: urlRef, hasError: false)
                if let modificationDate = fileInfo.modificationDate {
                    let dateString = DateFormatter.localizedString(
                        from: modificationDate,
                        dateStyle: .long,
                        timeStyle: .medium)
                    self.fileDetailLabel?.text = dateString
                } else {
                    self.fileDetailLabel?.text = nil
                }
                self.fileDetailLabel?.textColor = UIColor.auxiliaryText
            case .failure:
                // The provided error can be .noInfoAvaiable, which is not informative.
                // So check the urlRef's error property instead.
                guard let error = urlRef.error else {
                    // no error, but failed -- probably info refresh is not finished yet
                    self.fileDetailLabel?.text = "..."
                    self.fileIconView?.image = self.getFileIcon(for: urlRef, hasError: false)
                    return
                }
                self.fileDetailLabel?.text = error.localizedDescription
                self.fileDetailLabel?.textColor = UIColor.errorMessage
                self.fileIconView?.image = self.getFileIcon(for: urlRef, hasError: true)
            }
        }
    }
    
    var isAnimating: Bool {
        get { spinner.isAnimating }
        set {
            if newValue {
                spinner.isHidden = false
                spinner.startAnimating()
            } else {
                spinner.stopAnimating()
                spinner.isHidden = true
            }
        }
    }
    
    /// Returns an appropriate icon for the target file.
    func getFileIcon(for urlRef: URLReference, hasError: Bool) -> UIImage? {
        return iconProvider?.getFileIcon(for: urlRef, hasError: hasError)
    }
}

fileprivate class DatabaseListCellIconProvider: FileListCellIconProvider {
    func getFileIcon(for urlRef: URLReference, hasError: Bool) -> UIImage? {
        guard !hasError else {
            return UIImage(asset: .databaseErrorListitem)
        }
        return UIImage.databaseIcon(for: urlRef)
    }
}

fileprivate class KeyFileListCellIconProvider: FileListCellIconProvider {
    func getFileIcon(for urlRef: URLReference, hasError: Bool) -> UIImage? {
        return UIImage(asset: .keyFileListitem)
    }
}
