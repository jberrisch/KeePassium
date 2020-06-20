//  KeePassium Password Manager
//  Copyright © 2018–2019 Andrei Popleteev <info@keepassium.com>
// 
//  This program is free software: you can redistribute it and/or modify it
//  under the terms of the GNU General Public License version 3 as published
//  by the Free Software Foundation: https://www.gnu.org/licenses/).
//  For commercial licensing, please contact the author.

import KeePassiumLib

protocol DatabaseChooserDelegate: class {
    /// Called when the user presses "Cancel"
    func databaseChooserShouldCancel(_ sender: DatabaseChooserVC)
    /// Called when the user presses "Add database"
    func databaseChooserShouldAddDatabase(_ sender: DatabaseChooserVC, popoverAnchor: PopoverAnchor)
    /// Called when the user selects a database from the list
    func databaseChooser(_ sender: DatabaseChooserVC, didSelectDatabase urlRef: URLReference)
    /// Called when the user wants to delete a (local) database file from the list
    func databaseChooser(_ sender: DatabaseChooserVC, shouldDeleteDatabase urlRef: URLReference)
    /// Called when the user wants to remove a database (reference) from the list
    func databaseChooser(_ sender: DatabaseChooserVC, shouldRemoveDatabase urlRef: URLReference)
    /// Called when the user requests additional info about a database file
    func databaseChooser(_ sender: DatabaseChooserVC, shouldShowInfoForDatabase urlRef: URLReference)
}

class DatabaseChooserVC: UITableViewController, Refreshable {
    private enum CellID {
        static let fileItem = "FileItemCell"
        static let noFiles = "NoFilesCell"
    }
    
    weak var delegate: DatabaseChooserDelegate?
    
    private(set) var databaseRefs: [URLReference] = []

    // handles background refresh of file attributes
    private let fileInfoReloader = FileInfoReloader()

    override func viewDidLoad() {
        super.viewDidLoad()
        clearsSelectionOnViewWillAppear = true
        
        let refreshControl = UIRefreshControl()
        refreshControl.addTarget(self, action: #selector(refresh), for: .valueChanged)
        self.refreshControl = refreshControl

        let longPressGestureRecognizer = UILongPressGestureRecognizer(
            target: self,
            action: #selector(didLongPressTableView))
        tableView.addGestureRecognizer(longPressGestureRecognizer)
        
        refresh()
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        navigationController?.setToolbarHidden(true, animated: true)
        refresh()
    }
    
    @objc func refresh() {
        if fileInfoReloader.isRefreshing {
            return
        }

        databaseRefs = FileKeeper.shared.getAllReferences(
            fileType: .database,
            includeBackup: Settings.current.isBackupFilesVisible)
        fileInfoReloader.getInfo(
            for: databaseRefs,
            update: { [weak self] (ref, fileInfo) in
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
        databaseRefs.sort { return fileSortOrder.compare($0, $1) }
        tableView.reloadData()
    }
    
    // MARK: - Actions
    
    @IBAction func didPressCancel(_ sender: Any) {
        Watchdog.shared.restart()
        delegate?.databaseChooserShouldCancel(self)
    }
    
    @IBAction func didPressAddDatabase(_ sender: UIBarButtonItem) {
        Watchdog.shared.restart()
        let popoverAnchor = PopoverAnchor(barButtonItem: sender)
        delegate?.databaseChooserShouldAddDatabase(self, popoverAnchor: popoverAnchor)
    }
    
    @objc func didLongPressTableView(_ gestureRecognizer: UILongPressGestureRecognizer) {
        Watchdog.shared.restart()
        let point = gestureRecognizer.location(in: tableView)
        guard gestureRecognizer.state == .began,
            let indexPath = tableView.indexPathForRow(at: point),
            tableView(tableView, canEditRowAt: indexPath) else { return }
        showActions(for: indexPath)
    }
    
    // MARK: - Table view data source

    override func numberOfSections(in tableView: UITableView) -> Int {
        return 1
    }

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        if databaseRefs.isEmpty {
            return 1 // for "nothing here" cell
        } else {
            return databaseRefs.count
        }
    }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {

        guard databaseRefs.count > 0 else {
            let cell = tableView.dequeueReusableCell(withIdentifier: CellID.noFiles, for: indexPath)
            return cell
        }
        
        let cell = FileListCellFactory.dequeueReusableCell(
            from: tableView,
            withIdentifier: CellID.fileItem,
            for: indexPath,
            for: .database)
        let dbRef = databaseRefs[indexPath.row]
        cell.showInfo(from: dbRef)
        cell.isAnimating = !fileInfoReloader.isProcessed(dbRef)
        return cell
    }

    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        guard databaseRefs.count > 0 else { return }
        let dbRef = databaseRefs[indexPath.row]
        delegate?.databaseChooser(self, didSelectDatabase: dbRef)
    }
    
    override func tableView(
        _ tableView: UITableView,
        accessoryButtonTappedForRowWith indexPath: IndexPath)
    {
        Watchdog.shared.restart()
        let urlRef = databaseRefs[indexPath.row]
        delegate?.databaseChooser(self, shouldShowInfoForDatabase: urlRef)
    }
    
    // Override to support conditional editing of the table view.
    override func tableView(_ tableView: UITableView, canEditRowAt indexPath: IndexPath) -> Bool {
        return databaseRefs.count > 0
    }
    
    override func tableView(
        _ tableView: UITableView,
        editActionsForRowAt indexPath: IndexPath
        ) -> [UITableViewRowAction]?
    {
        Watchdog.shared.restart()
        guard databaseRefs.count > 0 else { return nil }
        
        let urlRef = databaseRefs[indexPath.row]
        let isInternalFile = urlRef.location.isInternal
        let deleteAction = UITableViewRowAction(
            style: .destructive,
            title: isInternalFile ? LString.actionDeleteFile : LString.actionRemoveFile)
        {
            [weak self] (_,_) in
            guard let _self = self else { return }
            _self.setEditing(false, animated: true)
            if isInternalFile {
                _self.delegate?.databaseChooser(_self, shouldDeleteDatabase: urlRef)
            } else {
                _self.delegate?.databaseChooser(_self, shouldRemoveDatabase: urlRef)
            }
        }
        deleteAction.backgroundColor = UIColor.destructiveTint
        
        return [deleteAction]
    }
    
    /// Shows a context menu with actions suitable for the given item.
    private func showActions(for indexPath: IndexPath) {
        let urlRef = databaseRefs[indexPath.row]
        let isInternalFile = urlRef.location.isInternal
        let deleteAction = UIAlertAction(
            title: isInternalFile ? LString.actionDeleteFile : LString.actionRemoveFile,
            style: .destructive,
            handler: { [weak self] _ in
                guard let self = self else { return }
                if isInternalFile {
                    self.delegate?.databaseChooser(self, shouldDeleteDatabase: urlRef)
                } else {
                    self.delegate?.databaseChooser(self, shouldRemoveDatabase: urlRef)
                }
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
}
