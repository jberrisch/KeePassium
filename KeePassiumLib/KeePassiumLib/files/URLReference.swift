//  KeePassium Password Manager
//  Copyright © 2018–2019 Andrei Popleteev <info@keepassium.com>
// 
//  This program is free software: you can redistribute it and/or modify it
//  under the terms of the GNU General Public License version 3 as published
//  by the Free Software Foundation: https://www.gnu.org/licenses/).
//  For commercial licensing, please contact the author.

import UIKit

/// General info about file URL: file name, timestamps, etc.
public struct FileInfo {
    public var fileName: String
    public var fileSize: Int64?
    public var creationDate: Date?
    public var modificationDate: Date?
    public var isExcludedFromBackup: Bool?
    public var isInTrash: Bool
}

/// Represents a URL as a URL bookmark. Useful for handling external (cloud-based) files.
public class URLReference:
    Equatable,
    Hashable,
    Codable,
    CustomDebugStringConvertible,
    Synchronizable
{
    public typealias Descriptor = String
    
    /// Specifies possible storage locations of files.
    public enum Location: Int, Codable, CustomStringConvertible {
        public static let allValues: [Location] =
            [.internalDocuments, .internalBackup, .internalInbox, .external]
        
        public static let allInternal: [Location] =
            [.internalDocuments, .internalBackup, .internalInbox]
        
        /// Files stored in app sandbox/Documents dir.
        case internalDocuments = 0
        /// Files stored in app sandbox/Documents/Backup dir.
        case internalBackup = 1
        /// Files temporarily imported via Documents/Inbox dir.
        case internalInbox = 2
        /// Files stored outside the app sandbox (e.g. in cloud)
        case external = 100
        
        /// True if the location is in app sandbox
        public var isInternal: Bool {
            return self != .external
        }
        
        /// Human-readable description of the location
        public var description: String {
            switch self {
            case .internalDocuments:
                return NSLocalizedString(
                    "[URLReference/Location] Local copy",
                    bundle: Bundle.framework,
                    value: "Local copy",
                    comment: "Human-readable file location: the file is on device, inside the app sandbox. Example: 'File Location: Local copy'")
            case .internalInbox:
                return NSLocalizedString(
                    "[URLReference/Location] Internal inbox",
                    bundle: Bundle.framework,
                    value: "Internal inbox",
                    comment: "Human-readable file location: the file is on device, inside the app sandbox. 'Inbox' is a special directory for files that are being imported. Can be also 'Internal import'. Example: 'File Location: Internal inbox'")
            case .internalBackup:
                return NSLocalizedString(
                    "[URLReference/Location] Internal backup",
                    bundle: Bundle.framework,
                    value: "Internal backup",
                    comment: "Human-readable file location: the file is on device, inside the app sandbox. 'Backup' is a dedicated directory for database backup files. Example: 'File Location: Internal backup'")
            case .external:
                return NSLocalizedString(
                    "[URLReference/Location] Cloud storage / Another app",
                    bundle: Bundle.framework,
                    value: "Cloud storage / Another app",
                    comment: "Human-readable file location. The file is situated either online / in cloud storage, or on the same device, but in some other app. Example: 'File Location: Cloud storage / Another app'")
            }
        }
    }
    
    /// Default timeout for async operations. If exceeded, the operation will finish with `AccessError.timeout` error.
    public static let defaultTimeout: TimeInterval = 15.0
    
    /// Returns the most recent known target file name.
    /// In case of error returns a predefined default string.
    /// NOTE: Don't use for indexing (because of predefined default string).
    public var visibleFileName: String { return url?.lastPathComponent ?? "?" }
    
    /// Last encountered error
    public private(set) var error: FileAccessError?
    public var hasError: Bool { return error != nil}
    
    /// True if the error is an access permission error associated with iOS 13 upgrade.
    /// (iOS 13 cannot access files bookmarked in iOS 12 (GitHub #63):
    /// "The file couldn’t be opened because you don’t have permission to view it.")
    public var hasPermissionError257: Bool {
        guard let nsError = error?.underlyingError as NSError? else { return false }
        return (nsError.domain == NSCocoaErrorDomain) && (nsError.code == 257)
    }
    
    /// True if the error is an "file doesn't exist" error (especially associated with iOS 14 upgrade).
    public var hasFileMissingError: Bool {
        guard location == .external,
              let underlyingError = error?.underlyingError,
              let nsError = underlyingError as NSError? else { return false }
        
        switch nsError.domain {
        case NSCocoaErrorDomain:
            // happens after iOS 14 upgrade
            return nsError.code == CocoaError.Code.fileNoSuchFile.rawValue
        case NSFileProviderErrorDomain:
            // happens when the file was actually deleted
            return nsError.code == NSFileProviderError.noSuchItem.rawValue
        default:
            return false
        }
    }
    
    /// Bookmark data
    private let data: Data
    /// Location type of the original URL
    public let location: Location
    
    /// The URL extracted from bookmark data
    internal var bookmarkedURL: URL?
    /// The URL (if any) stored along with the bookmark data
    internal var cachedURL: URL?
    /// The URL received by resolving bookmark data
    internal var resolvedURL: URL?
    
    /// The original bookmarked URL, if known (cached or bookmarked, not resolved).
    internal var originalURL: URL? {
        return bookmarkedURL ?? cachedURL
    }

    /// The most up-to-date URL we know, if any
    internal var url: URL? {
        return resolvedURL ?? cachedURL ?? bookmarkedURL
    }
    
    
    /// True if there is at least one ongoing refreshInfo() request
    public var isRefreshingInfo: Bool {
        let result = synchronized {
            return (self.infoRefreshRequestCount > 0)
        }
        return result
    }

    /// Number of ongoing refreshInfo() requests
    private var infoRefreshRequestCount = 0

    /// Cached result of the last refreshInfo() call
    private var cachedInfo: FileInfo?
    
    
    /// A unique identifier of the serving file provider.
    public private(set) var fileProvider: FileProvider?
    
    /// Dispatch queue for asynchronous URLReference operations
    fileprivate static let backgroundQueue = DispatchQueue(
        label: "com.keepassium.URLReference",
        qos: .background,
        attributes: [.concurrent])
    
    
    
    private enum CodingKeys: String, CodingKey {
        case data = "data"
        case location = "location"
        case cachedURL = "url"
    }
    
    // MARK: -
    
    public init(from url: URL, location: Location) throws {
        let isAccessed = url.startAccessingSecurityScopedResource()
        defer {
            if isAccessed {
                url.stopAccessingSecurityScopedResource()
            }
        }
        cachedURL = url
        bookmarkedURL = url
        self.location = location
        if location.isInternal {
            data = Data() // for backward compatibility
        } else {
            data = try url.bookmarkData(
                options: URLReference.getBookmarkCreationOptions(),
                includingResourceValuesForKeys: nil,
                relativeTo: nil) // throws an internal system error
        }
        processReference()
    }

    private static func getBookmarkCreationOptions() -> URL.BookmarkCreationOptions {
        if ProcessInfo.isRunningOnMac {
            /// iOS app on macOS, does not support .minimalBookmark for security-scoped bookmarks
            return []
        } else {
            return [.minimalBookmark]
        }
    }
    
    public static func == (lhs: URLReference, rhs: URLReference) -> Bool {
        guard lhs.location == rhs.location else { return false }
        guard let lhsOriginalURL = lhs.originalURL, let rhsOriginalURL = rhs.originalURL else {
            assertionFailure()
            Diag.debug("Original URL of the file is nil.")
            return false
        }
        // Two refs are equal if their original URLs are the same.
        // We ignore resolved URLs, since they can change at any moment.
        return lhsOriginalURL == rhsOriginalURL
    }
    
    public func hash(into hasher: inout Hasher) {
        hasher.combine(location)
        guard let originalURL = originalURL else {
            assertionFailure()
            return
        }
        hasher.combine(originalURL)
    }
    
    public func serialize() -> Data {
        return try! JSONEncoder().encode(self)
    }
    
    public static func deserialize(from data: Data) -> URLReference? {
        guard let ref = try? JSONDecoder().decode(URLReference.self, from: data) else {
            return nil
        }
        ref.processReference()
        return ref
    }
    
    public var debugDescription: String {
        return " ‣ Location: \(location)\n" +
            " ‣ bookmarkedURL: \(bookmarkedURL?.relativeString ?? "nil")\n" +
            " ‣ cachedURL: \(cachedURL?.relativeString ?? "nil")\n" +
            " ‣ resolvedURL: \(resolvedURL?.relativeString ?? "nil")\n" +
            " ‣ fileProvider: \(fileProvider?.id ?? "nil")\n" +
            " ‣ data: \(data.count) bytes"
    }
    
    // MARK: - Async creation
    
    /// One of the parameters is guaranteed to be non-nil
    public typealias CreateCallback = (Result<URLReference, FileAccessError>) -> ()

    /// Creates a reference for the given URL, asynchronously.
    /// Takes several stages (attempts):
    ///  - startAccessingSecurityScopedResource / stopAccessingSecurityScopedResource
    ///  - access the file (but don't open)
    ///  - open UIDocument
    ///
    /// - Parameters:
    ///   - url: target URL
    ///   - location: location of the target URL
    ///   - completion: called once the process has finished (either successfully or with an error); called on main queue
    public static func create(
        for url: URL,
        location: URLReference.Location,
        completion callback: @escaping CreateCallback)
    {
        let isAccessed = url.startAccessingSecurityScopedResource()
        defer {
            if isAccessed {
                url.stopAccessingSecurityScopedResource()
            }
        }

        // Stage 1: try to simply create
        if tryCreate(for: url, location: location, callbackOnError: false, callback: callback) {
            print("URL bookmarked on stage 1")
            return
        }

        // Stage 2: try to create after accessing the document
        let tmpDoc = BaseDocument(fileURL: url, fileProvider: nil)
        tmpDoc.open(withTimeout: URLReference.defaultTimeout) { (result) in
            defer {
                tmpDoc.close(completionHandler: nil)
            }
            switch result {
            case .success(_):
                // The file is fetched & secure-scope-accessed, let's try to bookmark it again.
                // (Last attempt, calls the callback in any case.)
                tryCreate(for: url, location: location, callbackOnError: true, callback: callback)
            case .failure(let fileAccessError):
                DispatchQueue.main.async {
                    callback(.failure(fileAccessError))
                }
            }
        }
    }
    
    /// Tries to create a URLReference for the given URL
    /// - Parameters:
    ///   - url: target URL
    ///   - location: target URL location
    ///   - callbackOnError: whether to return error via callback before returning `false`
    ///   - callback: called once reference created (or failed, if callbackOnError is true); called on main queue
    /// - Returns: true if successful, false otherwise
    @discardableResult
    private static func tryCreate(
        for url: URL,
        location: URLReference.Location,
        callbackOnError: Bool = false,
        callback: @escaping CreateCallback
    ) -> Bool {
        do {
            let urlRef = try URLReference(from: url, location: location)
            DispatchQueue.main.async {
                callback(.success(urlRef))
            }
            return true
        } catch {
            if callbackOnError {
                DispatchQueue.main.async {
                    let fileAccessError = FileAccessError.make(from: error, fileProvider: nil)
                    callback(.failure(fileAccessError))
                }
            }
            return false
        }
    }
    
    // MARK: - Async resolving
    
    /// One of the parameters is guaranteed to be non-nil
    public typealias ResolveCallback = (Result<URL, FileAccessError>) -> ()
    
    /// Resolves the reference asynchronously.
    /// - Parameters:
    ///   - timeout: time to wait for resolving to finish
    ///   - callback: called when resolving either finishes or terminates by timeout. Is called on the main queue.
    public func resolveAsync(
        timeout: TimeInterval = URLReference.defaultTimeout,
        callback: @escaping ResolveCallback)
    {
        execute(
            withTimeout: URLReference.defaultTimeout,
            on: URLReference.backgroundQueue,
            slowSyncOperation: { () -> Result<URL, Error> in
                do {
                    let url = try self.resolveSync()
                    return .success(url)
                } catch {
                    return .failure(error)
                }
            },
            onSuccess: { [weak self] result in
                guard let self = self else { return }
                switch result {
                case .success(let url):
                    self.error = nil
                    self.dispatchMain {
                        callback(.success(url))
                    }
                case .failure(let error):
                    let fileAccessError = FileAccessError.make(
                        from: error,
                        fileProvider: self.fileProvider
                    )
                    self.error = fileAccessError
                    self.dispatchMain {
                        callback(.failure(fileAccessError))
                    }
                }
            },
            onTimeout: { [self] in
                self.error = FileAccessError.timeout(fileProvider: self.fileProvider)
                self.dispatchMain {
                    callback(.failure(FileAccessError.timeout(fileProvider: self.fileProvider)))
                }
            }
        )
    }
    
    // MARK: - Async info
    
    public typealias InfoCallback = (Result<FileInfo, FileAccessError>) -> ()
    
    private enum InfoRefreshRequestState {
        case added
        case completed
    }
    
    private func registerInfoRefreshRequest(_ state: InfoRefreshRequestState) {
        synchronized { [self] in
            switch state {
            case .added:
                self.infoRefreshRequestCount += 1
            case .completed:
                self.infoRefreshRequestCount -= 1
            }
        }
    }
    
    /// Retruns the last known info about the target file.
    /// If no previous info available, fetches it.
    /// - Parameters:
    ///   - canFetch: try to fetch fresh info, or return nil?
    ///   - callback: called on the main queue once the operation is complete (with info or with an error)
    public func getCachedInfo(canFetch: Bool, completion callback: @escaping InfoCallback) {
        if let info = cachedInfo {
            DispatchQueue.main.async {
                // don't change `error`, simply return cached info
                callback(.success(info))
            }
        } else {
            guard canFetch else {
                let error: FileAccessError = self.error ?? .noInfoAvailable
                callback(.failure(error))
                return
            }
            refreshInfo(completion: callback)
        }
    }
    
    
    /// Fetches information about target file, asynchronously.
    /// - Parameters:
    ///   - timeout: timeout to resolve the reference
    ///   - callback: called on the main queue once the operation completes (either with info or an error)
    public func refreshInfo(
        timeout: TimeInterval = URLReference.defaultTimeout,
        completion callback: @escaping InfoCallback)
    {
        registerInfoRefreshRequest(.added)
        resolveAsync(timeout: timeout) {
            [self] (result) in // strong self
            // we're already in main queue
            switch result {
            case .success(let url):
                // don't update info request counter here
                URLReference.backgroundQueue.async { // strong self
                    self.refreshInfo(for: url, completion: callback)
                }
            case .failure(let error):
                self.registerInfoRefreshRequest(.completed)
                // propagate the resolving error
                self.error = error
                callback(.failure(error))
            }
        }
    }
    
    /// Should be called in a background queue.
    private func refreshInfo(for url: URL, completion callback: @escaping InfoCallback) {
        assert(!Thread.isMainThread)

        // without secruity scoping, won't get file attributes
        let isAccessed = url.startAccessingSecurityScopedResource()
        
        // Using a temporary UIDocument to fetch&coordinate access to the file.
        // A more lightweight NSFileCoordinator solution causes
        // frequent freezes with GDrive, for yet-unknown reasons...
        let tmpDoc = BaseDocument(fileURL: url, fileProvider: fileProvider)
        tmpDoc.open(withTimeout: URLReference.defaultTimeout) { [self] (result) in
            defer {
                if isAccessed {
                    url.stopAccessingSecurityScopedResource()
                }
                tmpDoc.close(completionHandler: nil)
            }
            self.registerInfoRefreshRequest(.completed)
            switch result {
            case .success(_):
                self.readFileInfo(url: url, completion: callback)
            case .failure(let fileAccessError):
                DispatchQueue.main.async { // strong self
                    self.error = fileAccessError
                    callback(.failure(fileAccessError))
                }
            }
        }
    }
    
    /// Reads attributes of the given file, updates the `cachedInfo` property,
    /// and calls the `completion` callback (on the main queue) once done.
    /// Fetches attributes synchronously, so should be called from a background thread.
    private func readFileInfo(url: URL, completion callback: @escaping InfoCallback) {
        assert(!Thread.isMainThread)
        // Read document file attributes
        let attributeKeys: Set<URLResourceKey> = [
            .fileSizeKey,
            .creationDateKey,
            .contentModificationDateKey,
            .isExcludedFromBackupKey,
            .ubiquitousItemDownloadingStatusKey,
        ]

        /// The system caches attributes for performance, and we need the actual values, not cached.
        /// Clearing the cache is a mutating function, so we create a mutable copy of the original const URL.
        var urlWithFreshAttributes = url
        urlWithFreshAttributes.removeAllCachedResourceValues()
        
        let attributes: URLResourceValues
        do {
            attributes = try urlWithFreshAttributes.resourceValues(forKeys: attributeKeys)
        } catch {
            Diag.error("Failed to get file info [reason: \(error.localizedDescription)]")
            let fileAccessError = FileAccessError.systemError(error)
            DispatchQueue.main.async { // strong self
                self.error = fileAccessError
                callback(.failure(fileAccessError))
            }
            return
        }
        
        let latestInfo = FileInfo(
            fileName: urlWithFreshAttributes.lastPathComponent,
            fileSize: Int64(attributes.fileSize ?? -1),
            creationDate: attributes.creationDate,
            modificationDate: attributes.contentModificationDate,
            isExcludedFromBackup: attributes.isExcludedFromBackup ?? false,
            isInTrash: url.isInTrashDirectory)
        self.cachedInfo = latestInfo
        DispatchQueue.main.async {
            self.error = nil
            callback(.success(latestInfo))
        }
    }
    
    // MARK: - Synchronous operations
    
    public func resolveSync() throws -> URL {
        if location.isInternal, let cachedURL = self.cachedURL {
            return cachedURL
        }
        
        var isStale = false
        let _resolvedURL = try URL(
            resolvingBookmarkData: data,
            options: [URL.BookmarkResolutionOptions.withoutUI],
            relativeTo: nil,
            bookmarkDataIsStale: &isStale)
        self.resolvedURL = _resolvedURL
        return _resolvedURL
    }
    
    /// Identifies this reference among others. Currently returns the file name (resolved, or cached, or at least the bookmarked one)
    public func getDescriptor() -> Descriptor? {
        if let resolvedFileName = resolvedURL?.lastPathComponent {
            return resolvedFileName
        }
        if let cachedFileName = cachedURL?.lastPathComponent {
            return cachedFileName
        }
        return bookmarkedURL?.lastPathComponent
    }
    
    /// Returns most recent information about resolved URL.
    /// - Parameters:
    ///   - canFetch: try to fetch fresh info, or return nil?
    public func getCachedInfoSync(canFetch: Bool) -> FileInfo? {
        if cachedInfo == nil && canFetch {
            refreshInfoSync()
        }
        return cachedInfo
    }
    
    /// Returns information about resolved URL.
    /// Might be slow, as it needs to resolve the URL.
    /// In case of trouble, returns `nil` and sets the `error` property.
    public func getInfoSync() -> FileInfo? {
        refreshInfoSync()
        return cachedInfo
    }
    
    /// Re-aquires information about resolved URL synchronously.
    private func refreshInfoSync() {
        let semaphore = DispatchSemaphore(value: 0)
        URLReference.backgroundQueue.async { [self] in
            self.refreshInfo { _ in
                // `cachedInfo` and `error` are already updated,
                // so we have nothing to do here.
                semaphore.signal()
            }
        }
        semaphore.wait()
    }
    
    /// Finds the same reference in the given list.
    /// If no exact match found, and `fallbackToNamesake` is `true`,
    /// looks also for references with the same file name.
    ///
    /// - Parameters:
    ///   - refs: list of references to search in
    ///   - fallbackToNamesake: if `true`, repeat search with relaxed conditions
    ///       (same file name instead of exact match).
    /// - Returns: suitable reference from `refs`, if any.
    public func find(in refs: [URLReference], fallbackToNamesake: Bool=false) -> URLReference? {
        if let exactMatchIndex = refs.firstIndex(of: self) {
            return refs[exactMatchIndex]
        }
        
        if fallbackToNamesake {
            guard let fileName = self.url?.lastPathComponent else {
                return nil
            }
            return refs.first(where: { $0.url?.lastPathComponent == fileName })
        }
        return nil
    }
    
    // MARK: - Bookmark data parsing
    
    /// Extracts additional info from bookmark data.
    ///
    /// Updates instance properties, using parsed bookmark data:
    /// - `bookmarkedURL` (might be `nil` if missing)
    /// - `fileProviderID` (might be `nil` if missing)
    fileprivate func processReference() {
        guard !data.isEmpty else {
            if location.isInternal {
                fileProvider = .localStorage
            }
            return
        }
        
        func getRecordValue(data: ByteArray, fpOffset: Int) -> String? {
            let contentBytes = data[fpOffset..<data.count]
            let contentStream = contentBytes.asInputStream()
            contentStream.open()
            defer { contentStream.close() }
            guard let recLength = contentStream.readUInt32(),
                let _ = contentStream.readUInt32(),
                let recBytes = contentStream.read(count: Int(recLength)),
                let utf8String = recBytes.toString(using: .utf8)
                else { return nil }
            return utf8String
        }
        
        func extractFileProviderID(_ fullString: String) -> String? {
            // The full string contains a lot of redundant info, we need to clean it up.
            // Moreover, its format depends on the iOS version that created the bookmark.
            
            // Since bookmark might be saved from an old iOS version,
            // we need to check all patterns until something fits.
            let regExpressions: [NSRegularExpression] = [
                // iOS 12/13 store file provider IDs like this:
                //     "fileprovider:#com.owncloud.ios-app.ownCloud-File-Provider/001F351B-02F7-4F70-B6E0-C8E5996F7F8C/A52BED37B76B4BA7A701F4654A6EE6B5"
                //     "fileprovider:com.owncloud.ios-app.ownCloud-File-Provider/001F351B-02F7-4F70-B6E0-C8E5996F7F8C/A52BED37B76B4BA7A701F4654A6EE6B5"
                try! NSRegularExpression(
                    pattern: #"fileprovider\:#?([a-zA-Z0-9\.\-\_]+)"#,
                    options: []),
                // iOS 14 stores file provider IDs like this:
                //     "fp:/OjRaKgcVe7nCFT6sFxYnWxTV3NNIdQZYcv5IlK6HDws=/com.apple.FileProvider.LocalStorage//did=636"
                //     "fp:/VR3ykTi_hHbvSDecanF2SYE4U1zKfCp53F7pitQa6dI=/com.getdropbox.Dropbox.FileProvider/123456/Base64abcC9hbGxfY2Fwcy5rZGJ4"
                try! NSRegularExpression(
                    pattern: #"fp\:/.*?/([a-zA-Z0-9\.\-\_]+)/"#,
                    options: [])
            ]

            let fullRange = NSRange(fullString.startIndex..<fullString.endIndex, in: fullString)
            for regexp in regExpressions {
                if let match = regexp.firstMatch(in: fullString, options: [], range: fullRange),
                   let foundRange = Range(match.range(at: 1), in: fullString)
                {
                    return String(fullString[foundRange])
                }
            }
            return nil
        }
        
        func extractBookmarkedURLString(_ sandboxInfoString: String) -> String? {
            let infoTokens = sandboxInfoString.split(separator: ";")
            guard let lastToken = infoTokens.last else { return nil }
            return String(lastToken)
        }
        
        let data = ByteArray(data: self.data)
        guard data.count > 0 else { return }
        let stream = data.asInputStream()
        stream.open()
        defer { stream.close() }
        
        stream.skip(count: 12)
        guard let contentOffset32 = stream.readUInt32() else { return }
        let contentOffset = Int(contentOffset32)
        stream.skip(count: contentOffset - 12 - 4)
        guard let firstTOC32 = stream.readUInt32() else { return }
        stream.skip(count: Int(firstTOC32) - 4 + 4*4)
        
        var _fileProviderID: String?
        var _sandboxBookmarkedURLString: String?
        var _hackyBookmarkedURLString: String?
        var _volumePath: String?
        guard let recordCount = stream.readUInt32() else { return }
        for _ in 0..<recordCount {
            guard let recordID = stream.readUInt32(),
                let offset = stream.readUInt64()
                else { return }
            switch recordID {
            case 0x2002:
                _volumePath = getRecordValue(data: data, fpOffset: contentOffset + Int(offset))
            case 0x2070: // File Provider record
                guard let fullFileProviderString =
                    getRecordValue(data: data, fpOffset: contentOffset + Int(offset))
                    else { continue }
                _fileProviderID = extractFileProviderID(fullFileProviderString)
            case 0xF080: // Sandbox Info record
                guard let sandboxInfoString =
                    getRecordValue(data: data, fpOffset: contentOffset + Int(offset))
                    else { continue }
                _sandboxBookmarkedURLString = extractBookmarkedURLString(sandboxInfoString)
            case 0x800003E8: // dedicated field for bookmarked URL (likely for simulator only)
                _hackyBookmarkedURLString =
                    getRecordValue(data: data, fpOffset: contentOffset + Int(offset))
            default:
                continue
            }
        }
        
        // Sanity check of extracted info
        if let volumePath = _volumePath,
            let hackyURLString = _hackyBookmarkedURLString,
            !hackyURLString.starts(with: volumePath)
        {
            // hacky string does not start with the volume path -> sanity check failed
            _hackyBookmarkedURLString = nil
        }
        if let urlString = _sandboxBookmarkedURLString ?? _hackyBookmarkedURLString {
            // In Xcode 11.3 debugger, bookmarkedURL appears `nil` even after assignment.
            // This is a debugger bug: https://stackoverflow.com/questions/58155061/convert-string-to-url-why-is-resulting-variable-nil
            self.bookmarkedURL = URL(fileURLWithPath: urlString, isDirectory: false)
        }
        if let fileProviderID = _fileProviderID {
            self.fileProvider = FileProvider(rawValue: fileProviderID)
        } else {
            if ProcessInfo.isRunningOnMac {
                self.fileProvider = .localStorage
                return
            }
            assertionFailure()
            self.fileProvider = nil
        }
    }
}
