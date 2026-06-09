import CommonCrypto
import CryptoKit
import Foundation

public enum EquilEncryption {
    // AES-256-GCM encryption matching AndroidAPS Equil implementation
    public static func encrypt(data: Data, key: Data) throws -> (ciphertext: Data, iv: Data, tag: Data) {
        guard key.count == 32 else {
            throw EquilError.encryptionError("Invalid key length")
        }

        // Generate random IV (12 bytes for GCM)
        var iv = Data(count: 12)
        let result = iv.withUnsafeMutableBytes { ivBytes in
            SecRandomCopyBytes(kSecRandomDefault, 12, ivBytes.baseAddress!)
        }

        guard result == errSecSuccess else {
            throw EquilError.encryptionError("Failed to generate IV")
        }

        // Use CryptoKit for AES-GCM encryption
        let symmetricKey = SymmetricKey(data: key)
        let nonce = try AES.GCM.Nonce(data: iv)
        let sealedBox = try AES.GCM.seal(data, using: symmetricKey, nonce: nonce)

        return (
            ciphertext: sealedBox.ciphertext,
            iv: iv,
            tag: sealedBox.tag
        )
    }

    public static func decrypt(ciphertext: Data, key: Data, iv: Data, tag: Data) throws -> Data {
        guard key.count == 32 else {
            throw EquilError.encryptionError("Invalid key length")
        }

        let symmetricKey = SymmetricKey(data: key)
        let nonce = try AES.GCM.Nonce(data: iv)
        let sealedBox = try AES.GCM.SealedBox(nonce: nonce, ciphertext: ciphertext, tag: tag)

        return try AES.GCM.open(sealedBox, using: symmetricKey)
    }

    // SHA-256 hash for password derivation (matching AndroidAPS)
    public static func sha256(data: Data) -> Data {
        var hash = [UInt8](repeating: 0, count: Int(CC_SHA256_DIGEST_LENGTH))
        data.withUnsafeBytes {
            _ = CC_SHA256($0.baseAddress, CC_LONG(data.count), &hash)
        }
        return Data(hash)
    }

    // Generate random password (for pairing)
    public static func generateRandomPassword(length: Int) -> Data {
        var data = Data(count: length)
        let result = data.withUnsafeMutableBytes {
            SecRandomCopyBytes(kSecRandomDefault, length, $0.baseAddress!)
        }

        guard result == errSecSuccess else {
            // Fallback to less secure random if SecRandom fails
            for i in 0 ..< length {
                data[i] = UInt8.random(in: 0 ... 255)
            }
        }

        return data
    }

    // Get Equil password from user password (matching AndroidAPS AESUtil.getEquilPassWord)
    public static func getEquilPassword(from password: String) -> Data {
        let passwordData = password.data(using: .utf8) ?? Data()
        return sha256(data: passwordData)
    }

    // CRC8 calculation (Maxim/Dallas algorithm)
    public static func crc8Maxim(data: Data) -> UInt8 {
        var crc: UInt8 = 0

        for byte in data {
            crc ^= byte
            for _ in 0 ..< 8 {
                if (crc & 0x80) != 0 {
                    crc = (crc << 1) ^ 0x31
                } else {
                    crc <<= 1
                }
            }
        }

        return crc
    }

    // CRC16 calculation for larger packets
    public static func crc16(data: Data) -> [UInt8] {
        var crc: UInt16 = 0xFFFF

        for byte in data {
            crc ^= UInt16(byte)
            for _ in 0 ..< 8 {
                if (crc & 0x0001) != 0 {
                    crc = (crc >> 1) ^ 0xA001
                } else {
                    crc >>= 1
                }
            }
        }

        // Return as little-endian bytes
        return [UInt8(crc & 0xFF), UInt8((crc >> 8) & 0xFF)]
    }
}

public enum EquilError: Error, LocalizedError {
    case encryptionError(String)
    case decryptionError(String)
    case invalidData(String)
    case communicationError(String)
    case pumpError(String)
    case noPumpPaired
    case pumpAlreadyPaired
    case invalidResponse
    case timeout

    public var errorDescription: String? {
        switch self {
        case let .encryptionError(msg):
            return "Encryption error: \(msg)"
        case let .decryptionError(msg):
            return "Decryption error: \(msg)"
        case let .invalidData(msg):
            return "Invalid data: \(msg)"
        case let .communicationError(msg):
            return "Communication error: \(msg)"
        case let .pumpError(msg):
            return "Pump error: \(msg)"
        case .noPumpPaired:
            return "No Equil pump paired"
        case .pumpAlreadyPaired:
            return "Equil pump already paired"
        case .invalidResponse:
            return "Invalid response from pump"
        case .timeout:
            return "Communication timeout"
        }
    }
}

// Made with Bob
