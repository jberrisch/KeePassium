//  KeePassium Password Manager
//  Copyright © 2018–2019 Andrei Popleteev <info@keepassium.com>
// 
//  This program is free software: you can redistribute it and/or modify it
//  under the terms of the GNU General Public License version 3 as published
//  by the Free Software Foundation: https://www.gnu.org/licenses/).
//  For commercial licensing, please contact the author.

import UIKit

enum DatabaseLockReason {
    case userRequest
    case timeout
}

fileprivate enum ProgressSteps {
    static let start: Int64 = -1 // initial progress of evey operation (negative means indefinite)
    static let all: Int64 = 100 // total number of steps

}


public class DatabaseManager {
    public static let shared = DatabaseManager()

    /// Loading/saving progress.
    /// Valid only during loading or saving process (between databaseWillLoad(Save),
    /// and until databaseDidLoad(Save)/databaseLoad/SaveError, inclusive).
    public var progress = ProgressEx()
    
    public private(set) var databaseRef: URLReference?
    public var database: Database? { return databaseDocument?.database }

    /// Indicates whether there is an open database
    public var isDatabaseOpen: Bool { return database != nil }
    
    private var databaseDocument: DatabaseDocument?
    private var databaseLoader: DatabaseLoader?
    private var databaseSaver: DatabaseSaver?
    
    private var serialDispatchQueue = DispatchQueue(
        label: "com.keepassium.DatabaseManager",
        qos: .userInitiated)
    
    public init() {
        // left empty
    }

    
    // MARK: - Database management routines
    
    /// Schedules to close database when any ongoing saving is finished.
    /// Asynchronous call, returns immediately.
    ///
    /// - Parameters:
    ///   - clearStoredKey: whether to remove the database key stored in keychain (if any)
    ///   - ignoreErrors: force-close ignoring any errors
    ///   - callback: called after closing the database. `error` parameter is nil in case of success.
    public func closeDatabase(
        clearStoredKey: Bool,
        ignoreErrors: Bool,
        completion callback: ((FileAccessError?) -> Void)?)
    {
        guard database != nil else {
            callback?(nil)
            return
        }
        Diag.verbose("Will queue close database")

        // Clear the key synchronously, otherwise auto-unlock might be racing with the closing.
        if clearStoredKey, let urlRef = databaseRef {
            DatabaseSettingsManager.shared.updateSettings(for: urlRef) { (dbSettings) in
                dbSettings.clearMasterKey()
                Diag.verbose("Master key cleared")
            }
        }

        serialDispatchQueue.async {
            guard let dbDoc = self.databaseDocument else {
                DispatchQueue.main.async {
                    callback?(nil)
                }
                return
            }
            Diag.debug("Will close database")
            
            let completionSemaphore = DispatchSemaphore(value: 0)
            
            // UIDocument.close() callbacks use the same queue as the .close() itself.
            // So we switch to the main queue, while the serialDispatchQueue awaits
            // for the completion.
            DispatchQueue.main.async {
                dbDoc.close { [self] result in // strong self
                    switch result {
                    case .success:
                        self.handleDatabaseClosing()
                        callback?(nil)
                        completionSemaphore.signal()
                    case .failure(let fileAccessError):
                        Diag.error("Failed to close database document [message: \(fileAccessError.localizedDescription)]")
                        if ignoreErrors {
                            Diag.warning("Ignoring errors and closing anyway")
                            self.handleDatabaseClosing()
                            callback?(nil) // pretend there's no error
                        } else {
                            callback?(fileAccessError)
                        }
                        completionSemaphore.signal()
                    }
                }
            }
            // Block the serial queue until the document is done closing.
            // Otherwise the user might try to re-open the DB before it is properly saved.
            completionSemaphore.wait()
        }
    }
    
    private func handleDatabaseClosing() {
        guard let dbRef = self.databaseRef else { assertionFailure(); return }
        
        self.notifyDatabaseWillClose(database: dbRef)
        self.databaseDocument = nil
        self.databaseRef = nil
        self.notifyDatabaseDidClose(database: dbRef)
        Diag.info("Database closed")
    }

    /// Tries to load a database and unlock it with given password/key file.
    /// Returns immediately, works asynchronously. Progress and results are sent as notifications.
    public func startLoadingDatabase(
        database dbRef: URLReference,
        password: String,
        keyFile keyFileRef: URLReference?,
        challengeHandler: ChallengeHandler?)
    {
        Diag.verbose("Will queue load database")
        let compositeKey = CompositeKey(
            password: password,
            keyFileRef: keyFileRef,
            challengeHandler: challengeHandler
        )
        serialDispatchQueue.async {
            self._loadDatabase(dbRef: dbRef, compositeKey: compositeKey)
        }
    }
    
    /// Tries to load database and unlock it with the given composite key
    /// (as opposed to password/keyfile pair).
    /// Returns immediately, works asynchronously.
    public func startLoadingDatabase(
        database dbRef: URLReference,
        compositeKey: CompositeKey,
        canUseFinalKey: Bool)
    {
        Diag.verbose("Will queue load database")
        
        /// compositeKey might be erased when we leave this block.
        /// So keep a local copy.
        let compositeKeyClone = compositeKey.clone()
        if !canUseFinalKey {
            compositeKeyClone.eraseFinalKeys()
        }
        serialDispatchQueue.async {
            self._loadDatabase(dbRef: dbRef, compositeKey: compositeKeyClone)
        }
    }
    
    private func _loadDatabase(dbRef: URLReference, compositeKey: CompositeKey) {
        precondition(database == nil, "Can only load one database at a time")

        Diag.info("Will load database")
        progress = ProgressEx()
        progress.totalUnitCount = ProgressSteps.all
        progress.completedUnitCount = ProgressSteps.start
        
        precondition(databaseLoader == nil)
        databaseLoader = DatabaseLoader(
            dbRef: dbRef,
            compositeKey: compositeKey,
            progress: progress,
            delegate: self)
        databaseLoader!.load()
    }

    /// Stores current database's key in keychain.
    ///
    /// - Parameter onlyIfExists:
    ///     If `true`, the method will only update an already stored key
    ///     (and do nothing if there is none).
    ///     If `false`, the method will set/update the key in any case.
    /// - Throws: KeychainError
    public func rememberDatabaseKey(onlyIfExists: Bool = false) throws {
        guard let databaseRef = databaseRef, let database = database else { return }
        let dsm = DatabaseSettingsManager.shared
        let dbSettings = dsm.getOrMakeSettings(for: databaseRef)
        if onlyIfExists && !dbSettings.hasMasterKey {
            return
        }
        
        Diag.info("Saving database key in keychain.")
        dbSettings.setMasterKey(database.compositeKey)
        dsm.setSettings(dbSettings, for: databaseRef)
    }
    
    /// Save previously opened database to its original path.
    /// Asynchronous call, returns immediately.
    public func startSavingDatabase() {
        guard let databaseDocument = databaseDocument, let dbRef = databaseRef else {
            Diag.warning("Tried to save database before opening one.")
            assertionFailure("Tried to save database before opening one.")
            return
        }
        serialDispatchQueue.async {
            self._saveDatabase(databaseDocument, dbRef: dbRef)
            Diag.info("Async database saving finished")
        }
    }
    
    private func _saveDatabase(
        _ dbDoc: DatabaseDocument,
        dbRef: URLReference)
    {
        precondition(database != nil, "No database to save")
        Diag.info("Saving database")
        
        progress = ProgressEx()
        progress.totalUnitCount = ProgressSteps.all
        progress.completedUnitCount = ProgressSteps.start
        
        precondition(databaseSaver == nil)
        databaseSaver = DatabaseSaver(
            databaseDocument: dbDoc,
            databaseRef: dbRef,
            progress: progress,
            delegate: self)
        databaseSaver!.save()
    }
    
    
    /// Changes the composite key of the current database.
    /// Make sure to call `startSavingDatabase` after that.
    public func changeCompositeKey(to newKey: CompositeKey) {
        database?.changeCompositeKey(to: newKey)
        Diag.info("Database composite key changed")
    }
    
    /// Creates a new composite key based on `password` and `keyFile` contents.
    /// Runs asyncronously, returns immediately.
    /// Key processing details depend on the provided `keyHelper`.
    public static func createCompositeKey(
        keyHelper: KeyHelper,
        password: String,
        keyFile keyFileRef: URLReference?,
        challengeHandler: ChallengeHandler?,
        success successHandler: @escaping((_ compositeKey: CompositeKey) -> Void),
        error errorHandler: @escaping((_ errorMessage: String) -> Void))
    {
        let mainQueueSuccessHandler: (_ compositeKey: CompositeKey)->Void = { (compositeKey) in
            DispatchQueue.main.async {
                successHandler(compositeKey)
            }
        }
        let mainQueueErrorHandler: (_ errorMessage: String)->Void = { (errorMessage) in
            DispatchQueue.main.async {
                errorHandler(errorMessage)
            }
        }
        
        let dataReadyHandler = { (keyFileData: ByteArray) -> Void in
            let passwordData = keyHelper.getPasswordData(password: password)
            if passwordData.isEmpty && keyFileData.isEmpty && challengeHandler == nil {
                Diag.error("Password and key file are both empty")
                mainQueueErrorHandler(LString.Error.passwordAndKeyFileAreBothEmpty)
                return
            }
            do {
                let staticComponents = try keyHelper.combineComponents(
                    passwordData: passwordData, // might be empty, but not nil
                    keyFileData: keyFileData    // might be empty, but not nil
                ) // throws KeyFileError
                let compositeKey = CompositeKey(
                    staticComponents: staticComponents,
                    challengeHandler: challengeHandler)
                Diag.debug("New composite key created successfully")
                mainQueueSuccessHandler(compositeKey)
            } catch let error as KeyFileError {
                Diag.error("Key file error [reason: \(error.localizedDescription)]")
                mainQueueErrorHandler(error.localizedDescription)
            } catch {
                let message = "Caught unrecognized exception" // unlikely to happen, don't localize
                assertionFailure(message)
                Diag.error(message)
                mainQueueErrorHandler(message)
            }
        }
        
        guard let keyFileRef = keyFileRef else {
            dataReadyHandler(ByteArray())
            return
        }
        
        // Got a key file, load it
        keyFileRef.resolveAsync { result in // no self
            switch result {
            case .success(let keyFileURL):
                let keyDoc = BaseDocument(fileURL: keyFileURL, fileProvider: keyFileRef.fileProvider)
                keyDoc.open { result in
                    switch result {
                    case .success(let keyFileData):
                        dataReadyHandler(keyFileData)
                    case .failure(let fileAccessError):
                        Diag.error("Failed to open key file [error: \(fileAccessError.localizedDescription)]")
                        mainQueueErrorHandler(LString.Error.failedToOpenKeyFile)
                    }
                }
            case .failure(let accessError):
                Diag.error("Failed to open key file [error: \(accessError.localizedDescription)]")
                mainQueueErrorHandler(LString.Error.failedToOpenKeyFile)
            }
        }
    }
    
    /// Creates an in-memory kp2v4 database with given master key,
    /// pre-populates it using `template` callback.
    /// The caller is responsible for calling `startSavingDatabase`.
    ///
    /// - Parameters:
    ///   - databaseURL: URL to a target file for the database; `DatabaseManager.databaseRef` will be based on this value in case of success.
    ///   - password: DB password; can be empty if `keyFile` is given.
    ///   - keyFile: DB key file reference; can be `nil` is `password` is given.
    ///   - templateSetupHandler: callback to populate the database with sample items;
    ///         has DB's root group as parameter.
    ///   - successHandler: called after successful setup of the database
    ///   - errorHandler: called in case of error; with error message as parameter
    public func createDatabase(
        databaseURL: URL,
        password: String,
        keyFile: URLReference?,
        challengeHandler: ChallengeHandler?,
        template templateSetupHandler: @escaping (Group2) -> Void,
        success successHandler: @escaping () -> Void,
        error errorHandler: @escaping ((String?) -> Void))
    {
        assert(database == nil)
        assert(databaseDocument == nil)
        let db2 = Database2.makeNewV4()
        guard let root2 = db2.root as? Group2 else { fatalError() }
        templateSetupHandler(root2)

        self.databaseDocument = DatabaseDocument(fileURL: databaseURL, fileProvider: nil)
        self.databaseDocument!.database = db2
        DatabaseManager.createCompositeKey(
            keyHelper: db2.keyHelper,
            password: password,
            keyFile: keyFile,
            challengeHandler: challengeHandler,
            success: { // strong self
                (newCompositeKey) in
                DatabaseManager.shared.changeCompositeKey(to: newCompositeKey)
                
                // we don't have dedicated location for temporary files,
                // so set it to generic `.internalInbox`
                do {
                    self.databaseRef = try URLReference(from: databaseURL, location: .internalInbox)
                        // throws some internal system error
                    successHandler()
                } catch {
                    Diag.error("Failed to create reference to temporary DB file [message: \(error.localizedDescription)]")
                    errorHandler(error.localizedDescription)
                }
            },
            error: { // strong self
                (message) in
                assert(self.databaseRef == nil)
                // cleanup failed DB document
                self.abortDatabaseCreation()
                Diag.error("Error creating composite key for a new database [message: \(message)]")
                errorHandler(message)
            }
        )
    }

    /// Cleans up DatabaseManager state after a cancelled or failed
    /// createDatabase() call.
    public func abortDatabaseCreation() {
        assert(self.databaseDocument != nil)
        self.databaseDocument?.database = nil
        self.databaseDocument = nil
        self.databaseRef = nil

    }
    
    /// Returns `true` for actual user DBs that should be backed up.
    /// Returns `false` for temporary and internal files that should _not_ be backed up.
    internal static func shouldUpdateLatestBackup(for dbRef: URLReference) -> Bool {
        switch dbRef.location {
        case .external, .internalDocuments:
            return true
        case .internalBackup, .internalInbox:
            return false
        }
    }
    
    // MARK: - Observer management
    
    fileprivate struct WeakObserver {
        weak var observer: DatabaseManagerObserver?
    }
    private var observers = [ObjectIdentifier: WeakObserver]()
    private var notificationQueue = DispatchQueue(
        label: "com.keepassium.DatabaseManager.notifications",
        qos: .default
    )
    
    public func addObserver(_ observer: DatabaseManagerObserver) {
        let id = ObjectIdentifier(observer)
        notificationQueue.async(flags: .barrier) { // strong self
            self.observers[id] = WeakObserver(observer: observer)
        }
    }
    
    public func removeObserver(_ observer: DatabaseManagerObserver) {
        let id = ObjectIdentifier(observer)
        notificationQueue.async(flags: .barrier) { // strong self
            self.observers.removeValue(forKey: id)
        }
    }

    // MARK: - Notification management
    
    fileprivate func notifyDatabaseWillCreate(database urlRef: URLReference) {
        notificationQueue.async { // strong self
            for (_, observer) in self.observers {
                guard let strongObserver = observer.observer else { continue }
                DispatchQueue.main.async {
                    strongObserver.databaseManager(willCreateDatabase: urlRef)
                }
            }
        }
    }

    fileprivate func notifyDatabaseWillClose(database urlRef: URLReference) {
        notificationQueue.async { // strong self
            for (_, observer) in self.observers {
                guard let strongObserver = observer.observer else { continue }
                DispatchQueue.main.async {
                    strongObserver.databaseManager(willCloseDatabase: urlRef)
                }
            }
        }
    }
    
    fileprivate func notifyDatabaseDidClose(database urlRef: URLReference) {
        notificationQueue.async { // strong self
            for (_, observer) in self.observers {
                guard let strongObserver = observer.observer else { continue }
                DispatchQueue.main.async {
                    strongObserver.databaseManager(didCloseDatabase: urlRef)
                }
            }
        }
    }
}

// Common notification methods for DatabaseLoader and DatabaseSaver
fileprivate extension DatabaseManager {
    func databaseOperationProgressDidChange(
        database dbRef: URLReference,
        progress: ProgressEx)
    {
        notificationQueue.async { // strong self
            for (_, observer) in self.observers {
                guard let strongObserver = observer.observer else { continue }
                DispatchQueue.main.async {
                    strongObserver.databaseManager(progressDidChange: progress)
                }
            }
        }
    }
    
    func databaseOperationCancelled(database dbRef: URLReference) {
        notificationQueue.async { // strong self
            for (_, observer) in self.observers {
                guard let strongObserver = observer.observer else { continue }
                DispatchQueue.main.async {
                    strongObserver.databaseManager(database: dbRef, isCancelled: true)
                }
            }
        }
    }
}

// MARK: - DatabaseLoaderDelegate
extension DatabaseManager: DatabaseLoaderDelegate {
    func databaseLoader(
        _ databaseLoader: DatabaseLoader,
        willLoadDatabase dbRef: URLReference)
    {
        notificationQueue.async { // strong self
            for (_, observer) in self.observers {
                guard let strongObserver = observer.observer else { continue }
                DispatchQueue.main.async {
                    strongObserver.databaseManager(willLoadDatabase: dbRef)
                }
            }
        }
    }
    
    func databaseLoader(
        _ databaseLoader: DatabaseLoader,
        didChangeProgress progress: ProgressEx,
        for dbRef: URLReference)
    {
        databaseOperationProgressDidChange(database: dbRef, progress: progress)
    }
    
    func databaseLoader(_ databaseLoader: DatabaseLoader, didCancelLoading dbRef: URLReference) {
        databaseOperationCancelled(database: dbRef)
    }
    
    func databaseLoader(
        _ databaseLoader: DatabaseLoader,
        didFailLoading dbRef: URLReference,
        withInvalidMasterKeyMessage message: String)
    {
        notificationQueue.async { // strong self
            for (_, observer) in self.observers {
                guard let strongObserver = observer.observer else { continue }
                DispatchQueue.main.async {
                    strongObserver.databaseManager(database: dbRef, invalidMasterKey: message)
                }
            }
        }
    }
    
    func databaseLoader(
        _ databaseLoader: DatabaseLoader,
        didFailLoading dbRef: URLReference,
        message: String,
        reason: String?)
    {
        notificationQueue.async { // strong self
            for (_, observer) in self.observers {
                guard let strongObserver = observer.observer else { continue }
                DispatchQueue.main.async {
                    strongObserver.databaseManager(
                        database: dbRef,
                        loadingError: message,
                        reason: reason)
                }
            }
        }
    }
    
    func databaseLoader(
        _ databaseLoader: DatabaseLoader,
        didLoadDatabase dbRef: URLReference,
        withWarnings warnings: DatabaseLoadingWarnings)
    {
        notificationQueue.async { // strong self
            for (_, observer) in self.observers {
                guard let strongObserver = observer.observer else { continue }
                DispatchQueue.main.async {
                    strongObserver.databaseManager(didLoadDatabase: dbRef, warnings: warnings)
                }
            }
        }
    }
    
    func databaseLoaderDidFinish(
        _ databaseLoader: DatabaseLoader,
        for dbRef: URLReference,
        withResult databaseDocument: DatabaseDocument?)
    {
        // databaseDocument is `nil` in case of error
        self.databaseRef = dbRef
        self.databaseDocument = databaseDocument
        self.databaseLoader = nil
    }
}

// MARK: - DatabaseSaverDelegate
extension DatabaseManager: DatabaseSaverDelegate {
    func databaseSaver(_ databaseSaver: DatabaseSaver, willSaveDatabase dbRef: URLReference) {
        notificationQueue.async { // strong self
            for (_, observer) in self.observers {
                guard let strongObserver = observer.observer else { continue }
                DispatchQueue.main.async {
                    strongObserver.databaseManager(willSaveDatabase: dbRef)
                }
            }
        }
    }
    
    func databaseSaver(
        _ databaseSaver: DatabaseSaver,
        didChangeProgress progress: ProgressEx,
        for dbRef: URLReference)
    {
        databaseOperationProgressDidChange(database: dbRef, progress: progress)
    }
    
    func databaseSaver(_ databaseSaver: DatabaseSaver, didCancelSaving dbRef: URLReference) {
        databaseOperationCancelled(database: dbRef)
    }
    
    func databaseSaver(_ databaseSaver: DatabaseSaver, didSaveDatabase dbRef: URLReference) {
        notificationQueue.async { // strong self
            for (_, observer) in self.observers {
                guard let strongObserver = observer.observer else { continue }
                DispatchQueue.main.async {
                    strongObserver.databaseManager(didSaveDatabase: dbRef)
                }
            }
        }
    }
    
    func databaseSaver(
        _ databaseSaver: DatabaseSaver,
        didFailSaving dbRef: URLReference,
        message: String,
        reason: String?)
    {
        notificationQueue.async { // strong self
            for (_, observer) in self.observers {
                guard let strongObserver = observer.observer else { continue }
                DispatchQueue.main.async {
                    strongObserver.databaseManager(
                        database: dbRef,
                        savingError: message,
                        reason: reason)
                }
            }
        }
    }
    
    func databaseSaverDidFinish(_ databaseSaver: DatabaseSaver, for dbRef: URLReference) {
        self.databaseSaver = nil
        // nothing else to do here
    }
}
