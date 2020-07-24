//  KeePassium Password Manager
//  Copyright © 2018–2020 Andrei Popleteev <info@keepassium.com>
//
//  This program is free software: you can redistribute it and/or modify it
//  under the terms of the GNU General Public License version 3 as published
//  by the Free Software Foundation: https://www.gnu.org/licenses/).
//  For commercial licensing, please contact the author.

import KeePassiumLib

public struct HelpArticle {
    public struct Section {
        var heading: String?
        var body: String
    }
    
    let title: String
    let sections: [Section]
    
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

extension HelpArticle {
    public static let perpetualFallbackLicense = HelpArticle(
        title: NSLocalizedString(
            "[Help/Perpetual Fallback License/title]",
            value: "Rent-to-own license (Perpetual fallback license)",
            comment: "Title of a help article. Please leave the `perpetual fallback license` part in English."
        ),
        sections: [
            Section(
                heading: "Section with an elaborate title written over serveral lines in a rather eloquent style",
                body: NSLocalizedString(
                    "[Help/Perpetual Fallback License/body 1",
                    value: "Lorem ipsum dolor sit amet, consectetur adipiscing elit. Vestibulum finibus molestie auctor. Etiam in ultrices est, at dapibus mauris. Phasellus accumsan, ipsum vel pulvinar ultrices, mi dolor auctor ante, vel luctus ex urna ut arcu. Donec eu orci non dolor eleifend viverra eu vel nulla. Aliquam vel tristique lacus, vel aliquet orci. Class aptent taciti sociosqu ad litora torquent per conubia nostra, per inceptos himenaeos. Praesent vel imperdiet lectus. Duis viverra tempor nisl, id laoreet tellus scelerisque et. Pellentesque nec nulla sed sapien commodo tempus a quis mauris.",
                    comment: "Content of a help article"
                )
            ),
            Section(
                heading: nil,
                body: NSLocalizedString(
                    "[Help/Perpetual Fallback License/body 1",
                    value: "Nam aliquam, sapien vel bibendum vulputate, quam massa consequat lacus, ac fringilla ipsum est in lectus. Quisque quis porta mi, dignissim dignissim quam. Proin quam justo, tempus at erat at, malesuada vehicula dui. Pellentesque habitant morbi tristique senectus et netus et malesuada fames ac turpis egestas. Vivamus efficitur imperdiet rhoncus. Integer eu sapien dui. Nullam iaculis orci tellus, quis sagittis risus aliquam in. Aenean sit amet nulla nec massa ornare convallis.",
                    comment: "Content of a help article"
                )
            ),
            Section(
                heading: "Section 3",
                body: NSLocalizedString(
                    "[Help/Perpetual Fallback License/body 1",
                    value: "Nullam euismod dolor sed lacinia luctus. Pellentesque augue sem, egestas sit amet lorem quis, tempor consectetur tellus. Aenean sodales, ligula eu finibus feugiat, magna orci pulvinar risus, id elementum est orci vel leo. Vestibulum ante ipsum primis in faucibus orci luctus et ultrices posuere cubilia curae; Maecenas ultrices leo eget dolor fringilla, auctor consectetur risus eleifend. Nulla facilisi. Vivamus tempus arcu sed sem aliquet, sed rhoncus leo commodo. Sed sed tristique mauris, a vestibulum nibh. Nulla et efficitur quam. Curabitur porta enim sed mauris ornare molestie. Etiam interdum lobortis nisi. Aliquam rhoncus ultrices dolor, vel convallis ipsum sodales ac.",
                    comment: "Content of a help article"
                )
            ),
        ]
    )
}
