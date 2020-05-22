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
    public static let defaultTimeout: TimeInterval = 5.0
    
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
        guard let nsError = error as NSError? else { return false }
        return (nsError.domain == "NSCocoaErrorDomain") && (nsError.code == 257)
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
    private var fileProviderID: String?
    
    fileprivate static let fileCoordinator = FileCoordinator()
    
    
    /// Dispatch queue for asynchronous URLReference operations
    fileprivate static let queue = DispatchQueue(
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
                options: [.minimalBookmark],
                includingResourceValuesForKeys: nil,
                relativeTo: nil) // throws an internal system error
        }
        processReference()
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
        hasher.combine(originalURL!)
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
            " ‣ fileProviderID: \(fileProviderID ?? "nil")\n" +
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
    ///   - completion: called once the process has finished (either successfully or with an error)
    public static func create(
        for url: URL,
        location: URLReference.Location,
        completion callback: @escaping CreateCallback)
    {
        let isAccessed = url.startAccessingSecurityScopedResource()
        
        // Stage 1: try to simply create
        if tryCreate(for: url, location: location, callbackOnError: false, callback: callback) {
            print("URL bookmarked on stage 1")
            if isAccessed {
                url.stopAccessingSecurityScopedResource()
            }
            return
        }
        
        // Stage 2: try to create after accessing the document
        let readingIntentOptions: NSFileCoordinator.ReadingOptions = [
            .withoutChanges, // don't force other processes to save the file first
            .resolvesSymbolicLink, // if sym link, resolve the real target URL first
            .immediatelyAvailableMetadataOnly] // don't download, use as-is immediately
                                               // N.B.: Shouldn't actually read the contents
        fileCoordinator.coordinateReading(
            at: url,
            options: readingIntentOptions,
            timeout: URLReference.defaultTimeout)
        {
            // Note: don't attempt to read the contents,
            // it won't work due to .immediatelyAvailableMetadataOnly above
            (fileAccessError) in
            defer {
                if isAccessed {
                    url.stopAccessingSecurityScopedResource()
                }
            }
            guard fileAccessError == nil else {
                callback(.failure(fileAccessError!))
                return
            }
            // calls the callback in any case
            tryCreate(for: url, location: location, callbackOnError: true, callback: callback)
        }
    }
    
    /// Tries to create a URLReference for the given URL
    /// - Parameters:
    ///   - url: target URL
    ///   - location: target URL location
    ///   - callbackOnError: whether to return error via callback before returning `false`
    ///   - callback: called once reference created (or failed, if callbackOnError is true)
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
            callback(.success(urlRef))
            return true
        } catch {
            if callbackOnError {
                callback(.failure(.accessError(error)))
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
        URLReference.queue.async { // strong self
            self.resolveAsyncInternal(timeout: timeout, completion: callback)
        }
    }
    
    private func resolveAsyncInternal(
        timeout: TimeInterval,
        completion callback: @escaping ResolveCallback)
    {
        assert(!Thread.isMainThread)
        
        let waitSemaphore = DispatchSemaphore(value: 0)
        var hasTimedOut = false
        // do slow resolving as a concurrent task
        URLReference.queue.async { // strong self
            var _url: URL?
            var _error: Error?
            do {
                _url = try self.resolveSync()
            } catch {
                _error = error
            }
            waitSemaphore.signal()
            guard !hasTimedOut else { return }
            DispatchQueue.main.async { // strong self
                assert(_url != nil || _error != nil)
                guard _error == nil else {
                    self.error = FileAccessError.accessError(_error)
                    callback(.failure(.accessError(_error)))
                    return
                }
                guard let url = _url else { // should not happen
                    assertionFailure()
                    Diag.error("Internal error")
                    self.error = FileAccessError.internalError
                    callback(.failure(.internalError))
                    return
                }
                self.error = nil
                callback(.success(url))
            }
        }
        
        // wait for a while to finish resolving
        let waitUntil = (timeout < 0) ? DispatchTime.distantFuture : DispatchTime.now() + timeout
        guard waitSemaphore.wait(timeout: waitUntil) != .timedOut else {
            hasTimedOut = true
            DispatchQueue.main.async {
                self.error = FileAccessError.timeout
                callback(.failure(FileAccessError.timeout))
            }
            return
        }
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
        resolveAsync(timeout: timeout) { // strong self
            (result) in
            // we're already in main queue
            switch result {
            case .success(let url):
                // don't update info request counter here
                URLReference.queue.async { // strong self
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
        
        // Access the document to ensure we fetch the latest metadata
        let readingIntentOptions: NSFileCoordinator.ReadingOptions = [
            // ensure any pending saves are completed first --> so, no .withoutChanges
            // OK to download the latest metadata --> so, no .immediatelyAvailableMetadataOnly
            .resolvesSymbolicLink // if sym link, resolve the real target URL first
        ]
        URLReference.fileCoordinator.coordinateReading(
            at: url,
            options: readingIntentOptions,
            timeout: URLReference.defaultTimeout)
        {
            (fileAccessError) in // strong self
            defer {
                if isAccessed {
                    url.stopAccessingSecurityScopedResource()
                }
            }

            self.registerInfoRefreshRequest(.completed)
            guard fileAccessError == nil else {
                DispatchQueue.main.async { // strong self
                    self.error = fileAccessError
                    callback(.failure(fileAccessError!))
                }
                return
            }
            let latestInfo = FileInfo(
                fileName: url.lastPathComponent,
                fileSize: url.fileSize,
                creationDate: url.fileCreationDate,
                modificationDate: url.fileModificationDate)
            self.cachedInfo = latestInfo
            DispatchQueue.main.async {
                self.error = nil
                callback(.success(latestInfo))
            }
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
        URLReference.queue.async { [self] in
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
            guard let fileName = self.cachedInfo?.fileName else {
                return nil
            }
            return refs.first(where: { $0.cachedInfo?.fileName == fileName })
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
        guard !data.isEmpty else { return }
        
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
            // The string looks like ""fileprovider:#com.owncloud.ios-app.ownCloud-File-Provider/001F351B-02F7-4F70-B6E0-C8E5996F7F8C/A52BED37B76B4BA7A701F4654A6EE6B5""
            // So we need to clean it up.
            let regexp = try! NSRegularExpression(
                pattern: #"fileprovider\:#?([a-zA-Z0-9\.\-\_]+)"#,
                options: [])
            let fullRange = NSRange(fullString.startIndex..<fullString.endIndex, in: fullString)
            guard let match = regexp.firstMatch(in: fullString, options: [], range: fullRange),
                let foundRange = Range(match.range(at: 1), in: fullString)
                else { return nil }
            return String(fullString[foundRange])
        }
        
        func extractBookmarkedURL(_ sandboxInfoString: String) -> URL {
            let infoTokens = sandboxInfoString.split(separator: ";")
            let url = URL(fileURLWithPath: String(infoTokens.last!))
            return url
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
        
        guard let recordCount = stream.readUInt32() else { return }
        for _ in 0..<recordCount {
            guard let recordID = stream.readUInt32(),
                let offset = stream.readUInt64()
                else { return }
            switch recordID {
            case 8304:
                guard let fullFileProviderString =
                    getRecordValue(data: data, fpOffset: contentOffset + Int(offset))
                    else { continue }
                self.fileProviderID = extractFileProviderID(fullFileProviderString)
            case 61568:
                guard let sandboxInfoString =
                    getRecordValue(data: data, fpOffset: contentOffset + Int(offset))
                    else { continue }
                self.bookmarkedURL = extractBookmarkedURL(sandboxInfoString)
            default:
                continue
            }
        }
    }

}
