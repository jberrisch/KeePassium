//  KeePassium Password Manager
//  Copyright © 2018–2019 Andrei Popleteev <info@keepassium.com>
//
//  This program is free software: you can redistribute it and/or modify it
//  under the terms of the GNU General Public License version 3 as published
//  by the Free Software Foundation: https://www.gnu.org/licenses/).
//  For commercial licensing, please contact the author.

import KeePassiumLib

class ChallengeResponseManager {
    static let instance = ChallengeResponseManager()
    
    private var accessorySessionStateObservation: NSKeyValueObservation?
    private var accessoryConnectedStateObservation: NSKeyValueObservation?
    private var nfcSessionStateObservation: NSKeyValueObservation?
    
    public private(set) var supportsNFC = false
    public private(set) var supportsMFI = false
    
    private var challenge: SecureByteArray?
    private var responseHandler: ResponseHandler?
    
    private var queue: DispatchQueue
    
    private init() {
        queue = DispatchQueue(label: "ChallengeResponseManager")
        setupSessions()
    }

    deinit {
        accessorySessionStateObservation = nil
        accessoryConnectedStateObservation = nil
        nfcSessionStateObservation = nil
    }
    
    // MARK: - Setup
    
    private func setupSessions() {
        supportsMFI = YubiKitDeviceCapabilities.supportsMFIAccessoryKey
        if supportsMFI {
            setupAccessorySession()
        }
        
        guard #available(iOS 13.0, *) else { return }
        supportsNFC = YubiKitDeviceCapabilities.supportsISO7816NFCTags
        if supportsNFC {
            setupNFCSession()
        }
    }
    
    @available(iOS 13.0, *)
    private func setupNFCSession() {
        let nfcSession = YubiKitManager.shared.nfcSession as! YKFNFCSession
        nfcSessionStateObservation = nfcSession.observe(
            \.iso7816SessionState,
            changeHandler: { [weak self] (session, newValue) in
                self?.nfcSessionStateDidChange()
            }
        )
    }
    
    private func setupAccessorySession() {
        let accessorySession = YubiKitManager.shared.accessorySession as! YKFAccessorySession
        accessorySessionStateObservation = accessorySession.observe(
            \.sessionState,
            changeHandler: {
                [weak self] (session, observedChange) in
                self?.accessorySessionStateDidChange()
            }
        )
    }
    
    
    // MARK: - Session state observation

    
    @available(iOS 13.0, *)
    private func nfcSessionStateDidChange() {
        let keySession = YubiKitManager.shared.nfcSession
        switch keySession.iso7816SessionState {
        case .opening:
            print("Accessory session -> opening")
        case .open:
            print("Accessory session -> open")
            keySession.stopIso7816Session()
        case .pooling:
            print("Accessory session -> pooling")
        case .closed:
            print("Accessory session -> closed")
        }
    }
    
    private func accessorySessionStateDidChange() {
        let keySession = YubiKitManager.shared.accessorySession as! YKFAccessorySession
        switch keySession.sessionState {
        case .opening:
            print("Accessory session -> opening")
        case .open:
            print("Accessory session -> open")
            queue.async { [weak self] in
                self?.performChallengeResponse(keySession)
                keySession.stopSessionSync()
            }
        case .closing:
            print("Accessory session -> closing")
        case .closed:
            print("Accessory session -> closed")
            accessoryConnectedStateObservation = nil // stop observing
        }
    }
    
    private func accessoryConnectedStateDidChange() {
        let keySession = YubiKitManager.shared.accessorySession
        if keySession.isKeyConnected {
            print("Accessory connected")
            keySession.startSessionSync()
        } else {
            print("Accessory disconnected")
            keySession.stopSession()
        }
    }
    
    private func startAccessorySessionWhenKeyConnected() {
        assert(accessoryConnectedStateObservation == nil)
        let accessorySession = YubiKitManager.shared.accessorySession as! YKFAccessorySession
        // TODO: does not get called on key connection
        accessoryConnectedStateObservation = accessorySession.observe(
            \.isKeyConnected,
            changeHandler: {
                [weak self] (session, observedChange) in
                self?.accessoryConnectedStateDidChange()
            }
        )
    }
    
    // MARK: - Public challenge-response stuff

    public func perform(
        with yubiKey: YubiKey,
        challenge: SecureByteArray,
        responseHandler: @escaping ResponseHandler)
    {
        guard #available(iOS 13.0, *) else { fatalError() }
        self.challenge = challenge.secureClone()
        self.responseHandler = responseHandler
        
        switch yubiKey.interface {
        case .nfc:
            let nfcSession = YubiKitManager.shared.nfcSession as! YKFNFCSession
            nfcSession.startIso7816Session()
        case .mfi:
            let keySession = YubiKitManager.shared.accessorySession
            if keySession.isKeyConnected {
                keySession.startSessionSync()
            } else {
                startAccessorySessionWhenKeyConnected()
            }
        }
    }
    
    /// Aborts any pending operations
    public func cancel() {
        // TODO: cancel only the current interface session, not both of them
        let accessorySession = YubiKitManager.shared.accessorySession
        if accessorySession.sessionState == .opening || accessorySession.sessionState == .open {
            accessorySession.stopSession()
        }
        accessorySessionStateObservation = nil
        accessoryConnectedStateObservation = nil
        
        if #available(iOS 13, *) {
            let nfcSession = YubiKitManager.shared.nfcSession
            nfcSession.cancelCommands()
            nfcSession.stopIso7816Session()
        }
        nfcSessionStateObservation = nil

        challenge?.erase()
        responseHandler = nil
    }
    
    // MARK: - Low-level exchange
    
    private static let swCodeSuccess: UInt16 = 0x9000
    
    private func returnResponse(_ response: SecureByteArray) {
        queue.async { [weak self] in
            self?.responseHandler?(response, nil)
            self?.cancel()
        }
    }

    private func returnError(_ error: ChallengeResponseError) {
        queue.async { [weak self] in
            self?.responseHandler?(SecureByteArray(), error)
            self?.cancel()
        }
    }
        
    private func performChallengeResponse(_ accessorySession: YKFAccessorySession) {
        assert(accessorySession.sessionState == .open)
        let keyName = accessorySession.accessoryDescription?.name ?? "(unknown)"
        Diag.info("Connecting to \(keyName)")
        guard let rawCommandService = accessorySession.rawCommandService else {
            let message = "YubiKey raw command service is not available"
            Diag.error(message)
            returnError(.communicationError(message: message))
            return
        }
        
        let appletID = Data([0xA0, 0x00, 0x00, 0x05, 0x27, 0x20, 0x01])
        guard let selectAppletAPDU = YKFAPDU(cla: 0x00, ins: 0xA4, p1: 0x04, p2: 0x00, data: appletID, type: .short) else {
            fatalError()
        }
        
        rawCommandService.executeSyncCommand(selectAppletAPDU, completion: {
            [weak self] (response, error) in
            guard let self = self else { return }
            if let error = error {
                Diag.error("YubiKey select applet failed [message: \(error.localizedDescription)]")
                self.returnError(.communicationError(message: error.localizedDescription))
                return
            }
            
            let responseParser = RawResponseParser(response: response!)
            let statusCode = responseParser.statusCode
            if statusCode == ChallengeResponseManager.swCodeSuccess {
                guard let responseData = responseParser.responseData else {
                    let message = "YubiKey response is empty"
                    Diag.error(message)
                    self.returnError(.communicationError(message: message))
                    return
                }
                let responseHexString = ByteArray(data: responseData).asHexString
                print("Applet selection result: \(responseHexString)") //TODO: remove after debug
            } else {
                let message = "YubiKey select applet failed with code \(String(format: "%04X", statusCode))"
                Diag.error(message)
                self.returnError(.communicationError(message: message))
            }
        })

        guard let challengeBytes = challenge?.bytesCopy() else {
            fatalError()
        }
//        let challengeBytes: [UInt8] = [
//            0x30,0x30,0x30,0x30,0x30,0x30,0x30,0x30 // "00000000"
//        ]
        guard let chalRespAPDU = YKFAPDU(cla: 0x00, ins: 0x01, p1: 0x38, p2: 0x00, data: Data(challengeBytes), type: .short) else {
            fatalError()
        }
        
        rawCommandService.executeSyncCommand(chalRespAPDU, completion: { [weak self] (response, error) in
            guard let self = self else { return }
            if let error = error {
                Diag.error("YubiKey error while executing command [message: \(error.localizedDescription)]")
                self.returnError(.communicationError(message: error.localizedDescription))
                return
            }
            
            let responseParser = RawResponseParser(response: response!)
            let statusCode = responseParser.statusCode
            if statusCode == ChallengeResponseManager.swCodeSuccess {
                guard let responseData = responseParser.responseData else {
                    let message = "YubiKey response is empty"
                    Diag.error(message)
                    self.returnError(.communicationError(message: message))
                    return
                }
                let responseHexString = ByteArray(data: responseData).asHexString
                print("Response: \(responseHexString)") //TODO: remove after debug
                let response = SecureByteArray(data: responseData)
                self.returnResponse(response)
            } else {
                let message = "YubiKey challenge failed with code \(String(format: "%04X", statusCode))"
                Diag.error(message)
                self.returnError(.communicationError(message: message))
            }
        })
    }
}


fileprivate class RawResponseParser {
    private var response: Data

    /// Initializes the parser with the response from the key.
    init(response: Data) {
        self.response = response
    }
    
    var statusCode: UInt16 {
        get {
            guard response.count >= 2 else {
                return 0x00
            }
            return UInt16(response[response.count - 2]) << 8 + UInt16(response[response.count - 1])
        }
    }
    
    var responseData: Data? {
        get {
            guard response.count > 2 else {
                return nil
            }
            return response.subdata(in: 0..<response.count - 2)
        }
    }
}
