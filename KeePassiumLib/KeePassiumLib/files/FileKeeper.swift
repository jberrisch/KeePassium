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

public class FileKeeper {
    public static let shared = FileKeeper()
    
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
    private let docDirURL: URL
    /// App group's shared Backup folder
    private let backupDirURL: URL
    /// App sandbox Documents/Inbox folder
    private let inboxDirURL: URL
    
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
        return refs
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
            if let refUrl = try? ref.resolve(), refUrl == url {
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
            let url = try urlRef.resolve()
            do {
                try FileManager.default.trashItem(at: url, resultingItemURL: nil)
                Diag.info("Local file moved to trash")
            } catch {
                Diag.warning("Failed to trash file, will delete instead [message: '\(error.localizedDescription)']")
                try FileManager.default.removeItem(at: url)
                Diag.info("Local file permanently deleted")
            }
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
            result.append(contentsOf:scanLocalDirectory(backupDirURL, fileType: fileType))
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
        return refs
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
        importFile(url: sourceURL, success: { url in
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
        }, error: errorHandler)
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
        // To access an external URL, we need to init a UIDocument with that URL,
        // and keep the instance around when using the URL.
        // Note: If dummyDoc is replaced with `_`, the document is immediately
        //       deallocated => transient "permission denied" issues.
        let dummyDoc = FileDocument(fileURL: sourceURL)
        
        // Creating a UIDocument is sufficient for some file providers.
        // However, some other file providers (like OneDrive) throw a "File does not exist"
        // unless we actually open the document.
        dummyDoc.open(
            successHandler: { [weak self] in
                guard let _self = self else { return }
                do {
                    let newRef = try URLReference(from: sourceURL, location: .external)
                        // throws an internal system error
                    
                    var storedRefs = _self.getStoredReferences(
                        fileType: fileType,
                        forExternalFiles: true)
                    storedRefs.insert(newRef, at: 0)
                    _self.storeReferences(storedRefs, fileType: fileType, forExternalFiles: true)
                    
                    Diag.info("External URL reference added OK")
                    successHandler?(newRef)
                } catch {
                    Diag.error("Failed to create URL reference [error: '\(error.localizedDescription)', url: '\(sourceURL.redacted)']")
                    let importError = FileKeeperError.openError(reason: error.localizedDescription)
                    errorHandler?(importError)
                }
            },
            errorHandler: { (error) in
                Diag.error("Failed to open document [error: '\(error.localizedDescription)', url: '\(sourceURL.redacted)']")
                let docError = FileKeeperError.openError(reason: error.localizedDescription)
                errorHandler?(docError)

            }
        )
    }
    
    /// Given a file (either external or in 'Documents/Inbox'), copes/moves it to 'Documents'.
    private func importFile(
        url sourceURL: URL,
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
        let doc = FileDocument(fileURL: sourceURL)
        doc.open(successHandler: {
            do {
                try doc.data.write(to: targetURL, options: [.withoutOverwriting])
                Diag.info("External file copied successfully")
                successHandler?(targetURL)
            } catch {
                Diag.error("Failed to save external file [message: \(error.localizedDescription)]")
                let importError = FileKeeperError.importError(reason: error.localizedDescription)
                errorHandler?(importError)
            }
            self.clearInbox()
        }, errorHandler: { error in
            Diag.error("Failed to import external file [message: \(error.localizedDescription)]")
            let importError = FileKeeperError.importError(reason: error.localizedDescription)
            errorHandler?(importError)
            self.clearInbox()
        })
    }
    
    
    /// Removes all files from Documents/Inbox.
    /// Silently ignores any errors.
    private func clearInbox() {
        guard let inboxFiles = try? FileManager.default.contentsOfDirectory(
            at: inboxDirURL,
            includingPropertiesForKeys: nil,
            options: [])
        else {
            // probably, there is no Inbox there
            return
        }
        for url in inboxFiles {
            try? FileManager.default.removeItem(at: url) // ignoring any errors
        }
    }
    
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
    
    /// Deletes old backup files. older than `maxAge` from now.
    ///
    /// - Returns: `false` if there were any errors with any file, `true` if all good.
    @discardableResult
    public func deleteExpiredBackupFiles() -> Bool {
        Diag.debug("Will perform backup maintenance")
        let isAllOK = deleteBackupFiles(olderThan: Settings.current.backupKeepingDuration.seconds)
        Diag.info("Backup maintenance completed [allOK: \(isAllOK)]")
        return isAllOK
    }

    /// Delete backup files older than given time interval from now.
    ///
    /// - Parameter olderThan: maximum age of remaining backups.
    /// - Returns: `false` if there were any errors with any file, `true` if all good.
    @discardableResult
    public func deleteBackupFiles(olderThan maxAge: TimeInterval) -> Bool {
        let allBackupFileRefs = getBackupFiles()
        var isEverythingProcessedOK = true
        let now = Date.now
        for fileRef in allBackupFileRefs {
            guard let modificationDate = fileRef.getInfo().modificationDate else { continue }
            if now.timeIntervalSince(modificationDate) < maxAge {
                // not old enough
                continue
            }
            do {
                try deleteFile(fileRef, fileType: .database, ignoreErrors: false)
                FileKeeperNotifier.notifyFileRemoved(urlRef: fileRef, fileType: .database)
            } catch {
                isEverythingProcessedOK = false
            }
        }
        return isEverythingProcessedOK
    }
}
