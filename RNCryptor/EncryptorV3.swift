//
//  Encryptor.swift
//  RNCryptor
//
//  Created by Rob Napier on 6/27/15.
//  Copyright © 2015 Rob Napier. All rights reserved.
//

import CommonCrypto


public final class EncryptorV3: CryptorType, Writable {
    // Sink chain is Cryptor -> Tee -> HMAC
    //                              -> Sink

    private let sink: Writable

    // There is no default value for these, they have to be var! in order to throw in init()
    private var engine: Engine
    private var hmacSink: HMACWriter

    private var pendingHeader: [UInt8]?

    private init(encryptionKey: [UInt8], hmacKey: [UInt8], iv: [UInt8], header: [UInt8], sink: Writable) {
        self.sink = sink
        self.hmacSink = HMACWriter(key: hmacKey)
        let tee = TeeWriter(self.hmacSink, sink)
        self.engine = Engine(operation: .Encrypt, key: encryptionKey, iv: iv, sink: tee)
        self.pendingHeader = header
    }

    // Expose random numbers for testing
    internal convenience init(encryptionKey: [UInt8], hmacKey: [UInt8], iv: [UInt8], sink: Writable) {
        var header = [UInt8]()
        header.extend([RNCryptorV3.version, UInt8(0)])
        header.extend(iv)
        self.init(encryptionKey: encryptionKey, hmacKey: hmacKey, iv: iv, header: header, sink: sink)
    }

    public convenience init(encryptionKey: [UInt8], hmacKey: [UInt8], sink: Writable) {
        self.init(encryptionKey: encryptionKey, hmacKey: hmacKey, iv: randomDataOfLength(RNCryptorV3.ivSize), sink: sink)
    }

    // Expose random numbers for testing
    internal convenience init(password: String, encryptionSalt: [UInt8], hmacSalt: [UInt8], iv: [UInt8], sink: Writable) {
        let encryptionKey = RNCryptorV3.keyForPassword(password, salt: encryptionSalt)
        let hmacKey = RNCryptorV3.keyForPassword(password, salt: hmacSalt)
        var header = [UInt8]()
        header.extend([RNCryptorV3.version, UInt8(1)])
        header.extend(encryptionSalt)
        header.extend(hmacSalt)
        header.extend(iv)
        self.init(encryptionKey: encryptionKey, hmacKey: hmacKey, iv: iv, header: header, sink: sink)
    }

    public convenience init(password: String, sink: Writable) {
        self.init(
            password: password,
            encryptionSalt: randomDataOfLength(RNCryptorV3.saltSize),
            hmacSalt:randomDataOfLength(RNCryptorV3.saltSize),
            iv: randomDataOfLength(RNCryptorV3.ivSize),
            sink: sink)
    }

    public func write(data: UnsafeBufferPointer<UInt8>) throws {
        if let header = self.pendingHeader {
            try header.withUnsafeBufferPointer { buf -> Void in
                try self.sink.write(buf)
                try self.hmacSink.write(buf)
            }
            self.pendingHeader = nil
        }

        try self.engine.write(data) // Cryptor -> HMAC -> sink
    }

    public func finish() throws {
        try self.engine.finish()
        try self.sink.write(self.hmacSink.final())
    }
}
