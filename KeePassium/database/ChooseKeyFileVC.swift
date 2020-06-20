//  KeePassium Password Manager
//  Copyright © 2018–2019 Andrei Popleteev <info@keepassium.com>
// 
//  This program is free software: you can redistribute it and/or modify it
//  under the terms of the GNU General Public License version 3 as published
//  by the Free Software Foundation: https://www.gnu.org/licenses/).
//  For commercial licensing, please contact the author.

import UIKit
import KeePassiumLib

protocol KeyFileChooserDelegate: class {
    func onKeyFileSelected(urlRef: URLReference?)
}

class ChooseKeyFileVC: UITableViewController, Refreshable {
    private enum CellID {
        static let passwordOnly = "PasswordOnlyCell"
        static let keyFile = "FileCell"
    }
    
    public weak var delegate: KeyFileChooserDelegate?

    // available key files
    private var urlRefs: [URLReference] = []

    private var fileKeeperNotifications: FileKeeperNotifications!
    
    // handles background refresh of file attributes
    private let fileInfoReloader = FileInfoReloader()

    static func make(
        popoverSourceView: UIView,
        delegate: KeyFileChooserDelegate?) -> UIViewController
    {
        let vc = ChooseKeyFileVC.instantiateFromStoryboard()
        vc.delegate = delegate
        
        // This will be a popup, so embed it into a navigation controller
        // to show a navigation bar on iPhone.
        let navVC = UINavigationController(rootViewController: vc)
        navVC.modalPresentationStyle = .popover
        if let popover = navVC.popoverPresentationController {
            popover.sourceView = popoverSourceView
            popover.sourceRect = popoverSourceView.bounds
            popover.delegate = vc
        }
        return navVC
    }
    
    // MARK: - VC life cycle
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        fileKeeperNotifications = FileKeeperNotifications(observer: self)
        let refreshControl = UIRefreshControl()
        refreshControl.addTarget(self, action: #selector(refresh), for: .valueChanged)
        self.refreshControl = refreshControl
        
        let longPressGestureRecognizer = UILongPressGestureRecognizer(
            target: self,
            action: #selector(didLongPressTableView))
        tableView.addGestureRecognizer(longPressGestureRecognizer)
        
        refresh()
        self.clearsSelectionOnViewWillAppear = true
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        
        // automatic popover height
        tableView.addObserver(self, forKeyPath: "contentSize", options: .new, context: nil)
    }
    
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        fileKeeperNotifications.startObserving()
        if FileKeeper.shared.hasPendingFileOperations {
            processPendingFileOperations()
        }
    }
    
    override func viewWillDisappear(_ animated: Bool) {
        tableView.removeObserver(self, forKeyPath: "contentSize")
        super.viewWillDisappear(animated)
    }
    
    override func viewDidDisappear(_ animated: Bool) {
        fileKeeperNotifications.stopObserving()
        super.viewDidDisappear(animated)
    }

    // MARK: - Refreshing
    
    @objc func refresh() {
        // Key files are non-modifiable, so no backups
        urlRefs = FileKeeper.shared.getAllReferences(fileType: .keyFile, includeBackup: false)
        fileInfoReloader.getInfo(
            for: urlRefs,
            update: { [weak self] (ref) in
                self?.tableView.reloadData()
            },
            completion: { [weak self] in
                self?.sortFileList()
                if let refreshControl = self?.refreshControl, refreshControl.isRefreshing {
                    refreshControl.endRefreshing()
                }
            }
        )
        // animates each row until it updates
        tableView.reloadData()
    }
    
    fileprivate func sortFileList() {
        let fileSortOrder = Settings.current.filesSortOrder
        self.urlRefs.sort { return fileSortOrder.compare($0, $1) }
        tableView.reloadData()
    }
    
    /// Updates popover height depending on table content
    override func observeValue(
        forKeyPath keyPath: String?,
        of object: Any?,
        change: [NSKeyValueChangeKey : Any]?,
        context: UnsafeMutableRawPointer?)
    {
        // adjust popover height to fit table content
        var preferredSize = tableView.contentSize
        if #available(iOS 13, *) {
            // on iOS 13, the table becomes too wide, so we limit it.
            preferredSize.width = 400
        }
        self.preferredContentSize = preferredSize
    }
    
    // MARK: - Action handlers
    
    @IBAction func didPressImportButton(_ sender: Any) {
        importKeyFile()
    }
    
    func didPressDeleteKeyFile(at indexPath: IndexPath) {
        let urlRef = urlRefs[indexPath.row - 1]
        if urlRef.hasError {
            // there is nothing useful in this reference, so delete without confirmation
            deleteKeyFile(urlRef: urlRef)
        } else {
            let confirmDeletionAlert = UIAlertController.make(
                title: urlRef.visibleFileName,
                message: LString.confirmKeyFileDeletion,
                cancelButtonTitle: LString.actionCancel)
            let deleteAction = UIAlertAction(title: LString.actionDelete, style: .destructive)
            {
                [unowned self] _ in
                self.deleteKeyFile(urlRef: urlRef)
            }
            confirmDeletionAlert.addAction(deleteAction)
            present(confirmDeletionAlert, animated: true, completion: nil)
        }
    }
    
    @objc func didLongPressTableView(_ gestureRecognizer: UILongPressGestureRecognizer) {
        let point = gestureRecognizer.location(in: tableView)
        guard gestureRecognizer.state == .began,
            let indexPath = tableView.indexPathForRow(at: point),
            tableView(tableView, canEditRowAt: indexPath) else { return }
        showActions(for: indexPath)
    }
    
    /// Shows a context menu with actions suitable for the given item.
    private func showActions(for indexPath: IndexPath) {
        let fileIndex = indexPath.row - 1
        let urlRef = urlRefs[fileIndex]
        let isInternalFile = urlRef.location.isInternal
        let deleteAction = UIAlertAction(
            title: isInternalFile ? LString.actionDeleteFile : LString.actionRemoveFile,
            style: .destructive,
            handler: { [weak self] _ in
                guard let self = self else { return }
                self.didPressDeleteKeyFile(at: indexPath)
            }
        )
        let cancelAction = UIAlertAction(title: LString.actionCancel, style: .cancel, handler: nil)
        
        let menu = UIAlertController(title: nil, message: nil, preferredStyle: .actionSheet)
        menu.addAction(deleteAction)
        menu.addAction(cancelAction)
        
        let pa = PopoverAnchor(tableView: tableView, at: indexPath)
        if let popover = menu.popoverPresentationController {
            pa.apply(to: popover)
        }
        present(menu, animated: true)
    }
    
    // MARK: - Table view data source
    
    override func numberOfSections(in tableView: UITableView) -> Int {
        return 1
    }
    
    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return 1 + urlRefs.count
    }
    
    override func tableView(
        _ tableView: UITableView,
        cellForRowAt indexPath: IndexPath
        ) -> UITableViewCell
    {
        if indexPath.row == 0 {
            return tableView.dequeueReusableCell(
                withIdentifier: CellID.passwordOnly,
                for: indexPath)
        }
        
        let keyFileRef = urlRefs[indexPath.row - 1]
        let cell = FileListCellFactory.dequeueReusableCell(
            from: tableView,
            withIdentifier: CellID.keyFile,
            for: indexPath,
            for: .keyFile)
        cell.showInfo(from: keyFileRef)
        cell.isAnimating = keyFileRef.isRefreshingInfo
        cell.accessoryTapHandler = { [weak self, indexPath] cell in
            guard let self = self else { return }
            self.tableView(self.tableView, accessoryButtonTappedForRowWith: indexPath)
        }
        return cell
    }
    
    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        let row = indexPath.row
        dismissPopover()
        if row == 0 {
            Diag.debug("Selected No Key File")
            delegate?.onKeyFileSelected(urlRef: nil)
        } else {
            Diag.debug("Selected a key file")
            let selectedRef = urlRefs[row - 1]
            delegate?.onKeyFileSelected(urlRef: selectedRef)
        }
    }
    
    override func tableView(
        _ tableView: UITableView,
        accessoryButtonTappedForRowWith indexPath: IndexPath)
    {
        let urlRef = urlRefs[indexPath.row - 1]
        let popoverAnchor = PopoverAnchor(tableView: tableView, at: indexPath)
        let keyFileInfoVC = FileInfoVC.make(urlRef: urlRef, fileType: .keyFile, at: popoverAnchor)
        keyFileInfoVC.canExport = false
        keyFileInfoVC.onDismiss = {
            keyFileInfoVC.dismiss(animated: true, completion: nil)
        }
        present(keyFileInfoVC, animated: true, completion: nil)
    }
    
    override func tableView(_ tableView: UITableView, canEditRowAt indexPath: IndexPath) -> Bool {
        return indexPath.row > 0
    }
    
    override func tableView(
        _ tableView: UITableView,
        editActionsForRowAt indexPath: IndexPath
        ) -> [UITableViewRowAction]?
    {
        let deleteAction = UITableViewRowAction(
            style: .destructive,
            title: LString.actionDelete)
        {
            [unowned self] _,_ in
            self.setEditing(false, animated: true)
            self.didPressDeleteKeyFile(at: indexPath)
        }
        return [deleteAction]
    }

    // MARK: - File management

    private func importKeyFile() {
        let picker = UIDocumentPickerViewController(documentTypes: FileType.keyFileUTIs, in: .open)
        picker.delegate = self
        picker.modalPresentationStyle = .overFullScreen
        present(picker, animated: true, completion: nil)
    }

    /// Removes given key file from the app.
    private func deleteKeyFile(urlRef: URLReference) {
        do {
            try FileKeeper.shared.deleteFile(
                urlRef,
                fileType: .keyFile,
                ignoreErrors: urlRef.hasError)
            DatabaseSettingsManager.shared.removeAllAssociations(of: urlRef)
            refresh()
        } catch {
            let errorAlert = UIAlertController.make(
                title: LString.titleError,
                message: error.localizedDescription)
            present(errorAlert, animated: true, completion: nil)
        }
    }
}

extension ChooseKeyFileVC: UIPopoverPresentationControllerDelegate {

    func presentationController(
        _ controller: UIPresentationController,
        viewControllerForAdaptivePresentationStyle style: UIModalPresentationStyle
        ) -> UIViewController?
    {
        if style != .popover {
            let navVC = controller.presentedViewController as? UINavigationController
            let cancelButton = UIBarButtonItem(
                barButtonSystemItem: .cancel,
                target: self,
                action: #selector(dismissPopover))
            navVC?.topViewController?.navigationItem.leftBarButtonItem = cancelButton
        }
        return nil // "keep existing"
    }
    
    @objc func dismissPopover() {
        dismiss(animated: true, completion: nil)
    }
}

extension ChooseKeyFileVC: UIDocumentPickerDelegate {
    func documentPicker(
        _ controller: UIDocumentPickerViewController,
        didPickDocumentsAt urls: [URL])
    {
        guard let url = urls.first else { return }
        if FileType.isDatabaseFile(url: url) {
            let alertVC = UIAlertController.make(
                title: LString.titleWarning,
                message: LString.dontUseDatabaseAsKeyFile,
                cancelButtonTitle: LString.actionOK)
            present(alertVC, animated: true, completion: nil)
            return
        }
        
        let fileKeeper = FileKeeper.shared
        fileKeeper.prepareToAddFile(url: url, mode: .import)
        fileKeeper.processPendingOperations(
            success: {
                [weak self] (addedRef) in
                self?.refresh()
            },
            error: {
                [weak self] (error) in
                guard let _self = self else { return }
                let alert = UIAlertController.make(
                    title: LString.titleFileImportError,
                    message: error.localizedDescription)
                _self.present(alert, animated: true, completion: nil)
            }
        )
    }
}

extension ChooseKeyFileVC: FileKeeperObserver {
    func fileKeeper(didAddFile urlRef: URLReference, fileType: FileType) {
        guard fileType == .keyFile else { return }
        refresh()
    }
    
    func fileKeeperHasPendingOperation() {
        processPendingFileOperations()
    }
    
    func fileKeeper(didRemoveFile urlRef: URLReference, fileType: FileType) {
        guard fileType == .keyFile else { return }
        refresh()
    }
    
    /// Adds pending files, if any
    private func processPendingFileOperations() {
        FileKeeper.shared.processPendingOperations(
            success: nil,
            error: {
                [weak self] (error) in
                guard let _self = self else { return }
                let alert = UIAlertController.make(
                    title: LString.titleError,
                    message: error.localizedDescription)
                _self.present(alert, animated: true, completion: nil)
            }
        )
    }
}
