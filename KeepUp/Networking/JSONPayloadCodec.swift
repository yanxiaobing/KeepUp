import Foundation
import Security
import SwiftyRSA

/// Compatibility with QuitSmoke's chunked RSA/PKCS#1 v1.5 JSON envelope.
/// HTTPS remains required; this legacy envelope is not a signature.
struct JSONPayloadCodec: Sendable {
    enum CodecError: Error { case invalidEnvelope, encryptionFailed }
    var publicKeyPEM: String = LegacyRSAKeys.pubKey
    var privateKeyPEM: String = LegacyRSAKeys.priKey

    func decode<T: Decodable>(_ type: T.Type, from data: Data) throws -> T {
        try JSONDecoder().decode(type, from: plaintext(data))
    }

    func plaintext(_ data: Data) throws -> Data {
        let json = try JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed])
        guard let object = json as? [String: Any], object.keys.contains("_xb_encrypted") else { return data }
        guard let string = object["_xb_encrypted"] as? String,
              let encrypted = Data(base64Encoded: string), !encrypted.isEmpty else {
            throw CodecError.invalidEnvelope
        }
        let key = try PrivateKey(pemEncoded: privateKeyPEM)
        guard encrypted.count.isMultiple(of: SecKeyGetBlockSize(key.reference)) else {
            throw CodecError.invalidEnvelope
        }
        return try EncryptedMessage(data: encrypted).decrypted(with: key, padding: .PKCS1).data
    }

    func encrypt(_ data: Data) throws -> Data {
        guard !data.isEmpty else { throw CodecError.encryptionFailed }
        let key = try PublicKey(pemEncoded: publicKeyPEM)
        let encrypted = try ClearMessage(data: data).encrypted(with: key, padding: .PKCS1)
        return try JSONSerialization.data(withJSONObject: ["_xb_encrypted": encrypted.base64String])
    }
}
