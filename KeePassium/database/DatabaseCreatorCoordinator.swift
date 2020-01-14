//  KeePassium Password Manager
//  Copyright © 2018–2019 Andrei Popleteev <info@keepassium.com>
// 
//  This program is free software: you can redistribute it and/or modify it
//  under the terms of the GNU General Public License version 3 as published
//  by the Free Software Foundation: https://www.gnu.org/licenses/).
//  For commercial licensing, please contact the author.

import UIKit
import KeePassiumLib

protocol DatabaseCreatorCoordinatorDelegate: class {
    func didCreateDatabase(
        in databaseCreatorCoordinator: DatabaseCreatorCoordinator,
        database urlRef: URLReference)
    func didPressCancel(in databaseCreatorCoordinator: DatabaseCreatorCoordinator)
}

class DatabaseCreatorCoordinator: NSObject {
    weak var delegate: DatabaseCreatorCoordinatorDelegate?
    
    private let navigationController: UINavigationController
    private weak var initialTopController: UIViewController?
    private let databaseCreatorVC: DatabaseCreatorVC
    
    init(navigationController: UINavigationController) {
        self.navigationController = navigationController
        self.initialTopController = navigationController.topViewController
        
        databaseCreatorVC = DatabaseCreatorVC.create()
        super.init()

        databaseCreatorVC.delegate = self
    }
    
    func start() {
        navigationController.pushViewController(databaseCreatorVC, animated: true)
    }
    
    // MARK: - Database creation procedure

    /// Step 0. Create an app-local temporary empty file
    ///
    /// - Parameter fileName: name of the file to be created
    /// - Returns: URL of the created file
    /// - Throws: some IO error
    private func createEmptyLocalFile(fileName: String) throws -> URL {
        let fileManager = FileManager()
        let docDir = try fileManager.url(
            for: .documentDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: false
        )
        let tmpDir = try fileManager.url(
            for: .itemReplacementDirectory,
            in: .userDomainMask,
            appropriateFor: docDir,
            create: true
        )
        let tmpFileURL = tmpDir
            .appendingPathComponent(fileName, isDirectory: false)
            .appendingPathExtension(FileType.DatabaseExtensions.kdbx)
        
        do {
            // remove previous leftovers, if any
            try? fileManager.removeItem(at: tmpFileURL)
            try Data().write(to: tmpFileURL, options: []) // throws some IO error
        } catch {
            Diag.error("Failed to create temporary file [message: \(error.localizedDescription)]")
            throw error
        }
        return tmpFileURL
    }
    
    
    /// Step 1: Make in-memory database, point it to a temporary file
    private func instantiateDatabase(fileName: String) {
        let tmpFileURL: URL
        do {
            tmpFileURL = try createEmptyLocalFile(fileName: fileName)
        } catch {
            databaseCreatorVC.setError(message: error.localizedDescription, animated: true)
            return
        }
        
        DatabaseManager.shared.createDatabase(
            databaseURL: tmpFileURL,
            password: databaseCreatorVC.password,
            keyFile: databaseCreatorVC.keyFile,
            challengeHandler: {
                (challenge: SecureByteArray, responseHandler: ResponseHandler) -> Void in
                assertionFailure("Not implemented") // TODO: implement this
            },
            template: { [weak self] (rootGroup2) in
                rootGroup2.name = fileName // override default "/" with a meaningful name
                self?.addTemplateItems(to: rootGroup2)
            },
            success: { [weak self] in
                self?.startSavingDatabase()
            },
            error: { [weak self] (message) in
                self?.databaseCreatorVC.setError(message: message, animated: true)
            }
        )
    }
    
    /// Step 2: Fill in-memory database with sample groups and entries
    private func addTemplateItems(to rootGroup: Group2) {
        let groupGeneral = rootGroup.createGroup()
        groupGeneral.iconID = .folder
        groupGeneral.name = NSLocalizedString(
            "[Database/Create/TemplateGroup/title] General",
            value: "General",
            comment: "Predefined group in a new database")
        
        let groupInternet = rootGroup.createGroup()
        groupInternet.iconID = .globe
        groupInternet.name = NSLocalizedString(
            "[Database/Create/TemplateGroup/title] Internet",
            value: "Internet",
            comment: "Predefined group in a new database")


        let groupEmail = rootGroup.createGroup()
        groupEmail.iconID = .envelopeOpen
        groupEmail.name = NSLocalizedString(
            "[Database/Create/TemplateGroup/title] Email",
            value: "Email",
            comment: "Predefined group in a new database")


        let groupHomebanking = rootGroup.createGroup()
        groupHomebanking.iconID = .currency
        groupHomebanking.name = NSLocalizedString(
            "[Database/Create/TemplateGroup/title] Finance",
            value: "Finance",
            comment: "Predefined group in a new database")

        
        let groupNetwork = rootGroup.createGroup()
        groupNetwork.iconID = .server
        groupNetwork.name = NSLocalizedString(
            "[Database/Create/TemplateGroup/title] Network",
            value: "Network",
            comment: "Predefined group in a new database")


        let groupLinux = rootGroup.createGroup()
        groupLinux.iconID = .apple
        groupLinux.name = NSLocalizedString(
            "[Database/Create/TemplateGroup/title] OS",
            value: "OS",
            comment: "Predefined `Operating system` group in a new database")
        
        let sampleEntry = rootGroup.createEntry()
        sampleEntry.iconID = .key
        sampleEntry.title = NSLocalizedString(
            "[Database/Create/TemplateEntry/title] Sample Entry",
            value: "Sample Entry",
            comment: "Title for a sample entry")
        sampleEntry.userName = NSLocalizedString(
            "[Database/Create/TemplateEntry/userName] john.smith",
            value: "john.smith",
            comment: "User name for a sample entry. Set it to a typical person name for your language ( https://en.wikipedia.org/wiki/List_of_placeholder_names_by_language).")
        sampleEntry.password = NSLocalizedString(
            "[Database/Create/TemplateEntry/password] pa$$word",
            value: "pa$$word",
            comment: "Password for a sample entry. Translation is optional.")
        sampleEntry.url = "https://keepassium.com" // do not localize
        sampleEntry.notes = NSLocalizedString(
            "[Database/Create/TemplateEntry/notes] You can also store some notes, if you like.",
            value: "You can also store some notes, if you like.",
            comment: "Note for a sample entry")
    }
    
    /// Step 3: Save temporary database
    private func startSavingDatabase() {
        DatabaseManager.shared.addObserver(self)
        DatabaseManager.shared.startSavingDatabase(challengeHandler: {
            (challenge: SecureByteArray, responseHandler: ResponseHandler) -> Void in
            assertionFailure("Not implemented") // TODO: implement this
        })
    }
    
    /// Step 4: Show picker to move temporary database to its final location
    private func pickTargetLocation(for tmpDatabaseRef: URLReference) {
        do{
            let tmpUrl = try tmpDatabaseRef.resolve() // throws some UIKit error
            let picker = UIDocumentPickerViewController(url: tmpUrl, in: .exportToService)
            picker.modalPresentationStyle = navigationController.modalPresentationStyle
            picker.delegate = self
            databaseCreatorVC.present(picker, animated: true, completion: nil)
        } catch {
            Diag.error("Failed to resolve temporary DB reference [message: \(error.localizedDescription)]")
            databaseCreatorVC.setError(message: error.localizedDescription, animated: true)
        }
    }
    
    /// Step 5: Save final location in FileKeeper
    private func addCreatedDatabase(at finalURL: URL) {
        let fileKeeper = FileKeeper.shared
        fileKeeper.addFile(
            url: finalURL,
            mode: .openInPlace,
            success: { [weak self] (addedRef) in
                guard let _self = self else { return }
                if let initialTopController = _self.initialTopController {
                    _self.navigationController.popToViewController(initialTopController, animated: true)
                }
                _self.delegate?.didCreateDatabase(in: _self, database: addedRef)
            },
            error: { [weak self] (fileKeeperError) in
                Diag.error("Failed to add created file [mesasge: \(fileKeeperError.localizedDescription)]")
                self?.databaseCreatorVC.setError(
                    message: fileKeeperError.localizedDescription,
                    animated: true
                )
            }
        )
    }
}

// MARK: - DatabaseCreatorDelegate
extension DatabaseCreatorCoordinator: DatabaseCreatorDelegate {
    func didPressCancel(in databaseCreatorVC: DatabaseCreatorVC) {
        if let initialTopController = self.initialTopController {
            navigationController.popToViewController(initialTopController, animated: true)
        }
        delegate?.didPressCancel(in: self)
    }
    
    func didPressContinue(in databaseCreatorVC: DatabaseCreatorVC) {
        instantiateDatabase(fileName: databaseCreatorVC.databaseFileName)
    }
    
    func didPressPickKeyFile(in databaseCreatorVC: DatabaseCreatorVC, popoverSource: UIView) {
        //TODO: switch to unified key file pickerd
        let keyFileChooser = ChooseKeyFileVC.make(popoverSourceView: popoverSource, delegate: self)
        navigationController.present(keyFileChooser, animated: true, completion: nil)
    }
}

// MARK: - KeyFileChooserDelegate
extension DatabaseCreatorCoordinator: KeyFileChooserDelegate {
    func onKeyFileSelected(urlRef: URLReference?) {
        databaseCreatorVC.keyFile = urlRef
        databaseCreatorVC.becomeFirstResponder()
    }
}

// MARK: - DatabaseManagerObserver
extension DatabaseCreatorCoordinator: DatabaseManagerObserver {
    func databaseManager(willSaveDatabase urlRef: URLReference) {
        databaseCreatorVC.showProgressView(
            title: LString.databaseStatusSaving,
            allowCancelling: true)
    }
    
    func databaseManager(progressDidChange progress: ProgressEx) {
        databaseCreatorVC.updateProgressView(with: progress)
    }
    
    func databaseManager(didSaveDatabase urlRef: URLReference) {
        DatabaseManager.shared.removeObserver(self)
        // databaseCreatorVC.hideProgressView() - keep it shown until the whole procedure is finished
        DatabaseManager.shared.closeDatabase(
            clearStoredKey: true,
            ignoreErrors: false,
            completion: { [weak self] (errorMessage) in
                if let errorMessage = errorMessage {
                    // there was a problem closing/saving the DB
                    self?.databaseCreatorVC.hideProgressView()
                    let errorAlert = UIAlertController.make(
                        title: LString.titleError,
                        message: errorMessage,
                        cancelButtonTitle: LString.actionDismiss)
                    self?.navigationController.present(errorAlert, animated: true, completion: nil)
                } else {
                    // all good, choose the saving location
                    DispatchQueue.main.async { [weak self] in
                        // the 100% progress overlay remains shown until the picker has finished
                        self?.pickTargetLocation(for: urlRef)
                    }
                }
            }
        )
    }
    
    func databaseManager(database urlRef: URLReference, isCancelled: Bool) {
        DatabaseManager.shared.removeObserver(self)
        DatabaseManager.shared.abortDatabaseCreation()
        self.databaseCreatorVC.hideProgressView()
    }
    
    func databaseManager(database urlRef: URLReference, savingError message: String, reason: String?) {
        DatabaseManager.shared.removeObserver(self)
        DatabaseManager.shared.abortDatabaseCreation()
        databaseCreatorVC.hideProgressView()
        if let reason = reason {
            databaseCreatorVC.setError(message: "\(message)\n\(reason)", animated: true)
        } else {
            databaseCreatorVC.setError(message: message, animated: true)
        }
    }
}

// MARK: - UIDocumentPickerDelegate
extension DatabaseCreatorCoordinator: UIDocumentPickerDelegate {
    func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
        // Hide the 100% progress overlay
        databaseCreatorVC.hideProgressView()
        
        // cancel overall database creation
        if let initialTopController = self.initialTopController {
            self.navigationController.popToViewController(initialTopController, animated: false)
        }
        self.delegate?.didPressCancel(in: self)
    }
    
    func documentPicker(
        _ controller: UIDocumentPickerViewController,
        didPickDocumentsAt urls: [URL])
    {
        guard let url = urls.first else { return }
        
        // Give the file provider a little time to settle down.
        // In the meanwhile, keep showing the 100% progress overlay.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { // strong self
            self.databaseCreatorVC.hideProgressView()
            self.addCreatedDatabase(at: url)
        }
    }
}
