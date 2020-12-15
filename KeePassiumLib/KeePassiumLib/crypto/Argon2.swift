//  KeePassium Password Manager
//  Copyright © 2018–2019 Andrei Popleteev <info@keepassium.com>
// 
//  This program is free software: you can redistribute it and/or modify it
//  under the terms of the GNU General Public License version 3 as published
//  by the Free Software Foundation: https://www.gnu.org/licenses/).
//  For commercial licensing, please contact the author.

import Foundation

/// Swift wrapper for C-code Argon2 hashing function.
public final class Argon2 {
    public static let version: UInt32 = 0x13
    
    public struct Params {
        /// salt array
        let salt: ByteArray
        /// requested parallelism (`nThreads`)
        let parallelism: UInt32
        /// requessted memory in KiB (`m_cost`)
        let memoryKiB: UInt32
        /// number of iterations (`t_cost`)
        let iterations: UInt32
        /// algorithm version
        let version: UInt32
    }
    
    /// Argon2 primitve type
    public enum PrimitiveType {
        case argon2d
        case argon2id
        
        var rawValue: argon2_type {
            let result: argon2_type
            switch self {
            case .argon2d:
                result = Argon2_d
            case .argon2id:
                result = Argon2_id
            }
            return result
        }
    }
    
    private init() {
        // nothing to do
    }
    
    /// Returns Argon2 hash
    ///
    /// - Parameters:
    ///   - data: data to hash
    ///   - params: Argon2 parameters
    ///   - primitiveType: Argon2 primitive type
    ///   - progress: initialized `Progress` instance to track iterations
    /// - Returns: 32-byte hash array
    /// - Throws: CryptoError.argon2Error, ProgressInterruption
    public static func hash(
        data pwd: ByteArray,
        params: Params,
        type: PrimitiveType,
        progress: ProgressEx?
        ) throws -> ByteArray
    {
        // 1. Inside this func, we switch to original Argon2 parameter names for clarity.
        // 2. Argon2 implementation in KeePass2 can take the optional "secret key"
        //    and "associated data" parameters. However, we use the reference implementation
        //    of argon2_hash() which ignores these -- so we ignore them too.

        var isAbortProcessing: UInt8 = 0
        
        progress?.totalUnitCount = Int64(params.iterations)
        progress?.completedUnitCount = 0
        let progressKVO = progress?.observe(
            \.isCancelled,
            options: [.new],
            changeHandler: { (progress, _) in
                if progress.cancellationReason == .lowMemoryWarning {
                    // We probably won't be able to wipe the memory.
                    // This is because `malloc` has _reserved_, but did not necessarily _allocate_
                    // all the needed physical pages, but `memset_sec` will be trying to
                    // wipe _all_ of them. Thus causing actual allocation,
                    // and only aggravating the memory condition.
                    // So we skip clearing the internal memory in low-memory state.
                    FLAG_clear_internal_memory = 0
                }
                isAbortProcessing = 1
            }
        )
        
        FLAG_clear_internal_memory = 1
        //TODO: ugly nesting, refactor
        var outBytes = [UInt8](repeating: 0, count: 32)
        let statusCode = pwd.withBytes {
            (pwdBytes) in
            return params.salt.withBytes {
                (saltBytes) -> Int32 in
                guard let progress = progress else {
                    // no progress - no callback
                    return argon2_hash(
                        params.iterations,  // t_cost: UInt32
                        params.memoryKiB,   // m_cost: UInt32
                        params.parallelism, // parallelism: UInt32
                        pwdBytes, pwdBytes.count,   // pwd: UnsafeRawPointer!, pwdlen: Int
                        saltBytes, saltBytes.count, // salt: UnsafeRawPointer!, saltlen: Int
                        &outBytes, outBytes.count,  // hash: UnsafeMutableRawPointer!, hashlen: Int
                        nil, 0,         // encoded: UnsafeMutablePointer<Int8>!, encodedlen: Int
                        type.rawValue,  // type: argon2_type
                        params.version, // version: UInt32
                        nil,            // progress_cbk: progress_fptr!
                        nil,            // progress_user_obj: UnsafeRawPointer!
                        &isAbortProcessing // flag_abort: UnsafePointer<UInt8>!
                    )
                }
                
                // pointer to the object to pass to the callback
                let progressPtr = UnsafeRawPointer(Unmanaged.passUnretained(progress).toOpaque())
                
                return argon2_hash(
                    params.iterations,
                    params.memoryKiB,
                    params.parallelism,
                    pwdBytes, pwdBytes.count,
                    saltBytes, saltBytes.count,
                    &outBytes, outBytes.count,
                    nil, 0,
                    type.rawValue,
                    params.version,
                    // A closure for updating progress from the C code
                    {
                        (pass: UInt32, observer: Optional<UnsafeRawPointer>) -> Int32 in
                        guard let observer = observer else { return 0 /* continue hashing */ }
                        let progress = Unmanaged<Progress>.fromOpaque(observer).takeUnretainedValue()
                        progress.completedUnitCount = Int64(pass)
                        // print("Argon2 pass: \(pass)")
                        let isShouldStop: Int32 = progress.isCancelled ? 1 : 0
                        return isShouldStop
                    },
                    progressPtr,
                    &isAbortProcessing)
            }
        }
        progressKVO?.invalidate()
        if let progress = progress {
            progress.completedUnitCount = Int64(params.iterations) // for consistency
            if progress.isCancelled {
                throw ProgressInterruption.cancelled(reason: progress.cancellationReason)
            }
        }
        
        if statusCode != ARGON2_OK.rawValue {
            throw CryptoError.argon2Error(code: Int(statusCode))
        }
        return ByteArray(bytes: outBytes)
    }
}
