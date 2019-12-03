//  KeePassium Password Manager
//  Copyright © 2018–2019 Andrei Popleteev <info@keepassium.com>
//
//  This program is free software: you can redistribute it and/or modify it
//  under the terms of the GNU General Public License version 3 as published
//  by the Free Software Foundation: https://www.gnu.org/licenses/).
//  For commercial licensing, please contact the author.

import Foundation

/// A collection of master key components
/// (password, key file, challenge-response handler)
public class CompositeKey {
    public enum State: Int, Comparable {
        case empty               = 0 // not initialized
        case rawComponents       = 1 // password and keyFileRef set, but not loaded
        case processedComponents = 2 // password converted to bytes, keyFile data loaded
        case combinedComponents  = 3 // password and keyFile data hashed and merged
        case final = 4
        
        public static func < (lhs: CompositeKey.State, rhs: CompositeKey.State) -> Bool {
            return lhs.rawValue < rhs.rawValue
        }
    }
    
    static let empty = CompositeKey()

    internal private(set) var state: State
    
    // These vars are valid in the .rawComponents state
    internal private(set) var password: String
    internal private(set) var keyFileRef: URLReference?
    public var challengeHandler: ChallengeHandler? // can be set by the UI
    
    // These vars are valid in the .processedComponents state
    internal private(set) var passwordData: SecureByteArray?
    internal private(set) var keyFileData: ByteArray?
    
    // These vars are valid in the .preTransform state
    /// password and key file concatenated, but not hashed yet
    internal private(set) var combinedStaticComponents: SecureByteArray?
    
    // These vars are valid in the .final state
    internal private(set) var finalKey: SecureByteArray?
    
    
    init() {
        self.password = ""
        self.keyFileRef = nil
        self.challengeHandler = nil
        state = .empty
    }
    
    /// Initializes an instance in the .rawComponents state
    init(password: String, keyFileRef: URLReference?, challengeHandler: ChallengeHandler?) {
        self.password = password
        self.keyFileRef = keyFileRef
        self.challengeHandler = challengeHandler
        state = .rawComponents
    }
    
    /// Initializes an instance in the .processedComponents state
    //TODO: probably redundant
    init(
        passwordData: SecureByteArray,
        keyFileData: ByteArray,
        challengeHandler: ChallengeHandler?)
    {
        self.password = ""
        self.keyFileRef = nil
        self.passwordData = passwordData
        self.keyFileData = keyFileData
        self.challengeHandler = challengeHandler
        
        state = .processedComponents
    }
    
    /// Alternative .preChallenge initializer
    init(staticComponents: SecureByteArray, challengeHandler: ChallengeHandler?) {
        self.password = ""
        self.keyFileRef = nil
        self.passwordData = nil
        self.keyFileData = nil
        self.combinedStaticComponents = staticComponents
        self.challengeHandler = challengeHandler
        state = .combinedComponents
    }
    
    deinit {
        erase()
    }
    
    func erase() {
        password.erase()
        keyFileRef = nil
        challengeHandler = nil
        
        passwordData?.erase()
        passwordData = nil
        keyFileData?.erase()
        keyFileData = nil
        
        combinedStaticComponents?.erase()
        combinedStaticComponents = nil
        
        state = .empty
    }

    func setProcessedComponents(passwordData: SecureByteArray, keyFileData: ByteArray) {
        assert(state == .rawComponents)
        self.passwordData = passwordData
        self.keyFileData = keyFileData
        state = .processedComponents
        
        self.password.erase()
        self.keyFileRef = nil
        // keep challengeHandler intact, though
        self.finalKey?.erase()
        self.finalKey = nil
    }
    
    func setCombinedStaticComponents(_ staticComponents: SecureByteArray) {
        assert(state <= .combinedComponents)
        self.combinedStaticComponents = staticComponents
        state = .combinedComponents
        
        self.password.erase()
        self.keyFileRef = nil
        self.passwordData?.erase()
        self.passwordData = nil
        self.keyFileData?.erase()
        self.keyFileData = nil
        // keep challengeHandler intact, though
        
        self.finalKey?.erase()
        self.finalKey = nil
    }
    
    func setFinalKey(_ finalKey: SecureByteArray) {
        assert(state == .combinedComponents)
        self.finalKey = finalKey
        state = .final
        // keep the combined components and challengeHandler, will need them for saving
    }
    
    /// - Throws: `ChallengeResponseError`
    func getResponse(challenge: SecureByteArray) throws -> SecureByteArray  {
        guard let handler = self.challengeHandler else {
            return SecureByteArray()
        }
        
        // Challenge-response is inherently asynchronous.
        // For convenience, we make it synchronous in this method.
        // That is, block the database queue with a semaphore
        // and wait until there is either a response or an error.
        
        var response: SecureByteArray?
        var challengeError: ChallengeResonseError?
        let responseReadySemaphore = DispatchSemaphore(value: 0)
        DispatchQueue.global(qos: .default).async {
            handler(challenge) {
                (_response, _error) in
                if let _error = _error {
                    // got a problem, remember it and quit
                    challengeError = _error
                    responseReadySemaphore.signal()
                    return
                }
                // got a response, remember it and quit
                response = _response
                responseReadySemaphore.signal()
            }
        }
        responseReadySemaphore.wait()
        
        if let challengeError = challengeError {
            throw challengeError // throws `ChallengeResponseError`
        } else if let response = response {
            return response
        } else {
            preconditionFailure("You should not be here")
        }
    }
}
