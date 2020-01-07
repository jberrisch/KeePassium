//  KeePassium Password Manager
//  Copyright © 2018–2019 Andrei Popleteev <info@keepassium.com>
//
//  This program is free software: you can redistribute it and/or modify it
//  under the terms of the GNU General Public License version 3 as published
//  by the Free Software Foundation: https://www.gnu.org/licenses/).
//  For commercial licensing, please contact the author.

import Foundation
import KeePassiumLib

protocol DestinationGroupPickerDelegate: class {
    func didPressCancel(in groupPicker: DestinationGroupPickerVC)
    func shouldSelectGroup(_ group: Group, in groupPicker: DestinationGroupPickerVC) -> Bool
    func didSelectGroup(_ group: Group, in groupPicker: DestinationGroupPickerVC)
}

/// Custom cell of the `GroupPickerVC`
class DestinationGroupPickerCell: UITableViewCell {
    enum CellState {
        case none
        case expanded
        case collapsed
    }
    @IBOutlet weak var iconView: UIImageView!
    @IBOutlet weak var titleLabel: UILabel!
    @IBOutlet weak var subtitleLabel: UILabel!
    @IBOutlet weak var leftConstraint: NSLayoutConstraint!
    
    private var arrowImageView: UIImageView!
    
    var isAllowedDestination: Bool = true {
        didSet {
            if isAllowedDestination {
                titleLabel.textColor = UIColor.primaryText
            } else {
                titleLabel.textColor = UIColor.disabledText
            }
        }
    }
    fileprivate var state: CellState = .none {
        didSet { refresh() }
    }
    
    override var indentationLevel: Int {
        didSet {
            leftConstraint.constant = CGFloat(indentationLevel) * indentationWidth
        }
    }
    
    override func awakeFromNib() {
        super.awakeFromNib()
        arrowImageView = UIImageView(frame: CGRect(x: 0, y: 0, width: 25, height: 25))
        arrowImageView.tintColor = .auxiliaryText
        self.accessoryView = arrowImageView
    }
    
    func refresh() {
        switch state {
        case .none:
            arrowImageView.image = nil
        case .collapsed:
            arrowImageView.image = UIImage(asset: .expandRowCellAccessory)
        case .expanded:
            arrowImageView.image = UIImage(asset: .collapseRowCellAccessory)
        }
    }
}

class DestinationGroupPickerVC: UITableViewController, Refreshable {
    private let cellID = "GroupCell"
    class Node {
        weak var group: Group?
        var level: Int
        var isExpanded: Bool
        var children = [Node]() // Children nodes should be pre-sorted
        
        init(group: Group, level: Int, isExpanded: Bool=false) {
            self.group = group
            self.level = level
            self.isExpanded = isExpanded
        }
    }
    
    @IBOutlet weak var doneButton: UIBarButtonItem!
    
    public weak var delegate: DestinationGroupPickerDelegate?
    
    /// The group selected by user
    public private(set) weak var selectedGroup: Group? {
        didSet {
            if let selectedGroup = selectedGroup {
                let isAllowedDestination = delegate?.shouldSelectGroup(selectedGroup, in: self) ?? false
                doneButton?.isEnabled = isAllowedDestination
            } else {
                doneButton?.isEnabled = false
            }
        }
    }
    
    /// The group used as a root of the tree
    public weak var rootGroup: Group? {
        didSet {
            if let rootGroup = rootGroup {
                rootNode = Node(group: rootGroup, level: 0)
                buildNodeTree(parent: rootNode!)
            } else {
                rootNode = nil
            }
            refresh()
        }
    }
    
    private var rootNode: Node?
    private var flatNodes = [Node]()
    
    override func viewDidLoad() {
        super.viewDidLoad()
        doneButton.title = LString.actionMove
    }
    
    func refresh() {
        rebuildFlatNodes()
        tableView.reloadData()
    }
    
    // Expands all the parents of the given group
    public func expandGroup(_ group: Group?) {
        guard let group = group, let rootNode = rootNode else { return }
        
        guard let expandedNode = expandNode(for: group, in: rootNode) else { return }
        refresh()
        
        guard let rowForNode = (flatNodes.firstIndex { $0 === expandedNode }) else { return }
        DispatchQueue.main.async { [weak self, weak group] in
            self?.selectedGroup = group
            self?.tableView.selectRow(
                at: IndexPath(row: rowForNode, section: 0),
                animated: true,
                scrollPosition: .middle
            )
        }
    }
    
    // MARK: - Tree-building routines
    
    private func buildNodeTree(parent: Node) {
        guard let group = parent.group else { return }
        parent.children.removeAll()
        group.groups.forEach {
            let subNode = Node(group: $0, level: parent.level + 1)
            parent.children.append(subNode)
            buildNodeTree(parent: subNode)
        }
    }
    
    private func rebuildFlatNodes() {
        flatNodes.removeAll(keepingCapacity: true)
        if let rootNode = rootNode {
            flatten(rootNode, to: &flatNodes)
        }
    }
    
    private func flatten(_ node: Node, to flatNodes: inout [Node]) {
        flatNodes.append(node)
        guard node.isExpanded else { return }
        node.children.forEach { flatten($0, to: &flatNodes) }
    }
    
    private func setSubtree(node: Node, expanded: Bool) {
        node.isExpanded = expanded
        node.children.forEach { setSubtree(node: $0, expanded: expanded) }
    }

    /// Finds given group in the subtree defined by the `node`,
    /// and expands its parent nodes.
    /// Returns the deepest found&expanded node.
    @discardableResult
    private func expandNode(for group: Group, in node: Node) -> Node? {
        if node.group === group {
            node.isExpanded = true
            return node
        }
        for subnode in node.children {
            if let finalNode = expandNode(for: group, in: subnode) {
                node.isExpanded = true
                return finalNode
            }
        }
        return nil
    }

    // MARK: - UITableViewDataSource
    
    override func numberOfSections(in tableView: UITableView) -> Int {
        return 1
    }
    
    override func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        guard section == 0 else { return nil }
        return NSLocalizedString(
            "[General/MoveItem] Select destination",
            value: "Select destination",
            comment: "Title of a hierarchy of group when moving an entry/group to another group")
    }
    
    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return flatNodes.count
    }
    
    override func tableView(_ tableView: UITableView, indentationLevelForRowAt indexPath: IndexPath) -> Int {
        let row = indexPath.row
        return flatNodes[row].level
    }
    
    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(
            withIdentifier: cellID,
            for: indexPath)
            as! DestinationGroupPickerCell
        
        let row = indexPath.row
        let node = flatNodes[row]
        if let group = node.group {
            cell.iconView.image = UIImage.kpIcon(forGroup: group)
            cell.titleLabel?.text = group.name
            cell.isAllowedDestination = delegate?.shouldSelectGroup(group, in: self) ?? false
            cell.subtitleLabel?.text = ""
        }
        
        if node.children.isEmpty {
            cell.state = .none
        } else {
            cell.state = node.isExpanded ? .expanded : .collapsed
        }
        cell.indentationLevel = node.level
        return cell
    }
    
    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        let row = indexPath.row
        let node = flatNodes[row]
        if node.isExpanded {
            collapseNode(at: row)
        } else {
            expandNode(at: row)
        }
        guard let group = node.group else { return }
        let isSelectable = delegate?.shouldSelectGroup(group, in: self) ?? false
        if isSelectable {
            tableView.selectRow(at: indexPath, animated: false, scrollPosition: .none)
            self.selectedGroup = group
        } else {
            tableView.deselectRow(at: indexPath, animated: false)
            self.selectedGroup = nil
        }
    }
    
    // MARK: - Tree operations
    
    func collapseNode(at index: Int) {
        let oldRowCount = flatNodes.count
        setSubtree(node: flatNodes[index], expanded: false)
        rebuildFlatNodes()
        let newRowCount = flatNodes.count
        
        let nRowsToRemove = oldRowCount - newRowCount
        tableView.beginUpdates()
        for i in 0..<nRowsToRemove {
            tableView.deleteRows(
                at: [IndexPath(row: index + i + 1, section: 0)],
                with: .fade
            )
        }
        tableView.reloadRows(at: [IndexPath(row: index, section: 0)], with: .fade)
        tableView.endUpdates()
    }
    
    func expandNode(at index: Int) {
        let oldRowCount = flatNodes.count
        flatNodes[index].isExpanded = true
        rebuildFlatNodes()
        let newRowCount = flatNodes.count
        
        let nRowsToAdd = newRowCount - oldRowCount
        tableView.beginUpdates()
        for i in 0..<nRowsToAdd {
            tableView.insertRows(
                at: [IndexPath(row: index + i + 1, section: 0)],
                with: .fade
            )
        }
        tableView.reloadRows(at: [IndexPath(row: index, section: 0)], with: .fade)
        tableView.endUpdates()
    }

    // MARK: - Actions
    
    @IBAction func didPressCancelButton(_ sender: Any) {
        delegate?.didPressCancel(in: self)
    }
    
    @IBAction func didPressDoneButton(_ sender: Any) {
        guard let selectedGroup = selectedGroup else {
            assertionFailure()
            return
        }
        delegate?.didSelectGroup(selectedGroup, in: self)
    }
}

// MARK: UIAdaptivePresentationControllerDelegate
extension DestinationGroupPickerVC: UIAdaptivePresentationControllerDelegate {
    func presentationControllerDidDismiss(_ presentationController: UIPresentationController) {
        didPressCancelButton(self)
    }
}
