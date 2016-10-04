import CLibreSSL
import Foundation
import Hash
import HMAC

public enum Algorithm {
    case none
    case es(HashSize)
    case hs(HashSize)
    //    case rs(HashSize)
}

public extension Algorithm {

    public init(_ string: String, key: String) throws {
        guard string != "none" else {
            self = .none
            return
        }

        guard let hashSizeStartIndex =
            string.index(string.startIndex, offsetBy: 2, limitedBy: string.endIndex) else {
                throw JWTError.unsupportedAlgorithm
        }

        let hashSize = try HashSize(string[hashSizeStartIndex..<string.endIndex], key: key)

        switch string.substring(to: hashSizeStartIndex).lowercased() {
        case "es":
            self = .es(hashSize)
        case "hs":
            self = .hs(hashSize)
        default:
            throw JWTError.unsupportedAlgorithm
        }
    }

    public var headerValue: String {
        switch self {
        case .none: return "none"
        case .hs(let hashSize):
            return "HS" + hashSize.string
        case .es(let hashSize):
            return "ES" + hashSize.string
        }
    }

    public func encrypt(_ message: String) throws -> String {
        switch self {
        case .hs(let hashSize):
            return try HMAC(hashSize.shaHMACMethod, message.bytes)
                .authenticate(key: hashSize.key.bytes).base64String
        case .es(let hashSize):
            var digest = try Hash(hashSize.shaHashMethod, message.bytes).hash()
            let ecKey = try hashSize.newECKeyPair()

            guard let sig = ECDSA_do_sign(&digest, Int32(digest.count), ecKey) else {
                throw JWTError.couldNotGenerateKey
            }

            var byte: UnsafeMutablePointer<UInt8>? = nil
            let derLength = i2d_ECDSA_SIG(sig, &byte)

            guard let byte2 = byte, derLength > 0 else {
                throw JWTError.couldNotGenerateKey
            }

            var bytes: [UInt8] = [UInt8](repeating: 0, count: Int(derLength))

            for b in 0..<Int(derLength) {
                bytes[b] = byte2[b]
            }

            return bytes.base64String
        default:
            return ""
        }
    }

    public func verifySignature(_ signature: String, message: String) throws -> Bool {
        switch self {
        case .none: return true
        case .hs:
            return try encrypt(message) == signature
        case .es(let hashSize):
            guard let der = Data(base64Encoded: signature) else {
                throw JWTError.notBase64Encoded
            }
            let derBytes = try der.makeBytes()
            var derBytesPointer: UnsafePointer? = UnsafePointer(derBytes)
            let signature = d2i_ECDSA_SIG(nil, &derBytesPointer, derBytes.count)
            let digest = try Hash(hashSize.shaHashMethod, message.bytes).hash()
            let ecKey = try hashSize.newECPublicKey()
            let verified = ECDSA_do_verify(digest, Int32(digest.count), signature, ecKey)
            return verified == 1
        }
    }
}
