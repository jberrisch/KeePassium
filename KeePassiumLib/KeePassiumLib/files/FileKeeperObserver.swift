//  KeePassium Password Manager
//  Copyright © 2018–2019 Andrei Popleteev <info@keepassium.com>
// 
//  This program is free software: you can redistribute it and/or modify it
//  under the terms of the GNU General Public License version 3 as published
//  by the Free Software Foundation: https://www.gnu.org/licenses/).
//  For commercial licensing, please contact the author.

import Foundation

/// A helper for observing notifications about file list changes,
/// such as added/removed databases or key files.
public protocol FileKeeperObserver: class {
    /// Called when a new file has been added
    func fileKeeper(didAddFile urlRef: URLReference, fileType: FileType)
    /// Called when a file has been removed
    func fileKeeper(didRemoveFile urlRef: URLReference, fileType: FileType)
    /// Called when there are files to import
    func fileKeeperHasPendingOperation()
}

public extension FileKeeperObserver {
    // Delegate method stubs
    func fileKeeper(didAddFile urlRef: URLReference, fileType: FileType) {}
    func fileKeeper(didRemoveFile urlRef: URLReference, fileType: FileType) {}
    func fileKeeperHasPendingOperation() {}
}

// A helper class to manage subscription to `FileKeeper` notifications.
public class FileKeeperNotifications: Synchronizable {
    private weak var observer: FileKeeperObserver?
    
    public init(observer: FileKeeperObserver) {
        self.observer = observer
    }
    
    public func startObserving() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(didAddFile(_:)),
            name: FileKeeperNotifier.fileAddedNotification,
            object: nil)
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(didRemoveFile(_:)),
            name: FileKeeperNotifier.fileRemovedNotification,
            object: nil)
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(gotPendingOperation(_:)),
            name: FileKeeperNotifier.pendingFileOperationNotification,
            object: nil)
    }

    public func stopObserving() {
        NotificationCenter.default.removeObserver(
            self, name: FileKeeperNotifier.fileAddedNotification, object: nil)
        NotificationCenter.default.removeObserver(
            self, name: FileKeeperNotifier.fileRemovedNotification, object: nil)
        NotificationCenter.default.removeObserver(
            self, name: FileKeeperNotifier.pendingFileOperationNotification, object: nil)
    }
    
    @objc private func didAddFile(_ notification: Notification) {
        guard let userInfo = notification.userInfo,
            let urlRef = userInfo[FileKeeperNotifier.UserInfoKeys.urlReferenceKey] as? URLReference,
            let fileType = userInfo[FileKeeperNotifier.UserInfoKeys.fileTypeKey] as? FileType else {
                fatalError("FileKeeper notification: something is missing")
        }
        dispatchMain { [self] in
            self.observer?.fileKeeper(didAddFile: urlRef, fileType: fileType)
        }
    }
    
    @objc private func didRemoveFile(_ notification: Notification) {
        guard let userInfo = notification.userInfo,
            let urlRef = userInfo[FileKeeperNotifier.UserInfoKeys.urlReferenceKey] as? URLReference,
            let fileType = userInfo[FileKeeperNotifier.UserInfoKeys.fileTypeKey] as? FileType else {
                fatalError("FileKeeper notification: something is missing")
        }
        dispatchMain { [self] in
            self.observer?.fileKeeper(didRemoveFile: urlRef, fileType: fileType)
        }
    }
    
    @objc private func gotPendingOperation(_ notification: Notification) {
        dispatchMain {
            self.observer?.fileKeeperHasPendingOperation()
        }
    }
}

/// A helper for posting notifications for `DatabaseListChangeObserver`.
class FileKeeperNotifier {
    fileprivate static let fileAddedNotification = Notification.Name("com.keepassium.fileKeeper.fileAdded")
    fileprivate static let fileRemovedNotification = Notification.Name("com.keepassium.fileKeeper.fileRemoved")
    fileprivate static let pendingFileOperationNotification = Notification.Name("com.keepassium.fileKeeper.pendingOperation")

    fileprivate enum UserInfoKeys {
        static let urlReferenceKey = "URLReference"
        static let fileTypeKey = "fileType"
    }
    
    static func notifyFileAdded(urlRef: URLReference, fileType: FileType) {
        NotificationCenter.default.post(
            name: fileAddedNotification,
            object: nil,
            userInfo: [
                UserInfoKeys.urlReferenceKey : urlRef,
                UserInfoKeys.fileTypeKey: fileType
            ]
        )
    }
    
    static func notifyFileRemoved(urlRef: URLReference, fileType: FileType) {
        NotificationCenter.default.post(
            name: fileRemovedNotification,
            object: nil,
            userInfo: [
                UserInfoKeys.urlReferenceKey : urlRef,
                UserInfoKeys.fileTypeKey: fileType
            ]
        )
    }

    static func notifyPendingFileOperation() {
        NotificationCenter.default.post(
            name: pendingFileOperationNotification,
            object: nil,
            userInfo: nil)
    }
}
