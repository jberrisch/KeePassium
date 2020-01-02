//  KeePassium Password Manager
//  Copyright © 2018–2019 Andrei Popleteev <info@keepassium.com>
//
//  This program is free software: you can redistribute it and/or modify it
//  under the terms of the GNU General Public License version 3 as published
//  by the Free Software Foundation: https://www.gnu.org/licenses/).
//  For commercial licensing, please contact the author.

import Foundation
import KeePassiumLib

protocol GroupPickerDelegate: class {
    func didSelectGroup(_ group: Group?, in groupPicker: GroupPickerVC)
}

/// Custom cell of the `GroupPickerVC`
class GroupPickerCell: UITableViewCell {
    @IBOutlet weak var iconView: UIImageView!
    @IBOutlet weak var titleLabel: UILabel!
    @IBOutlet weak var subtitleLabel: UILabel!
    @IBOutlet weak var leftConstraint: NSLayoutConstraint!
    
    override var indentationLevel: Int {
        didSet {
            leftConstraint.constant = CGFloat(indentationLevel) * indentationWidth
        }
    }
}

class GroupPickerVC: UITableViewController, Refreshable {
    private let cellID = "GroupCell"
    class Node {
        weak var group: Group?
        var level: Int
        var isExpanded: Bool
        
        // Children nodes should be pre-sorted
        var children = [Node]()
        init(group: Group, level: Int=0, isExpanded: Bool=false) {
            self.group = group
            self.level = level
            self.isExpanded = isExpanded
        }
    }
    
    public weak var delegate: GroupPickerDelegate?
    
    public weak var rootGroup: Group? {
        didSet {
            buildNodes()
            refresh()
        }
    }
    /// Group that should be initially expanded
    public weak var selectedGroup: Group? // unused at the moment
    
    private var rootNode: Node?
    private var flatNodes = [Node]()
    private var items = [Weak<Group>]()
    private var levels = [Int]()
    private var isExpanded = [Bool]()
    
    // MARK: - Tree-building routines
    
    func buildNodes() {
        rootNode = nil
        guard let rootGroup = rootGroup else { return }
        let _rootNode = Node(group: rootGroup, level: 0, isExpanded: true)
        addChildrenNodes(for: _rootNode)
        rootNode = _rootNode
    }
    
    func addChildrenNodes(for node: Node) {
        guard let group = node.group else { return }

        let groupSortOrder = Settings.current.groupSortOrder
        let subGroupsSorted = group.groups.sorted { return groupSortOrder.compare($0, $1) }
        for subGroup in subGroupsSorted {
            let childNode = Node(group: subGroup, level: node.level + 1, isExpanded: true)
            addChildrenNodes(for: childNode)
            node.children.append(childNode)
        }
    }
    
    func refresh() {
        flatNodes.removeAll(keepingCapacity: true)
        items.removeAll(keepingCapacity: true)
        levels.removeAll(keepingCapacity: true)
        isExpanded.removeAll(keepingCapacity: true)
        
        if let rootNode = rootNode {
            processNode(rootNode)
        }

        tableView.beginUpdates()
        tableView.reloadData()
        tableView.endUpdates()
    }
    
    private func processNode(_ node: Node) {
        guard let group = node.group else { return }
        guard node.isExpanded else { return }
        flatNodes.append(node)
        items.append(Weak(group))
        levels.append(node.level)
        isExpanded.append(node.isExpanded)
        node.children.forEach { subNode in
            processNode(subNode)
        }
    }
    
    // MARK: - UITableViewDataSource
    
    override func numberOfSections(in tableView: UITableView) -> Int {
        return 1
    }
    
    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return items.count
    }
    
    override func tableView(_ tableView: UITableView, indentationLevelForRowAt indexPath: IndexPath) -> Int {
        return levels[indexPath.row]
    }
    
    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(
            withIdentifier: cellID,
            for: indexPath)
            as! GroupPickerCell
        guard let group = items[indexPath.row].value else {
            assertionFailure()
            return cell
        }
        cell.iconView.image = UIImage.kpIcon(forGroup: group)
        cell.titleLabel.text = group.name
        cell.subtitleLabel.text = isExpanded[indexPath.row] ? "V" : ">"
        cell.indentationLevel = levels[indexPath.row]
        return cell
    }
    
    // MARK: - Actions
    
    @IBAction func didPressCancelButton(_ sender: Any) {
        delegate?.didSelectGroup(nil, in: self)
    }
    
    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        flatNodes[indexPath.row].isExpanded = true
        refresh()
    }
}
