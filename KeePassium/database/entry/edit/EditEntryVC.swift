//  KeePassium Password Manager
//  Copyright © 2018–2019 Andrei Popleteev <info@keepassium.com>
// 
//  This program is free software: you can redistribute it and/or modify it
//  under the terms of the GNU General Public License version 3 as published
//  by the Free Software Foundation: https://www.gnu.org/licenses/).
//  For commercial licensing, please contact the author.

import UIKit
import KeePassiumLib

protocol EditEntryFieldsDelegate: class {
    func entryEditor(entryDidChange entry: Entry)
}

class EditEntryVC: UITableViewController, Refreshable {
    @IBOutlet weak var addFieldButton: UIBarButtonItem!
    
    private weak var entry: Entry? {
        didSet {
            rememberOriginalState()
            addFieldButton.isEnabled = entry?.isSupportsExtraFields ?? false
        }
    }
    private weak var delegate: EditEntryFieldsDelegate?
    private var fields = [EditableField]()
    private var isModified = false {// was anything edited?
        didSet {
            if #available(iOS 13.0, *) {
                isModalInPresentation = isModified
            }
        }
    }
    /// Operation mode of the editor
    public enum Mode {
        case create
        case edit
    }
    private var mode: Mode = .edit
    
    
    /// Return an instance of the entry editor in `create` mode
    static func make(
        createInGroup group: Group,
        popoverSource: UIView?,
        delegate: EditEntryFieldsDelegate?
        ) -> UIViewController
    {
        let newEntry = group.createEntry()
        newEntry.populateStandardFields()
        if group.iconID == Group.defaultIconID || group.iconID == Group.defaultOpenIconID {
            newEntry.iconID = Entry.defaultIconID
        } else {
            newEntry.iconID = group.iconID
        }
        
        if let newEntry2 = newEntry as? Entry2, let group2 = group as? Group2 {
            newEntry2.customIconUUID = group2.customIconUUID
            newEntry2.userName = (group2.database as? Database2)?.defaultUserName ?? ""
        }
        newEntry.title = LString.defaultNewEntryName
        return make(mode: .create, entry: newEntry, popoverSource: popoverSource, delegate: delegate)
    }
    
    /// Return an instance of the entry editor in `edit` mode
    static func make(
        entry: Entry,
        popoverSource: UIView?,
        delegate: EditEntryFieldsDelegate?
        ) -> UIViewController
    {
        return make(mode: .edit, entry: entry, popoverSource: popoverSource, delegate: delegate)
    }

    private static func make(
        mode: Mode,
        entry: Entry,
        popoverSource: UIView?,
        delegate: EditEntryFieldsDelegate?
        ) -> UIViewController
    {
        let editEntryVC = EditEntryVC.instantiateFromStoryboard()
        editEntryVC.mode = mode
        editEntryVC.entry = entry
        guard let database = entry.database else { fatalError() }
        editEntryVC.fields = EditableFieldFactory.makeAll(from: entry, in: database)
        editEntryVC.delegate = delegate

        let navVC = UINavigationController(rootViewController: editEntryVC)
        navVC.modalPresentationStyle = .formSheet
        navVC.presentationController?.delegate = editEntryVC
        if let popover = navVC.popoverPresentationController, let popoverSource = popoverSource {
            popover.sourceView = popoverSource
            popover.sourceRect = popoverSource.bounds
        }
        return navVC
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        tableView.rowHeight = UITableView.automaticDimension
        tableView.estimatedRowHeight = 44.0
        
        entry?.accessed()
        refresh()
        if mode == .create {
            //FIXME: dirty hack with 0.8s delay, could not find a better way
            DispatchQueue.main.asyncAfter(deadline: DispatchTime.now() + 0.8)
            {
                [weak self] in
                let firstRow = IndexPath(row: 0, section: 0)
                let titleCell = self?.tableView.cellForRow(at: firstRow) as? EditEntryTitleCell
                _ = titleCell?.becomeFirstResponder()
            }
        }
    }
    
    // MARK: - Keeping/restoring the original state
    
    private var originalEntry: Entry? // backup clone of the original entry
    
    func rememberOriginalState() {
        guard let entry = entry else { fatalError() }
        if mode == .edit {
            entry.backupState() //FIXME: creates redundant backups if editing is cancelled
        }
        originalEntry = entry.clone(makeNewUUID: false)
    }
    
    func restoreOriginalState() {
        switch mode {
        case .create:
            entry?.deleteWithoutBackup()
        case .edit:
            if let entry = entry, let originalEntry = originalEntry {
                originalEntry.apply(to: entry, makeNewUUID: false)
            }
        }
    }

    // MARK: - Action handlers
    
    @IBAction func onCancelAction(_ sender: Any) {
        if isModified {
            // there are unsaved changes
            let alertController = UIAlertController(
                title: nil,
                message: LString.messageUnsavedChanges,
                preferredStyle: .alert)
            let discardAction = UIAlertAction(title: LString.actionDiscard, style: .destructive)
            {
                [weak self] _ in
                guard let _self = self else { return }
                _self.restoreOriginalState()
                _self.dismiss(animated: true, completion: nil)
            }
            let editAction = UIAlertAction(title: LString.actionEdit, style: .cancel, handler: nil)
            alertController.addAction(editAction)
            alertController.addAction(discardAction)
            present(alertController, animated: true, completion: nil)
        } else {
            if mode == .create {
                // even if not modified, need to remove the temporary entry
                restoreOriginalState()
            }
            dismiss(animated: true, completion: nil)
        }
    }
    
    @IBAction func onSaveAction(_ sender: Any) {
        applyChangesAndSaveDatabase()
    }
    
    // MARK: - Actions
    @IBAction func didPressAddField(_ sender: Any) {
        guard let entry2 = entry as? Entry2 else {
            assertionFailure("Tried to add custom field to an entry which does not support them")
            return
        }
        let newField = entry2.makeEntryField(
            name: LString.defaultNewCustomFieldName,
            value: "",
            isProtected: true)
        entry2.fields.append(newField)
        fields.append(EditableField(field: newField))
        
        let newIndexPath = IndexPath(row: fields.count - 1, section: 0)
        tableView.beginUpdates()
        tableView.insertRows(at: [newIndexPath], with: .fade)
        tableView.endUpdates()
        tableView.scrollToRow(at: newIndexPath, at: .top, animated: false) // if animated is true, insertedCell will be nil
        let insertedCell = tableView.cellForRow(at: newIndexPath)
        insertedCell?.becomeFirstResponder()
        (insertedCell as? EditEntryCustomFieldCell)?.selectNameText()
        
        isModified = true
        revalidate()
    }
    
    /// The user wants to delete a field at `indexPath`
    func didPressDeleteField(at indexPath: IndexPath) {
        guard let entry2 = entry as? Entry2 else {
            assertionFailure("Tried to remove a field from a non-KP2 entry")
            return
        }

        let fieldNumber = indexPath.row
        let editableField = fields[fieldNumber]
        guard let entryField = editableField.field else { return }
        
        entry2.removeField(entryField)
        fields.remove(at: fieldNumber)

        tableView.beginUpdates()
        tableView.deleteRows(at: [indexPath], with: .fade)
        tableView.endUpdates()
        
        isModified = true
        refresh()
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        refresh()
    }
    
    // MARK: - Table view data source

    override func numberOfSections(in tableView: UITableView) -> Int {
        return 1
    }

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return fields.count
    }

    override func tableView(
        _ tableView: UITableView,
        cellForRowAt indexPath: IndexPath
        ) -> UITableViewCell
    {
        guard let entry = entry else { fatalError() }
        
        let fieldNumber = indexPath.row
        let field = fields[fieldNumber]
        if field.internalName == EntryField.title { // title cell
            let cell = tableView.dequeueReusableCell(
                withIdentifier: EditEntryTitleCell.storyboardID,
                for: indexPath)
                as! EditEntryTitleCell
            cell.delegate = self
            cell.icon = UIImage.kpIcon(forEntry: entry)
            cell.field = field
//            field.cell = cell
            return cell
        }
        
        let cell = EditableFieldCellFactory
            .dequeueAndConfigureCell(from: tableView, for: indexPath, field: field)
        cell.delegate = self
        cell.validate() // highlight if invalid
        return cell
    }
    
    override func tableView(_ tableView: UITableView, canEditRowAt indexPath: IndexPath) -> Bool {
        let fieldNumber = indexPath.row
        return !fields[fieldNumber].isFixed
    }
    
    override func tableView(
        _ tableView: UITableView,
        editingStyleForRowAt indexPath: IndexPath
        ) -> UITableViewCell.EditingStyle
    {
        return UITableViewCell.EditingStyle.delete
    }
    
    override func tableView(
        _ tableView: UITableView,
        commit editingStyle: UITableViewCell.EditingStyle,
        forRowAt indexPath: IndexPath)
    {
        if editingStyle == .delete {
            didPressDeleteField(at: indexPath)
        }
    }

    // MARK: - Updating, refreshing
    
    func refresh() {
        guard let entry = entry else { return }
        let category = ItemCategory.get(for: entry)
        fields.sort { category.compare($0.internalName, $1.internalName)}
        revalidate()
        tableView.reloadData()
    }
    
    /// Re-checks validity of all the fields
    func revalidate() {
        var isAllFieldsValid = true
        for field in fields {
            field.isValid = isFieldValid(field: field)
            isAllFieldsValid = isAllFieldsValid && field.isValid
        }
        // update the visible cells
        tableView.visibleCells.forEach {
            ($0 as? EditableFieldCell)?.validate()
        }
        navigationItem.rightBarButtonItem?.isEnabled = isAllFieldsValid
    }
    
    // MARK: - Database saving
    
    func applyChangesAndSaveDatabase() {
        guard let entry = entry else { return }
        entry.modified()
        view.endEditing(true)
        DatabaseManager.shared.addObserver(self)
        DatabaseManager.shared.startSavingDatabase(challengeHandler: {
            (challenge: SecureByteArray, responseHandler: ResponseHandler) -> Void in
            assertionFailure("Not implemented") // TODO: implement this
        })
    }

    private var savingOverlay: ProgressOverlay?
    
    private func showSavingOverlay() {
        navigationController?.setNavigationBarHidden(true, animated: true)
        if #available(iOS 13, *) {
            isModalInPresentation = true // block dismissal while in progress
        }
        savingOverlay = ProgressOverlay.addTo(
            view,
            title: LString.databaseStatusSaving,
            animated: true)
        savingOverlay?.isCancellable = true
    }
    
    private func hideSavingOverlay() {
        guard savingOverlay != nil else { return }
        navigationController?.setNavigationBarHidden(false, animated: true)
        savingOverlay?.dismiss(animated: true)
        {
            [weak self] (finished) in
            guard let _self = self else { return }
            _self.savingOverlay?.removeFromSuperview()
            _self.savingOverlay = nil
        }
    }
}

// validator for entry title
extension EditEntryVC: ValidatingTextFieldDelegate {
    func validatingTextField(_ sender: ValidatingTextField, textDidChange text: String) {
        entry?.title = text
        isModified = true
    }
    
    func validatingTextFieldShouldValidate(_ sender: ValidatingTextField) -> Bool {
        return sender.text?.isNotEmpty ?? false
    }
    
    func validatingTextField(_ sender: ValidatingTextField, validityDidChange isValid: Bool) {
        revalidate()
    }
}

// MARK: - EditableFieldCellDelegate

extension EditEntryVC: EditableFieldCellDelegate {
    func didPressButton(field: EditableField, in cell: EditableFieldCell) {
        if cell is EditEntryTitleCell {
            didPressChangeIcon(in: cell)
        } else if cell is EditEntrySingleLineProtectedCell {
            didPressRandomize(field: field, in: cell)
        } else if field.internalName == EntryField.userName {
            didPressChooseUserName(field: field, in: cell)
        }
    }
    
    func didPressChangeIcon(in cell: EditableFieldCell) {
        showIconChooser()
    }

    func didPressReturn(in cell: EditableFieldCell) {
        onSaveAction(self)
    }

    func didChangeField(field: EditableField, in cell: EditableFieldCell) {
        isModified = true
        revalidate()
    }
    
    func didPressRandomize(field: EditableField, in cell: EditableFieldCell) {
        let vc = PasswordGeneratorVC.make(completion: {
            [weak self] (password) in
            guard let _self = self else { return }
            guard let newValue = password else { return } // user cancelled
            field.value = newValue
            _self.isModified = true
            _self.revalidate()
        })
        navigationController?.pushViewController(vc, animated: true)
    }
    
    func didPressChooseUserName(field: EditableField, in cell: EditableFieldCell) {
        guard let database = entry?.database,
            let userNameCell = cell as? EditEntrySingleLineCell
            else { return }
        
        let textField = userNameCell.textField!
        textField.becomeFirstResponder()
        let handler = { (action: UIAlertAction) in
            self.isModified = true
            field.value = action.title
            userNameCell.textField.text = action.title
            cell.validate()
        }

        let nameChooser = UIAlertController(
            title: LString.fieldUserName,
            message: nil,
            preferredStyle: .actionSheet)
        for userName in UserNameHelper.getUserNameSuggestions(from: database, count: 5) {
            let action = UIAlertAction(title: userName, style: .default, handler: handler)
            nameChooser.addAction(action)
        }
        nameChooser.addAction(
            UIAlertAction(title: LString.actionCancel, style: .cancel, handler: nil))
        
        nameChooser.modalPresentationStyle = .popover
        if let popover = nameChooser.popoverPresentationController {
            popover.sourceView = textField
            popover.sourceRect = textField.bounds
            popover.permittedArrowDirections = [.up, .down]
        }
        self.present(nameChooser, animated: true, completion: nil)
    }
    
    func isFieldValid(field: EditableField) -> Bool {
        if field.internalName == EntryField.title {
            return field.value?.isNotEmpty ?? false
        }
        
        // Names of custom fields must be (1) non-empty and (2) unique
        if field.internalName.isEmpty {
            return false
        }
        
        // unique: met only once
        var sameNameCount = 0
        for f in fields {
            if f.internalName == field.internalName  {
                sameNameCount += 1
            }
        }
        return (sameNameCount == 1)
    }
}

extension EditEntryVC: IconChooserDelegate {
    func showIconChooser() {
        let iconChooser = ChooseIconVC.make(selectedIconID: entry?.iconID, delegate: self)
        navigationController?.pushViewController(iconChooser, animated: true)
    }
    
    func iconChooser(didChooseIcon iconID: IconID?) {
        guard let entry = entry, let iconID = iconID else { return }
        guard iconID != entry.iconID else { return }
        
        entry.iconID = iconID
        isModified = true
        refresh()
    }
}

extension EditEntryVC: DatabaseManagerObserver {
    func databaseManager(willSaveDatabase urlRef: URLReference) {
        showSavingOverlay()
    }
    
    func databaseManager(didSaveDatabase urlRef: URLReference) {
        DatabaseManager.shared.removeObserver(self)
        hideSavingOverlay()
        if let entry = self.entry {
            delegate?.entryEditor(entryDidChange: entry)
            EntryChangeNotifications.post(entryDidChange: entry)
        }
        dismiss(animated: true, completion: nil)
    }
    
    func databaseManager(database urlRef: URLReference, isCancelled: Bool) {
        DatabaseManager.shared.removeObserver(self)
        hideSavingOverlay()
    }
    
    func databaseManager(
        database urlRef: URLReference,
        savingError message: String,
        reason: String?)
    {
        DatabaseManager.shared.removeObserver(self)
        hideSavingOverlay()
        
        let errorAlert = UIAlertController.make(
            title: message,
            message: reason,
            cancelButtonTitle: LString.actionDismiss)
        let showDetailsAction = UIAlertAction(title: LString.actionShowDetails, style: .default)
        {
            [weak self] _ in
            let diagnosticsVC = ViewDiagnosticsVC.make()
            self?.present(diagnosticsVC, animated: true, completion: nil)
        }
        errorAlert.addAction(showDetailsAction)
        present(errorAlert, animated: true, completion: nil)
        // after that, we'll be back to editor
    }
    
    func databaseManager(progressDidChange progress: ProgressEx) {
        savingOverlay?.update(with: progress)
    }
}

extension EditEntryVC: UIAdaptivePresentationControllerDelegate {
    func presentationControllerDidAttemptToDismiss(
        _ presentationController: UIPresentationController)
    {
        guard savingOverlay == nil else {
            // saving in progress, don't interrupt
            return
        }
        // called when the user tried but failed to dismiss.
        onCancelAction(presentationController) // will show an alert about unsaved chages
    }
    
    func presentationControllerDidDismiss(_ presentationController: UIPresentationController) {
        onCancelAction(presentationController) // will clean up
    }
}
