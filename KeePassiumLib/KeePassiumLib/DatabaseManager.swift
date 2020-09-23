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
    static let all: Int64 = 100 // total number of step
    
    static let didReadDatabaseFile: Int64 = -1
    static let didReadKeyFile: Int64 = -1
    static let willDecryptDatabase: Int64 = 0
    static let didDecryptDatabase: Int64 = 100

    static let willMakeBackup: Int64 = -1
    static let willEncryptDatabase: Int64 = 0
    static let didEncryptDatabase: Int64 = 90
    static let didWriteDatabase: Int64 = 100
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
    public func startLoadingDatabase(database dbRef: URLReference, compositeKey: CompositeKey) {
        Diag.verbose("Will queue load database")
        /// compositeKey might be erased when we leave this block.
        /// So keep a local copy.
        let compositeKeyClone = compositeKey.clone()
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
            completion: databaseLoaderFinished)
        databaseLoader!.load()
    }
    
    // dbDoc is `nil` in case of error
    private func databaseLoaderFinished(_ dbRef: URLReference, _ dbDoc: DatabaseDocument?) {
        self.databaseRef = dbRef
        self.databaseDocument = dbDoc
        self.databaseLoader = nil
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
        notifyDatabaseWillSave(database: dbRef)
        
        precondition(databaseSaver == nil)
        databaseSaver = DatabaseSaver(
            databaseDocument: dbDoc,
            databaseRef: dbRef,
            progress: progress,
            completion: databaseSaverFinished)
        databaseSaver!.save()
    }
    
    private func databaseSaverFinished(_ urlRef: URLReference, _ dbDoc: DatabaseDocument) {
        databaseSaver = nil
        // nothing else to do here
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
        let dataReadyHandler = { (keyFileData: ByteArray) -> Void in
            let passwordData = keyHelper.getPasswordData(password: password)
            if passwordData.isEmpty && keyFileData.isEmpty {
                Diag.error("Password and key file are both empty")
                errorHandler(LString.Error.passwordAndKeyFileAreBothEmpty)
                return
            }
            let staticComponents = keyHelper.combineComponents(
                passwordData: passwordData, // might be empty, but not nil
                keyFileData: keyFileData    // might be empty, but not nil
            )
            let compositeKey = CompositeKey(
                staticComponents: staticComponents,
                challengeHandler: challengeHandler)
            Diag.debug("New composite key created successfully")
            successHandler(compositeKey)
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
                        errorHandler(LString.Error.failedToOpenKeyFile)
                    }
                }
            case .failure(let accessError):
                Diag.error("Failed to open key file [error: \(accessError.localizedDescription)]")
                errorHandler(LString.Error.failedToOpenKeyFile)
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
    
    fileprivate static func shouldUpdateLatestBackup(for dbRef: URLReference) -> Bool {
        // Update latest backup only for actual user DBs,
        // ignore temporary and internal files
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

    fileprivate func notifyDatabaseWillLoad(database urlRef: URLReference) {
        notificationQueue.async { // strong self
            for (_, observer) in self.observers {
                guard let strongObserver = observer.observer else { continue }
                DispatchQueue.main.async {
                    strongObserver.databaseManager(willLoadDatabase: urlRef)
                }
            }
        }
    }
    
    fileprivate func notifyDatabaseDidLoad(
        database urlRef: URLReference,
        warnings: DatabaseLoadingWarnings)
    {
        notificationQueue.async { // strong self
            for (_, observer) in self.observers {
                guard let strongObserver = observer.observer else { continue }
                DispatchQueue.main.async {
                    strongObserver.databaseManager(didLoadDatabase: urlRef, warnings: warnings)
                }
            }
        }
    }
    
    fileprivate func notifyOperationCancelled(database urlRef: URLReference) {
        notificationQueue.async { // strong self
            for (_, observer) in self.observers {
                guard let strongObserver = observer.observer else { continue }
                DispatchQueue.main.async {
                    strongObserver.databaseManager(database: urlRef, isCancelled: true)
                }
            }
        }
    }

    fileprivate func notifyProgressDidChange(database urlRef: URLReference, progress: ProgressEx) {
        notificationQueue.async { // strong self
            for (_, observer) in self.observers {
                guard let strongObserver = observer.observer else { continue }
                DispatchQueue.main.async {
                    strongObserver.databaseManager(progressDidChange: progress)
                }
            }
        }
    }

    
    fileprivate func notifyDatabaseLoadError(
        database urlRef: URLReference,
        isCancelled: Bool,
        message: String,
        reason: String?)
    {
        if isCancelled {
            notifyOperationCancelled(database: urlRef)
            return
        }
        
        notificationQueue.async { // strong self
            for (_, observer) in self.observers {
                guard let strongObserver = observer.observer else { continue }
                DispatchQueue.main.async {
                    strongObserver.databaseManager(
                        database: urlRef,
                        loadingError: message,
                        reason: reason)
                }
            }
        }
    }
    
    fileprivate func notifyDatabaseInvalidMasterKey(database urlRef: URLReference, message: String) {
        notificationQueue.async { // strong self
            for (_, observer) in self.observers {
                guard let strongObserver = observer.observer else { continue }
                DispatchQueue.main.async {
                    strongObserver.databaseManager(database: urlRef, invalidMasterKey: message)
                }
            }
        }
    }
    
    fileprivate func notifyDatabaseWillSave(database urlRef: URLReference) {
        notificationQueue.async { // strong self
            for (_, observer) in self.observers {
                guard let strongObserver = observer.observer else { continue }
                DispatchQueue.main.async {
                    strongObserver.databaseManager(willSaveDatabase: urlRef)
                }
            }
        }
    }
    
    fileprivate func notifyDatabaseDidSave(database urlRef: URLReference) {
        notificationQueue.async { // strong self
            for (_, observer) in self.observers {
                guard let strongObserver = observer.observer else { continue }
                DispatchQueue.main.async {
                    strongObserver.databaseManager(didSaveDatabase: urlRef)
                }
            }
        }
    }
    
    fileprivate func notifyDatabaseSaveError(
        database urlRef: URLReference,
        isCancelled: Bool,
        message: String,
        reason: String?)
    {
        if isCancelled {
            notifyOperationCancelled(database: urlRef)
            return
        }

        notificationQueue.async { // strong self
            for (_, observer) in self.observers {
                guard let strongObserver = observer.observer else { continue }
                DispatchQueue.main.async {
                    strongObserver.databaseManager(
                        database: urlRef,
                        savingError: message,
                        reason: reason)
                }
            }
        }
    }

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

// MARK: - Progress observer

/// Helper class to keep track of Progress KVO notifications.
fileprivate class ProgressObserver {
    internal let progress: ProgressEx
    private var progressFractionKVO: NSKeyValueObservation?
    private var progressDescriptionKVO: NSKeyValueObservation?
    
    init(progress: ProgressEx) {
        self.progress = progress
    }
    
    func startObservingProgress() {
        assert(progressFractionKVO == nil && progressDescriptionKVO == nil)
        progressFractionKVO = progress.observe(
            \.fractionCompleted,
            options: [.new],
            changeHandler: {
                [weak self] (progress, _) in
                self?.progressDidChange(progress: progress)
            }
        )
        progressDescriptionKVO = progress.observe(
            \.localizedDescription,
            options: [.new],
            changeHandler: {
                [weak self] (progress, _) in
                self?.progressDidChange(progress: progress)
            }
        )
    }
    
    func stopObservingProgress() {
        assert(progressFractionKVO != nil && progressDescriptionKVO != nil)
        progressFractionKVO?.invalidate()
        progressDescriptionKVO?.invalidate()
        progressFractionKVO = nil
        progressDescriptionKVO = nil
    }
    
    func progressDidChange(progress: ProgressEx) {
        assertionFailure("Override this")
    }
}

// MARK: - DatabaseLoader

fileprivate class DatabaseLoader: ProgressObserver {
    typealias CompletionHandler = (URLReference, DatabaseDocument?) -> Void
    
    private let dbRef: URLReference
    private let compositeKey: CompositeKey
    private unowned var notifier: DatabaseManager
    /// Warning messages related to DB loading, that should be shown to the user.
    private let warnings: DatabaseLoadingWarnings
    private let completion: CompletionHandler
    
    /// `completion` is always called once done, even if there was an error.
    init(
        dbRef: URLReference,
        compositeKey: CompositeKey,
        progress: ProgressEx,
        completion: @escaping(CompletionHandler))
    {
        assert(compositeKey.state != .empty)
        self.dbRef = dbRef
        self.compositeKey = compositeKey
        self.completion = completion
        self.warnings = DatabaseLoadingWarnings()
        self.notifier = DatabaseManager.shared
        super.init(progress: progress)
    }

    private func initDatabase(signature data: ByteArray) -> Database? {
        if Database1.isSignatureMatches(data: data) {
            Diag.info("DB signature: KPv1")
            return Database1()
        } else if Database2.isSignatureMatches(data: data) {
            Diag.info("DB signature: KPv2")
            return Database2()
        } else {
            Diag.info("DB signature: no match")
            return nil
        }
    }
    
    // MARK: - Running in background
    
    private var backgroundTask: UIBackgroundTaskIdentifier?
    private func startBackgroundTask() {
        // App extensions don't have UIApplication instance and cannot manage background tasks.
        guard let appShared = AppGroup.applicationShared else { return }
        
        print("Starting background task")
        backgroundTask = appShared.beginBackgroundTask(withName: "DatabaseLoading") {
            Diag.warning("Background task expired, loading cancelled")
            self.progress.cancel()
            self.endBackgroundTask()
        }
        startTime = Date.now
    }
    
    private func endBackgroundTask() {
        // App extensions don't have UIApplication instance and cannot manage background tasks.
        guard let appShared = AppGroup.applicationShared else { return }
        if let startTime = startTime {
            let duration = Date.now.timeIntervalSince(startTime)
            print(String(format: "Done in %.2f s", arguments: [duration]))
        }
        
        guard let bgTask = backgroundTask else { return }
        print("ending background task")
        backgroundTask = nil
        appShared.endBackgroundTask(bgTask)
    }
    
    // MARK: - Progress tracking
    
    override func progressDidChange(progress: ProgressEx) {
        notifier.notifyProgressDidChange(
            database: dbRef,
            progress: progress)
    }
    
    // MARK: - Loading and decryption
    
    func load() {
        startBackgroundTask()
        startObservingProgress()
        notifier.notifyDatabaseWillLoad(database: dbRef)
        progress.status = LString.Progress.contactingStorageProvider
        dbRef.resolveAsync { result in // strong self
            switch result {
            case .success(let dbURL):
                self.onDatabaseURLResolved(url: dbURL, fileProvider: self.dbRef.fileProvider)
            case .failure(let accessError):
                self.onDatabaseURLResolveError(accessError)
            }
        }
    }

    private func onDatabaseURLResolveError(_ error: FileAccessError) {
        Diag.error("Failed to resolve database URL reference [error: \(error.localizedDescription)]")
        stopObservingProgress()
        notifier.notifyDatabaseLoadError(
            database: dbRef,
            isCancelled: progress.isCancelled,
            message: LString.Error.cannotFindDatabaseFile,
            reason: error.localizedDescription)
        completion(dbRef, nil)
        endBackgroundTask()
    }
    
    private func onDatabaseURLResolved(url: URL, fileProvider: FileProvider?) {
        let dbDoc = DatabaseDocument(fileURL: url, fileProvider: fileProvider)
        progress.status = LString.Progress.loadingDatabaseFile
        dbDoc.open { [weak self] (result) in
            guard let self = self else { return }
            switch result {
            case .success(let docData):
                self.onDatabaseDocumentOpened(dbDoc: dbDoc, data: docData)
            case .failure(let fileAccessError):
                Diag.error("Failed to open database document [error: \(fileAccessError.localizedDescription)]")
                self.stopObservingProgress()
                self.notifier.notifyDatabaseLoadError(
                    database: self.dbRef,
                    isCancelled: self.progress.isCancelled,
                    message: LString.Error.cannotOpenDatabaseFile,
                    reason: fileAccessError.localizedDescription)
                self.completion(self.dbRef, nil)
                self.endBackgroundTask()
            }
        }
    }
    
    private func onDatabaseDocumentOpened(dbDoc: DatabaseDocument, data: ByteArray) {
        progress.completedUnitCount = ProgressSteps.didReadDatabaseFile
        
        // Create DB instance of appropriate version
        guard let db = initDatabase(signature: data) else {
            let hexPrefix = data.prefix(8).asHexString
            Diag.error("Unrecognized database format [firstBytes: \(hexPrefix)]")
            if hexPrefix == "7b226572726f7222" {
                // additional diagnostics for DS file error
                let fullResponse = String(data: data.asData, encoding: .utf8) ?? "nil"
                Diag.debug("Full error content for DS file: \(fullResponse)")
            }
            stopObservingProgress()
            notifier.notifyDatabaseLoadError(
                database: dbRef,
                isCancelled: progress.isCancelled,
                message: LString.Error.unrecognizedDatabaseFormat,
                reason: nil)
            completion(dbRef, nil)
            endBackgroundTask()
            return
        }
        
        dbDoc.database = db
        guard compositeKey.state == .rawComponents else {
            // No need to load the key file, it's already been processed
            
            // Shortcut: we already have the composite key, so skip password/key file processing
            progress.completedUnitCount = ProgressSteps.didReadKeyFile
            Diag.info("Using a ready composite key")
            onCompositeKeyComponentsProcessed(dbDoc: dbDoc, compositeKey: compositeKey)
            return
        }
        
        // OK, so the key is in rawComponents state, let's load the key file
        guard let keyFileRef = compositeKey.keyFileRef else {
            // no key file, continue with empty data
            onKeyFileDataReady(dbDoc: dbDoc, keyFileData: ByteArray())
            return
        }
        
        Diag.debug("Loading key file")
        progress.localizedDescription = LString.Progress.loadingKeyFile
        keyFileRef.resolveAsync { result in // strong self
            switch result {
            case .success(let keyFileURL):
                self.onKeyFileURLResolved(
                    url: keyFileURL,
                    fileProvider: keyFileRef.fileProvider,
                    dbDoc: dbDoc)
            case .failure(let accessError):
                self.onKeyFileURLResolveError(accessError)
            }
        }
    }
    
    private func onKeyFileURLResolveError(_ error: FileAccessError) {
        Diag.error("Failed to resolve key file URL reference [error: \(error.localizedDescription)]")
        stopObservingProgress()
        notifier.notifyDatabaseLoadError(
            database: dbRef,
            isCancelled: progress.isCancelled,
            message: LString.Error.cannotFindKeyFile,
            reason: error.localizedDescription)
        completion(dbRef, nil)
        endBackgroundTask()
    }

    private func onKeyFileURLResolved(url: URL, fileProvider: FileProvider?, dbDoc: DatabaseDocument) {
        let keyDoc = BaseDocument(fileURL: url, fileProvider: fileProvider)
        keyDoc.open { [weak self] result in
            guard let self = self else { return }
            switch result {
            case .success(let docData):
                self.onKeyFileDataReady(dbDoc: dbDoc, keyFileData: docData)
            case .failure(let fileAccessError):
                Diag.error("Failed to open key file [error: \(fileAccessError.localizedDescription)]")
                self.stopObservingProgress()
                self.notifier.notifyDatabaseLoadError(
                    database: self.dbRef,
                    isCancelled: self.progress.isCancelled,
                    message: LString.Error.cannotOpenKeyFile,
                    reason: fileAccessError.localizedDescription)
                self.completion(self.dbRef, nil)
                self.endBackgroundTask()
            }
        }
    }
    
    private func onKeyFileDataReady(dbDoc: DatabaseDocument, keyFileData: ByteArray) {
        guard let database = dbDoc.database else { fatalError() }
        
        progress.completedUnitCount = ProgressSteps.didReadKeyFile
        let keyHelper = database.keyHelper
        let passwordData = keyHelper.getPasswordData(password: compositeKey.password)
        if passwordData.isEmpty && keyFileData.isEmpty {
            Diag.error("Both password and key file are empty")
            stopObservingProgress()
            notifier.notifyDatabaseInvalidMasterKey(
                database: dbRef,
                message: LString.Error.needPasswordOrKeyFile)
            completion(dbRef, nil)
            endBackgroundTask()
            return
        }
        compositeKey.setProcessedComponents(passwordData: passwordData, keyFileData: keyFileData)
        onCompositeKeyComponentsProcessed(dbDoc: dbDoc, compositeKey: compositeKey)
    }
        
    func onCompositeKeyComponentsProcessed(dbDoc: DatabaseDocument, compositeKey: CompositeKey) {
        assert(compositeKey.state >= .processedComponents)
        guard let db = dbDoc.database else { fatalError() }
        
        progress.completedUnitCount = ProgressSteps.willDecryptDatabase
        let remainingUnitCount = ProgressSteps.didDecryptDatabase - ProgressSteps.willDecryptDatabase
        do {
            progress.addChild(db.initProgress(), withPendingUnitCount: remainingUnitCount)
            Diag.info("Loading database")
            try db.load(
                dbFileName: dbDoc.fileURL.lastPathComponent,
                dbFileData: dbDoc.data,
                compositeKey: compositeKey,
                warnings: warnings)
                // throws DatabaseError, ProgressInterruption
            Diag.info("Database loaded OK")
            
            let shouldUpdateBackup = Settings.current.isBackupDatabaseOnLoad
                    && DatabaseManager.shouldUpdateLatestBackup(for: dbRef)
            if shouldUpdateBackup {
                Diag.debug("Updating latest backup")
                progress.status = LString.Progress.makingDatabaseBackup
                // At this stage, the DB should have a resolved URL
                assert(dbRef.url != nil)
                FileKeeper.shared.makeBackup(
                    nameTemplate: dbRef.url?.lastPathComponent ?? "Backup",
                    mode: .latest,
                    contents: dbDoc.data)
            }
            
            progress.completedUnitCount = ProgressSteps.all
            progress.localizedDescription = LString.Progress.done
            completion(dbRef, dbDoc)
            stopObservingProgress()
            notifier.notifyDatabaseDidLoad(database: dbRef, warnings: warnings)
            endBackgroundTask()
            
        } catch let error as DatabaseError {
            // first, clean up
            dbDoc.database = nil
            dbDoc.close(completionHandler: nil)
            // now, notify everybody
            switch error {
            case .loadError:
                Diag.error("""
                        Database load error. [
                            isCancelled: \(progress.isCancelled),
                            message: \(error.localizedDescription),
                            reason: \(String(describing: error.failureReason))]
                    """)
                stopObservingProgress()
                notifier.notifyDatabaseLoadError(
                    database: dbRef,
                    isCancelled: progress.isCancelled,
                    message: error.localizedDescription,
                    reason: error.failureReason)
            case .invalidKey:
                Diag.error("Invalid master key. [message: \(error.localizedDescription)]")
                stopObservingProgress()
                notifier.notifyDatabaseInvalidMasterKey(
                    database: dbRef,
                    message: error.localizedDescription)
            case .saveError:
                Diag.error("saveError while loading?!")
                fatalError("Database saving error while loading?!")
            }
            completion(dbRef, nil)
            endBackgroundTask()
        } catch let error as ProgressInterruption {
            dbDoc.database = nil
            dbDoc.close(completionHandler: nil)
            switch error {
            case .cancelled(let reason):
                Diag.info("Database loading was cancelled. [reason: \(reason.localizedDescription)]")
                stopObservingProgress()
                switch reason {
                case .userRequest:
                    notifier.notifyDatabaseLoadError(
                        database: dbRef,
                        isCancelled: true,
                        message: error.localizedDescription,
                        reason: error.failureReason)
                case .lowMemoryWarning:
                    // this is treated like an error, not really a cancellation
                    notifier.notifyDatabaseLoadError(
                        database: dbRef,
                        isCancelled: false,
                        message: error.localizedDescription,
                        reason: nil)
                }
                completion(dbRef, nil)
                endBackgroundTask()
            }
        } catch {
            // should not happen, but just in case
            assertionFailure("Unprocessed exception")
            dbDoc.database = nil
            dbDoc.close(completionHandler: nil)
            Diag.error("Unexpected error [message: \(error.localizedDescription)]")
            stopObservingProgress()
            notifier.notifyDatabaseLoadError(
                database: dbRef,
                isCancelled: progress.isCancelled,
                message: error.localizedDescription,
                reason: nil)
            completion(dbRef, nil)
            endBackgroundTask()
        }
    }
}

// MARK: - DatabaseSaver

fileprivate class DatabaseSaver: ProgressObserver {
    typealias CompletionHandler = (URLReference, DatabaseDocument) -> Void
    
    private let dbDoc: DatabaseDocument
    private let dbRef: URLReference
    private var progressKVO: NSKeyValueObservation?
    private unowned var notifier: DatabaseManager
    private let completion: CompletionHandler

    /// `dbRef` refers to the existing URL of the currently opened `dbDoc`.
    /// `completion` is always called once done, even if there was an error.
    init(
        databaseDocument dbDoc: DatabaseDocument,
        databaseRef dbRef: URLReference,
        progress: ProgressEx,
        completion: @escaping(CompletionHandler))
    {
        assert(dbDoc.documentState.contains(.normal))
        self.dbDoc = dbDoc
        self.dbRef = dbRef
        notifier = DatabaseManager.shared
        self.completion = completion
        super.init(progress: progress)
    }
    
    // MARK: - Running in background
    
    private var backgroundTask: UIBackgroundTaskIdentifier?
    private func startBackgroundTask() {
        // App extensions don't have UIApplication instance and cannot manage background tasks.
        guard let appShared = AppGroup.applicationShared else { return }
        
        print("Starting background task")
        backgroundTask = appShared.beginBackgroundTask(withName: "DatabaseSaving") {
            self.progress.cancel()
            self.endBackgroundTask()
        }
    }
    
    private func endBackgroundTask() {
        // App extensions don't have UIApplication instance and cannot manage background tasks.
        guard let appShared = AppGroup.applicationShared else { return }
        
        guard let bgTask = backgroundTask else { return }
        backgroundTask = nil
        appShared.endBackgroundTask(bgTask)
    }
    
    // MARK: - Progress tracking
    
    override func progressDidChange(progress: ProgressEx) {
        notifier.notifyProgressDidChange(
            database: dbRef,
            progress: progress)
    }
    
    // MARK: - Encryption and saving
    
    func save() {
        guard let database = dbDoc.database else { fatalError("Database is nil") }

        startBackgroundTask()
        startObservingProgress()
        do {
            if Settings.current.isBackupDatabaseOnSave {
                // dbDoc has already been opened, so we backup its old encrypted data.
                progress.completedUnitCount = ProgressSteps.willMakeBackup
                progress.status = LString.Progress.makingDatabaseBackup
                
                // At this stage, the DB should have a resolved URL
                assert(dbRef.url != nil)
                let nameTemplate = dbRef.url?.lastPathComponent ?? "Backup"
                FileKeeper.shared.makeBackup(
                    nameTemplate: nameTemplate,
                    mode: .timestamped,
                    contents: dbDoc.data)
            }

            Diag.info("Encrypting database")
            progress.completedUnitCount = ProgressSteps.willEncryptDatabase
            let encryptionUnitCount = ProgressSteps.didEncryptDatabase - ProgressSteps.willEncryptDatabase
            progress.addChild(
                database.initProgress(),
                withPendingUnitCount: encryptionUnitCount)
            let outData = try database.save() // DatabaseError, ProgressInterruption
            progress.completedUnitCount = ProgressSteps.didEncryptDatabase
            
            Diag.info("Writing database document")
            dbDoc.data = outData
            dbDoc.save { [self] result in // strong self
                switch result {
                case .success:
                    self.progress.status = LString.Progress.done
                    self.progress.completedUnitCount = ProgressSteps.didWriteDatabase
                    Diag.info("Database saved OK")
                    self.updateLatestBackup(with: outData)
                    self.stopObservingProgress()
                    self.notifier.notifyDatabaseDidSave(database: self.dbRef)
                    self.completion(self.dbRef, self.dbDoc)
                    self.endBackgroundTask()
                case .failure(let fileAccessError):
                    Diag.error("Database saving error. [message: \(fileAccessError.localizedDescription)]")
                    self.stopObservingProgress()
                    self.notifier.notifyDatabaseSaveError(
                        database: self.dbRef,
                        isCancelled: self.progress.isCancelled,
                        message: fileAccessError.localizedDescription,
                        reason: nil)
                    self.completion(self.dbRef, self.dbDoc)
                    self.endBackgroundTask()
                }
            }
        } catch let error as DatabaseError {
            Diag.error("""
                Database saving error. [
                    isCancelled: \(progress.isCancelled),
                    message: \(error.localizedDescription),
                    reason: \(String(describing: error.failureReason))]
                """)
            stopObservingProgress()
            notifier.notifyDatabaseSaveError(
                database: dbRef,
                isCancelled: progress.isCancelled,
                message: error.localizedDescription,
                reason: error.failureReason)
            completion(dbRef, dbDoc)
            endBackgroundTask()
        } catch let error as ProgressInterruption {
            stopObservingProgress()
            switch error {
            case .cancelled(let reason):
                Diag.error("Database saving was cancelled. [reason: \(reason.localizedDescription)]")
                switch reason {
                case .userRequest:
                    notifier.notifyDatabaseSaveError(
                        database: dbRef,
                        isCancelled: true,
                        message: error.localizedDescription,
                        reason: nil)
                case .lowMemoryWarning:
                    // this is treated like an error, not a simple cancellation
                    notifier.notifyDatabaseSaveError(
                        database: dbRef,
                        isCancelled: false,
                        message: error.localizedDescription,
                        reason: nil)
                }
                completion(dbRef, dbDoc)
                endBackgroundTask()
            }
        } catch { // file writing errors
            Diag.error("Database saving error. [isCancelled: \(progress.isCancelled), message: \(error.localizedDescription)]")
            stopObservingProgress()
            notifier.notifyDatabaseSaveError(
                database: dbRef,
                isCancelled: progress.isCancelled,
                message: error.localizedDescription,
                reason: nil)
            completion(dbRef, dbDoc)
            endBackgroundTask()
        }
    }
    
    /// Updates the -latest backup with the new data.
    private func updateLatestBackup(with data: ByteArray) {
        guard Settings.current.isBackupDatabaseOnSave,
            DatabaseManager.shouldUpdateLatestBackup(for: dbRef) else
        {
            return
        }
        
        Diag.debug("Updating latest backup")
        progress.status = LString.Progress.makingDatabaseBackup
        
        assert(dbRef.url != nil)
        let nameTemplate = dbRef.url?.lastPathComponent ?? "Backup"
        FileKeeper.shared.makeBackup(
            nameTemplate: nameTemplate,
            mode: .latest,
            contents: data)
    }
}
