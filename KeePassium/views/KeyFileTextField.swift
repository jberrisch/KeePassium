//
//  KeyFileTextField.swift
//  KeePassium
//
//  Created by Andrei on 25/11/2019.
//  Copyright © 2019 Andrei Popleteev. All rights reserved.
//

import UIKit

typealias YubiHandler = ((KeyFileTextField)->Void)

class KeyFileTextField: ValidatingTextField {
    private let horizontalInsets = CGFloat(8.0)
    private let verticalInsets = CGFloat(2.0)
    
    private let yubiImage = UIImage(asset: .yubikeyAccessory)
    
    private var yubiButton: UIButton! // owned strong ref
    public var isYubikeyActive: Bool = false {
        didSet {
            yubiButton?.isSelected = isYubikeyActive
        }
    }
    
    public var yubikeyHandler: YubiHandler? = nil
    
    override func awakeFromNib() {
        super.awakeFromNib()
        setupYubiButton()
    }
    
    private func setupYubiButton() {
        let yubiButton = UIButton(type: .custom)
        yubiButton.tintColor = UIColor.actionTint
        yubiButton.addTarget(self, action: #selector(didPressYubiButton), for: .touchUpInside)
        yubiButton.setImage(yubiImage, for: .normal)
        yubiButton.setImage(yubiImage, for: .selected)
        
        let horizontalInsets = CGFloat(8.0)
        let verticalInsets = CGFloat(2.0)
        yubiButton.imageEdgeInsets = UIEdgeInsets(
            top: verticalInsets,
            left: horizontalInsets,
            bottom: verticalInsets,
            right: horizontalInsets)
        yubiButton.frame = CGRect(
            x: 0.0,
            y: 0.0,
            width: yubiImage.size.width + 2 * horizontalInsets,
            height: yubiImage.size.height + 2 * verticalInsets)
        yubiButton.isAccessibilityElement = true
        yubiButton.accessibilityLabel = NSLocalizedString(
            "[Database/Unlock] YubiKey",
            value: "YubiKey",
            comment: "Action/button to setup YubiKey key component")
        self.rightView = yubiButton
        self.rightViewMode = .always
    }
    
    override func rightViewRect(forBounds bounds: CGRect) -> CGRect {
        return CGRect(
            x: bounds.maxX - yubiImage.size.width - 2 * horizontalInsets,
            y: bounds.midY - yubiImage.size.height / 2 - verticalInsets,
            width: yubiImage.size.width + 2 * horizontalInsets,
            height: yubiImage.size.height + 2 * verticalInsets)
    }
    
    @objc private func didPressYubiButton(_ sender: Any) {
        self.yubikeyHandler?(self)
    }
}
