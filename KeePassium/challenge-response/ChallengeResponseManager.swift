//  KeePassium Password Manager
//  Copyright © 2018–2019 Andrei Popleteev <info@keepassium.com>
//
//  This program is free software: you can redistribute it and/or modify it
//  under the terms of the GNU General Public License version 3 as published
//  by the Free Software Foundation: https://www.gnu.org/licenses/).
//  For commercial licensing, please contact the author.

import KeePassiumLib

fileprivate let YUBIKEY_SUCCESS: UInt16 = 0x9000

class ChallengeResponseManager {
    static let instance = ChallengeResponseManager()
    
    private var accessorySessionStateObservation: NSKeyValueObservation?
    private var accessoryConnectedStateObservation: NSKeyValueObservation?
    private var nfcSessionStateObservation: NSKeyValueObservation?
    
    public private(set) var supportsNFC = false
    public private(set) var supportsMFI = false
    
    private var challenge: SecureByteArray?
    private var responseHandler: ResponseHandler?
    private var currentKey: YubiKey?
    private var isResponseSent = false
    
    private var queue: DispatchQueue
        
    private init() {
        queue = DispatchQueue(label: "ChallengeResponseManager")
        initSessionObservers()
    }

    deinit {
        accessorySessionStateObservation = nil
        accessoryConnectedStateObservation = nil
        nfcSessionStateObservation = nil
    }
    
    /// Creates a default challenge handler for the given key.
    /// If the key is `nil`, the handler is also `nil`.
    public static func makeHandler(for yubiKey: YubiKey?) -> ChallengeHandler? {
        guard let yubiKey = yubiKey else {
            Diag.debug("Challenge-response is not used")
            return nil
        }
        let challengeHandler: ChallengeHandler = {
            (challenge, responseHandler) in
            instance.perform(
                with: yubiKey,
                challenge: challenge,
                responseHandler: responseHandler
            )
        }
        return challengeHandler
    }
    
    // MARK: - Initialization
    
    private func initSessionObservers() {
        supportsMFI = YubiKitDeviceCapabilities.supportsMFIAccessoryKey
        if supportsMFI {
            initMFISessionObserver()
        }
        
        guard #available(iOS 13.0, *) else { return }
        supportsNFC = YubiKitDeviceCapabilities.supportsISO7816NFCTags
        if supportsNFC {
            initNFCSessionObserver()
        }
    }
    
    private func initMFISessionObserver() {
        let accessorySession = YubiKitManager.shared.accessorySession as! YKFAccessorySession
        accessorySessionStateObservation = accessorySession.observe(
            \.sessionState,
            changeHandler: {
                [weak self] (session, observedChange) in
                self?.accessorySessionStateDidChange()
            }
        )
    }
    
    @available(iOS 13.0, *)
    private func initNFCSessionObserver() {
        let nfcSession = YubiKitManager.shared.nfcSession as! YKFNFCSession
        nfcSessionStateObservation = nfcSession.observe(
            \.iso7816SessionState,
            changeHandler: { [weak self] (session, newValue) in
                self?.nfcSessionStateDidChange()
            }
        )
    }
    

    // MARK: - Session state observation

    private func accessorySessionStateDidChange() {
        let keySession = YubiKitManager.shared.accessorySession as! YKFAccessorySession
        switch keySession.sessionState {
        case .opening:
            print("Accessory session -> opening")
        case .open:
            print("Accessory session -> open")
            queue.async { [weak self] in
                guard let key = self?.currentKey else { assertionFailure(); return }
                self?.performChallengeResponse(keySession, slot: key.slot)
                keySession.stopSessionSync()
            }
        case .closing:
            print("Accessory session -> closing")
        case .closed:
            print("Accessory session -> closed")
            accessoryConnectedStateObservation = nil // stop observing
        }
    }
    
    @available(iOS 13.0, *)
    private func nfcSessionStateDidChange() {
        let keySession = YubiKitManager.shared.nfcSession as! YKFNFCSession
        switch keySession.iso7816SessionState {
        case .opening:
            print("NFC session -> opening")
        case .open:
            print("NFC session -> open")
            queue.async { [weak self] in
                guard let key = self?.currentKey else { assertionFailure(); return }
                self?.performChallengeResponse(keySession, slot: key.slot)
                keySession.stopIso7816Session()
            }
        case .pooling:
            print("NFC session -> pooling")
        case .closed:
            print("NFC session -> closed")
            if !isResponseSent {
                returnError(.cancelled)
            }
        }
    }
    
    // MARK: - Public challenge-response stuff
    
    /// Performs challenge-response, by sending the `challenge` to the YubiKey interface/slot
    /// specified by `yubiKey`. Asynchronous call, returns immediately. Once the response is ready,
    /// returns the response (or error) by calling the `responseHandler`.
    ///
    /// - Parameter yubiKey: specifies YubiKey hardware interface and slot
    /// - Parameter challenge: challenge to be sent to the key
    /// - Parameter responseHandler: callback that handles finished response (or error)
    public func perform(
        with yubiKey: YubiKey,
        challenge: SecureByteArray,
        responseHandler: @escaping ResponseHandler)
    {
        self.challenge = challenge.secureClone()
        self.responseHandler = responseHandler
        
        isResponseSent = false
        switch yubiKey.interface {
        case .nfc:
            startNFCSession(with: yubiKey, challenge: challenge, responseHandler: responseHandler)
        case .mfi:
            startMFISession(with: yubiKey, challenge: challenge, responseHandler: responseHandler)
        }
    }
    
    private func returnResponse(_ response: SecureByteArray) {
        queue.async { [weak self] in
            guard let self = self else { return }
            self.responseHandler?(response, nil)
            self.isResponseSent = true
            self.cancel()
        }
    }

    private func returnError(_ error: ChallengeResponseError) {
        queue.async { [weak self] in
            guard let self = self else { return }
            self.responseHandler?(SecureByteArray(), error)
            self.isResponseSent = true
            self.cancel()
        }
    }
    
    // MARK: - Internal session management
    
    private func startMFISession(
        with yubiKey: YubiKey,
        challenge: SecureByteArray,
        responseHandler: @escaping ResponseHandler)
    {
        guard supportsMFI else {
            returnError(.notSupportedByDeviceOrSystem(interface: yubiKey.interface.description))
            return
        }
        currentKey = yubiKey
        let keySession = YubiKitManager.shared.accessorySession
        if keySession.isKeyConnected {
            keySession.startSessionSync()
        } else {
            returnError(.keyNotConnected)
        }
    }
    
    private func startNFCSession(
        with yubiKey: YubiKey,
        challenge: SecureByteArray,
        responseHandler: @escaping ResponseHandler)
    {
        guard #available(iOS 13, *), supportsNFC else {
            returnError(.notSupportedByDeviceOrSystem(interface: yubiKey.interface.description))
            return
        }
        currentKey = yubiKey
        let nfcSession = YubiKitManager.shared.nfcSession as! YKFNFCSession
        nfcSession.startIso7816Session()
    }
    
    /// Aborts any pending operations
    private func cancel() {
        guard let currentKey = currentKey else {
            challenge?.erase()
            responseHandler = nil
            return
        }
        
        switch currentKey.interface {
        case .mfi:
            cancelMFISession()
        case .nfc:
            cancelNFCSession()
        }
        challenge?.erase()
        responseHandler = nil
        self.currentKey = nil
    }
    
    private func cancelMFISession() {
        let accessorySession = YubiKitManager.shared.accessorySession
        if accessorySession.sessionState == .opening || accessorySession.sessionState == .open {
            accessorySession.stopSession()
        }
    }
    
    private func cancelNFCSession() {
        guard #available(iOS 13, *) else { assertionFailure(); return }
    
        let nfcSession = YubiKitManager.shared.nfcSession
        nfcSession.cancelCommands()
        nfcSession.stopIso7816Session()
    }
    
    // MARK: - Low-level challenge-response communication
    
    private func performChallengeResponse(
        _ accessorySession: YKFAccessorySession,
        slot: YubiKey.Slot)
    {
        assert(accessorySession.sessionState == .open)
        let keyName = accessorySession.accessoryDescription?.name ?? "(unknown)"
        Diag.info("Connecting to \(keyName)")
        guard let rawCommandService = accessorySession.rawCommandService else {
            let message = "YubiKey raw command service is not available"
            Diag.error(message)
            returnError(.communicationError(message: message))
            return
        }
        performChallengeResponse(rawCommandService: rawCommandService, slot: slot)
    }
    
    @available(iOS 13.0, *)
    private func performChallengeResponse(
        _ nfcSession: YKFNFCSession,
        slot: YubiKey.Slot)
    {
        assert(nfcSession.iso7816SessionState == .open)
        let keyName = nfcSession.tagDescription?.identifier.description ?? "(unknown)"
        Diag.info("Found NFC tag \(keyName)")
        guard let rawCommandService = nfcSession.rawCommandService else {
            let message = "YubiKey raw command service is not available"
            Diag.error(message)
            returnError(.communicationError(message: message))
            return
        }
        performChallengeResponse(rawCommandService: rawCommandService, slot: slot)
    }

    
    private func performChallengeResponse(
        rawCommandService: YKFKeyRawCommandServiceProtocol,
        slot: YubiKey.Slot)
    {
        let appletID = Data([0xA0, 0x00, 0x00, 0x05, 0x27, 0x20, 0x01])
        guard let selectAppletAPDU =
            YKFAPDU(cla: 0x00, ins: 0xA4, p1: 0x04, p2: 0x00, data: appletID, type: .short)
            else { fatalError() }
        
        rawCommandService.executeSyncCommand(selectAppletAPDU) {
            [weak self] (response, error) in
            guard let self = self else { return }
            if let error = error {
                Diag.error("YubiKey select applet failed [message: \(error.localizedDescription)]")
                self.returnError(.communicationError(message: error.localizedDescription))
                return
            }
            
            let responseParser = RawResponseParser(response: response!)
            let statusCode = responseParser.statusCode
            if statusCode == YUBIKEY_SUCCESS {
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
        }

        guard var challengeBytes = challenge?.bytesCopy(),
            challengeBytes.count <= 64
            else { fatalError() }
        
        // YubiKey needs 64-byte challenge for compatibility reasons.
        let paddingLength = 64 - challengeBytes.count
        let pkcs7padding: [UInt8] = Array(repeating: UInt8(paddingLength), count: paddingLength)
        challengeBytes.append(contentsOf: pkcs7padding)
        let challengeData = Data(challengeBytes)
            
        let slotID = getSlotID(for: slot)
        guard let chalRespAPDU =
            YKFAPDU(cla: 0x00, ins: 0x01, p1: slotID, p2: 0x00, data: challengeData, type: .short)
            else { fatalError() }
        
        rawCommandService.executeSyncCommand(chalRespAPDU) {
            [weak self] (response, error) in
            guard let self = self else { return }
            if let error = error {
                Diag.error("YubiKey error while executing command [message: \(error.localizedDescription)]")
                self.returnError(.communicationError(message: error.localizedDescription))
                return
            }
            
            let responseParser = RawResponseParser(response: response!)
            let statusCode = responseParser.statusCode
            if statusCode == YUBIKEY_SUCCESS {
                guard let responseData = responseParser.responseData else {
                    let message = "YubiKey response is empty. Slot not configured?"
                    Diag.error(message)
                    self.returnError(.keyNotConfigured)
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
        }
    }
    
    private func getSlotID(for slot: YubiKey.Slot) -> UInt8 {
        switch slot {
        case .slot1:
            return 0x30
        case .slot2:
            return 0x38
        }
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
                return 0
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
