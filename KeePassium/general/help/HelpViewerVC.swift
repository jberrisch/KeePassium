//  KeePassium Password Manager
//  Copyright © 2018–2020 Andrei Popleteev <info@keepassium.com>
//
//  This program is free software: you can redistribute it and/or modify it
//  under the terms of the GNU General Public License version 3 as published
//  by the Free Software Foundation: https://www.gnu.org/licenses/).
//  For commercial licensing, please contact the author.

import KeePassiumLib

protocol HelpViewerDelegate: class {
    //TODO: not routed yet
    func didPressCancel(in viewController: HelpViewerVC)
}

class HelpViewerVC: UIViewController {
    @IBOutlet weak var bodyLabel: UILabel!
    weak var delegate: HelpViewerDelegate?
    
    var content: HelpArticle? {
        didSet {
            refresh()
        }
    }
    
    // MARK: - VC life cycle
    
    public static func create() -> HelpViewerVC {
        return HelpViewerVC.instantiateFromStoryboard()
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        self.title = NSLocalizedString(
            "[Help Viewer/title]",
            tableName: "help",
            value: "Help",
            comment: "Generic title of the help viewer")
        
        refresh()
    }
    
    func refresh() {
        guard isViewLoaded else { return }
        guard let content = content else {
            bodyLabel.attributedText = nil
            bodyLabel.text = nil
            return
        }
        bodyLabel.attributedText = content.rendered()
    }
    @IBAction func didPressCancel(_ sender: Any) {
        delegate?.didPressCancel(in: self)
    }
}
