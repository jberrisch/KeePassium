//  KeePassium Password Manager
//  Copyright © 2018–2019 Andrei Popleteev <info@keepassium.com>
// 
//  This program is free software: you can redistribute it and/or modify it
//  under the terms of the GNU General Public License version 3 as published
//  by the Free Software Foundation: https://www.gnu.org/licenses/).
//  For commercial licensing, please contact the author.

import Foundation

class AESKDF: KeyDerivationFunction {
    
    private static let _uuid = UUID(uuid: (0xC9,0xD9,0xF3,0x9A,0x62,0x8A,0x44,0x60,0xBF,0x74,0x0D,0x08,0xC1,0x8A,0x4F,0xEA))
    public static let transformSeedParam = "S"
    public static let transformRoundsParam = "R"
    
    public var uuid: UUID { return AESKDF._uuid }
    public var name: String { return "AES KDF" }
    
    private let subkeySize = 16
    private var progress = ProgressEx()
    

    public var defaultParams: KDFParams {
        let params = KDFParams()
        params.setValue(key: KDFParams.uuidParam, value: VarDict.TypedValue(value: uuid.data))
        
        let transformSeed = ByteArray(count: SHA256_SIZE) // to be randomized separately
        params.setValue(
            key: AESKDF.transformSeedParam,
            value: VarDict.TypedValue(value: transformSeed))
        params.setValue(
            key: AESKDF.transformRoundsParam,
            value: VarDict.TypedValue(value: UInt64(100_000)))
        return params
    }
    
    required init() {
        // nothing to do here
    }
    
    func initProgress() -> ProgressEx {
        progress = ProgressEx()
        progress.localizedDescription = NSLocalizedString(
            "[KDF/Progress] Processing the master key",
            bundle: Bundle.framework,
            value: "Processing the master key",
            comment: "Status message: processing of the master key is in progress")
        return progress
    }
    
    
    /// Returns the parameter that should be used for challenge-response.
    /// Throws `CryptoError.invalidKDFParam`
    func getChallenge(_ params: KDFParams) throws -> ByteArray {
        guard let transformSeed = params.getValue(key: AESKDF.transformSeedParam)?.asByteArray() else {
            throw CryptoError.invalidKDFParam(kdfName: name, paramName: AESKDF.transformSeedParam)
        }
        return transformSeed
    }
    
    /// Randomize KDF parameters (for example, before saving the DB)
    /// - Throws: CryptoError.rngError
    func randomize(params: inout KDFParams) throws {
        let transformSeed = try CryptoManager.getRandomBytes(count: SHA256_SIZE)
        params.setValue(
            key: AESKDF.transformSeedParam,
            value: VarDict.TypedValue(value: transformSeed))
    }
    
    /// Performs AES-based key transformation.
    /// - Throws: CryptoError, ProgressInterruption
    /// - Returns: resulting key
    func transform(key compositeKey: SecureByteArray, params: KDFParams) throws -> SecureByteArray {
        guard let transformSeed = params.getValue(key: AESKDF.transformSeedParam)?.asByteArray() else {
            throw CryptoError.invalidKDFParam(kdfName: name, paramName: AESKDF.transformSeedParam)
        }
        guard let transformRounds = params.getValue(key: AESKDF.transformRoundsParam)?.asUInt64() else {
            throw CryptoError.invalidKDFParam(kdfName: name, paramName: AESKDF.transformRoundsParam)
        }
        assert(transformSeed.count == Int(kCCKeySizeAES256))
        assert(compositeKey.count == SHA256_SIZE)
        
        progress.totalUnitCount = Int64(transformRounds)
        
        // Key transformation alters the key, but we want compositeKey intact. So make a copy.
        let keyCopy = compositeKey.secureClone()
        
        let status = transformSeed.withBytes { (trSeedBytes)  in
            return keyCopy.withMutableBytes { (trKeyBytes: inout [UInt8]) -> Int32 in
                
                // Unfortunately, Swift prevents the use of the same array as input and output params
                // for CCCryptorUpdate(). But making an array copy on every round is waaay slow.
                // As a workaround, we delegate the transformation rounds to the native code
                // which does not need to make intermediate array copies, hence works much faster.
                
                // pointer to the object to pass to the callback
                let progressPtr = UnsafeRawPointer(Unmanaged.passUnretained(progress).toOpaque())
                return aeskdf_rounds(
                    trSeedBytes,
                    &trKeyBytes,
                    transformRounds,
                    {
                        (round: UInt64, progressPtr: Optional<UnsafeRawPointer>) -> Int32 in
                        guard let progressPtr = progressPtr else {
                            return 0 /* continue transformations */
                        }
                        let progress = Unmanaged<ProgressEx>
                            .fromOpaque(progressPtr)
                            .takeUnretainedValue()
                        progress.completedUnitCount = Int64(round)
                        let isShouldStop: Int32 = progress.isCancelled ? 1 : 0
                        return isShouldStop
                    },
                    progressPtr)
            }
        }
        progress.completedUnitCount = progress.totalUnitCount
        if progress.isCancelled {
            throw ProgressInterruption.cancelled(reason: progress.cancellationReason)
        }
        
        guard status == kCCSuccess else {
            Diag.error("doRounds() crypto error [code: \(status)]")
            throw CryptoError.aesEncryptError(code: Int(status))
        }
        return keyCopy.sha256
    }
}
