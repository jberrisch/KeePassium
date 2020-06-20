//  KeePassium Password Manager
//  Copyright © 2020 Andrei Popleteev <info@keepassium.com>
//
//  This program is free software: you can redistribute it and/or modify it
//  under the terms of the GNU General Public License version 3 as published
//  by the Free Software Foundation: https://www.gnu.org/licenses/).
//  For commercial licensing, please contact the author.

import KeePassiumLib

protocol DynamicFileList: class {
    /// Duration of the `tableView.moveRow` animation
    var sortingAnimationDuration: TimeInterval { get }
    
    var ongoingUpdateAnimations: Int { get set }
    func sortAndAnimateFileInfoUpdate(refs: inout [URLReference], in tableView: UITableView)
//    func scheduleDataReload(in tableView: UITableView)
    
    /// Maps file's position in the array of reference to its position in the table.
    func getIndexPath(for fileIndex: Int) -> IndexPath
}

extension DynamicFileList {
    var sortingAnimationDuration: TimeInterval { return 0.3 }
    
    func sortAndAnimateFileInfoUpdate(
        refs: inout [URLReference],
        in tableView: UITableView)
    {
        let sortOrder = Settings.current.filesSortOrder
        let indexedAndSorted = refs.enumerated().sorted {
            sortOrder.compare($0.element, $1.element)
        }
        refs = indexedAndSorted.map { return $0.1 }
        let oldIndices = indexedAndSorted.map { return $0.0 }

        DispatchQueue.main.async { [weak self, weak tableView, oldIndices] in
            guard let self = self, let tableView = tableView else { return }
            // Avoid animation when the table is off screen.
            // Prevents UITableViewAlertForLayoutOutsideViewHierarchy
            guard tableView.window != nil else { return }
            
            self.animateSorting(oldIndices: oldIndices, in: tableView)
        }
    }
    
    private func animateSorting(oldIndices: [Int], in tableView: UITableView) {
        ongoingUpdateAnimations += 1
        tableView.performBatchUpdates(
            {
                [weak tableView] in
                for i in 0..<oldIndices.count {
                    tableView?.moveRow(
                        at: getIndexPath(for: oldIndices[i]),
                        to: getIndexPath(for: i))
                }
            },
            completion: { [weak self, weak tableView] finished in
                guard let self = self,
                    let tableView = tableView
                    else { return }
                self.scheduleDataReload(in: tableView)
            }
        )
    }
    
    /// Schedules a `reloadData()` on the given tableView, if there are no onging update animations.
    func scheduleDataReload(in tableView: UITableView) {
        // Try to reloadData after all table animation would be complete.
        DispatchQueue.main.asyncAfter(deadline: .now() + sortingAnimationDuration) {
            [weak self] in
            guard let self = self else { return }
            self.ongoingUpdateAnimations -= 1
            assert(self.ongoingUpdateAnimations >= 0)
            // if there is a subsequent animation ongoing,
            // leave reloading to that animation's scheduled reload.
            if self.ongoingUpdateAnimations == 0 {
                tableView.reloadData()
            }
        }
    }
}
