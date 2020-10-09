//  KeePassium Password Manager
//  Copyright © 2018–2019 Andrei Popleteev <info@keepassium.com>
//
//  This program is free software: you can redistribute it and/or modify it
//  under the terms of the GNU General Public License version 3 as published
//  by the Free Software Foundation: https://www.gnu.org/licenses/).
//  For commercial licensing, please contact the author.

import UIKit
import MessageUI
import KeePassiumLib

/// Helper class to create support email templates.
class SupportEmailComposer: NSObject {
    private let freeSupportEmail = "support@keepassium.com"
    private let betaSupportEmail = "beta@keepassium.com"
    private let premiumSupportEmail = "premium-support@keepassium.com"
    
    enum Subject: String { // do not localize
        case problem = "Problem"
        case supportRequest = "Support Request"
        case proUpgrade = "Pro Upgradе"
    }
    
    typealias CompletionHandler = ((Bool)->Void)
    private let completionHandler: CompletionHandler?
    private weak var parent: UIViewController?
    private var subject = ""
    private var content = ""
    
    private init(subject: String, content: String, parent: UIViewController, completionHandler: CompletionHandler?) {
        self.completionHandler = completionHandler
        self.subject = subject
        self.content = content
        self.parent = parent
    }
    
    /// Prepares a draft email message, optionally with diagnostic info.
    /// - Parameters:
    ///   - subject: type of the email
    ///   - parent: ViewController to present any popovers/alerts
    ///   - completion: called once the email has been saved or sent.
    static func show(subject: Subject, parent: UIViewController, completion: CompletionHandler?=nil) {
        let subjectText = "\(AppInfo.name) - \(subject.rawValue)" // do not localize
            .addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed)! // safe to unwrap
        
        let includeDiagnostics = (subject == .problem)
        let contentText: String
        if includeDiagnostics {
            contentText = LString.emailTemplateDescribeTheProblemHere +
                "\n\n----- Diagnostic Info -----\n" +
                Diag.toString() +
                "\n\n\(AppInfo.description)"
        } else {
            contentText = "\n\n\(AppInfo.description)"
        }
        
        let instance = SupportEmailComposer(
            subject: subjectText,
            content: contentText,
            parent: parent,
            completionHandler: completion)
        
        //        if MFMailComposeViewController.canSendMail() {
        //            instance.showEmailComposer()
        //        } else {
        //            instance.openSystemEmailComposer()
        //        }
        // In-app composer does not show up on iOS11+, thus mailto workaround
        instance.openSystemEmailComposer()
    }
    
    private func getSupportEmail() -> String {
        if Settings.current.isTestEnvironment {
            return betaSupportEmail
        }
        
        if PremiumManager.shared.isPremiumSupportEnabled() {
            return premiumSupportEmail
        } else {
            return freeSupportEmail
        }
    }
    
    private func showEmailComposer() {
        let emailComposerVC = MFMailComposeViewController()
        emailComposerVC.mailComposeDelegate = self
        emailComposerVC.setToRecipients([getSupportEmail()])
        emailComposerVC.setSubject(subject)
        emailComposerVC.setMessageBody(content, isHTML: false)
    }
    
    private func openSystemEmailComposer() {
        let body = content.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed)! // safe to unwrap
        let mailtoUrl = "mailto:\(getSupportEmail())?subject=\(subject)&body=\(body)"
        guard let url = URL(string: mailtoUrl) else {
            Diag.error("Failed to create mailto URL")
            return
        }
        let app = UIApplication.shared
        guard app.canOpenURL(url) else {
            showExportSheet(for: url, completion: self.completionHandler)
            return
        }
        app.open(url, options: [:]) { success in // strong self
            if success {
                self.completionHandler?(success)
            } else {
                self.showExportSheet(for: url, completion: self.completionHandler)
            }
        }
    }
    
    private func showExportSheet(for url: URL, completion: CompletionHandler?) {
        guard let parent = parent else {
            completion?(false)
            return
        }
        
        let exportSheet = UIActivityViewController(activityItems: [url], applicationActivities: nil)
        parent.present(exportSheet, animated: true) {
            completion?(true)
        }
    }
}

extension SupportEmailComposer: MFMailComposeViewControllerDelegate {
    func mailComposeController(
        _ controller: MFMailComposeViewController,
        didFinishWith result: MFMailComposeResult,
        error: Error?)
    {
        let success = (result == .saved || result == .sent)
        completionHandler?(success)
    }
}
