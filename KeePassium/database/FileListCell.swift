//  KeePassium Password Manager
//  Copyright © 2018–2019 Andrei Popleteev <info@keepassium.com>
// 
//  This program is free software: you can redistribute it and/or modify it
//  under the terms of the GNU General Public License version 3 as published
//  by the Free Software Foundation: https://www.gnu.org/licenses/).
//  For commercial licensing, please contact the author.

import KeePassiumLib

class FileListCellFactory {
    public static func dequeueReusableCell(
        from tableView: UITableView,
        withIdentifier identifier: String,
        for indexPath: IndexPath,
        for fileType: FileType
    ) -> FileListCell {
        let cell = tableView
            .dequeueReusableCell(withIdentifier: identifier, for: indexPath)
            as! FileListCell
        cell.fileType = fileType
        return cell
    }
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
    fileprivate(set) var fileType: FileType!
    
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
        
        if let error = urlRef.error {
            // There's a pre-existing error, it is more important to show than old cached info.
            // For example, if we cached file info and then the file was deleted:
            // the fact "file is missing" is more important than outdated cache info.
            showFileError(error, for: urlRef)
            return
        }
        
        urlRef.getCachedInfo(canFetch: false) { [weak self] result in
            guard let self = self else { return }
            switch result {
            case .success(let fileInfo):
                self.showFileInfo(fileInfo, for: urlRef)
            case .failure:
                self.showFileError(urlRef.error, for: urlRef)
            }
        }
    }
    
    private func showFileInfo(_ fileInfo: FileInfo, for urlRef: URLReference) {
        fileIconView?.image = urlRef.getIcon(fileType: fileType)
        if let modificationDate = fileInfo.modificationDate {
            let dateString = DateFormatter.localizedString(
                from: modificationDate,
                dateStyle: .long,
                timeStyle: .medium)
            fileDetailLabel?.text = dateString
        } else {
            fileDetailLabel?.text = nil
        }
        fileDetailLabel?.textColor = UIColor.auxiliaryText
    }
    
    private func showFileError(_ error: FileAccessError?, for urlRef: URLReference) {
        // The provided error can be .noInfoAvaiable, which is not informative.
        // So check the urlRef's error property instead.
        guard let error = error else {
            // no error, but failed -- probably info refresh is not finished yet
            self.fileDetailLabel?.text = "..."
            self.fileIconView?.image = urlRef.getIcon(fileType: self.fileType)
            return
        }
        self.fileDetailLabel?.text = error.localizedDescription
        self.fileDetailLabel?.textColor = UIColor.errorMessage
        self.fileIconView?.image = urlRef.getIcon(fileType: self.fileType)
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
}
