//  KeePassium Password Manager
//  Copyright © 2018–2019 Andrei Popleteev <info@keepassium.com>
// 
//  This program is free software: you can redistribute it and/or modify it
//  under the terms of the GNU General Public License version 3 as published
//  by the Free Software Foundation: https://www.gnu.org/licenses/).
//  For commercial licensing, please contact the author.

import UIKit

public enum FileKeeperError: LocalizedError {
    case openError(reason: String)
    case importError(reason: String)
    case removalError(reason: String)
    public var errorDescription: String? {
        switch self {
        case .openError(let reason):
            return String.localizedStringWithFormat(
                NSLocalizedString(
                    "[FileKeeper] Failed to open file. Reason: %@",
                    bundle: Bundle.framework,
                    value: "Failed to open file. Reason: %@",
                    comment: "Error message [reason: String]"),
                reason)
        case .importError(let reason):
            return String.localizedStringWithFormat(
                NSLocalizedString(
                    "[FileKeeper] Failed to import file. Reason: %@",
                    bundle: Bundle.framework,
                    value: "Failed to import file. Reason: %@",
                    comment: "Error message [reason: String]"),
                reason)
        case .removalError(let reason):
            return String.localizedStringWithFormat(
                NSLocalizedString(
                    "[FileKeeper] Failed to delete file. Reason: %@",
                    bundle: Bundle.framework,
                    value: "Failed to delete file. Reason: %@",
                    comment: "Error message [reason: String]"),
                reason)
        }
    }
}

public protocol FileKeeperDelegate: class {
    
    /// Called on file import, when there is already a file with the same name.
    /// - Parameters:
    ///   - target: URL of the target/conflicting file
    ///   - handler: will be called once the user confirms the resolution strategy.
    ///              The only parameter is `FileKeeper.ConflictResolution`
    func shouldResolveImportConflict(
        target: URL,
        handler: @escaping (FileKeeper.ConflictResolution) -> Void
    )
}

public class FileKeeper {
    public static let shared = FileKeeper()
    
    public weak var delegate: FileKeeperDelegate?
    
    /// Defines how to handle existing files when importing incoming files.
    public enum ConflictResolution {
        /// Ask the user what to do
        case ask
        /// Abort operation, remove the incoming file.
        case abort
        /// Rename the incoming file to a non-conflicting name.
        case rename
        /// Overwrite the existing file with the incoming one.
        case overwrite
    }

    private enum UserDefaultsKey {
        // Also, since extension cannot resolve URL bookmarks created
        // by the main app, the app and the extension have separate
        // and independent file lists. Therefore, different prefixes.
        static var mainAppPrefix: String {
            if BusinessModel.type == .prepaid {
                return "com.keepassium.pro.recentFiles"
            } else {
                return "com.keepassium.recentFiles"
            }
        }

        static var autoFillExtensionPrefix: String {
            if BusinessModel.type == .prepaid {
                return "com.keepassium.pro.autoFill.recentFiles"
            } else {
                return "com.keepassium.autoFill.recentFiles"
            }
        }
        
        static let internalDatabases = ".internal.databases"
        static let internalKeyFiles = ".internal.keyFiles"
        static let externalDatabases = ".external.databases"
        static let externalKeyFiles = ".external.keyFiles"
    }
    
    private static let documentsDirectoryName = "Documents"
    private static let inboxDirectoryName = "Inbox"
    private static let backupDirectoryName = "Backup"
    
    public enum OpenMode {
        case openInPlace
        case `import`
    }
    
    /// URL to be opened/imported
    private var urlToOpen: URL?
    /// How `urlToOpen` should be treated.
    private var openMode: OpenMode = .openInPlace
    /// Ensures thread safety of delayed file operations
    private var pendingOperationGroup = DispatchGroup()
    
    /// App sandbox Documents folder
    fileprivate let docDirURL: URL
    /// App group's shared Backup folder
    fileprivate let backupDirURL: URL
    /// App sandbox Documents/Inbox folder
    fileprivate let inboxDirURL: URL
    
    fileprivate var referenceCache = ReferenceCache()
    
    // True when there are files to be opened/imported.
    public var hasPendingFileOperations: Bool {
        return urlToOpen != nil
    }

    private init() {
        docDirURL = FileManager.default
            .urls(for: .documentDirectory, in: .userDomainMask)
            .first!  // ok to force-unwrap
            .standardizedFileURL
        inboxDirURL = docDirURL.appendingPathComponent(
            FileKeeper.inboxDirectoryName,
            isDirectory: true)
            .standardizedFileURL

        print("\nDoc dir: \(docDirURL)\n")
        
        // Intitialize (and create if necessary) internal directories.
        guard let sharedContainerURL = FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: AppGroup.id) else { fatalError() }
        backupDirURL = sharedContainerURL.appendingPathComponent(
            FileKeeper.backupDirectoryName,
            isDirectory: true)
            .standardizedFileURL
        do {
            try FileManager.default.createDirectory(
                at: backupDirURL, withIntermediateDirectories: true, attributes: nil)
        } catch {
            Diag.warning("Failed to create backup directory")
            // No further action: postponing the error until the first file writing operation
            // that has UI to show the error to the user.
        }
        
        deleteExpiredBackupFiles()
    }

    /// Returns URL of an internal directory corresponding to given location.
    /// Non-nil value guaranteed only for internal locations; for external ones returns `nil`.
    fileprivate func getDirectory(for location: URLReference.Location) -> URL? {
        switch location {
        case .internalDocuments:
            return docDirURL
        case .internalBackup:
            return backupDirURL
        case .internalInbox:
            return inboxDirURL
        default:
            return nil
        }
    }
    
    /// Returns the location type corresponding to given url.
    /// (Defaults to `.external` when does not match any internal location.)
    public func getLocation(for filePath: URL) -> URLReference.Location {
        let path: String
        if filePath.isDirectory {
            path = filePath.standardizedFileURL.path
        } else {
            path = filePath.standardizedFileURL.deletingLastPathComponent().path
        }
        
        for candidateLocation in URLReference.Location.allInternal {
            guard let dirPath = getDirectory(for: candidateLocation)?.path else {
                assertionFailure()
                continue
            }
            if path == dirPath {
                return candidateLocation
            }
        }
        return .external
    }
    
    private func userDefaultsKey(for fileType: FileType, external isExternal: Bool) -> String {
        let keySuffix: String
        switch fileType {
        case .database:
            if isExternal {
                keySuffix = UserDefaultsKey.externalDatabases
            } else {
                keySuffix = UserDefaultsKey.internalDatabases
            }
        case .keyFile:
            if isExternal {
                keySuffix = UserDefaultsKey.externalKeyFiles
            } else {
                keySuffix = UserDefaultsKey.internalKeyFiles
            }
        }
        if AppGroup.isMainApp {
            return UserDefaultsKey.mainAppPrefix + keySuffix
        } else {
            return UserDefaultsKey.autoFillExtensionPrefix + keySuffix
        }
    }
    
    /// Returns URL references stored in user defaults.
    private func getStoredReferences(
        fileType: FileType,
        forExternalFiles isExternal: Bool
        ) -> [URLReference]
    {
        let key = userDefaultsKey(for: fileType, external: isExternal)
        guard let refsData = UserDefaults.appGroupShared.array(forKey: key) else {
            return []
        }
        var refs: [URLReference] = []
        for data in refsData {
            if let ref = URLReference.deserialize(from: data as! Data) {
                refs.append(ref)
            }
        }
        let result = referenceCache.update(with: refs, fileType: fileType, isExternal: isExternal)
        return result
    }
    
    
    /// Stores given URL references in user defaults.
    private func storeReferences(
        _ refs: [URLReference],
        fileType: FileType,
        forExternalFiles isExternal: Bool)
    {
        let serializedRefs = refs.map{ $0.serialize() }
        let key = userDefaultsKey(for: fileType, external: isExternal)
        UserDefaults.appGroupShared.set(serializedRefs, forKey: key)
    }

    /// Returns the stored reference for the given URL, if such reference exists.
    private func findStoredExternalReferenceFor(url: URL, fileType: FileType) -> URLReference? {
        let storedRefs = getStoredReferences(fileType: fileType, forExternalFiles: true)
        for ref in storedRefs {
            // resolvedURL is too volatile for stable search, so use one of the saved ones
            let storedURL = ref.cachedURL ?? ref.bookmarkedURL
            if storedURL == url {
                return ref
            }
        }
        return nil
    }

    /// For local files in ~/Documents/**/*, removes the file.
    /// - Throws: `FileKeeperError`
    public func deleteFile(_ urlRef: URLReference, fileType: FileType, ignoreErrors: Bool) throws {
        Diag.debug("Will trash local file [fileType: \(fileType)]")
        do {
            let url = try urlRef.resolveSync() // hopefully quick for local files
            try FileManager.default.removeItem(at: url)
            Diag.info("Local file deleted")
            FileKeeperNotifier.notifyFileRemoved(urlRef: urlRef, fileType: fileType)
        } catch {
            if ignoreErrors {
                Diag.debug("Suppressed file deletion error [message: '\(error.localizedDescription)']")
            } else {
                Diag.error("Failed to delete file [message: '\(error.localizedDescription)']")
                throw FileKeeperError.removalError(reason: error.localizedDescription)
            }
        }
    }
    
    /// Removes reference to an external file from user defaults (keeps the file).
    /// If no such reference, still silently returns.
    public func removeExternalReference(_ urlRef: URLReference, fileType: FileType) {
        Diag.debug("Removing URL reference [fileType: \(fileType)]")
        var refs = getStoredReferences(fileType: fileType, forExternalFiles: true)
        if let index = refs.index(of: urlRef) {
            refs.remove(at: index)
            storeReferences(refs, fileType: fileType, forExternalFiles: true)
            FileKeeperNotifier.notifyFileRemoved(urlRef: urlRef, fileType: fileType)
            Diag.info("URL reference removed successfully")
        } else {
            assertionFailure("Tried to delete non-existent reference")
            Diag.warning("Failed to remove URL reference - no such reference")
        }
    }
    
    /// Returns references to both local and external files.
    public func getAllReferences(fileType: FileType, includeBackup: Bool) -> [URLReference] {
        var result: [URLReference] = []
//        result.append(contentsOf:
//            scanLocalDirectory(fileType: fileType, location: .internalDocuments))
        result.append(contentsOf:getStoredReferences(fileType: fileType, forExternalFiles: true))
        if AppGroup.isMainApp {
            let sandboxFileRefs = scanLocalDirectory(docDirURL, fileType: fileType)
            // store app's sandboxed file refs for the app extension
            storeReferences(sandboxFileRefs, fileType: fileType, forExternalFiles: false)
            result.append(contentsOf: sandboxFileRefs)
        } else {
            // App extension has no access to app sandbox,
            // so we use pre-saved references to sandbox contents instead.
            result.append(contentsOf:
                getStoredReferences(fileType: fileType, forExternalFiles: false))
        }

        if includeBackup {
            let backupFileRefs = scanLocalDirectory(backupDirURL, fileType: fileType)
            result.append(contentsOf: backupFileRefs)
        }
        return result
    }
    
    /// Returns all files of the given type in the given directory.
    /// Performs shallow search, does not follow deeper directories.
    func scanLocalDirectory(_ dirURL: URL, fileType: FileType) -> [URLReference] {
        var refs: [URLReference] = []
        let location = getLocation(for: dirURL)
        do {
            let dirContents = try FileManager.default.contentsOfDirectory(
                at: dirURL,
                includingPropertiesForKeys: nil,
                options: [])
            for url in dirContents {
                if !url.isDirectory && FileType(for: url) == fileType {
                    let urlRef = try URLReference(from: url, location: location)
                    refs.append(urlRef)
                }
            }
        } catch {
            Diag.error(error.localizedDescription)
        }
        let cachedRefs = referenceCache.update(with: refs, from: dirURL, fileType: fileType)
        return cachedRefs
    }
    
    /// Adds given file to the file keeper.
    /// (A combination of `prepareToAddFile` and `processPendingOperations`.)
    ///
    /// - Parameters:
    ///   - url: file to add
    ///   - mode: whether to import the file or open in place
    ///   - successHandler: called after the file has been added
    ///   - errorHandler: called in case of error
    public func addFile(
        url: URL,
        mode: OpenMode,
        success successHandler: ((URLReference)->Void)?,
        error errorHandler: ((FileKeeperError)->Void)?)
    {
        prepareToAddFile(url: url, mode: mode, notify: false)
        processPendingOperations(success: successHandler, error: errorHandler)
    }
    
    /// Stores the `url` to be added (opened or imported) as a file at some later point.
    ///
    /// - Parameters:
    ///   - url: URL of the file to add
    ///   - mode: whether to import the file or open in place
    ///   - notify: if true (default), notifies observers about pending file operation
    public func prepareToAddFile(url: URL, mode: OpenMode, notify: Bool=true) {
        Diag.debug("Preparing to add file [mode: \(mode)]")
        let origURL = url
        let actualURL = origURL.resolvingSymlinksInPath()
        print("\n originURL: \(origURL) \n actualURL: \(actualURL) \n")
        self.urlToOpen = origURL
        self.openMode = mode
        if notify {
            FileKeeperNotifier.notifyPendingFileOperation()
        }
    }
    
    /// Performs prepared file operation (see `prepareToAddFile`) asynchronously.
    public func processPendingOperations(
        success successHandler: ((URLReference)->Void)?,
        error errorHandler: ((FileKeeperError)->Void)?)
    {
        pendingOperationGroup.wait()
        pendingOperationGroup.enter()
        defer { pendingOperationGroup.leave() }
        
        guard let sourceURL = urlToOpen else { return }
        urlToOpen = nil

        Diag.debug("Will process pending file operations")

        guard sourceURL.isFileURL else {
            Diag.error("Tried to import a non-file URL: \(sourceURL.redacted)")
            let messageNotAFileURL = NSLocalizedString(
                "[FileKeeper] Not a file URL",
                bundle: Bundle.framework,
                value: "Not a file URL",
                comment: "Error message: tried to import URL which does not point to a file")
            switch openMode {
            case .import:
                let importError = FileKeeperError.importError(reason: messageNotAFileURL)
                errorHandler?(importError)
                return
            case .openInPlace:
                let openError = FileKeeperError.openError(reason: messageNotAFileURL)
                errorHandler?(openError)
                return
            }
        }
        
        // General plan of action:
        // External files:
        //  - Key file: import
        //  - Database: open in place, or import (if shared from external app via Copy to KeePassium)
        // Internal files:
        //    /Inbox: import (key file and database)
        //    /Backup: open in place
        //    /Documents: open in place
        
        let fileType = FileType(for: sourceURL)
        let location = getLocation(for: sourceURL)
        switch location {
        case .external:
            // key file: import, database: open in place
            processExternalFile(
                url: sourceURL,
                fileType: fileType,
                success: successHandler,
                error: errorHandler)
        case .internalDocuments, .internalBackup:
            // we already have the file: open in place
            processInternalFile(
                url: sourceURL,
                fileType: fileType,
                location: location,
                success: successHandler,
                error: errorHandler)
        case .internalInbox:
            processInboxFile(
                url: sourceURL,
                fileType: fileType,
                location: location,
                success: successHandler,
                error: errorHandler)
        }
    }
    
    /// Performs addition of an external file.
    /// Key files are copied to Documents.
    /// Database files are added as URL references.
    private func processExternalFile(
        url sourceURL: URL,
        fileType: FileType,
        success successHandler: ((URLReference) -> Void)?,
        error errorHandler: ((FileKeeperError) -> Void)?)
    {
        switch fileType {
        case .database:
            if let urlRef = findStoredExternalReferenceFor(url: sourceURL, fileType: fileType) {
                Settings.current.startupDatabase = urlRef
                FileKeeperNotifier.notifyFileAdded(urlRef: urlRef, fileType: fileType)
                Diag.info("Added already known external file, deduplicating.")
                successHandler?(urlRef)
                return
            }
            addExternalFileRef(
                url: sourceURL,
                fileType: fileType,
                success: { urlRef in
                    Settings.current.startupDatabase = urlRef
                    FileKeeperNotifier.notifyFileAdded(urlRef: urlRef, fileType: fileType)
                    Diag.info("External database added successfully")
                    successHandler?(urlRef)
                },
                error: errorHandler)
        case .keyFile:
            guard AppGroup.isMainApp else {
                addExternalFileRef(
                    url: sourceURL,
                    fileType: fileType,
                    success: { (urlRef) in
                        FileKeeperNotifier.notifyFileAdded(urlRef: urlRef, fileType: fileType)
                        Diag.info("External key file added successfully")
                        successHandler?(urlRef)
                    },
                    error: errorHandler
                )
                return 
            }
            importFile(
                url: sourceURL,
                fileProvider: nil, // unknown - there is no URLReference yet
                success: { (url) in
                    do {
                        let urlRef = try URLReference(
                            from: url,
                            location: self.getLocation(for: url))
                        FileKeeperNotifier.notifyFileAdded(urlRef: urlRef, fileType: fileType)
                        Diag.info("External key file imported successfully")
                        successHandler?(urlRef)
                    } catch {
                        Diag.error("""
                            Failed to import external file [
                                type: \(fileType),
                                message: \(error.localizedDescription),
                                url: \(sourceURL.redacted)]
                            """)
                        let importError = FileKeeperError.importError(reason: error.localizedDescription)
                        errorHandler?(importError)
                    }
                },
                error: errorHandler
            )
        }
    }
    
    /// Perform import of a file in Documents/Inbox.
    private func processInboxFile(
        url sourceURL: URL,
        fileType: FileType,
        location: URLReference.Location,
        success successHandler: ((URLReference) -> Void)?,
        error errorHandler: ((FileKeeperError) -> Void)?)
    {
        importFile(
            url: sourceURL,
            fileProvider: FileProvider.localStorage,
            success: { url in
                do {
                    let urlRef = try URLReference(from: url, location: location)
                    if fileType == .database {
                        Settings.current.startupDatabase = urlRef
                    }
                    FileKeeperNotifier.notifyFileAdded(urlRef: urlRef, fileType: fileType)
                    Diag.info("Inbox file added successfully [fileType: \(fileType)]")
                    successHandler?(urlRef)
                } catch {
                    Diag.error("Failed to import inbox file [type: \(fileType), message: \(error.localizedDescription)]")
                    let importError = FileKeeperError.importError(reason: error.localizedDescription)
                    errorHandler?(importError)
                }
            },
            error: errorHandler)
    }
    
    
    /// Handles processing request for an internal file.
    /// Does nothing with the file, but pretends as if it has been imported
    /// (notifies, updates startup database, ...)
    private func processInternalFile(
        url sourceURL: URL,
        fileType: FileType,
        location: URLReference.Location,
        success successHandler: ((URLReference) -> Void)?,
        error errorHandler: ((FileKeeperError) -> Void)?)
    {
        do {
            let urlRef = try URLReference(from: sourceURL, location: location)
            if fileType == .database {
                Settings.current.startupDatabase = urlRef
            }
            FileKeeperNotifier.notifyFileAdded(urlRef: urlRef, fileType: fileType)
            Diag.info("Internal file processed successfully [fileType: \(fileType), location: \(location)]")
            successHandler?(urlRef)
        } catch {
            Diag.error("Failed to create URL reference [error: '\(error.localizedDescription)', url: '\(sourceURL.redacted)']")
            let importError = FileKeeperError.openError(reason: error.localizedDescription)
            errorHandler?(importError)
        }
    }
    
    /// Adds external file as a URL reference.
    private func addExternalFileRef(
        url sourceURL: URL,
        fileType: FileType,
        success successHandler: ((URLReference) -> Void)?,
        error errorHandler: ((FileKeeperError) -> Void)?)
    {
        Diag.debug("Will add external file reference")
        
        URLReference.create(for: sourceURL, location: .external) {
            [weak self] result in
            guard let self = self else { return }
            switch result {
            case .success(let newRef):
                var storedRefs = self.getStoredReferences(
                    fileType: fileType,
                    forExternalFiles: true)
                storedRefs.insert(newRef, at: 0)
                self.storeReferences(storedRefs, fileType: fileType, forExternalFiles: true)
                
                Diag.info("External URL reference added OK")
                successHandler?(newRef)
            case .failure(let fileAccessError):
                Diag.error("Failed to create URL reference [error: '\(fileAccessError.localizedDescription)', url: '\(sourceURL.redacted)']")
                let importError = FileKeeperError.openError(reason: fileAccessError.localizedDescription)
                errorHandler?(importError)
            }
        }
    }
    
    // MARK: - File import
    
    /// Given a file (either external or in 'Documents/Inbox'), copes/moves it to 'Documents'.
    private func importFile(
        url sourceURL: URL,
        fileProvider: FileProvider?,
        success successHandler: ((URL) -> Void)?,
        error errorHandler: ((FileKeeperError)->Void)?)
    {
        let fileName = sourceURL.lastPathComponent
        let targetURL = docDirURL.appendingPathComponent(fileName)
        let sourceDirs = sourceURL.deletingLastPathComponent() // without file name
        
        if sourceDirs.path == docDirURL.path {
            Diag.info("Tried to import a file already in Documents, nothing to do")
            successHandler?(sourceURL)
            return
        }
        
        Diag.debug("Will import a file")
        let doc = BaseDocument(fileURL: sourceURL, fileProvider: fileProvider)
        doc.open { [self] result in // strong self
            switch result {
            case .success(let docData):
                self.saveDataWithConflictResolution(
                    docData,
                    to: targetURL,
                    conflictResolution: .ask,
                    success: successHandler,
                    error: errorHandler)
            case .failure(let fileAccessError):
                Diag.error("Failed to import external file [message: \(fileAccessError.localizedDescription)]")
                let importError = FileKeeperError.importError(reason: fileAccessError.localizedDescription)
                errorHandler?(importError)
                self.clearInbox()
            }
        }
    }
    
    /// Saves given data to a local file (in /Documents), handling potential file name conflicts.
    /// - Parameters:
    ///   - data: data to save
    ///   - targetURL: where to save the data
    ///   - conflictResolution: how to handle file name conflicts
    ///   - successHandler: called after successful completion
    ///   - errorHandler: called in case of error (unrelated to conflicts)
    private func saveDataWithConflictResolution(
        _ data: ByteArray,
        to targetURL: URL,
        conflictResolution: FileKeeper.ConflictResolution,
        success successHandler: ((URL) -> Void)?,
        error errorHandler: ((FileKeeperError)->Void)?)
    {
        let hasConflict = FileManager.default.fileExists(atPath: targetURL.path)
        guard hasConflict else {
            // No conflicts to handle, just save
            writeToFile(data, to: targetURL, success: successHandler, error: errorHandler)
            clearInbox()
            return
        }
        
        switch conflictResolution {
        case .ask:
            assert(delegate != nil)
            delegate?.shouldResolveImportConflict(
                target: targetURL,
                handler: { (resolution) in // strong self
                    Diag.info("Conflict resolution: \(resolution)")
                    // call the save func with the user-chosed conflict resolution
                    self.saveDataWithConflictResolution(
                        data,
                        to: targetURL,
                        conflictResolution: resolution,
                        success: successHandler,
                        error: errorHandler)
                }
            )
        case .abort:
            clearInbox()
            // nothing else to do, but the callback should be called
            successHandler?(targetURL)
        case .rename:
            let newURL = makeUniqueFileName(targetURL)
            writeToFile(data, to: newURL, success: successHandler, error: errorHandler)
            clearInbox()
            successHandler?(newURL)
        case .overwrite:
            writeToFile(data, to: targetURL, success: successHandler, error: errorHandler)
            clearInbox()
            successHandler?(targetURL)
        }
    }
    
    
    /// Given a file URL, adds a numbered suffix to the file name
    /// until the name is unique (no such file exists).
    /// - Parameter url: original file URL (e.g. "file://folder/file.dat")
    /// - Returns: a unique file URL (e.g. "file://folder/file (1).dat")
    private func makeUniqueFileName(_ url: URL) -> URL {
        let fileManager = FileManager.default

        let path = url.deletingLastPathComponent()
        let fileNameNoExt = url.deletingPathExtension().lastPathComponent
        let fileExt = url.pathExtension
        
        var fileName = url.lastPathComponent
        var index = 1
        while fileManager.fileExists(atPath: path.appendingPathComponent(fileName).path) {
            fileName = String(format: "%@ (%d).%@", fileNameNoExt, index, fileExt)
            index += 1
        }
        return path.appendingPathComponent(fileName)
    }
    
    private func writeToFile(
        _ bytes: ByteArray,
        to targetURL: URL,
        success successHandler: ((URL) -> Void)?,
        error errorHandler: ((FileKeeperError)->Void)?)
    {
        do {
            try bytes.write(to: targetURL, options: [.atomicWrite])
            Diag.debug("File imported successfully")
            clearInbox()
            successHandler?(targetURL)
        } catch {
            Diag.error("Failed to save external file [message: \(error.localizedDescription)]")
            let importError = FileKeeperError.importError(reason: error.localizedDescription)
            errorHandler?(importError)
        }
    }
    
    /// Removes all files from Documents/Inbox.
    /// Silently ignores any errors.
    private func clearInbox() {
        let fileManager = FileManager()
        let inboxFiles = try? fileManager.contentsOfDirectory(
            at: inboxDirURL,
            includingPropertiesForKeys: nil,
            options: [])
        inboxFiles?.forEach {
            try? fileManager.removeItem(at: $0) // ignoring any errors
        }
    }
    
    // MARK: - Database backup
    
    /// Saves `contents` in a timestamped file in local Documents/Backup folder.
    ///
    /// - Parameters:
    ///     - nameTemplate: template file name (e.g. "filename.ext")
    ///     - contents: bytes to store
    /// - Throws: nothing, any errors are silently ignored.
    func makeBackup(nameTemplate: String, contents: ByteArray) {
        guard !contents.isEmpty else {
            Diag.info("No data to backup.")
            return
        }
        guard let encodedNameTemplate = nameTemplate
            .addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) else { return }
        guard let nameTemplateURL = URL(string: encodedNameTemplate) else { return }
        
        deleteExpiredBackupFiles()
        
        let fileManager = FileManager.default
        do {
            try fileManager.createDirectory(
                at: backupDirURL,
                withIntermediateDirectories: true,
                attributes: nil)

            // We deduct one second from the timestamp to ensure
            // correct timing order of backup vs. original files
            let timestamp = Date.now - 1.0
            let dateFormatter = DateFormatter()
            dateFormatter.dateFormat = "yyyy-MM-dd_HHmmss"
            let timestampStr = dateFormatter.string(from: timestamp)

            let baseFileName = nameTemplateURL
                .deletingPathExtension()
                .absoluteString
                .removingPercentEncoding  // should be OK, but if failed - fallback to
                ?? nameTemplate           // original template, even with extension
            let baseFileExt = nameTemplateURL.pathExtension
            let backupFileURL = backupDirURL
                .appendingPathComponent(baseFileName + "_" + timestampStr, isDirectory: false)
                .appendingPathExtension(baseFileExt)
            try contents.asData.write(to: backupFileURL, options: .atomic)
            
            // set file timestamps
            try fileManager.setAttributes(
                [FileAttributeKey.creationDate: timestamp,
                 FileAttributeKey.modificationDate: timestamp],
                ofItemAtPath: backupFileURL.path)
            Diag.info("Backup copy created OK")
        } catch {
            Diag.warning("Failed to make backup copy [error: \(error.localizedDescription)]")
            // no further action, simply return
        }
    }
    
    /// Returns all available database backup files.
    ///
    /// - Returns: matching files found in backup directory
    public func getBackupFiles() -> [URLReference] {
        return scanLocalDirectory(backupDirURL, fileType: .database)
    }
    
    /// Asynchronously deletes old backup files.
    public func deleteExpiredBackupFiles() {
        Diag.debug("Will perform backup maintenance")
        deleteBackupFiles(olderThan: Settings.current.backupKeepingDuration.seconds)
        Diag.info("Backup maintenance completed")
    }

    /// Asynchronously delete backup files older than given time interval from now.
    ///
    /// - Parameter olderThan: maximum age of remaining backups.
    public func deleteBackupFiles(olderThan maxAge: TimeInterval) {
        let allBackupFileRefs = getBackupFiles()
        let now = Date.now
        for fileRef in allBackupFileRefs {
            fileRef.getCachedInfo(canFetch: true) { [weak self] result in
                guard let self = self else { return }
                switch result {
                case .success(let fileInfo):
                    guard let modificationDate = fileInfo.modificationDate else {
                        Diag.warning("Failed to get backup file age.")
                        return
                    }
                    guard now.timeIntervalSince(modificationDate) > maxAge else {
                        // not old enough
                        return
                    }
                    do {
                        try self.deleteFile(fileRef, fileType: .database, ignoreErrors: false)
                        FileKeeperNotifier.notifyFileRemoved(urlRef: fileRef, fileType: .database)
                    } catch {
                        Diag.warning("Failed to delete backup file [reason: \(error.localizedDescription)]")
                    }
                case .failure(let error):
                    Diag.warning("Failed to check backup file age [reason: \(error.localizedDescription)]")
                }
            }
        }
    }
}

// MARK: - References cache

/// Keeps and maintains a cache of URLReference instances, so that `FileKeeper` returns the same instances.
/// This way, references will preserve cached instance info instead of re-acquiring it every time.
fileprivate class ReferenceCache {
    private struct FileTypeExternalKey: Hashable {
        var fileType: FileType
        var isExternal: Bool
    }
    private struct DirectoryFileTypeKey: Hashable {
        var directory: URL
        var fileType: FileType
    }
    
    private var cache = [FileTypeExternalKey: [URLReference]]()
    private var cacheSet = [FileTypeExternalKey: Set<URLReference>]()
    private var directoryCache = [DirectoryFileTypeKey: [URLReference]]()
    private var directoryCacheSet = [DirectoryFileTypeKey: Set<URLReference>]()
    
    /// Updates the cache to match the given references (adds/removes cached instances as needed)
    /// - Parameters:
    ///   - newRefs: new expected state for the cache
    ///   - fileType: type of references
    ///   - isExternal: whether the references are for external files
    /// - Returns: updated cached references for the given combination of fileType/isExternal
    func update(with newRefs: [URLReference], fileType: FileType, isExternal: Bool) -> [URLReference] {
        let key = FileTypeExternalKey(fileType: fileType, isExternal: isExternal)
        guard var _cache = cache[key], let _cacheSet = cacheSet[key] else {
            cache[key] = newRefs
            cacheSet[key] = Set(newRefs)
            return newRefs
        }
        let newRefsSet = Set(newRefs)
        let addedRefs = newRefsSet.subtracting(_cacheSet)
        let removedRefs = _cacheSet.subtracting(newRefsSet)
        if !removedRefs.isEmpty {
            _cache.removeAll { ref in removedRefs.contains(ref) }
        }
        _cache.append(contentsOf: addedRefs)
        cache[key] = _cache
        cacheSet[key] = _cacheSet.subtracting(removedRefs).union(addedRefs)
        return _cache
    }
    
    /// Updates the cache associated with the given `directory` (adds/removes cached instances as needed).
    /// - Parameters:
    ///   - newRefs: new expected state for the cache
    ///   - directory: directory where these references come from
    ///   - fileType: type of referenced files
    func update(with newRefs: [URLReference], from directory: URL, fileType: FileType) -> [URLReference] {
        let key = DirectoryFileTypeKey(directory: directory, fileType: fileType)
        guard var _directoryCache = directoryCache[key],
            let _directoryCacheSet = directoryCacheSet[key] else
        {
            directoryCache[key] = newRefs
            directoryCacheSet[key] = Set(newRefs)
            return newRefs
        }
        let newRefsSet = Set(newRefs)
        let addedRefs = newRefsSet.subtracting(_directoryCacheSet)
        let removedRefs = _directoryCacheSet.subtracting(newRefsSet)
        _directoryCache.removeAll { ref in removedRefs.contains(ref) }
        _directoryCache.append(contentsOf: addedRefs)
        directoryCache[key] = _directoryCache
        directoryCacheSet[key] = _directoryCacheSet.subtracting(removedRefs).union(addedRefs)
        return _directoryCache
    }
}
