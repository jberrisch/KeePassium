//  KeePassium Password Manager
//  Copyright © 2018–2019 Andrei Popleteev <info@keepassium.com>
//
//  This program is free software: you can redistribute it and/or modify it
//  under the terms of the GNU General Public License version 3 as published
//  by the Free Software Foundation: https://www.gnu.org/licenses/).
//  For commercial licensing, please contact the author.

import Foundation

/// Handles persistance of `DatabaseSettings` instances.
public class DatabaseSettingsManager {
    public static let shared = DatabaseSettingsManager()
    
    init() {
        // left empty
    }
    
    /// Returns an instance of settings for the given database.
    /// If nothing has been stored, returns `nil`.
    public func getSettings(for databaseRef: URLReference) -> DatabaseSettings? {
        guard let databaseDescriptor = databaseRef.getDescriptor() else {
            Diag.warning("Cannot get database descriptor")
            return nil
        }

        do {
            if let dbSettings = try Keychain.shared.getDatabaseSettings(for: databaseDescriptor) { // throws KeychainError
                return dbSettings
            }
            return nil
        } catch {
            Diag.warning(error.localizedDescription)
            return nil
        }
    }
    
    /// Same as `get()`, but if no settings have been set, returns a default instance.
    public func getOrMakeSettings(for databaseRef: URLReference) -> DatabaseSettings {
        if let storedSettings = getSettings(for: databaseRef) {
            return storedSettings
        }
        let defaultResult = DatabaseSettings(for: databaseRef)
        return defaultResult
    }
    
    public func setSettings(_ dbSettings: DatabaseSettings, for databaseRef: URLReference) {
        guard let databaseDescriptor = databaseRef.getDescriptor() else {
            Diag.warning("Cannot get database descriptor")
            return
        }
        
        do {
            try Keychain.shared.setDatabaseSettings(dbSettings, for: databaseDescriptor) // throws KeychainError
        } catch {
            Diag.error(error.localizedDescription)
        }
    }
    
    public func updateSettings(for databaseRef: URLReference, updater: (DatabaseSettings) -> Void) {
        let dbSettings = getOrMakeSettings(for: databaseRef)
        updater(dbSettings)
        setSettings(dbSettings, for: databaseRef)
    }
    
    /// Removes settings associated with the given database
    /// - Parameters:
    ///   - databaseRef: associated database
    ///   - onlyIfUnused: if true, keep settings if there is another associated database.
    ///     If false, delete settings unconditionally.
    public func removeSettings(for databaseRef: URLReference, onlyIfUnused: Bool) {
        guard let databaseDescriptor = databaseRef.getDescriptor() else {
            Diag.warning("Cannot get database descriptor")
            return
        }
        
        if onlyIfUnused {
            let allDatabaseDescriptors = FileKeeper.shared.getAllReferences(
                fileType: .database,
                includeBackup: true)
                .map { $0.getDescriptor() }
            if allDatabaseDescriptors.contains(databaseDescriptor) {
                // there is a database that uses these settings, so keep them
                return
            }
        }
        
        do {
            try Keychain.shared.removeDatabaseSettings(for: databaseDescriptor)
        } catch {
            Diag.error(error.localizedDescription)
        }
    }
    
    public func forgetAllKeyFiles() {
        let allDatabaseRefs = FileKeeper.shared.getAllReferences(
            fileType: .database,
            includeBackup: true
        )
        for dbRef in allDatabaseRefs {
            guard let dbSettings = getSettings(for: dbRef) else { continue }
            dbSettings.setAssociatedKeyFile(nil)
            setSettings(dbSettings, for: dbRef)
        }
    }
    
    public func forgetAllHardwareKeys() {
        let allDatabaseRefs = FileKeeper.shared.getAllReferences(
            fileType: .database,
            includeBackup: true
        )
        for dbRef in allDatabaseRefs {
            guard let dbSettings = getSettings(for: dbRef) else { continue }
            dbSettings.setAssociatedYubiKey(nil)
            setSettings(dbSettings, for: dbRef)
        }
    }

    /// Removes the given key file reference from any database associations.
    public func removeAllAssociations(of keyFileRef: URLReference) {
        guard let keyFileDescriptor = keyFileRef.getDescriptor() else { return }
        let allDatabaseRefs = FileKeeper.shared.getAllReferences(
            fileType: .database,
            includeBackup: true
        )
        
        for dbRef in allDatabaseRefs {
            guard let dbSettings = getSettings(for: dbRef) else { continue }
            if let associatedKeyFile = dbSettings.associatedKeyFile,
                associatedKeyFile.getDescriptor() == keyFileDescriptor
            {
                dbSettings.setAssociatedKeyFile(nil)
                setSettings(dbSettings, for: dbRef)
            }
        }
    }
    
    public func eraseAllMasterKeys() {
        let allDatabaseRefs = FileKeeper.shared.getAllReferences(
            fileType: .database,
            includeBackup: true
        )
        for dbRef in allDatabaseRefs {
            guard let dbSettings = getSettings(for: dbRef) else { continue }
            dbSettings.clearMasterKey()
            setSettings(dbSettings, for: dbRef)
        }
    }
}
