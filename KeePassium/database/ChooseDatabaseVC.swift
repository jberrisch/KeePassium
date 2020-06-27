//  KeePassium Password Manager
//  Copyright © 2018–2019 Andrei Popleteev <info@keepassium.com>
// 
//  This program is free software: you can redistribute it and/or modify it
//  under the terms of the GNU General Public License version 3 as published
//  by the Free Software Foundation: https://www.gnu.org/licenses/).
//  For commercial licensing, please contact the author.

import UIKit
import KeePassiumLib

// Custom cell class for the "App Lock Setup" cell
class AppLockSetupCell: UITableViewCell {
    var buttonHandler: (() -> Void)?
    @IBAction func didPressButton(_ sender: Any) {
        buttonHandler?()
    }
}

class ChooseDatabaseVC: UITableViewController, DynamicFileList, Refreshable {
    
    private enum CellID: String {
        case fileItem = "FileItemCell"
        case noFiles = "NoFilesCell"
        case appLockSetup = "AppLockSetupCell"
    }
    @IBOutlet weak var addDatabaseBarButton: UIBarButtonItem!
    @IBOutlet weak var sortOrderButton: UIBarButtonItem!
    
    private var _isEnabled = true
    var isEnabled: Bool {
        get { return _isEnabled }
        set {
            _isEnabled = newValue
            let alpha: CGFloat = _isEnabled ? 1.0 : 0.5
            navigationController?.navigationBar.isUserInteractionEnabled = _isEnabled
            navigationController?.navigationBar.alpha = alpha
            tableView.isUserInteractionEnabled = _isEnabled
            tableView.alpha = alpha
            if let toolbarItems = toolbarItems {
                for item in toolbarItems {
                    item.isEnabled = _isEnabled
                }
            }
        }
    }
    
    // available database files (both local and external)
    private var databaseRefs: [URLReference] = []
    
    private weak var databaseUnlocker: UnlockDatabaseVC?
    
    private var fileKeeperNotifications: FileKeeperNotifications!
    private var settingsNotifications: SettingsNotifications!
    
    // handles background refresh of file attributes
    private let fileInfoReloader = FileInfoReloader()
    
    private let premiumUpgradeHelper = PremiumUpgradeHelper()
    
    // Flag to auto-unlock DB on launch only
    private var isJustLaunched = true
    
    // Keeps track of animations while sorting files
    internal var ongoingUpdateAnimations = 0
    
    // MAKE: - VC lifecycle
    override func viewDidLoad() {
        super.viewDidLoad()
        
        splitViewController?.preferredDisplayMode = .allVisible
        
        tableView.delegate = self
        tableView.dataSource = self
        tableView.estimatedRowHeight = 44.0
        tableView.rowHeight = UITableView.automaticDimension
        
        fileKeeperNotifications = FileKeeperNotifications(observer: self)
        settingsNotifications = SettingsNotifications(observer: self)
        
        let refreshControl = UIRefreshControl()
        refreshControl.addTarget(self, action: #selector(refresh), for: .valueChanged)
        self.refreshControl = refreshControl
        
        clearsSelectionOnViewWillAppear = false
        
        let longPressGestureRecognizer = UILongPressGestureRecognizer(
            target: self,
            action: #selector(didLongPressTableView))
        tableView.addGestureRecognizer(longPressGestureRecognizer)
        
        updateDetailView(onlyInTwoPaneMode: false)
    }
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        navigationController?.isToolbarHidden = false
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        guard let splitVC = splitViewController else { fatalError() }
        if !splitVC.isCollapsed {
            navigationItem.backBarButtonItem = UIBarButtonItem(
                title: LString.actionCloseDatabase,
                style: .plain,
                target: nil,
                action: nil
            )
        }
        databaseUnlocker = nil
        if !isJustLaunched {
            updateDetailView(onlyInTwoPaneMode: true)
        }
        isJustLaunched = false
        settingsNotifications.startObserving()
        fileKeeperNotifications.startObserving()
        processPendingFileOperations()
        refresh()
    }

    override func viewDidDisappear(_ animated: Bool) {
        fileKeeperNotifications.stopObserving()
        settingsNotifications.stopObserving()
        super.viewDidDisappear(animated)
    }
    
    /// Ensures the detail VC is synchronized with the master VC.
    func updateDetailView(onlyInTwoPaneMode: Bool) {
        refresh()

        let isTwoPaneMode = !(splitViewController?.isCollapsed ?? true)
        if onlyInTwoPaneMode && !isTwoPaneMode {
            return
        }

        if databaseRefs.isEmpty {
            databaseUnlocker = nil
            // Should show a welcome VC. But first make sure we are not showing one already
            let rootNavVC = splitViewController?.viewControllers.last as? UINavigationController
            let detailNavVC = rootNavVC?.topViewController as? UINavigationController
            let topDetailVC = detailNavVC?.topViewController
            if topDetailVC is WelcomeVC {
                return
            }
            let welcomeVC = WelcomeVC.make(delegate: self)
            let wrapperNavVC = UINavigationController(rootViewController: welcomeVC)
            showDetailViewController(wrapperNavVC, sender: self)
            return
        }

        if let databaseUnlocker = databaseUnlocker {
            // there is an UnlockDatabaseVC in the detail panel
            if !databaseRefs.contains(databaseUnlocker.databaseRef) {
                // and it shows a database which is not in the left list anymore
                tableView.selectRow(at: nil, animated: true, scrollPosition: .none)
                showDetailViewController(PlaceholderVC.make(), sender: self)
                return
            }
        }
        
        let canAutoSelectDatabase = isTwoPaneMode || Settings.current.isAutoUnlockStartupDatabase
        
        guard let startDatabase = Settings.current.startupDatabase,
            let selRow = databaseRefs.index(of: startDatabase),
            canAutoSelectDatabase else
        {
            tableView.selectRow(at: nil, animated: true, scrollPosition: .none)
            return
        }

        let selectIndexPath = IndexPath(row: selRow, section: 0)
        DispatchQueue.main.async { [weak self] in
            self?.tableView.selectRow(at: selectIndexPath, animated: true, scrollPosition: .none)
            self?.didSelectDatabase(urlRef: startDatabase)
        }
    }
    
    // MARK: - Refreshing and sorting

    /// Reloads the list of available DB files
    @objc func refresh() {
        refreshSortOrderButton()
        
        databaseRefs = FileKeeper.shared.getAllReferences(
            fileType: .database,
            includeBackup: Settings.current.isBackupFilesVisible)
        sortFileList()

        fileInfoReloader.getInfo(
            for: databaseRefs,
            update: { [weak self] (ref) in
                guard let self = self else { return }
                self.refreshControl?.endRefreshing()
                self.sortAndAnimateFileInfoUpdate(refs: &self.databaseRefs, in: self.tableView)
            },
            completion: { [weak self] in
                guard let self = self else { return }
                self.refreshControl?.endRefreshing()
                // wait for any ongoing animation to finish, and reload the final data, just in case
                DispatchQueue.main.asyncAfter(deadline: .now() + self.sortingAnimationDuration) {
                    [weak self] in
                    self?.sortFileList()
                }
            }
        )
    }
    
    fileprivate func sortFileList() {
        let fileSortOrder = Settings.current.filesSortOrder
        databaseRefs.sort { return fileSortOrder.compare($0, $1) }
        tableView.reloadData()
    }
    
    private func refreshSortOrderButton() {
        sortOrderButton.image = Settings.current.filesSortOrder.toolbarIcon
    }
    
    func getIndexPath(for fileIndex: Int) -> IndexPath {
        return IndexPath(row: fileIndex, section: 0)
    }
    
    // MARK: -
    private func shouldShowAppLockSetup() -> Bool {
        let settings = Settings.current
        let isDataVulnerable = settings.isRememberDatabaseKey && !settings.isAppLockEnabled
        return isDataVulnerable
    }
    
    // MARK: - Item actions
    
    /// For deletion, the action name depends on where that file is.
    /// This function returns the appropriate title.
    private func getDeleteActionName(for urlRef: URLReference) -> String {
        if urlRef.location == .external || urlRef.hasError {
            return LString.actionRemoveFile
        } else {
            return LString.actionDeleteFile
        }
    }
    
    /// Shows a context menu with actions suitable for the given item.
    private func showActions(for indexPath: IndexPath) {
        let cellType = getCellType(for: indexPath)
        guard cellType == .fileItem else { return }
        
        let urlRef = databaseRefs[indexPath.row]
        let exportAction = UIAlertAction(
            title: LString.actionExport,
            style: .default,
            handler: { [weak self] alertAction in
                self?.didPressExportDatabase(at: indexPath)
            }
        )
        let deleteAction = UIAlertAction(
            title: getDeleteActionName(for: urlRef),
            style: .destructive,
            handler: { [weak self] alertAction in
                self?.didPressDeleteDatabase(at: indexPath)
            }
        )
        let cancelAction = UIAlertAction(title: LString.actionCancel, style: .cancel, handler: nil)
        
        let menu = UIAlertController(title: nil, message: nil, preferredStyle: .actionSheet)
        menu.addAction(exportAction)
        menu.addAction(deleteAction)
        menu.addAction(cancelAction)
        
        let popoverAnchor = PopoverAnchor(tableView: tableView, at: indexPath)
        if let popover = menu.popoverPresentationController {
            popoverAnchor.apply(to: popover)
            popover.permittedArrowDirections = [.left]
        }
        present(menu, animated: true)
    }
    
    
    // MARK: - Action handlers
    
    @IBAction func didPressSortButton(_ sender: Any) {
        let vc = SettingsFileSortingVC.make(popoverFromBar: sender as? UIBarButtonItem)
        present(vc, animated: true, completion: nil)
    }

    @IBAction func didPressSettingsButton(_ sender: Any) {
        let settingsVC = SettingsVC.make(popoverFromBar: sender as? UIBarButtonItem)
        present(settingsVC, animated: true, completion: nil)
    }
    
    @IBAction func didPressHelpButton(_ sender: Any) {
        tableView.selectRow(at: nil, animated: true, scrollPosition: .none)
        let aboutVC = AboutVC.make()
        showDetailViewController(aboutVC, sender: self)
    }
    
    func didPressAppLockSetup() {
        // The user wants to enable App Lock, so we ask for passcode first
        let passcodeInputVC = PasscodeInputVC.instantiateFromStoryboard()
        passcodeInputVC.delegate = self
        passcodeInputVC.mode = .setup
        passcodeInputVC.modalPresentationStyle = .formSheet
        passcodeInputVC.isCancelAllowed = true
        present(passcodeInputVC, animated: true, completion: nil)
    }
    
    @objc func didLongPressTableView(_ gestureRecognizer: UILongPressGestureRecognizer) {
        let point = gestureRecognizer.location(in: tableView)
        guard gestureRecognizer.state == .began,
            let indexPath = tableView.indexPathForRow(at: point),
            tableView(tableView, canEditRowAt: indexPath)
            else { return }
        showActions(for: indexPath)
    }

    @IBAction func didPressAddDatabase(_ sender: Any) {
        let nonBackupDatabaseRefs = databaseRefs.filter { $0.location != .internalBackup }
        if nonBackupDatabaseRefs.count > 0 {
            premiumUpgradeHelper.performActionOrOfferUpgrade(.canUseMultipleDatabases, in: self) {
                [weak self] in
                self?.handleDidPressAddDatabase()
            }
        } else {
            handleDidPressAddDatabase()
        }
    }
    
    private func handleDidPressAddDatabase() {
        let actionSheet = UIAlertController(title: nil, message: nil, preferredStyle: .actionSheet)
        
        actionSheet.addAction(UIAlertAction(title: LString.actionOpenDatabase, style: .default) {
            [weak self] _ in
            self?.didPressOpenDatabase()
        })
        
        actionSheet.addAction(UIAlertAction(title: LString.actionCreateDatabase, style: .default) {
            [weak self] _ in
            self?.didPressCreateDatabase()
        })
        
        actionSheet.addAction(UIAlertAction(
            title: LString.actionCancel,
            style: .cancel,
            handler: nil)
        )
            
        if let popover = actionSheet.popoverPresentationController {
            popover.barButtonItem = addDatabaseBarButton
        }
        present(actionSheet, animated: true, completion: nil)
    }
    
    func didPressOpenDatabase() {
        let picker = UIDocumentPickerViewController(
            documentTypes: FileType.databaseUTIs,
            in: .open)
        picker.delegate = self
        picker.modalPresentationStyle = .pageSheet
        present(picker, animated: true, completion: nil)
    }
    
    var databaseCreatorCoordinator: DatabaseCreatorCoordinator?
    func didPressCreateDatabase() {
        let navVC = UINavigationController()
        navVC.modalPresentationStyle = .formSheet
        
        assert(databaseCreatorCoordinator == nil)
        databaseCreatorCoordinator = DatabaseCreatorCoordinator(navigationController: navVC)
        databaseCreatorCoordinator!.delegate = self
        databaseCreatorCoordinator!.start()
        present(navVC, animated: true)
    }

    func didPressExportDatabase(at indexPath: IndexPath) {
        let urlRef = databaseRefs[indexPath.row]
        let popoverAnchor = PopoverAnchor(tableView: tableView, at: indexPath)
        FileExportHelper.showFileExportSheet(urlRef, at: popoverAnchor, parent: self)
    }
        
    func didPressDeleteDatabase(at indexPath: IndexPath) {
        let urlRef = databaseRefs[indexPath.row]
        if urlRef.hasError {
            // dead reference, just remove it without confirmation
            removeDatabaseFile(urlRef: urlRef)
            return
        }
        
        let message: String
        let destructiveAction: UIAlertAction
        if urlRef.location.isInternal {
            message = LString.confirmDatabaseDeletion
            destructiveAction = UIAlertAction(
                title: LString.actionDeleteFile,
                style: .destructive)
            {
                [unowned self] _ in
                
                // disable auto-open of startup database, which interferes with mass deletions
                Settings.current.startupDatabase = nil
                self.updateDetailView(onlyInTwoPaneMode: true)
                self.deleteDatabaseFile(urlRef: urlRef)
            }
        } else {
            message = LString.confirmDatabaseRemoval
            destructiveAction = UIAlertAction(title: LString.actionRemoveFile, style: .destructive)
            {
                [unowned self] _ in
                // disable auto-open of startup database, which interferes with mass deletions
                Settings.current.startupDatabase = nil
                self.updateDetailView(onlyInTwoPaneMode: true)
                self.removeDatabaseFile(urlRef: urlRef)
            }
        }
        let confirmationAlert = UIAlertController.make(
            title: urlRef.visibleFileName,
            message: message,
            cancelButtonTitle: LString.actionCancel)
        confirmationAlert.addAction(destructiveAction)
        present(confirmationAlert, animated: true, completion: nil)
    }
    
    private func didSelectDatabase(urlRef: URLReference) {
        Settings.current.startupDatabase = urlRef
        if databaseUnlocker != nil {
            databaseUnlocker?.databaseRef = urlRef
            return
        }
        let unlockDatabaseVC = UnlockDatabaseVC.make(databaseRef: urlRef)
        unlockDatabaseVC.isJustLaunched = isJustLaunched // is reset once this VC appears
        showDetailViewController(unlockDatabaseVC, sender: self)
        databaseUnlocker = unlockDatabaseVC
    }

    // MARK: - Removals

    private func deleteDatabaseFile(urlRef: URLReference) {
        if urlRef == Settings.current.startupDatabase {
            Settings.current.startupDatabase = nil
        }

        DatabaseSettingsManager.shared.removeSettings(for: urlRef)
        do {
            try FileKeeper.shared.deleteFile(
                urlRef,
                fileType: .database,
                ignoreErrors: urlRef.hasError)
                // throws `FileKeeperError`
            refresh()
        } catch {
            Diag.error("Failed to delete database file [reason: \(error.localizedDescription)]")
            let errorAlert = UIAlertController.make(
                title: LString.titleError,
                message: error.localizedDescription)
            present(errorAlert, animated: true, completion: nil)
        }
    }
    
    private func removeDatabaseFile(urlRef: URLReference) {
        if urlRef == Settings.current.startupDatabase {
            Settings.current.startupDatabase = nil
        }
        DatabaseSettingsManager.shared.removeSettings(for: urlRef)
        FileKeeper.shared.removeExternalReference(urlRef, fileType: .database)
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
    
    // MARK: - UITableViewDataSource
    
    override func numberOfSections(in tableView: UITableView) -> Int {
        return 1
    }

    func numberOfRows() -> Int {
        let contentCellCount = max(databaseRefs.count, 1)
        if shouldShowAppLockSetup() {
            return contentCellCount + 1
        } else {
            return contentCellCount
        }
    }
    
    private func getCellType(for indexPath: IndexPath) -> CellID {
        if indexPath.row < databaseRefs.count {
            return .fileItem
        }
        if shouldShowAppLockSetup() && indexPath.row == (numberOfRows() - 1) {
            return .appLockSetup
        }
        return .noFiles
    }

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return numberOfRows()
    }

    override func tableView(
        _ tableView: UITableView,
        cellForRowAt indexPath: IndexPath
        ) -> UITableViewCell
    {
        let cellType = getCellType(for: indexPath)
        switch cellType {
        case .noFiles:
            let cell = tableView
                .dequeueReusableCell(withIdentifier: cellType.rawValue, for: indexPath)
            return cell
        case .fileItem:
            let cell = FileListCellFactory.dequeueReusableCell(
                from: tableView,
                withIdentifier: cellType.rawValue,
                for: indexPath,
                for: .database)
            let dbRef = databaseRefs[indexPath.row]
            cell.showInfo(from: dbRef)
            cell.isAnimating = dbRef.isRefreshingInfo
            cell.accessoryTapHandler = { [weak self, indexPath] cell in
                guard let self = self else { return }
                self.tableView(self.tableView, accessoryButtonTappedForRowWith: indexPath)
            }
            return cell
        case .appLockSetup:
            let cell = tableView
                .dequeueReusableCell(withIdentifier: cellType.rawValue, for: indexPath)
                as! AppLockSetupCell
            cell.buttonHandler = { [weak self] in
                self?.didPressAppLockSetup()
            }
            return cell
        }
    }
    
    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        if splitViewController?.isCollapsed ?? false {
            tableView.deselectRow(at: indexPath, animated: true)
        }
        switch getCellType(for: indexPath) {
        case .noFiles:
            break
        case .fileItem:
            let selectedRef = databaseRefs[indexPath.row]
            didSelectDatabase(urlRef: selectedRef)
        case .appLockSetup:
            // we call AppLock setup only when the button is tapped,
            // not the whole cell
            break
        }
    }
    
    override func tableView(
        _ tableView: UITableView,
        accessoryButtonTappedForRowWith indexPath: IndexPath)
    {
        let cellType = getCellType(for: indexPath)
        guard cellType == .fileItem else {
            assertionFailure()
            return
        }
        let urlRef = databaseRefs[indexPath.row]
        let popoverAnchor = PopoverAnchor(tableView: tableView, at: indexPath)
        let databaseInfoVC = FileInfoVC.make(urlRef: urlRef, fileType: .database, at: popoverAnchor)
        databaseInfoVC.canExport = true
        databaseInfoVC.onDismiss = { [weak self, weak databaseInfoVC] in
            self?.refresh()
            databaseInfoVC?.dismiss(animated: true, completion: nil)
        }
        present(databaseInfoVC, animated: true, completion: nil)
    }
    
    override func tableView(_ tableView: UITableView, canEditRowAt indexPath: IndexPath) -> Bool {
        let canEdit = getCellType(for: indexPath) == .fileItem
        return canEdit
    }
    
    override func tableView(
        _ tableView: UITableView,
        editActionsForRowAt indexPath: IndexPath
        ) -> [UITableViewRowAction]?
    {
        guard indexPath.row < databaseRefs.count else {
            return nil
        }
        let shareAction = UITableViewRowAction(
            style: .default,
            title: LString.actionExport)
        {
            [unowned self] (_,_) in
            self.setEditing(false, animated: true)
            self.didPressExportDatabase(at: indexPath)
        }
        shareAction.backgroundColor = UIColor.actionTint
        
        // For deletion, the action name depends on where that file is.
        let urlRef = databaseRefs[indexPath.row]
        let deleteAction = UITableViewRowAction(
            style: .destructive,
            title: getDeleteActionName(for: urlRef))
        {
            [unowned self] (_,_) in
            self.setEditing(false, animated: true)
            self.didPressDeleteDatabase(at: indexPath)
        }
        deleteAction.backgroundColor = UIColor.destructiveTint
        
        return [deleteAction, shareAction]
    }
}

extension ChooseDatabaseVC: SettingsObserver {
    func settingsDidChange(key: Settings.Keys) {
        switch key {
        case .filesSortOrder, .backupFilesVisible:
            refresh()
        case .appLockEnabled, .rememberDatabaseKey:
            // hide/show AppLock setup prompt, animated
            tableView.reloadSections([0], with: .automatic)
        default:
            break
        }
    }
}

extension ChooseDatabaseVC: FileKeeperObserver {
    func fileKeeper(didAddFile urlRef: URLReference, fileType: FileType) {
        guard fileType == .database else { return }
        Settings.current.startupDatabase = urlRef
        updateDetailView(onlyInTwoPaneMode: false)
    }

    func fileKeeper(didRemoveFile urlRef: URLReference, fileType: FileType) {
        guard fileType == .database else { return }
        updateDetailView(onlyInTwoPaneMode: false)
    }

    func fileKeeperHasPendingOperation() {
        if isViewLoaded {
            processPendingFileOperations()
        }
    }
}

extension ChooseDatabaseVC: UIDocumentPickerDelegate {
    func documentPicker(
        _ controller: UIDocumentPickerViewController,
        didPickDocumentsAt urls: [URL])
    {
        guard let url = urls.first else { return }
        guard FileType.isDatabaseFile(url: url) else {
            let fileName = url.lastPathComponent
            let errorMessage = String.localizedStringWithFormat(
                NSLocalizedString(
                    "[Database/Add] Selected file \"%@\" does not look like a database.",
                    value: "Selected file \"%@\" does not look like a database.",
                    comment: "Warning when trying to add a random file as a database. [fileName: String]"),
                fileName)
            let errorAlert = UIAlertController.make(
                title: LString.titleWarning,
                message: errorMessage,
                cancelButtonTitle: LString.actionOK)
            present(errorAlert, animated: true, completion: nil)
            return
        }
        
        switch controller.documentPickerMode {
        case .open:
            FileKeeper.shared.prepareToAddFile(url: url, mode: .openInPlace)
        case .import:
            FileKeeper.shared.prepareToAddFile(url: url, mode: .import)
        default:
            assertionFailure("Unexpected document picker mode")
        }
        processPendingFileOperations()
        navigationController?.popToViewController(self, animated: true) // dismiss eventual WelcomeVC
    }
}

// MARK: - DatabaseCreatorCoordinatorDelegate
extension ChooseDatabaseVC: DatabaseCreatorCoordinatorDelegate {
    func didPressCancel(in databaseCreatorCoordinator: DatabaseCreatorCoordinator) {
        presentedViewController?.dismiss(animated: true) { // strong self
            self.databaseCreatorCoordinator = nil
        }
    }
    
    func didCreateDatabase(
        in databaseCreatorCoordinator: DatabaseCreatorCoordinator,
        database urlRef: URLReference)
    {
        presentedViewController?.dismiss(animated: true) { // strong self
            self.databaseCreatorCoordinator = nil
        }
        navigationController?.popToViewController(self, animated: true) // dismiss eventual WelcomeVC
        Settings.current.startupDatabase = urlRef
        updateDetailView(onlyInTwoPaneMode: false)
    }
}

// MARK: - WelcomeDelegate
extension ChooseDatabaseVC: WelcomeDelegate {
    func didPressCreateDatabase(in welcomeVC: WelcomeVC) {
        didPressCreateDatabase()
    }

    func didPressAddExistingDatabase(in welcomeVC: WelcomeVC) {
        didPressOpenDatabase()
    }
}

// MARK: - PasscodeInputDelegate
extension ChooseDatabaseVC: PasscodeInputDelegate {
    func passcodeInputDidCancel(_ sender: PasscodeInputVC) {
        Settings.current.isAppLockEnabled = false
        sender.dismiss(animated: true, completion: nil)
        tableView.reloadData()
    }
    
    func passcodeInput(_sender: PasscodeInputVC, canAcceptPasscode passcode: String) -> Bool {
        return passcode.count > 0
    }
    
    func passcodeInput(_ sender: PasscodeInputVC, didEnterPasscode passcode: String) {
        sender.dismiss(animated: true) {
            [weak self] in
            do {
                try Keychain.shared.setAppPasscode(passcode)
                let settings = Settings.current
                settings.isAppLockEnabled = true
                // Automatically turn on biometrics for new users
                settings.isBiometricAppLockEnabled = true
                self?.tableView.reloadData()
            } catch {
                Diag.error(error.localizedDescription)
                let alert = UIAlertController.make(
                    title: LString.titleKeychainError,
                    message: error.localizedDescription)
                self?.present(alert, animated: true, completion: nil)
            }
        }
    }
}
