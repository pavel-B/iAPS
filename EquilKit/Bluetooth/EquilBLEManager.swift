import CoreBluetooth
import Foundation
import os.log

protocol EquilBLEManagerDelegate: AnyObject {
    func bleManager(_ manager: EquilBLEManager, didUpdateState state: CBManagerState)
    func bleManager(_ manager: EquilBLEManager, didConnect peripheral: CBPeripheral)
    func bleManager(_ manager: EquilBLEManager, didDisconnect peripheral: CBPeripheral, error: Error?)
    func bleManager(_ manager: EquilBLEManager, didReceiveData data: Data)
}

class EquilBLEManager: NSObject {
    private let log = OSLog(category: "EquilBLEManager")

    // BLE UUIDs for Equil (from AndroidAPS GattAttributes)
    private let serviceUUID = CBUUID(string: "0000fff0-0000-1000-8000-00805f9b34fb")
    private let writeCharacteristicUUID = CBUUID(string: "0000fff2-0000-1000-8000-00805f9b34fb")
    private let notifyCharacteristicUUID = CBUUID(string: "0000fff1-0000-1000-8000-00805f9b34fb")

    weak var delegate: EquilBLEManagerDelegate?

    private var centralManager: CBCentralManager!
    private var peripheral: CBPeripheral?
    private var writeCharacteristic: CBCharacteristic?
    private var notifyCharacteristic: CBCharacteristic?

    private var commandQueue: [EquilCommand] = []
    private var currentCommand: EquilCommand?
    private var responseData = Data()

    private var isScanning = false
    private var targetAddress: String?

    var isConnected: Bool {
        peripheral?.state == .connected
    }

    override init() {
        super.init()
        centralManager = CBCentralManager(delegate: self, queue: nil)
    }

    func connectToDevice(address: String) {
        log.info("Attempting to connect to device: \(address)")
        targetAddress = address

        guard centralManager.state == .poweredOn else {
            log.error("Bluetooth not powered on")
            return
        }

        // Try to retrieve already connected peripherals
        let peripherals = centralManager.retrieveConnectedPeripherals(withServices: [serviceUUID])

        if let peripheral = peripherals.first(where: { $0.identifier.uuidString == address }) {
            self.peripheral = peripheral
            peripheral.delegate = self
            centralManager.connect(peripheral, options: nil)
        } else {
            // Start scanning
            startScanning()
        }
    }

    private func startScanning() {
        guard !isScanning else { return }

        log.info("Starting BLE scan")
        isScanning = true
        centralManager.scanForPeripherals(withServices: [serviceUUID], options: [
            CBCentralManagerScanOptionAllowDuplicatesKey: false
        ])

        // Stop scanning after 30 seconds
        DispatchQueue.main.asyncAfter(deadline: .now() + 30) { [weak self] in
            self?.stopScanning()
        }
    }

    private func stopScanning() {
        guard isScanning else { return }

        log.info("Stopping BLE scan")
        isScanning = false
        centralManager.stopScan()
    }

    func disconnect() {
        guard let peripheral = peripheral else { return }
        log.info("Disconnecting from peripheral")
        centralManager.cancelPeripheralConnection(peripheral)
    }

    func sendCommand(_ command: EquilCommand, completion: @escaping (Result<Data, Error>) -> Void) {
        command.completion = completion
        commandQueue.append(command)
        processNextCommand()
    }

    private func processNextCommand() {
        guard currentCommand == nil, !commandQueue.isEmpty else { return }
        guard isConnected, let writeChar = writeCharacteristic else {
            // Fail all queued commands if not connected
            for cmd in commandQueue {
                cmd.completion?(.failure(EquilError.communicationError("Not connected")))
            }
            commandQueue.removeAll()
            return
        }

        currentCommand = commandQueue.removeFirst()

        guard let command = currentCommand else { return }

        do {
            let packets = try command.encode()
            log.info("Sending command with \(packets.count) packets")
            sendPackets(packets, to: writeChar)

            // Set timeout for response
            DispatchQueue.main.asyncAfter(deadline: .now() + 22) { [weak self] in
                guard let self = self, self.currentCommand === command else { return }
                self.log.error("Command timeout")
                self.currentCommand?.completion?(.failure(EquilError.timeout))
                self.currentCommand = nil
                self.responseData = Data()
                self.processNextCommand()
            }
        } catch {
            log.error("Failed to encode command: \(error.localizedDescription)")
            currentCommand?.completion?(.failure(error))
            currentCommand = nil
            processNextCommand()
        }
    }

    private func sendPackets(_ packets: [Data], to characteristic: CBCharacteristic) {
        guard let peripheral = peripheral else { return }

        for (index, packet) in packets.enumerated() {
            log.debug("Sending packet \(index + 1)/\(packets.count): \(packet.hexString)")
            peripheral.writeValue(packet, for: characteristic, type: .withResponse)

            // Small delay between packets (50ms as in AndroidAPS)
            if index < packets.count - 1 {
                Thread.sleep(forTimeInterval: 0.05)
            }
        }
    }

    private func handleResponse(_ data: Data) {
        log.debug("Received data: \(data.hexString)")
        responseData.append(data)

        // Check if response is complete (based on Equil protocol)
        if isResponseComplete(responseData) {
            log.info("Response complete, processing")

            do {
                try currentCommand?.decode(response: responseData)
                currentCommand?.completion?(.success(responseData))
            } catch {
                log.error("Failed to decode response: \(error.localizedDescription)")
                currentCommand?.completion?(.failure(error))
            }

            responseData = Data()
            currentCommand = nil
            processNextCommand()
        }
    }

    private func isResponseComplete(_ data: Data) -> Bool {
        guard data.count >= 6 else { return false }

        // Check end flag (bit 7 of byte 4)
        let flags = data[4]
        return (flags & 0x80) != 0
    }
}

// MARK: - CBCentralManagerDelegate

extension EquilBLEManager: CBCentralManagerDelegate {
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        log.info("Central manager state: \(central.state.rawValue)")
        delegate?.bleManager(self, didUpdateState: central.state)

        if central.state == .poweredOn, let address = targetAddress {
            connectToDevice(address: address)
        }
    }

    func centralManager(
        _ central: CBCentralManager,
        didDiscover peripheral: CBPeripheral,
        advertisementData _: [String: Any],
        rssi _: NSNumber
    ) {
        log.info("Discovered peripheral: \(peripheral.identifier.uuidString)")

        // Check if this is our target device
        if let targetAddress = targetAddress, peripheral.identifier.uuidString == targetAddress {
            stopScanning()
            self.peripheral = peripheral
            peripheral.delegate = self
            central.connect(peripheral, options: nil)
        }
    }

    func centralManager(_: CBCentralManager, didConnect peripheral: CBPeripheral) {
        log.info("Connected to peripheral: \(peripheral.identifier.uuidString)")
        delegate?.bleManager(self, didConnect: peripheral)
        peripheral.discoverServices([serviceUUID])
    }

    func centralManager(_: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        log.info("Disconnected from peripheral: \(peripheral.identifier.uuidString)")

        if let error = error {
            log.error("Disconnection error: \(error.localizedDescription)")
        }

        delegate?.bleManager(self, didDisconnect: peripheral, error: error)

        // Clear command queue on disconnect
        for cmd in commandQueue {
            cmd.completion?(.failure(EquilError.communicationError("Disconnected")))
        }
        commandQueue.removeAll()
        currentCommand = nil
        responseData = Data()
    }

    func centralManager(_: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
        log.error("Failed to connect to peripheral: \(error?.localizedDescription ?? "unknown error")")
        delegate?.bleManager(self, didDisconnect: peripheral, error: error)
    }
}

// MARK: - CBPeripheralDelegate

extension EquilBLEManager: CBPeripheralDelegate {
    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        guard error == nil, let services = peripheral.services else {
            log.error("Error discovering services: \(String(describing: error))")
            return
        }

        log.info("Discovered \(services.count) services")

        for service in services where service.uuid == serviceUUID {
            peripheral.discoverCharacteristics([writeCharacteristicUUID, notifyCharacteristicUUID], for: service)
        }
    }

    func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        guard error == nil, let characteristics = service.characteristics else {
            log.error("Error discovering characteristics: \(String(describing: error))")
            return
        }

        log.info("Discovered \(characteristics.count) characteristics")

        for characteristic in characteristics {
            if characteristic.uuid == writeCharacteristicUUID {
                writeCharacteristic = characteristic
                log.info("Found write characteristic")
            } else if characteristic.uuid == notifyCharacteristicUUID {
                notifyCharacteristic = characteristic
                peripheral.setNotifyValue(true, for: characteristic)
                log.info("Found notify characteristic, enabled notifications")
            }
        }

        // Request high priority connection (iOS 11+)
        if #available(iOS 11.0, *) {
            peripheral.readRSSI()
        }
    }

    func peripheral(_: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        guard error == nil, let data = characteristic.value else {
            log.error("Error reading characteristic: \(String(describing: error))")
            return
        }

        handleResponse(data)
        delegate?.bleManager(self, didReceiveData: data)
    }

    func peripheral(_: CBPeripheral, didWriteValueFor _: CBCharacteristic, error: Error?) {
        if let error = error {
            log.error("Error writing characteristic: \(error.localizedDescription)")
            currentCommand?.completion?(.failure(error))
            currentCommand = nil
            processNextCommand()
        }
    }

    func peripheral(_: CBPeripheral, didUpdateNotificationStateFor characteristic: CBCharacteristic, error: Error?) {
        if let error = error {
            log.error("Error updating notification state: \(error.localizedDescription)")
        } else {
            log.info("Notification state updated for characteristic: \(characteristic.uuid)")
        }
    }
}

// MARK: - Data Extension

extension Data {
    var hexString: String {
        map { String(format: "%02x", $0) }.joined()
    }
}

// Made with Bob
