//  KeePassium Password Manager
//  Copyright © 2018–2019 Andrei Popleteev <info@keepassium.com>
// 
//  This program is free software: you can redistribute it and/or modify it
//  under the terms of the GNU General Public License version 3 as published
//  by the Free Software Foundation: https://www.gnu.org/licenses/).
//  For commercial licensing, please contact the author.

import Foundation

public protocol SettingsObserver: class {
    /// Called whenever settings have changed.
    /// Make sure to `subscribeToSettingsNotifications` first.
    func settingsDidChange(key: Settings.Keys)
}

public class SettingsNotifications {
    private weak var observer: SettingsObserver?
    
    public init(observer: SettingsObserver) {
        self.observer = observer
    }
    
    /// Starts observing notifications about settings changes.
    public func startObserving() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(settingsDidChange(_:)),
            name: Settings.Notifications.settingsChanged,
            object: nil)
    }
    
    /// Stops observing notifications about settings changes.
    public func stopObserving() {
        NotificationCenter.default.removeObserver(
            self,
            name: Settings.Notifications.settingsChanged,
            object: nil)
    }
    
    @objc private func settingsDidChange(_ notification: Notification) {
        guard let userInfo = notification.userInfo,
            let keyString = userInfo[Settings.Notifications.userInfoKey] as? String else { return }
        
        guard let key = Settings.Keys(rawValue: keyString) else {
            assertionFailure("Unknown Settings.Keys value: \(keyString)")
            return
        }
        observer?.settingsDidChange(key: key)
    }
}

/// Singleton for KeePassium app settings.
public class Settings {
    public static let latestVersion = 3
    public static let current = Settings()
    
    public enum Keys: String {
        case testEnvironment
        case settingsVersion
        case firstLaunchTimestamp
        
        // Database list
        case filesSortOrder
        case backupFilesVisible

        // Database unlock
        case startupDatabase
        case rememberDatabaseKey
        case keepKeyFileAssociations
        case keepHardwareKeyAssociations
        case hardwareKeyAssociations

        // AppLock and timeouts
        case appLockEnabled
        case biometricAppLockEnabled
        case lockAllDatabasesOnFailedPasscode
        case recentUserActivityTimestamp
        case appLockTimeout
        case databaseLockTimeout
        case clipboardTimeout

        // Database content
        case startWithSearch
        case groupSortOrder
        case entryListDetail
        case entryViewerPage

        // Backup
        case backupDatabaseOnSave
        case backupKeepingDuration
        
        // AutoFill
        case autoFillFinishedOK
        case copyTOTPOnAutoFill
        case autoFillPerfectMatch
        
        // Haptic feedback
        case hapticFeedbackEnabled
        
        // Password generator
        case passwordGeneratorLength
        case passwordGeneratorIncludeLowerCase
        case passwordGeneratorIncludeUpperCase
        case passwordGeneratorIncludeSpecials
        case passwordGeneratorIncludeDigits
        case passwordGeneratorIncludeLookAlike
        case passcodeKeyboardType
    }

    /// Notification constants
    fileprivate enum Notifications {
        static let settingsChanged = Notification.Name("com.keepassium.SettingsChanged")
        static let userInfoKey = "changedKey" // userInfo dict key - which Settings.Keys was changed
    }

    // MARK: - Internal types
    
    public enum AppLockTimeout: Int {
        /// The start event of the timeout
        public enum TriggerMode {
            case userIdle
            case appMinimized
        }
        
        public static let allValues = [
            immediately,
            // after1second — excluded, as it is used as internal replacement for `immediately`
            after3seconds, after15seconds, after30seconds,
            after1minute, after2minutes, after5minutes]
        
        case never = -1 // left for backward compatibility
        case immediately = 0
        case after1second = 1 // workaround for some bugs with `immediately`
        case after3seconds = 3
        case after15seconds = 15
        case after30seconds = 30
        case after1minute = 60
        case after2minutes = 120
        case after5minutes = 300
        
        public var seconds: Int {
            return self.rawValue
        }
        
        public var triggerMode: TriggerMode {
            switch self {
            case .never,
                 .immediately,
                 .after1second,
                 .after3seconds:
                return .appMinimized
            default:
                return .userIdle
            }
        }
        
        public var fullTitle: String {
            switch self {
            case .never:
                return NSLocalizedString(
                    "[Settings/AppLockTimeout/fullTitle] Never",
                    bundle: Bundle.framework,
                    value: "Never",
                    comment: "An option in Settings. Will be shown as 'App Lock: Timeout: Never'")
            case .immediately:
                return NSLocalizedString(
                    "[Settings/AppLockTimeout/fullTitle] Immediately",
                    bundle: Bundle.framework,
                    value: "Immediately",
                    comment: "An option in Settings. Will be shown as 'App Lock: Timeout: Immediately'")
            default:
                let formatter = DateComponentsFormatter()
                formatter.allowedUnits = [.hour, .minute, .second]
                formatter.collapsesLargestUnit = true
                formatter.maximumUnitCount = 2
                formatter.unitsStyle = .full
                guard let result = formatter.string(from: TimeInterval(self.rawValue)) else {
                    assertionFailure()
                    return "?"
                }
                return result
            }
        }
        public var shortTitle: String {
            switch self {
            case .never:
                return NSLocalizedString(
                    "[Settings/AppLockTimeout/shortTitle] Never",
                    bundle: Bundle.framework,
                    value: "Never",
                    comment: "An option in Settings. Will be shown as 'App Lock: Timeout: Never'")
            case .immediately:
                return NSLocalizedString(
                    "[Settings/AppLockTimeout/shortTitle] Immediately",
                    bundle: Bundle.framework,
                    value: "Immediately",
                    comment: "An option in Settings. Will be shown as 'App Lock: Timeout: Immediately'")
            default:
                let formatter = DateComponentsFormatter()
                formatter.allowedUnits = [.hour, .minute, .second]
                formatter.collapsesLargestUnit = true
                formatter.maximumUnitCount = 2
                formatter.unitsStyle = .brief
                guard let result = formatter.string(from: TimeInterval(self.rawValue)) else {
                    assertionFailure()
                    return "?"
                }
                return result
            }
        }
        public var description: String? {
            switch triggerMode {
            case .appMinimized:
                return NSLocalizedString(
                    "[Settings/AppLockTimeout/description] After leaving the app",
                    bundle: Bundle.framework,
                    value: "After leaving the app",
                    comment: "A description/subtitle for Settings/AppLock/Timeout options that trigger when the app is minimized. For example: 'AppLock Timeout: 3 seconds (After leaving the app)")
            case .userIdle:
                return NSLocalizedString(
                    "[Settings/AppLockTimeout/description] After last interaction",
                    bundle: Bundle.framework,
                    value: "After last interaction",
                    comment: "A description/subtitle for Settings/AppLockTimeout options that trigger when the user has been idle for a while. For example: 'AppLock Timeout: 3 seconds (After last interaction)")
            }
        }
    }

    public enum DatabaseLockTimeout: Int, Comparable {
        public static let allValues = [
            immediately, /*after5seconds, after15seconds, */after30seconds,
            after1minute, after2minutes, after5minutes, after10minutes,
            after30minutes, after1hour, after2hours, after4hours, after8hours,
            after24hours, never]
        case never = -1
        case immediately = 0
        case after5seconds = 5
        case after15seconds = 15
        case after30seconds = 30
        case after1minute = 60
        case after2minutes = 120
        case after5minutes = 300
        case after10minutes = 600
        case after30minutes = 1800
        case after1hour = 3600
        case after2hours = 7200
        case after4hours = 14400
        case after8hours = 28800
        case after24hours = 86400

        public var seconds: Int {
            return self.rawValue
        }
        
        public static func < (a: DatabaseLockTimeout, b: DatabaseLockTimeout) -> Bool {
            return a.seconds < b.seconds
        }
        
        public var fullTitle: String {
            switch self {
            case .never:
                return NSLocalizedString(
                    "[Settings/DatabaseLockTimeout/fullTitle] Never",
                    bundle: Bundle.framework,
                    value: "Never",
                    comment: "An option in Settings. Will be shown as 'Database Lock: Timeout: Never'")
            case .immediately:
                return NSLocalizedString(
                    "[Settings/DatabaseLockTimeout/fullTitle] Immediately",
                    bundle: Bundle.framework,
                    value: "Immediately",
                    comment: "An option in Settings. Will be shown as 'Database Lock: Timeout: Immediately'")
            default:
                let formatter = DateComponentsFormatter()
                formatter.allowedUnits = [.hour, .minute, .second]
                formatter.collapsesLargestUnit = true
                formatter.maximumUnitCount = 2
                formatter.unitsStyle = .full
                guard let result = formatter.string(from: TimeInterval(self.rawValue)) else {
                    assertionFailure()
                    return "?"
                }
                return result
            }
        }
        public var shortTitle: String {
            switch self {
            case .never:
                return NSLocalizedString(
                    "[Settings/DatabaseLockTimeout/shortTitle] Never",
                    bundle: Bundle.framework,
                    value: "Never",
                    comment: "An option in Settings. Will be shown as 'Database Lock: Timeout: Never'")
            case .immediately:
                return NSLocalizedString(
                    "[Settings/DatabaseLockTimeout/shortTitle] Immediately",
                    bundle: Bundle.framework,
                    value: "Immediately",
                    comment: "An option in Settings. Will be shown as 'Database Lock: Timeout: Immediately'")
            default:
                let formatter = DateComponentsFormatter()
                formatter.allowedUnits = [.hour, .minute, .second]
                formatter.collapsesLargestUnit = true
                formatter.maximumUnitCount = 2
                formatter.unitsStyle = .brief
                guard let result = formatter.string(from: TimeInterval(self.rawValue)) else {
                    assertionFailure()
                    return "?"
                }
                return result
            }
        }
        public var description: String? {
            switch self {
            case .immediately:
                return NSLocalizedString(
                    "[Settings/DatabaseLockTimeout/description] When leaving the app",
                    bundle: Bundle.framework,
                    value: "When leaving the app",
                    comment: "A description/subtitle for the 'DatabaseLockTimeout: Immediately'.")
            default:
                return nil
            }
        }
    }
    
    public enum ClipboardTimeout: Int {
        public static let allValues = [
            after10seconds, after20seconds, after30seconds, after1minute, after2minutes,
            after3minutes, after5minutes, after10minutes, after20minutes, never]
        case never = -1
        case after10seconds = 10
        case after20seconds = 20
        case after30seconds = 30
        case after1minute = 60
        case after2minutes = 120
        case after3minutes = 180
        case after5minutes = 300
        case after10minutes = 600
        case after20minutes = 1200

        public var seconds: Int {
            return self.rawValue
        }
        
        public var fullTitle: String {
            switch self {
            case .never:
                return NSLocalizedString(
                    "[Settings/ClipboardTimeout/fullTitle] Never",
                    bundle: Bundle.framework,
                    value: "Never",
                    comment: "An option in Settings. Will be shown as 'Clipboard Timeout: Never'")
            default:
                let formatter = DateComponentsFormatter()
                formatter.allowedUnits = [.hour, .minute, .second]
                formatter.collapsesLargestUnit = true
                formatter.maximumUnitCount = 2
                formatter.unitsStyle = .full
                guard let result = formatter.string(from: TimeInterval(self.rawValue)) else {
                    assertionFailure()
                    return "?"
                }
                return result
            }
        }
        public var shortTitle: String {
            switch self {
            case .never:
                return NSLocalizedString(
                    "[Settings/ClipboardTimeout/shortTitle] Never",
                    bundle: Bundle.framework,
                    value: "Never",
                    comment: "An option in Settings. Will be shown as 'Clipboard Timeout: Never'")
            default:
                let formatter = DateComponentsFormatter()
                formatter.allowedUnits = [.hour, .minute, .second]
                formatter.collapsesLargestUnit = true
                formatter.maximumUnitCount = 2
                formatter.unitsStyle = .brief
                guard let result = formatter.string(from: TimeInterval(self.rawValue)) else {
                    assertionFailure()
                    return "?"
                }
                return result
            }
        }
    }
    
    /// Allowed age of backup files
    public enum BackupKeepingDuration: Int {
        public static let allValues: [BackupKeepingDuration] = [
            .forever, _1year, _6months, _4weeks, _1week, _1day, _4hours, _1hour
        ]
        case _1hour = 3600
        case _4hours = 14400
        case _1day = 86400
        case _1week = 604_800
        case _4weeks = 2_419_200
        case _6months = 15_552_000
        case _1year = 31_536_000
        case forever

        public var seconds: TimeInterval {
            switch self {
            case .forever:
                return TimeInterval.infinity
            default:
                return TimeInterval(self.rawValue)
            }
        }
        
        public var shortTitle: String {
            switch self {
            case .forever:
                return NSLocalizedString(
                    "[Settings/BackupKeepingDuration/shortTitle] Forever",
                    bundle: Bundle.framework,
                    value: "Forever",
                    comment: "An option in Settings. Please keep it short. Will be shown as 'Keep Backup Files: Forever'")
            default:
                let formatter = DateComponentsFormatter()
                formatter.allowedUnits = [.year, .month, .day, .hour]
                formatter.collapsesLargestUnit = true
                formatter.maximumUnitCount = 1
                formatter.unitsStyle = .full
                guard let result = formatter.string(from: TimeInterval(self.rawValue)) else {
                    assertionFailure()
                    return "?"
                }
                return result
            }
        }
        
        public var fullTitle: String {
            return shortTitle
        }
    }
    
    /// Info to show in the second line of entry lsists
    public enum EntryListDetail: Int {
        public static let allValues = [none, userName, password, url, notes, lastModifiedDate]
        
        case none
        case userName
        case password
        case url
        case notes
        case lastModifiedDate
        
        public var longTitle: String {
            switch self {
            case .none:
                return NSLocalizedString(
                    "[Settings/EntryListDetail/longTitle] None",
                    bundle: Bundle.framework,
                    value: "None",
                    comment: "An option in Group Viewer settings. Will be shown as 'Entry Subtitle: None', meanining that no entry details will be shown in any lists.")
            case .userName:
                return NSLocalizedString(
                    "[Settings/EntryListDetail/longTitle] User Name",
                    bundle: Bundle.framework,
                    value: "User Name",
                    comment: "An option in Group Viewer settings. It refers to login information rather than person's name. Will be shown as 'Entry Subtitle: User Name'.")
            case .password:
                return NSLocalizedString(
                    "[Settings/EntryListDetail/longTitle] Password",
                    bundle: Bundle.framework,
                    value: "Password",
                    comment: "An option in Group Viewer settings. Will be shown as 'Entry Subtitle: Password'.")
            case .url:
                return NSLocalizedString(
                    "[Settings/EntryListDetail/longTitle] URL",
                    bundle: Bundle.framework,
                    value: "URL",
                    comment: "An option in Group Viewer settings. Will be shown as 'Entry Subtitle: URL'.")
            case .notes:
                return NSLocalizedString(
                    "[Settings/EntryListDetail/longTitle] Notes",
                    bundle: Bundle.framework,
                    value: "Notes",
                    comment: "An option in Group Viewer settings. Refers to comments/notes field of the entry. Will be shown as 'Entry Subtitle: Notes'.")
            case .lastModifiedDate:
                return NSLocalizedString(
                    "[Settings/EntryListDetail/longTitle] Last Modified Date",
                    bundle: Bundle.framework,
                    value: "Last Modified Date",
                    comment: "An option in Group Viewer settings. Refers fo the most recent time when the entry was modified. Will be shown as 'Entry Subtitle: Last Modified Date'.")
            }
        }
    }

    /// Sort order of group lists
    public enum GroupSortOrder: Int {
        public static let allValues = [
            noSorting,
            nameAsc, nameDesc,
            creationTimeDesc, creationTimeAsc,
            modificationTimeDesc, modificationTimeAsc]
        
        case noSorting
        case nameAsc
        case nameDesc
        case creationTimeAsc
        case creationTimeDesc
        case modificationTimeAsc
        case modificationTimeDesc
        
        public var longTitle: String {
            switch self {
            case .noSorting:
                return NSLocalizedString(
                    "[GroupSortOrder/longTitle] No Sorting",
                    bundle: Bundle.framework,
                    value: "No Sorting",
                    comment: "An option in Group Viewer settings. Example: 'Sort Order: No Sorting'")
            case .nameAsc:
                return NSLocalizedString(
                    "[GroupSortOrder/longTitle] By Title (A..Z)",
                    bundle: Bundle.framework,
                    value: "By Title (A..Z)",
                    comment: "An option in Group Viewer settings. Example: 'Sort Order: By Title (A..Z)'")
            case .nameDesc:
                return NSLocalizedString(
                    "[GroupSortOrder/longTitle] By Title (Z..A)",
                    bundle: Bundle.framework,
                    value: "By Title (Z..A)",
                    comment: "An option in Group Viewer settings. Example: 'Sort Order: By Title (Z..A)'")
            case .creationTimeAsc:
                return NSLocalizedString(
                    "[GroupSortOrder/longTitle] By Creation Date (Old..New)",
                    bundle: Bundle.framework,
                    value: "By Creation Date (Old..New)",
                    comment: "An option in Group Viewer settings. Example: 'Sort Order: By Creation Date (Old..New)'")
            case .creationTimeDesc:
                return NSLocalizedString(
                    "[GroupSortOrder/longTitle] By Creation Date (New..Old)",
                    bundle: Bundle.framework,
                    value: "By Creation Date (New..Old)",
                    comment: "An option in Group Viewer settings. Example: 'Sort Order: By Creation Date (New..Old)'")
            case .modificationTimeAsc:
                return NSLocalizedString(
                    "[GroupSortOrder/longTitle] By Modification Date (Old..New)",
                    bundle: Bundle.framework,
                    value: "By Modification Date (Old..New)",
                    comment: "An option in Group Viewer settings. Example: 'Sort Order: By Modification Date (Old..New)'")
            case .modificationTimeDesc:
                return NSLocalizedString(
                    "[GroupSortOrder/longTitle] By Modification Date (New..Old)",
                    bundle: Bundle.framework,
                    value: "By Modification Date (New..Old)",
                    comment: "An option in Group Viewer settings. Example: 'Sort Order: By Modification Date (New..Old)'")
            }
        }
        /// Comparator function for sorting
        public func compare(_ group1: Group, _ group2: Group) -> Bool {
            switch self {
            case .noSorting:
                return false
            case .nameAsc:
                return group1.name.localizedStandardCompare(group2.name) == .orderedAscending
            case .nameDesc:
                return group1.name.localizedStandardCompare(group2.name) == .orderedDescending
            case .creationTimeAsc:
                return group1.creationTime.compare(group2.creationTime) == .orderedAscending
            case .creationTimeDesc:
                return group1.creationTime.compare(group2.creationTime) == .orderedDescending
            case .modificationTimeAsc:
                return group1.lastModificationTime.compare(group2.lastModificationTime) == .orderedAscending
            case .modificationTimeDesc:
                return group1.lastModificationTime.compare(group2.lastModificationTime) == .orderedDescending
            }
        }
        public func compare(_ entry1: Entry, _ entry2: Entry) -> Bool {
            switch self {
            case .noSorting:
                return false
            case .nameAsc:
                return entry1.title.localizedStandardCompare(entry2.title) == .orderedAscending
            case .nameDesc:
                return entry1.title.localizedStandardCompare(entry2.title) == .orderedDescending
            case .creationTimeAsc:
                return entry1.creationTime.compare(entry2.creationTime) == .orderedAscending
            case .creationTimeDesc:
                return entry1.creationTime.compare(entry2.creationTime) == .orderedDescending
            case .modificationTimeAsc:
                return entry1.lastModificationTime.compare(entry2.lastModificationTime) == .orderedAscending
            case .modificationTimeDesc:
                return entry1.lastModificationTime.compare(entry2.lastModificationTime) == .orderedDescending
            }
        }
    }
    
    /// Sort order of file lists
    public enum FilesSortOrder: Int {
        public static let allValues = [
            noSorting,
            nameAsc, nameDesc,
            creationTimeDesc, creationTimeAsc,
            modificationTimeDesc, modificationTimeAsc]
        
        case noSorting
        case nameAsc
        case nameDesc
        case creationTimeAsc
        case creationTimeDesc
        case modificationTimeAsc
        case modificationTimeDesc
        
        public var longTitle: String {
            switch self {
            case .noSorting:
                return NSLocalizedString(
                    "[FilesSortOrder/longTitle] No Sorting",
                    bundle: Bundle.framework,
                    value: "No Sorting",
                    comment: "A sorting option for a list of files. Example: 'Sort Order: No Sorting'")
            case .nameAsc:
                return NSLocalizedString(
                    "[FilesSortOrder/longTitle] Name (A..Z)",
                    bundle: Bundle.framework,
                    value: "Name (A..Z)",
                    comment: "A sorting option for a list of files, by file name. Example: 'Sort Order: Name (A..Z)'")
            case .nameDesc:
                return NSLocalizedString(
                    "[FilesSortOrder/longTitle] Name (Z..A)",
                    bundle: Bundle.framework,
                    value: "Name (Z..A)",
                    comment: "A sorting option for a list of files, by file name. Example: 'Sort Order: Name (Z..A)'")
            case .creationTimeAsc:
                return NSLocalizedString(
                    "[FilesSortOrder/longTitle] Creation Date (Oldest First)",
                    bundle: Bundle.framework,
                    value: "Creation Date (Oldest First)",
                    comment: "A sorting option for a list of files, by file creation date. Example: 'Sort Order: Creation Date (Oldest First)'")
            case .creationTimeDesc:
                return NSLocalizedString(
                    "[FilesSortOrder/longTitle] Creation Date (Recent First)",
                    bundle: Bundle.framework,
                    value: "Creation Date (Recent First)",
                    comment: "A sorting option for a list of files, by file creation date. Example: 'Sort Order: Creation Date (Recent First)'")
            case .modificationTimeAsc:
                return NSLocalizedString(
                    "[FilesSortOrder/longTitle] Modification Date (Oldest First)",
                    bundle: Bundle.framework,
                    value: "Modification Date (Oldest First)",
                    comment: "A sorting option for a list of files, by file's last modification date. Example: 'Sort Order: Modification Date (Oldest First)'")
            case .modificationTimeDesc:
                return NSLocalizedString(
                    "[FilesSortOrder/longTitle] Modification Date (Recent First)",
                    bundle: Bundle.framework,
                    value: "Modification Date (Recent First)",
                    comment: "A sorting option for a list of files, by file's last modification date. Example: 'Sort Order: Modification Date (Recent First)'")
            }
        }

        /// Comparator function for sorting.
        public func compare(_ lhs: URLReference, _ rhs: URLReference) -> Bool {
            switch self {
            case .noSorting:
                return false
            case .nameAsc:
                return lhs.info.fileName.localizedCaseInsensitiveCompare(rhs.info.fileName) == .orderedAscending
            case .nameDesc:
                return lhs.info.fileName.localizedCaseInsensitiveCompare(rhs.info.fileName) == .orderedDescending
            case .creationTimeAsc:
                guard let date1 = lhs.info.creationDate,
                    let date2 = rhs.info.creationDate else { return false }
                return date1.compare(date2) == .orderedAscending
            case .creationTimeDesc:
                guard let date1 = lhs.info.creationDate,
                    let date2 = rhs.info.creationDate else { return false }
                return date1.compare(date2) == .orderedDescending
            case .modificationTimeAsc:
                guard let date1 = lhs.info.modificationDate,
                    let date2 = rhs.info.modificationDate else { return false }
                return date1.compare(date2) == .orderedAscending
            case .modificationTimeDesc:
                guard let date1 = lhs.info.modificationDate,
                    let date2 = rhs.info.modificationDate else { return false }
                return date1.compare(date2) == .orderedDescending
            }
        }
    }
    
    /// Type of keyboard to use for App Lock passcode
    public enum PasscodeKeyboardType: Int {
        public static let allValues = [numeric, alphanumeric]
        case numeric
        case alphanumeric
        public var title: String {
            switch self {
            case .numeric:
                return NSLocalizedString(
                    "[AppLock/Passcode/KeyboardType/title] Numeric",
                    bundle: Bundle.framework,
                    value: "Numeric",
                    comment: "Type of keyboard to show for App Lock passcode: digits only (PIN code).")
            case .alphanumeric:
                return NSLocalizedString(
                    "[AppLock/Passcode/KeyboardType/title] Alphanumeric",
                    bundle: Bundle.framework,
                    value: "Alphanumeric",
                    comment: "Type of keyboard to show for App Lock passcode: letters and digits.")
            }
        }
    }
    
    // MARK: - Internal
    
    /// True iff running in simulator or in TestFlight.
    public private(set) var isTestEnvironment: Bool
    
    /// True iff the app has never been launched before.
    public var isFirstLaunch: Bool { return _isFirstLaunch }
    
    public var settingsVersion: Int {
        get {
            let storedVersion = UserDefaults.appGroupShared
                .object(forKey: Keys.settingsVersion.rawValue)
                as? Int
            return storedVersion ?? 0
        }
        set {
            let oldValue = settingsVersion
            UserDefaults.appGroupShared.set(newValue, forKey: Keys.settingsVersion.rawValue)
            if newValue != oldValue {
                postChangeNotification(changedKey: Keys.settingsVersion)
            }
        }
    }
    
    /// Timestamp when the app was first launched (since install)
    public var firstLaunchTimestamp: Date {
        get {
            if let storedTimestamp = UserDefaults.appGroupShared
                .object(forKey: Keys.firstLaunchTimestamp.rawValue)
                as? Date
            {
                return storedTimestamp
            } else {
                let firstLaunchTimestamp = Date.now
                UserDefaults.appGroupShared.set(
                    firstLaunchTimestamp,
                    forKey: Keys.firstLaunchTimestamp.rawValue)
                return firstLaunchTimestamp
            }
        }
    }
    
#if DEBUG
    /// To be used for debug.
    public func resetFirstLaunchTimestampToNow() {
        UserDefaults.appGroupShared.set(
            Date.now,
            forKey: Keys.firstLaunchTimestamp.rawValue)
    }
#endif

    // MARK: - Database list
    
    /// Sort order for the file lists
    public var filesSortOrder: FilesSortOrder {
        get {
            if let rawValue = UserDefaults.appGroupShared
                .object(forKey: Keys.filesSortOrder.rawValue) as? Int,
                let sortOrder = FilesSortOrder(rawValue: rawValue)
            {
                return sortOrder
            }
            return FilesSortOrder.noSorting
        }
        set {
            let oldValue = filesSortOrder
            UserDefaults.appGroupShared.set(newValue.rawValue, forKey: Keys.filesSortOrder.rawValue)
            if newValue != oldValue {
                postChangeNotification(changedKey: Keys.filesSortOrder)
            }
        }
    }
    
    /// Whether to show backup files in file lists
    public var isBackupFilesVisible: Bool {
        get {
            let stored = UserDefaults.appGroupShared
                .object(forKey: Keys.backupFilesVisible.rawValue)
                as? Bool
            return stored ?? false
        }
        set {
            updateAndNotify(
                oldValue: isBackupFilesVisible,
                newValue: newValue,
                key: .backupFilesVisible)
        }
    }
    
    // MARK: - Database unlock
    
    /// Last used/default database file to open on app launch.
    public var startupDatabase: URLReference? {
        get {
            if let data = UserDefaults.appGroupShared.data(forKey: Keys.startupDatabase.rawValue) {
                return URLReference.deserialize(from: data)
            } else {
                return nil
            }
        }
        set {
            let oldValue = startupDatabase
            UserDefaults.appGroupShared.set(
                newValue?.serialize(),
                forKey: Keys.startupDatabase.rawValue)
            if newValue != oldValue {
                postChangeNotification(changedKey: Keys.startupDatabase)
            }
        }
    }
    
    /// Whether to store database's key in keychain after unlock
    public var isRememberDatabaseKey: Bool {
        get {
            let stored = UserDefaults.appGroupShared
                .object(forKey: Keys.rememberDatabaseKey.rawValue)
                as? Bool
            return stored ?? true
        }
        set {
            updateAndNotify(
                oldValue: isRememberDatabaseKey,
                newValue: newValue,
                key: .rememberDatabaseKey)
        }
    }
    
    /// Should we keep track of which key file is used with which database?
    public var isKeepKeyFileAssociations: Bool {
        get {
            if contains(key: Keys.keepKeyFileAssociations) {
                return UserDefaults.appGroupShared.bool(forKey: Keys.keepKeyFileAssociations.rawValue)
            } else {
                return true
            }
        }
        set {
            let oldValue = isKeepKeyFileAssociations
            UserDefaults.appGroupShared.set(newValue, forKey: Keys.keepKeyFileAssociations.rawValue)
            if !newValue {
                DatabaseSettingsManager.shared.forgetAllKeyFiles()
            }
            if newValue != oldValue {
                postChangeNotification(changedKey: Keys.keepKeyFileAssociations)
            }
        }
    }
    
    /// Should we keep track of which hardware key is used with the database?
    public var isKeepHardwareKeyAssociations: Bool {
        get {
            if contains(key: Keys.keepHardwareKeyAssociations) {
                return UserDefaults.appGroupShared.bool(forKey: Keys.keepHardwareKeyAssociations.rawValue)
            } else {
                return true
            }
        }
        set {
            let oldValue = isKeepHardwareKeyAssociations
            UserDefaults.appGroupShared.set(newValue, forKey: Keys.keepHardwareKeyAssociations.rawValue)
            if !newValue {
                DatabaseSettingsManager.shared.forgetAllHardwareKeys()
            }
            if newValue != oldValue {
                postChangeNotification(changedKey: Keys.keepHardwareKeyAssociations)
            }
        }
    }
    
    // MARK: - AppLock and other timeouts
    
    public var isAppLockEnabled: Bool {
        get {
            let stored = UserDefaults.appGroupShared
                .object(forKey: Keys.appLockEnabled.rawValue)
                as? Bool
            return stored ?? false
        }
        set {
            updateAndNotify(
                oldValue: isAppLockEnabled,
                newValue: newValue,
                key: .appLockEnabled)
        }
    }
    
    /// Whether the user can use TouchID/FaceID to unlock the app
    public var isBiometricAppLockEnabled: Bool {
        get {
            let stored = UserDefaults.appGroupShared
                .object(forKey: Keys.biometricAppLockEnabled.rawValue)
                as? Bool
            return stored ?? true
        }
        set {
            updateAndNotify(
                oldValue: isBiometricAppLockEnabled,
                newValue: newValue,
                key: .biometricAppLockEnabled)
        }
    }
    
    /// Whether to clear all database keys from keychain
    /// after a wrong AppLock passcode has been entered.
    public var isLockAllDatabasesOnFailedPasscode: Bool {
        get {
            let stored = UserDefaults.appGroupShared
                .object(forKey: Keys.lockAllDatabasesOnFailedPasscode.rawValue)
                as? Bool
            return stored ?? true
        }
        set {
            updateAndNotify(
                oldValue: isLockAllDatabasesOnFailedPasscode,
                newValue: newValue,
                key: .lockAllDatabasesOnFailedPasscode)
        }
    }
    
    /// Timestamp of most recent user activity event (touching or typing).
    public var recentUserActivityTimestamp: Date {
        get {
            if let storedTimestamp = UserDefaults.appGroupShared
                .object(forKey: Keys.recentUserActivityTimestamp.rawValue)
                as? Date
            {
                return storedTimestamp
            }
            return Date.now
        }
        set {
            if contains(key: Keys.recentUserActivityTimestamp) {
                // We'll ignore sub-second differences, just to avoid too frequent writes.
                // (They are probably cached, but anyway.)
                let oldWholeSeconds = floor(recentUserActivityTimestamp.timeIntervalSinceReferenceDate)
                let newWholeSeconds = floor(newValue.timeIntervalSinceReferenceDate)
                if newWholeSeconds == oldWholeSeconds {
                    return
                }
            }
            UserDefaults.appGroupShared.set(
                newValue,
                forKey: Keys.recentUserActivityTimestamp.rawValue)
            postChangeNotification(changedKey: Keys.recentUserActivityTimestamp)
        }
    }
    
    /// Instance var, set externally by SystemIssueDetector
    public var isAffectedByAutoFillFaceIDLoop_iOS_13_1_3 = false
    
    /// Workaround for infinite Face ID lock on iOS 13.1.3 (and higher)
    /// (https://github.com/keepassium/KeePassium/issues/74)
    /// Converts immediate timeout to a 1-second one.
    public func maybeFixAutoFillFaceIDLoop_iOS_13_1_3(_ timeout: AppLockTimeout) -> AppLockTimeout {
        if isAffectedByAutoFillFaceIDLoop_iOS_13_1_3 && timeout == .immediately {
            return .after1second
        } else {
            return timeout
        }
    }
    
    /// Timeout for automatically locking the app, in seconds.
    public var appLockTimeout: AppLockTimeout {
        get {
            if let rawValue = UserDefaults.appGroupShared
                .object(forKey: Keys.appLockTimeout.rawValue) as? Int,
                let timeout = AppLockTimeout(rawValue: rawValue)
            {
                return maybeFixAutoFillFaceIDLoop_iOS_13_1_3(timeout)
            }
            return maybeFixAutoFillFaceIDLoop_iOS_13_1_3(AppLockTimeout.immediately)
        }
        set {
            let oldValue = appLockTimeout
            UserDefaults.appGroupShared.set(newValue.rawValue, forKey: Keys.appLockTimeout.rawValue)
            if newValue != oldValue {
                postChangeNotification(changedKey: Keys.appLockTimeout)
            }
        }
    }
    
    /// Timeout for automatically locking the database, in seconds.
    public var databaseLockTimeout: DatabaseLockTimeout {
        get {
            if let rawValue = UserDefaults.appGroupShared
                    .object(forKey: Keys.databaseLockTimeout.rawValue) as? Int,
                let timeout = DatabaseLockTimeout(rawValue: rawValue)
            {
                return timeout
            }
            return DatabaseLockTimeout.never
        }
        set {
            let oldValue = databaseLockTimeout
            UserDefaults.appGroupShared.set(
                newValue.rawValue,
                forKey: Keys.databaseLockTimeout.rawValue)
            if newValue != oldValue {
                postChangeNotification(changedKey: Keys.databaseLockTimeout)
            }
        }
    }
    
    /// Timeout for temporary clipboard content, in seconds.
    public var clipboardTimeout: ClipboardTimeout {
        get {
            if let rawValue = UserDefaults.appGroupShared
                    .object(forKey: Keys.clipboardTimeout.rawValue) as? Int,
                let timeout = ClipboardTimeout(rawValue: rawValue)
            {
                return timeout
            }
            return ClipboardTimeout.after1minute
        }
        set {
            let oldValue = clipboardTimeout
            UserDefaults.appGroupShared.set(newValue.rawValue, forKey: Keys.clipboardTimeout.rawValue)
            if newValue != oldValue {
                postChangeNotification(changedKey: Keys.clipboardTimeout)
            }
        }
    }
    
    // MARK: - Database view
    
    /// Automatically show search bar after opening a database.
    public var isStartWithSearch: Bool {
        get {
            let stored = UserDefaults.appGroupShared
                .object(forKey: Keys.startWithSearch.rawValue)
                as? Bool
            return stored ?? false
        }
        set {
            updateAndNotify(
                oldValue: isStartWithSearch,
                newValue: newValue,
                key: .startWithSearch)
        }
    }
    
    /// Which field to use for entry subtitles in ViewGroupVC
    public var groupSortOrder: GroupSortOrder {
        get {
            if let rawValue = UserDefaults.appGroupShared
                    .object(forKey: Keys.groupSortOrder.rawValue) as? Int,
                let sortOrder = GroupSortOrder(rawValue: rawValue)
            {
                return sortOrder
            }
            return GroupSortOrder.noSorting
        }
        set {
            let oldValue = groupSortOrder
            UserDefaults.appGroupShared.set(newValue.rawValue, forKey: Keys.groupSortOrder.rawValue)
            if newValue != oldValue {
                postChangeNotification(changedKey: Keys.groupSortOrder)
            }
        }
    }

    /// Which field to use for entry subtitles in ViewGroupVC
    public var entryListDetail: EntryListDetail {
        get {
            if let rawValue = UserDefaults.appGroupShared
                .object(forKey: Keys.entryListDetail.rawValue) as? Int,
                let detail = EntryListDetail(rawValue: rawValue)
            {
                return detail
            }
            return EntryListDetail.userName
        }
        set {
            let oldValue = entryListDetail
            UserDefaults.appGroupShared.set(newValue.rawValue, forKey: Keys.entryListDetail.rawValue)
            if newValue != oldValue {
                postChangeNotification(changedKey: Keys.entryListDetail)
            }
        }
    }
    
    /// Last used page/tab of the EntryViewer
    public var entryViewerPage: Int {
        get {
            let storedPage = UserDefaults.appGroupShared
                .object(forKey: Keys.entryViewerPage.rawValue) as? Int
            return storedPage ?? 0
        }
        set {
            updateAndNotify(
                oldValue: entryViewerPage,
                newValue: newValue,
                key: Keys.entryViewerPage)
        }
    }
    
    // MARK: - Backup
    
    /// Whether to create a backup copy everytime database is saved.
    public var isBackupDatabaseOnSave: Bool {
        get {
            let stored = UserDefaults.appGroupShared
                .object(forKey: Keys.backupDatabaseOnSave.rawValue)
                as? Bool
            return stored ?? true
        }
        set {
            updateAndNotify(
                oldValue: isBackupDatabaseOnSave,
                newValue: newValue,
                key: .backupDatabaseOnSave)
        }
    }
    
    /// Maximum allowed age of backup files
    public var backupKeepingDuration: BackupKeepingDuration {
        get {
            if let stored = UserDefaults.appGroupShared
                .object(forKey: Keys.backupKeepingDuration.rawValue) as? Int,
                let timeout = BackupKeepingDuration(rawValue: stored)
            {
                return timeout
            }
            return BackupKeepingDuration.forever
        }
        set {
            let oldValue = backupKeepingDuration
            UserDefaults.appGroupShared.set(
                newValue.rawValue,
                forKey: Keys.backupKeepingDuration.rawValue)
            if newValue != oldValue {
                postChangeNotification(changedKey: Keys.backupKeepingDuration)
            }
        }
    }
    
    // MARK: - AutoFill
    
    /// Is set to `false` while AutoFill is running,
    /// and set to `true` only after a controlled/graceful finish.
    /// If this flag is `false` on AutoFill start,
    /// the extension has previously crashed (likely went out of memory).
    public var isAutoFillFinishedOK: Bool {
        get {
            let stored = UserDefaults.appGroupShared
                .object(forKey: Keys.autoFillFinishedOK.rawValue)
                as? Bool
            return stored ?? true
        }
        set {
            updateAndNotify(
                oldValue: isAutoFillFinishedOK,
                newValue: newValue,
                key: Keys.autoFillFinishedOK)
            
            // `isAutoFillFinishedOK` is written just before a possible out of memory crash,
            // so we must make sure it has actually been written.
            UserDefaults.appGroupShared.synchronize()
        }
    }
    
    /// Whether to copy TOTP when auto-filling an entry.
    public var isCopyTOTPOnAutoFill: Bool {
        get {
            let stored = UserDefaults.appGroupShared
                .object(forKey: Keys.copyTOTPOnAutoFill.rawValue)
                as? Bool
            return stored ?? true
        }
        set {
            updateAndNotify(
                oldValue: isCopyTOTPOnAutoFill,
                newValue: newValue,
                key: .copyTOTPOnAutoFill)
        }
    }

    /// Whether  to choose (fill-in( the perfectly matching entries automatically
    public var autoFillPerfectMatch: Bool {
        get {
            let stored = UserDefaults.appGroupShared
                .object(forKey: Keys.autoFillPerfectMatch.rawValue)
                as? Bool
            return stored ?? true
        }
        set {
            updateAndNotify(
                oldValue: autoFillPerfectMatch,
                newValue: newValue,
                key: .autoFillPerfectMatch)
        }
    }

    /// Whether to play tactile/haptic feedback
    public var isHapticFeedbackEnabled: Bool {
        get {
            let stored = UserDefaults.appGroupShared
                .object(forKey: Keys.hapticFeedbackEnabled.rawValue)
                as? Bool
            return stored ?? true
        }
        set {
            updateAndNotify(
                oldValue: isHapticFeedbackEnabled,
                newValue: newValue,
                key: .hapticFeedbackEnabled)
        }
    }
    
    // MARK: - Password generator
    
    /// Password generator: length of generated passwords
    public var passwordGeneratorLength: Int {
        get {
            let stored = UserDefaults.appGroupShared
                .object(forKey: Keys.passwordGeneratorLength.rawValue)
                as? Int
            return stored ?? PasswordGenerator.defaultLength
        }
        set {
            updateAndNotify(
                oldValue: passwordGeneratorLength,
                newValue: newValue,
                key: .passwordGeneratorLength)
        }
    }
    public var passwordGeneratorIncludeLowerCase: Bool {
        get {
            let stored = UserDefaults.appGroupShared
                .object(forKey: Keys.passwordGeneratorIncludeLowerCase.rawValue)
                as? Bool
            return stored ?? true
        }
        set {
            updateAndNotify(
                oldValue: passwordGeneratorIncludeLowerCase,
                newValue: newValue,
                key: .passwordGeneratorIncludeLowerCase)
        }
    }
    public var passwordGeneratorIncludeUpperCase: Bool {
        get {
            let stored = UserDefaults.appGroupShared
                .object(forKey: Keys.passwordGeneratorIncludeUpperCase.rawValue)
                as? Bool
            return stored ?? true
        }
        set {
            updateAndNotify(
                oldValue: passwordGeneratorIncludeUpperCase,
                newValue: newValue,
                key: .passwordGeneratorIncludeUpperCase)
        }
    }
    public var passwordGeneratorIncludeSpecials: Bool {
        get {
            let stored = UserDefaults.appGroupShared
                .object(forKey: Keys.passwordGeneratorIncludeSpecials.rawValue)
                as? Bool
            return stored ?? true
        }
        set {
            updateAndNotify(
                oldValue: passwordGeneratorIncludeSpecials,
                newValue: newValue,
                key: .passwordGeneratorIncludeSpecials)
        }
    }
    public var passwordGeneratorIncludeDigits: Bool {
        get {
            let stored = UserDefaults.appGroupShared
                .object(forKey: Keys.passwordGeneratorIncludeDigits.rawValue)
                as? Bool
            return stored ?? true
        }
        set {
            updateAndNotify(
                oldValue: passwordGeneratorIncludeDigits,
                newValue: newValue,
                key: .passwordGeneratorIncludeDigits)
        }
    }
    public var passwordGeneratorIncludeLookAlike: Bool {
        get {
            let stored = UserDefaults.appGroupShared
                .object(forKey: Keys.passwordGeneratorIncludeLookAlike.rawValue)
                as? Bool
            return stored ?? false
        }
        set {
            updateAndNotify(
                oldValue: passwordGeneratorIncludeLookAlike,
                newValue: newValue,
                key: .passwordGeneratorIncludeLookAlike)
        }
    }
    
    /// Type of keyboard to show for App Lock passcode.
    public var passcodeKeyboardType: PasscodeKeyboardType {
        get {
            if let rawValue = UserDefaults.appGroupShared
                .object(forKey: Keys.passcodeKeyboardType.rawValue) as? Int,
                let keyboardType = PasscodeKeyboardType(rawValue: rawValue)
            {
                return keyboardType
            }
            return PasscodeKeyboardType.numeric
        }
        set {
            let oldValue = passcodeKeyboardType
            UserDefaults.appGroupShared.set(newValue.rawValue, forKey: Keys.passcodeKeyboardType.rawValue)
            if newValue != oldValue {
                postChangeNotification(changedKey: Keys.passcodeKeyboardType)
            }
        }
    }
    
    // MARK: - Internal vars and methods
    
    private var _isFirstLaunch: Bool
    private init() {
        #if DEBUG
        isTestEnvironment = true
        #else
        if AppGroup.isMainApp {
            let lastPathComp = Bundle.main.appStoreReceiptURL?.lastPathComponent
            isTestEnvironment = lastPathComp == "sandboxReceipt"
            UserDefaults.appGroupShared.set(isTestEnvironment, forKey: Keys.testEnvironment.rawValue)
        } else {
            isTestEnvironment = UserDefaults.appGroupShared
                .object(forKey: Keys.testEnvironment.rawValue) as? Bool
                ?? false
        }
        #endif
        
        let versionInfo = UserDefaults.appGroupShared
            .object(forKey: Keys.settingsVersion.rawValue) as? Int
        _isFirstLaunch = (versionInfo == nil)
    }

    // MARK: - Helper methods
    
    /// Updates stored value, and notifies observers if the new value is different.
    private func updateAndNotify(oldValue: Bool, newValue: Bool, key: Keys) {
        UserDefaults.appGroupShared.set(newValue, forKey: key.rawValue)
        if newValue != oldValue {
            postChangeNotification(changedKey: key)
        }
    }

    /// Updates stored value, and notifies observers if the new value is different.
    private func updateAndNotify(oldValue: Int, newValue: Int, key: Keys) {
        UserDefaults.appGroupShared.set(newValue, forKey: key.rawValue)
        if newValue != oldValue {
            postChangeNotification(changedKey: key)
        }
    }

    /// Checks if given key is present in UserDefaults
    private func contains(key: Keys) -> Bool {
        return UserDefaults.appGroupShared.object(forKey: key.rawValue) != nil
    }

    /// Sends a notification about settigns change.
    fileprivate func postChangeNotification(changedKey: Settings.Keys) {
        NotificationCenter.default.post(
            name: Notifications.settingsChanged,
            object: self,
            userInfo: [
                Notifications.userInfoKey: changedKey.rawValue
            ]
        )
    }
}
