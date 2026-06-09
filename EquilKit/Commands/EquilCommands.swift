import Foundation

// MARK: - Pair Command

class PairCommand: BaseEquilCommand {
    let serialNumber: String
    let password: String
    var randomPassword: Data?
    var deviceKey: String?
    var runPassword: String?

    init(serialNumber: String, password: String) {
        self.serialNumber = serialNumber
        self.password = password
        super.init(port: "0E0E")
    }

    override func encode() throws -> [Data] {
        // Convert serial number (matching AndroidAPS CmdPair)
        let convertedSN = convertSerialNumber(serialNumber)
        guard let snData = Data(hexString: convertedSN) else {
            throw EquilError.invalidData("Invalid serial number")
        }

        // Hash the serial number with SHA-256
        let pwdHash = EquilEncryption.sha256(data: snData)

        // Get Equil password from user password
        let equilPassword = EquilEncryption.getEquilPassword(from: password)

        // Generate random password (32 bytes)
        randomPassword = EquilEncryption.generateRandomPassword(length: 32)

        // Concatenate equilPassword + randomPassword
        var data = Data()
        data.append(equilPassword)
        data.append(randomPassword!)

        // Encrypt with pwd hash as key
        return try createEncryptedPacket(data: data, key: pwdHash, port: "0D0D0000")
    }

    override func decode(response: Data) throws {
        guard let randomPwd = randomPassword else {
            throw EquilError.invalidData("No random password available")
        }

        // Decrypt response
        let decrypted = try decodeEncryptedResponse(response: response, key: randomPwd)
        let decryptedHex = decrypted.hexString()

        // Check for error response
        let errorPwd = String(repeating: "0", count: 64)
        if decryptedHex.hasPrefix(errorPwd) {
            throw EquilError.pumpError("Pairing failed - invalid password")
        }

        // Extract device key (first 64 hex chars = 32 bytes)
        guard decryptedHex.count >= 128 else {
            throw EquilError.invalidData("Response too short")
        }

        deviceKey = String(decryptedHex.prefix(64))
        runPassword = String(decryptedHex.suffix(64))
    }

    private func convertSerialNumber(_ sn: String) -> String {
        // Convert "Equil - XXXXX" to "0X0X0X0X0X"
        let cleaned = sn.replacingOccurrences(of: "Equil - ", with: "").trimmingCharacters(in: .whitespaces)
        return cleaned.map { "0\($0)" }.joined()
    }
}

// MARK: - Status Command

class StatusCommand: BaseEquilCommand {
    var battery: Int?
    var reservoir: Int?
    var runMode: RunMode?

    init(state _: EquilState) {
        super.init(port: "0404")
    }

    override func encode() throws -> [Data] {
        // Simple status request
        let data = Data([0x01]) // Status request code
        return createPackets(payload: data, port: port)
    }

    override func decode(response: Data) throws {
        // Parse status response
        guard response.count >= 10 else {
            throw EquilError.invalidData("Status response too short")
        }

        // Extract battery (example byte position)
        battery = Int(response[6])

        // Extract reservoir (example byte positions)
        reservoir = Int(response[7]) << 8 | Int(response[8])

        // Extract run mode
        let modeValue = response[9]
        switch modeValue {
        case 0: runMode = .none
        case 1: runMode = .run
        case 2: runMode = .suspend
        case 3: runMode = .stop
        default: runMode = .none
        }
    }
}

// MARK: - Bolus Command

class BolusCommand: BaseEquilCommand {
    let units: Double
    let state: EquilState

    init(units: Double, state: EquilState) {
        self.units = units
        self.state = state
        super.init(port: "0404")
    }

    override func encode() throws -> [Data] {
        guard let password = state.password.data(using: .utf8) else {
            throw EquilError.invalidData("Invalid password")
        }

        let key = EquilEncryption.sha256(data: password)

        // Convert units to pulses (0.05U per pulse)
        let pulses = Int(units / EquilPod.pulseSize)

        // Build bolus command data
        var data = Data()
        data.append(0x02) // Bolus command code
        data.append(UInt8((pulses >> 8) & 0xFF))
        data.append(UInt8(pulses & 0xFF))

        return try createEncryptedPacket(data: data, key: key, port: port)
    }

    override func decode(response: Data) throws {
        // Verify success response
        guard response.count >= 6 else {
            throw EquilError.invalidData("Bolus response too short")
        }

        // Check for success code
        if response[6] != 0x00 {
            throw EquilError.pumpError("Bolus command failed")
        }
    }
}

// MARK: - Temp Basal Command

class TempBasalCommand: BaseEquilCommand {
    let rate: Double
    let duration: TimeInterval
    let state: EquilState
    let cancel: Bool

    init(rate: Double, duration: TimeInterval, state: EquilState, cancel: Bool = false) {
        self.rate = rate
        self.duration = duration
        self.state = state
        self.cancel = cancel
        super.init(port: "0404")
    }

    override func encode() throws -> [Data] {
        guard let password = state.password.data(using: .utf8) else {
            throw EquilError.invalidData("Invalid password")
        }

        let key = EquilEncryption.sha256(data: password)

        var data = Data()

        if cancel {
            // Cancel temp basal
            data.append(0x04) // Cancel temp basal code
        } else {
            // Set temp basal
            data.append(0x03) // Temp basal command code

            // Rate in 0.05U/hr increments
            let rateValue = Int(rate / EquilPod.pulseSize)
            data.append(UInt8((rateValue >> 8) & 0xFF))
            data.append(UInt8(rateValue & 0xFF))

            // Duration in minutes
            let durationMinutes = Int(duration / 60)
            data.append(UInt8((durationMinutes >> 8) & 0xFF))
            data.append(UInt8(durationMinutes & 0xFF))
        }

        return try createEncryptedPacket(data: data, key: key, port: port)
    }

    override func decode(response: Data) throws {
        guard response.count >= 6 else {
            throw EquilError.invalidData("Temp basal response too short")
        }

        if response[6] != 0x00 {
            throw EquilError.pumpError("Temp basal command failed")
        }
    }
}

// MARK: - Basal Schedule Command

class BasalScheduleCommand: BaseEquilCommand {
    let schedule: BasalSchedule
    let state: EquilState

    init(schedule: BasalSchedule, state: EquilState) {
        self.schedule = schedule
        self.state = state
        super.init(port: "0404")
    }

    override func encode() throws -> [Data] {
        guard let password = state.password.data(using: .utf8) else {
            throw EquilError.invalidData("Invalid password")
        }

        let key = EquilEncryption.sha256(data: password)

        var data = Data()
        data.append(0x05) // Basal schedule command code
        data.append(UInt8(schedule.entries.count))

        for entry in schedule.entries {
            // Start time in minutes from midnight
            data.append(UInt8((entry.startTime >> 8) & 0xFF))
            data.append(UInt8(entry.startTime & 0xFF))

            // Rate in 0.05U/hr increments
            let rateValue = Int(entry.rate / EquilPod.pulseSize)
            data.append(UInt8((rateValue >> 8) & 0xFF))
            data.append(UInt8(rateValue & 0xFF))
        }

        return try createEncryptedPacket(data: data, key: key, port: port)
    }

    override func decode(response: Data) throws {
        guard response.count >= 6 else {
            throw EquilError.invalidData("Basal schedule response too short")
        }

        if response[6] != 0x00 {
            throw EquilError.pumpError("Basal schedule command failed")
        }
    }
}

// MARK: - Suspend/Resume Commands

class SuspendCommand: BaseEquilCommand {
    let state: EquilState

    init(state: EquilState) {
        self.state = state
        super.init(port: "0404")
    }

    override func encode() throws -> [Data] {
        guard let password = state.password.data(using: .utf8) else {
            throw EquilError.invalidData("Invalid password")
        }

        let key = EquilEncryption.sha256(data: password)

        var data = Data()
        data.append(0x06) // Suspend command code

        return try createEncryptedPacket(data: data, key: key, port: port)
    }

    override func decode(response: Data) throws {
        guard response.count >= 6 else {
            throw EquilError.invalidData("Suspend response too short")
        }

        if response[6] != 0x00 {
            throw EquilError.pumpError("Suspend command failed")
        }
    }
}

class ResumeCommand: BaseEquilCommand {
    let state: EquilState

    init(state: EquilState) {
        self.state = state
        super.init(port: "0404")
    }

    override func encode() throws -> [Data] {
        guard let password = state.password.data(using: .utf8) else {
            throw EquilError.invalidData("Invalid password")
        }

        let key = EquilEncryption.sha256(data: password)

        var data = Data()
        data.append(0x07) // Resume command code

        return try createEncryptedPacket(data: data, key: key, port: port)
    }

    override func decode(response: Data) throws {
        guard response.count >= 6 else {
            throw EquilError.invalidData("Resume response too short")
        }

        if response[6] != 0x00 {
            throw EquilError.pumpError("Resume command failed")
        }
    }
}

// MARK: - Cancel Bolus Command

class CancelBolusCommand: BaseEquilCommand {
    let state: EquilState

    init(state: EquilState) {
        self.state = state
        super.init(port: "0404")
    }

    override func encode() throws -> [Data] {
        guard let password = state.password.data(using: .utf8) else {
            throw EquilError.invalidData("Invalid password")
        }

        let key = EquilEncryption.sha256(data: password)

        var data = Data()
        data.append(0x08) // Cancel bolus command code

        return try createEncryptedPacket(data: data, key: key, port: port)
    }

    override func decode(response: Data) throws {
        guard response.count >= 6 else {
            throw EquilError.invalidData("Cancel bolus response too short")
        }

        if response[6] != 0x00 {
            throw EquilError.pumpError("Cancel bolus command failed")
        }
    }
}

// Made with Bob
