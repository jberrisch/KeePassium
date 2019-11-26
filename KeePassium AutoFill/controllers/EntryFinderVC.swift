//  KeePassium Password Manager
//  Copyright © 2018–2019 Andrei Popleteev <info@keepassium.com>
// 
//  This program is free software: you can redistribute it and/or modify it
//  under the terms of the GNU General Public License version 3 as published
//  by the Free Software Foundation: https://www.gnu.org/licenses/).
//  For commercial licensing, please contact the author.

import KeePassiumLib
import AuthenticationServices

protocol EntryFinderDelegate: class {
    func entryFinder(_ sender: EntryFinderVC, didSelectEntry entry: Entry)
    func entryFinderShouldLockDatabase(_ sender: EntryFinderVC)
}

class EntryFinderCell: UITableViewCell {
    fileprivate static let storyboardID = "EntryFinderCell"
    
    @IBOutlet weak var titleLabel: UILabel!
    @IBOutlet weak var subtitleLabel: UILabel!
    @IBOutlet weak var iconView: UIImageView!
    
    
    fileprivate var entry: Entry? {
        didSet {
            guard let entry = entry else {
                titleLabel?.text = ""
                subtitleLabel?.text = ""
                iconView?.image = nil
                return
            }
            titleLabel?.text = entry.title
            subtitleLabel?.text = entry.userName
            iconView?.image = UIImage.kpIcon(forEntry: entry)
        }
    }
}


class EntryFinderVC: UITableViewController {
    private enum CellID {
        static let entry = EntryFinderCell.storyboardID
        static let nothingFound = "NothingFoundCell"
    }
    @IBOutlet var separatorView: UIView!
    
    weak var database: Database?
    weak var delegate: EntryFinderDelegate?
    var databaseName: String? {
        didSet{ refreshDatabaseName() }
    }
    var serviceIdentifiers = [ASCredentialServiceIdentifier]() {
        didSet{ updateSearchCriteria() }
    }
    
    private var searchHelper = SearchHelper()
    private var searchResults = FuzzySearchResults(exactMatch: [], partialMatch: [])
    private var searchController: UISearchController! // owned strong ref
    private var manualSearchButton: UIBarButtonItem! // owned strong ref
    
    private var shouldAutoSelectFirstMatch: Bool = false
    private var tapGestureRecognizer: UITapGestureRecognizer?
    

    override func viewDidLoad() {
        super.viewDidLoad()
        self.clearsSelectionOnViewWillAppear = false
        setupSearch()

        manualSearchButton = UIBarButtonItem(
            barButtonSystemItem: .search,
            target: self,
            action: #selector(didPressManualSearch))
        navigationItem.rightBarButtonItem = manualSearchButton

        refreshDatabaseName()
        updateSearchCriteria()
        if shouldAutoSelectFirstMatch {
            // Make sure the user can abort auto-selection on tap
            setupAutoSelectCancellation()
        }
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        navigationController?.setToolbarHidden(false, animated: true)
    }
    
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        if shouldAutoSelectFirstMatch {
            // We've got a perfect match that should be auto-selected.
            simulateFirstRowSelection()
        }
    }
    
    // MARK: - Search setup
    
    private func setupSearch() {
        searchController = UISearchController(searchResultsController: nil)
        navigationItem.searchController = searchController
        navigationItem.hidesSearchBarWhenScrolling = true
        searchController.searchBar.searchBarStyle = .default
        searchController.searchBar.returnKeyType = .search
        searchController.searchBar.barStyle = .default
        
        searchController.dimsBackgroundDuringPresentation = false
        searchController.obscuresBackgroundDuringPresentation = false
        searchController.searchResultsUpdater = self
        searchController.delegate = self
        definesPresentationContext = true
    }
    
    private func updateSearchCriteria() {
        guard isViewLoaded, let database = database else { return }
        
        // If we have serviceIdentifiers - use them. Otherwise, activate manual search.
        let automaticResults = searchHelper.find(
            database: database,
            serviceIdentifiers: serviceIdentifiers
        )
        if !automaticResults.isEmpty {
            searchResults = automaticResults
            tableView.reloadData()
            if automaticResults.hasPerfectMatch {
                // There is a perfectly suitable automatic result,
                // remember to auto-select it when the VC appears.
                shouldAutoSelectFirstMatch = true
                return
            }
            return
        }
    
        // No automatical results, so fallback to manual search
        updateSearchResults(for: searchController)
        DispatchQueue.main.async {
            self.searchController.isActive = true
        }
    }
    
    func refreshDatabaseName() {
        guard isViewLoaded else { return }
        navigationItem.title = databaseName
    }

    // MARK: - Auto selection
    
    func setupAutoSelectCancellation() {
        assert(tapGestureRecognizer == nil)
        let tapGestureRecognizer = UITapGestureRecognizer(
            target: self,
            action: #selector(handleTableViewTapped)
        )
        tableView.addGestureRecognizer(tapGestureRecognizer)
        self.tapGestureRecognizer = tapGestureRecognizer
    }
    
    @objc private func handleTableViewTapped(_ gestureRecognizer: UITapGestureRecognizer) {
        // Regardless of gesture state: if the user touched the screen — abort auto-selection
        shouldAutoSelectFirstMatch = false
        // Disable the recognizer, otherwise it interferes with manual row selection.
        gestureRecognizer.isEnabled = false
    }
    
    /// Animates that the row was selected, and calls the delegate to process selection.
    private func simulateFirstRowSelection() {
        let indexPath = IndexPath(row: 0, section: 0)
        tableView.selectRow(at: indexPath, animated: true, scrollPosition: .none)
        DispatchQueue.main.asyncAfter(deadline: DispatchTime.now() + 0.3) { [weak self] in
            guard let self = self else { return }
            if self.shouldAutoSelectFirstMatch {
                self.tableView.deselectRow(at: indexPath, animated: true)
            } else {
                // auto select cancelled, deselect ASAP
                self.tableView.deselectRow(at: indexPath, animated: false)
            }
        }
        DispatchQueue.main.asyncAfter(deadline: DispatchTime.now() + 0.6) { [weak self] in
            guard let self = self else { return }
            guard self.shouldAutoSelectFirstMatch else { return } // aborted  by user?
            self.tableView(self.tableView, didSelectRowAt: indexPath)
        }
    }
    
    // MARK: - Table view data source

    override func numberOfSections(in tableView: UITableView) -> Int {
        if searchResults.isEmpty {
            return 1 // for "Nothing found" cell
        }
        
        var nSections = searchResults.exactMatch.count
        let hasPartialResults = !searchResults.partialMatch.isEmpty
        if hasPartialResults {
            nSections += searchResults.partialMatch.count + 1 // +1 is a separator
        }
        return nSections
    }

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        if searchResults.isEmpty {
            return (section == 0) ? 1 : 0 // "Nothing found" cell
        }
        let nExactResults = searchResults.exactMatch.count
        if section < nExactResults {
            let iExactResult = section
            return searchResults.exactMatch[iExactResult].entries.count
        } else if section == nExactResults {
            // separator
            return 0
        } else {
            let iPartialResult = section - nExactResults - 1
            return searchResults.partialMatch[iPartialResult].entries.count
        }
    }
    
    override open func tableView(
        _ tableView: UITableView,
        titleForHeaderInSection section: Int
        ) -> String?
    {
        guard !searchResults.isEmpty else { return nil }

        let nExactResults = searchResults.exactMatch.count
        if section < nExactResults {
            let iExactResult = section
            return searchResults.exactMatch[iExactResult].group.name
        } else if section == nExactResults {
            // separator
            return nil
        } else {
            let iPartialResult = section - nExactResults - 1
            return searchResults.partialMatch[iPartialResult].group.name
        }
    }
    
    override func tableView(_ tableView: UITableView, viewForFooterInSection section: Int) -> UIView? {
        let hasPartialResults = searchResults.partialMatch.count > 0
        let nExactResults = searchResults.exactMatch.count
        if hasPartialResults && section == nExactResults {
            return separatorView
        }
        return nil
    }
    
    override func tableView(
        _ tableView: UITableView,
        cellForRowAt indexPath: IndexPath
        ) -> UITableViewCell
    {
        if searchResults.isEmpty {
            let cell = tableView.dequeueReusableCell(
                withIdentifier: CellID.nothingFound,
                for: indexPath)
            return cell
        }

        let cell = tableView.dequeueReusableCell(
            withIdentifier: CellID.entry,
            for: indexPath)
            as! EntryFinderCell

        let section = indexPath.section
        let nExactResults = searchResults.exactMatch.count
        if section < nExactResults {
            let iExactResult = section
            cell.entry = searchResults.exactMatch[iExactResult].entries[indexPath.row].entry
        } else if section == nExactResults {
            // separator
            assertionFailure("Should not be here")
        } else {
            let iPartialResult = section - nExactResults - 1
            cell.entry = searchResults.partialMatch[iPartialResult].entries[indexPath.row].entry
        }
        return cell
    }
    
    // MARK: - Actions
    
    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        Watchdog.shared.restart()
        let section = indexPath.section
        let nExactResults = searchResults.exactMatch.count
        if section < nExactResults {
            let iExactResult = section
            let selectedEntry = searchResults.exactMatch[iExactResult].entries[indexPath.row].entry
            delegate?.entryFinder(self, didSelectEntry: selectedEntry)
        } else if section == nExactResults {
            // separator
            assertionFailure("Should not be here")
        } else {
            let iPartialResult = section - nExactResults - 1
            let selectedEntry = searchResults.partialMatch[iPartialResult].entries[indexPath.row].entry
            delegate?.entryFinder(self, didSelectEntry: selectedEntry)
        }
    }
    
    @objc func didPressManualSearch(_ sender: Any) {
        serviceIdentifiers.removeAll()
        updateSearchCriteria()
        searchController.searchBar.becomeFirstResponder()
    }
    
    @IBAction func didPressLockDatabase(_ sender: UIBarButtonItem) {
        Watchdog.shared.restart()
        let confirmationAlert = UIAlertController(title: nil, message: nil, preferredStyle: .actionSheet)
        let lockDatabaseAction = UIAlertAction(title: LString.actionLockDatabase, style: .destructive) {
            [weak self](action) in
            guard let self = self else { return }
            self.delegate?.entryFinderShouldLockDatabase(self)
        }
        let cancelAction = UIAlertAction(title: LString.actionCancel, style: .cancel, handler: nil)
        confirmationAlert.addAction(lockDatabaseAction)
        confirmationAlert.addAction(cancelAction)
        confirmationAlert.modalPresentationStyle = .popover
        if let popover = confirmationAlert.popoverPresentationController {
            popover.barButtonItem = sender
        }
        present(confirmationAlert, animated: true, completion: nil)
    }
}

// MARK: - UISearchControllerDelegate
extension EntryFinderVC: UISearchControllerDelegate {
    func didPresentSearchController(_ searchController: UISearchController) {
        DispatchQueue.main.async {
            searchController.searchBar.becomeFirstResponder()
        }
    }
}

extension EntryFinderVC: UISearchResultsUpdating {
    // Called to update results of manual search
    public func updateSearchResults(for searchController: UISearchController) {
        Watchdog.shared.restart()
        guard let searchText = searchController.searchBar.text,
            let database = database else { return }
        searchResults.exactMatch = searchHelper.find(database: database, searchText: searchText)
        searchResults.partialMatch = []
        sortSearchResults()
        tableView.reloadData()
    }

    private func sortSearchResults() {
        let groupSortOrder = Settings.current.groupSortOrder
        sort(&searchResults.exactMatch, sortOrder: groupSortOrder)
        sort(&searchResults.partialMatch, sortOrder: groupSortOrder)
    }
    
    private func sort(_ searchResults: inout SearchResults, sortOrder: Settings.GroupSortOrder) {
        searchResults.sort { sortOrder.compare($0.group, $1.group) }
        for i in 0..<searchResults.count {
            searchResults[i].entries.sort { (scoredEntry1, scoredEntry2) in
                if scoredEntry1.similarityScore == scoredEntry2.similarityScore {
                    return sortOrder.compare(scoredEntry1.entry, scoredEntry2.entry)
                } else {
                    return (scoredEntry2.similarityScore > scoredEntry1.similarityScore)
                }
            }
        }
    }
}
