//  KeePassium Password Manager
//  Copyright © 2018–2019 Andrei Popleteev <info@keepassium.com>
//
//  This program is free software: you can redistribute it and/or modify it
//  under the terms of the GNU General Public License version 3 as published
//  by the Free Software Foundation: https://www.gnu.org/licenses/).
//  For commercial licensing, please contact the author.

import KeePassiumLib

protocol ItemMoveCoordinatorDelegate: class {
    func didFinish(_ coordinator: ItemMoveCoordinator)
}

class ItemMoveCoordinator: Coordinator {
    var childCoordinators = [Coordinator]()
    
    public weak var delegate: ItemMoveCoordinatorDelegate?
    
    public let parentViewController: UIViewController
    private weak var database: Database?
    public var itemsToMove = [Weak<DatabaseItem>]()
    
    private let navigationController: UINavigationController
    private var groupPickerVC: GroupPickerVC
    private weak var destinationGroup: Group?
    private var savingProgressOverlay: ProgressOverlay?
    
    init(database: Database, parentViewController: UIViewController) {
        self.database = database
        self.parentViewController = parentViewController

        let groupPicker = GroupPickerVC.instantiateFromStoryboard()
        self.groupPickerVC = groupPicker
        navigationController = UINavigationController(rootViewController: groupPickerVC)
        navigationController.modalPresentationStyle = .pageSheet
        
        navigationController.presentationController?.delegate = groupPicker
        groupPicker.delegate = self
    }
    
    func start() {
        guard let database = database,
            let rootGroup = database.root
            else { return }

        groupPickerVC.rootGroup = rootGroup
        parentViewController.present(navigationController, animated: true) { [weak self] in
            let currentGroup = self?.itemsToMove.first?.value?.parent
            self?.groupPickerVC.expandGroup(currentGroup)
        }

        DatabaseManager.shared.addObserver(self)
    }
    
    func stop() {
        DatabaseManager.shared.removeObserver(self)
        navigationController.dismiss(animated: true) { // strong self
            self.delegate?.didFinish(self)
        }
    }
    
    /// Checks whether the given group can accept all the items to be moved.
    private func isAllowedDestination(_ group: Group) -> Bool {
        guard let database = group.database else { return false }
        
        // Cannot move KP1 entries to the root group
        if let database1 = group.database as? Database1,
            let root1 = database1.root,
            group === root1
        {
            for item in itemsToMove {
                if item.value is Entry1 {
                    return false
                }
            }
        }
        
        // Cannot move a group to itself or its subgroup
        for item in itemsToMove {
            guard let groupToMove = item.value else { continue }
            if groupToMove === group || groupToMove.isAncestor(of: group) {
                return false
            }
        }
        
        // Cannot move the backup group
        let backupGroup = database.getBackupGroup(createIfMissing: false)
        return (group !== backupGroup)
    }
    
    /// Moves all the items to the given destination group.
    private func moveItems(to destinationGroup: Group) {
        for item in itemsToMove {
            if let entry = item.value as? Entry {
                entry.move(to: destinationGroup)
            } else if let group = item.value as? Group {
                group.move(to: destinationGroup)
            } else {
                assertionFailure()
            }
        }
    }
    
    /// Send notifications that source and destination groups have changed.
    private func notifyContentChanged() {
        for item in itemsToMove {
            if let entry = item.value as? Entry, let group = entry.parent {
                EntryChangeNotifications.post(entryDidChange: entry)
                GroupChangeNotifications.post(groupDidChange: group)
            } else if let group = item.value as? Group {
                GroupChangeNotifications.post(groupDidChange: group)
            }
        }
        if let destinationGroup = destinationGroup {
            GroupChangeNotifications.post(groupDidChange: destinationGroup)
        }
    }
}

// MARK: - GroupPickerDelegate
extension ItemMoveCoordinator: GroupPickerDelegate {
    func didPressCancel(in groupPicker: GroupPickerVC) {
        stop()
    }
    
    func shouldSelectGroup(_ group: Group, in groupPicker: GroupPickerVC) -> Bool {
        return isAllowedDestination(group)
    }
    
    func didSelectGroup(_ group: Group, in groupPicker: GroupPickerVC) {
        destinationGroup = group
        moveItems(to: group)
        DatabaseManager.shared.startSavingDatabase()
    }
}

// MARK: - ProgressViewHost
extension ItemMoveCoordinator: ProgressViewHost {
    
    func showSavingProgressView() {
        showProgressView(title: LString.databaseStatusSaving, allowCancelling: false)
    }
    public func showProgressView(title: String, allowCancelling: Bool) {
        assert(savingProgressOverlay == nil)
        savingProgressOverlay = ProgressOverlay.addTo(
            navigationController.view,
            title: title,
            animated: true)
        savingProgressOverlay?.isCancellable = allowCancelling
        if #available(iOS 13, *) {
            // block dismissal while in progress
            navigationController.isModalInPresentation = true
        }
        navigationController.setNavigationBarHidden(true, animated: true)
    }
    
    public func updateProgressView(with progress: ProgressEx) {
        savingProgressOverlay?.update(with: progress)
    }
    
    public func hideProgressView() {
        guard savingProgressOverlay != nil else { return }
        navigationController.setNavigationBarHidden(false, animated: true)
        if #available(iOS 13, *) {
            // block dismissal while in progress
            navigationController.isModalInPresentation = false
        }
        savingProgressOverlay?.dismiss(animated: true) {
            [weak self] (finished) in
            guard let self = self else { return }
            self.savingProgressOverlay?.removeFromSuperview()
            self.savingProgressOverlay = nil
        }
    }
}

// MARK: - DatabaseManagerObserver
extension ItemMoveCoordinator: DatabaseManagerObserver {
    func databaseManager(willSaveDatabase urlRef: URLReference) {
        showSavingProgressView()
    }

    func databaseManager(progressDidChange progress: ProgressEx) {
        updateProgressView(with: progress)
    }

    func databaseManager(didSaveDatabase urlRef: URLReference) {
        hideProgressView()
        notifyContentChanged()
        stop()
    }
    
    func databaseManager(database urlRef: URLReference, isCancelled: Bool) {
        hideProgressView()
        // cancelled by the user, just return to editing
    }

    func databaseManager(
        database urlRef: URLReference,
        savingError message: String,
        reason: String?)
    {
        hideProgressView()

        let errorAlert = UIAlertController(title: message, message: reason, preferredStyle: .alert)
        let showDetailsAction = UIAlertAction(title: LString.actionShowDetails, style: .default) {
            [weak self] _ in
            let diagnosticsViewer = ViewDiagnosticsVC.make()
            self?.navigationController.present(diagnosticsViewer, animated: true, completion: nil)
        }
        let cancelAction = UIAlertAction(
            title: LString.actionDismiss,
            style: .cancel,
            handler: nil)
        errorAlert.addAction(showDetailsAction)
        errorAlert.addAction(cancelAction)
        navigationController.present(errorAlert, animated: true, completion: nil)
        // after that, we'll be back to the group picker
    }
}
