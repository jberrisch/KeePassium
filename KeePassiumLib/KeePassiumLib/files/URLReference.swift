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
    public var hasError: Bool { return error != nil}
    public var errorMessage: String? { return error?.localizedDescription }
    public var error: Error?

    /// True if the error is an access permission error associated with iOS 13 upgrade.
    /// (iOS 13 cannot access files bookmarked in iOS 12 (GitHub #63):
    /// "The file couldn’t be opened because you don’t have permission to view it.")
    public var hasPermissionError257: Bool {
        guard let nsError = error as NSError? else { return false }
        return (nsError.domain == "NSCocoaErrorDomain") && (nsError.code == 257)
    }

    public var fileSize: Int64?
    public var creationDate: Date?
    public var modificationDate: Date?
}

/// Represents a URL as a URL bookmark. Useful for handling external (cloud-based) files.
public class URLReference: Equatable, Codable {

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
    
    /// Bookmark data
    private let data: Data
    /// sha256 hash of `data`
    lazy private(set) var hash: ByteArray = CryptoManager.sha256(of: ByteArray(data: data))
    /// Location type of the original URL
    public let location: Location
    /// Cached original URL (nil if needs resolving)
    private var url: URL?
    
    private enum CodingKeys: String, CodingKey {
        case data = "data"
        case location = "location"
        case url = "url"
    }
    
    public init(from url: URL, location: Location) throws {
        let isAccessed = url.startAccessingSecurityScopedResource()
        defer {
            if isAccessed {
                url.stopAccessingSecurityScopedResource()
            }
        }
        self.url = url
        data = try url.bookmarkData(
            options: [.minimalBookmark],
            includingResourceValuesForKeys: nil,
            relativeTo: nil) // throws an internal system error
        self.location = location
    }

    public static func == (lhs: URLReference, rhs: URLReference) -> Bool {
        guard lhs.location == rhs.location else { return false }
        if lhs.location.isInternal {
            // For internal files, URL references are generated dynamically
            // and same URL can have different refs. So we compare by URL.
            guard let leftURL = try? lhs.resolve(),
                let rightURL = try? rhs.resolve() else { return false }
            return leftURL == rightURL
        } else {
            // For external files, URL references are stored, so same refs
            // will have same hash.
            return lhs.hash == rhs.hash
        }
    }
    
    public func serialize() -> Data {
        return try! JSONEncoder().encode(self)
    }
    public static func deserialize(from data: Data) -> URLReference? {
        return try? JSONDecoder().decode(URLReference.self, from: data)
    }
    
    public func resolve() throws -> URL {
        if let url = url, FileManager.default.fileExists(atPath: url.path) {
            // skip resolving, use the cached URL
            return url
        }
        
        var isStale = false
        let resolvedUrl = try URL(
            resolvingBookmarkData: data,
            options: [URL.BookmarkResolutionOptions.withoutUI],
            relativeTo: nil,
            bookmarkDataIsStale: &isStale)
        self.url = resolvedUrl
        return resolvedUrl
    }
    
    /// Identifies this reference among others.
    /// Currently returns file name if available.
    /// If the reference is not resolvable, returns nil.
    public func getDescriptor() -> Descriptor? {
        guard !info.hasError else {
            //TODO: lookup file name by hash, in some persistent table
            return nil
        }
        return info.fileName
    }
    
    /// Cached information about resolved URL.
    /// Cached after first call; use `getInfo()` to update.
    /// In case of trouble, only `hasError` and `errorMessage` fields are valid.
    public lazy var info: FileInfo = getInfo()
    
    /// Returns information about resolved URL (also updates the `info` property).
    /// Might be slow, as it needs to resolve the URL.
    /// In case of trouble, only `hasError` and `errorMessage` fields are valid.
    public func getInfo() -> FileInfo {
        refreshInfo()
        return info
    }
    
    /// Re-aquires information about resolved URL and updates the `info` field.
    public func refreshInfo() {
        let result: FileInfo
        do {
            let url = try resolve()
            // without secruity scoping, won't get file attributes
            let isAccessed = url.startAccessingSecurityScopedResource()
            defer {
                if isAccessed {
                    url.stopAccessingSecurityScopedResource()
                }
            }
            result = FileInfo(
                fileName: url.lastPathComponent,
                error: nil,
                fileSize: url.fileSize,
                creationDate: url.fileCreationDate,
                modificationDate: url.fileModificationDate)
        } catch {
            result = FileInfo(
                fileName: "?",
                error: error,
                fileSize: nil,
                creationDate: nil,
                modificationDate: nil)
        }
        self.info = result
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
            let fileName = self.info.fileName
            return refs.first(where: { $0.info.fileName == fileName })
        }
        return nil
    }
}
