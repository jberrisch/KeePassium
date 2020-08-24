//  KeePassium Password Manager
//  Copyright © 2018–2020 Andrei Popleteev <info@keepassium.com>
//
//  This program is free software: you can redistribute it and/or modify it
//  under the terms of the GNU General Public License version 3 as published
//  by the Free Software Foundation: https://www.gnu.org/licenses/).
//  For commercial licensing, please contact the author.

import KeePassiumLib

public struct HelpArticle: Decodable {
    public struct Section: Decodable {
        var heading: String?
        var body: String
    }
    
    let title: String
    let sections: [Section]
    
    public enum Key: String {
        case perpetualFallbackLicense = "perpetual-fallback-license"
    }
    
    public func rendered() -> NSAttributedString {
        let output = NSMutableAttributedString()
        
        output.append(title.appendingNewLine.styled(.title1, paragraphSpacing: 12))
        for section in sections {
            if let heading = section.heading {
                output.append(heading.appendingNewLine.styled(.headline))
            }
            output.append(section.body.appendingNewLine.styled(.body))
        }
        return output
    }
    
    /// Loads a HelpArticle instance from a JSON resource file with the given name.
    public static func load(_ key: Key) -> HelpArticle? {
        let fileName = key.rawValue
        guard let url = Bundle.main.url(forResource: fileName, withExtension: "json", subdirectory: "") else {
            Diag.error("Failed to find help article file")
            return nil
        }
        do {
            let fileContents = try Data(contentsOf: url)
            let jsonDecoder = JSONDecoder()
            let helpArticle = try jsonDecoder.decode(HelpArticle.self, from: fileContents)
            return helpArticle
        } catch {
            Diag.error("Failed to load help article file [reason: \(error.localizedDescription)]")
            return nil
        }
    }
}

fileprivate extension String {
    var appendingNewLine: String {
        if self.last != "\n" {
            return self + "\n"
        } else {
            return self
        }
    }
    
    func styled(
        _ textStyle: UIFont.TextStyle = .body,
        paragraphSpacing: CGFloat = 6.0,
        paragraphSpacingBefore: CGFloat = 12.0,
        alignment: NSTextAlignment = .natural)
        -> NSAttributedString
    {
        let font = UIFont.preferredFont(forTextStyle: textStyle)
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.paragraphSpacing = paragraphSpacing
        paragraphStyle.paragraphSpacingBefore = paragraphSpacingBefore
        paragraphStyle.alignment = .left
        let attributedString = NSMutableAttributedString(
            string: self,
            attributes: [
                NSAttributedString.Key.font: font,
                NSAttributedString.Key.paragraphStyle: paragraphStyle
            ]
        )
        return attributedString
    }
}
