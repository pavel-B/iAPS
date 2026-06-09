import Foundation

// Base protocol for all Equil commands
protocol EquilCommand: AnyObject {
    var port: String { get }
    var completion: ((Result<Data, Error>) -> Void)? { get set }

    func encode() throws -> [Data]
    func decode(response: Data) throws
}

// Base class for Equil commands
class BaseEquilCommand: EquilCommand {
    var port: String
    var completion: ((Result<Data, Error>) -> Void)?

    private static var requestIndex: UInt8 = 0
    private static let requestIndexLock = NSLock()

    init(port: String) {
        self.port = port
    }

    func encode() throws -> [Data] {
        fatalError("Must be overridden by subclass")
    }

    func decode(response _: Data) throws {
        fatalError("Must be overridden by subclass")
    }

    // Create packets following Equil protocol (matching AndroidAPS BaseCmd.responseCmd)
    func createPackets(payload: Data, port _: String) -> [Data] {
        var packets: [Data] = []
        let maxPayloadPerPacket = 10
        var offset = 0
        var packetIndex = 0

        // Calculate total packets needed
        let totalPayloadSize = payload.count
        let packetCount = (totalPayloadSize + maxPayloadPerPacket - 1) / maxPayloadPerPacket

        while offset < totalPayloadSize {
            let remainingBytes = totalPayloadSize - offset
            let payloadSize = min(remainingBytes, maxPayloadPerPacket)
            let isLastPacket = (offset + payloadSize) >= totalPayloadSize

            var packet = Data()

            // Header (2 bytes)
            packet.append(contentsOf: [0x00, 0x00])

            // Length byte
            packet.append(UInt8(6 + payloadSize))

            // Offset byte
            packet.append(UInt8(packetIndex * 10))

            // Flags byte (includes request index and end flag)
            var flags = BaseEquilCommand.getNextRequestIndex()
            if isLastPacket {
                flags |= 0x80 // Set end bit (bit 7)
            }
            packet.append(flags)

            // CRC8 (calculated on first 5 bytes)
            let crc = EquilEncryption.crc8Maxim(data: packet)
            packet.append(crc)

            // Payload
            let payloadSlice = payload.subdata(in: offset ..< (offset + payloadSize))
            packet.append(payloadSlice)

            packets.append(packet)
            offset += payloadSize
            packetIndex += 1
        }

        return packets
    }

    // Create encrypted command packet
    func createEncryptedPacket(data: Data, key: Data, port: String) throws -> [Data] {
        // Encrypt the data
        let encrypted = try EquilEncryption.encrypt(data: data, key: key)

        // Build the payload: port + tag + iv + ciphertext
        var payload = Data()

        // Port (4 hex chars = 2 bytes)
        if let portData = Data(hexString: port) {
            payload.append(portData)
        }

        // Tag (16 bytes)
        payload.append(encrypted.tag)

        // IV (12 bytes)
        payload.append(encrypted.iv)

        // Ciphertext
        payload.append(encrypted.ciphertext)

        // Calculate CRC16 for the entire payload
        let crc16 = EquilEncryption.crc16(data: payload)

        // Insert CRC16 after port (at position 2)
        var finalPayload = Data()
        finalPayload.append(payload.prefix(2)) // Port
        finalPayload.append(contentsOf: crc16) // CRC16
        finalPayload.append(payload.suffix(from: 2)) // Rest of payload

        return createPackets(payload: finalPayload, port: port)
    }

    // Decode encrypted response
    func decodeEncryptedResponse(response: Data, key: Data) throws -> Data {
        // Extract components from response packets
        var combinedData = Data()
        var offset = 0

        while offset < response.count {
            guard offset + 6 <= response.count else { break }

            let packetLength = Int(response[offset + 2])
            guard offset + packetLength <= response.count else { break }

            // Extract payload (skip header, length, offset, flags, crc)
            let payloadStart = offset + 6
            let payloadEnd = offset + packetLength

            if payloadStart < payloadEnd, payloadEnd <= response.count {
                combinedData.append(response.subdata(in: payloadStart ..< payloadEnd))
            }

            offset += packetLength
        }

        // Parse encrypted data: skip port (2 bytes) + CRC16 (2 bytes)
        guard combinedData.count > 4 else {
            throw EquilError.invalidData("Response too short")
        }

        let encryptedData = combinedData.suffix(from: 4)

        // Extract tag (16 bytes), IV (12 bytes), ciphertext (rest)
        guard encryptedData.count >= 28 else {
            throw EquilError.invalidData("Encrypted data too short")
        }

        let tag = encryptedData.prefix(16)
        let iv = encryptedData.subdata(in: 16 ..< 28)
        let ciphertext = encryptedData.suffix(from: 28)

        // Decrypt
        return try EquilEncryption.decrypt(ciphertext: ciphertext, key: key, iv: iv, tag: tag)
    }

    private static func getNextRequestIndex() -> UInt8 {
        requestIndexLock.lock()
        defer { requestIndexLock.unlock() }

        let index = requestIndex
        requestIndex = (requestIndex + 1) & 0x3F // Keep within 6 bits (0-63)
        return index
    }
}

// MARK: - Data Extension for Hex Conversion

extension Data {
    init?(hexString: String) {
        let len = hexString.count / 2
        var data = Data(capacity: len)
        var i = hexString.startIndex

        for _ in 0 ..< len {
            let j = hexString.index(i, offsetBy: 2)
            let bytes = hexString[i ..< j]
            if var num = UInt8(bytes, radix: 16) {
                data.append(&num, count: 1)
            } else {
                return nil
            }
            i = j
        }

        self = data
    }

    func hexString() -> String {
        map { String(format: "%02x", $0) }.joined()
    }
}

// Made with Bob
