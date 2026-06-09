# EquilKit - Equil Pump Integration for iAPS

## Overview

EquilKit is a complete implementation of Equil patch pump support for iAPS, based on the AndroidAPS Equil implementation and following the architectural patterns of OmniBLE (Omnipod Dash) in iAPS.

## Features

### ✅ Implemented Features

1. **Bluetooth Communication**
   - BLE connection management
   - Automatic reconnection
   - Packet-based communication protocol
   - AES-256-GCM encryption

2. **Pump Pairing**
   - Secure pairing with password
   - Device key exchange
   - Serial number validation

3. **Insulin Delivery**
   - Bolus delivery
   - Bolus cancellation
   - Temp basal rates
   - Basal schedule programming

4. **Pump Control**
   - Suspend delivery
   - Resume delivery
   - Status monitoring

5. **Monitoring & Alerts**
   - **Reservoir Level Monitoring**
     - Real-time reservoir tracking
     - Low reservoir alerts (≤10U)
     - Critical reservoir alerts (≤5U)
     - Automatic updates every minute
   
   - **Battery Monitoring**
     - Battery percentage display
     - Low battery alerts (≤20%)
     - Critical battery alerts (≤10%)
     - Battery status in pump status
   
   - **Pump Expiration**
     - 72-hour service duration tracking
     - Expiration warnings (12 hours before)
     - Automatic expiration alerts
   
   - **Communication Alerts**
     - Connection status monitoring
     - Disconnection notifications
     - Communication error alerts

6. **User Notifications**
   - Push notifications for all alerts
   - Critical alerts with special sound
   - Alert acknowledgment system
   - Customizable notification preferences

## Architecture

```
EquilKit/
├── Models/
│   ├── EquilPod.swift          # Constants and pump specifications
│   └── EquilState.swift        # State management and data models
├── Bluetooth/
│   ├── EquilBLEManager.swift   # BLE communication layer
│   └── EquilEncryption.swift   # AES encryption and CRC
├── Commands/
│   ├── EquilCommand.swift      # Base command protocol
│   └── EquilCommands.swift     # Specific command implementations
├── PumpManager/
│   └── EquilPumpManager.swift  # Main pump manager (LoopKit integration)
└── UI/
    └── (UI components to be added)
```

## Key Differences from Omnipod Dash

| Feature | Omnipod Dash | Equil |
|---------|--------------|-------|
| Encryption | EAP-AKA + Milenage | AES-256-GCM |
| Pairing | X25519 key exchange | Password-based with SHA-256 |
| Packet Size | Variable | 16 bytes max |
| Reservoir | 200U | 200U |
| Service Duration | 80 hours | 72 hours |
| Pulse Size | 0.05U | 0.05U |

## Integration with iAPS

### 1. Add EquilKit to Xcode Project

1. Open `FreeAPS.xcodeproj` in Xcode
2. Add EquilKit folder to project:
   - Right-click on project root
   - Select "Add Files to FreeAPS"
   - Select the `EquilKit` folder
   - Check "Create groups"
   - Add to FreeAPS target

### 2. Update Dependencies

Add to `Package.swift` or project dependencies:
- CryptoKit (built-in iOS 13+)
- CommonCrypto (built-in)

### 3. Register Pump Manager

In `FreeAPS/Sources/Application/FreeAPSApp.swift`, add:

```swift
import EquilKit

// In pump manager registration
pumpManagers.append(EquilPumpManager.self)
```

### 4. Add UI Components

Create UI views for:
- Pump pairing wizard
- Pump status display
- Settings screen
- Alert management

### 5. Update Info.plist

Add Bluetooth permissions:

```xml
<key>NSBluetoothAlwaysUsageDescription</key>
<string>iAPS needs Bluetooth to communicate with your Equil pump</string>
<key>NSBluetoothPeripheralUsageDescription</key>
<string>iAPS needs Bluetooth to communicate with your Equil pump</string>
```

## Usage

### Pairing a New Pump

```swift
let state = EquilState(
    address: "DEVICE-UUID",
    serialNumber: "XXXXX",
    password: "user-password"
)

let pumpManager = EquilPumpManager(
    state: EquilPumpManagerState(equilState: state)
)

// Pair command will be sent automatically on connection
```

### Delivering a Bolus

```swift
pumpManager.enactBolus(units: 5.0, automatic: false) { result in
    switch result {
    case .success(let dose):
        print("Bolus delivered: \(dose.value)U")
    case .failure(let error):
        print("Bolus failed: \(error)")
    }
}
```

### Setting Temp Basal

```swift
pumpManager.enactTempBasal(
    unitsPerHour: 1.5,
    for: .minutes(30)
) { result in
    switch result {
    case .success(let dose):
        print("Temp basal set: \(dose.value)U/hr")
    case .failure(let error):
        print("Temp basal failed: \(error)")
    }
}
```

### Suspending/Resuming

```swift
// Suspend
pumpManager.suspendDelivery { error in
    if let error = error {
        print("Suspend failed: \(error)")
    } else {
        print("Delivery suspended")
    }
}

// Resume
pumpManager.resumeDelivery { error in
    if let error = error {
        print("Resume failed: \(error)")
    } else {
        print("Delivery resumed")
    }
}
```

### Monitoring Status

```swift
// Battery level (0-100%)
let battery = pumpManager.status.pumpBatteryChargeRemaining

// Reservoir level (Units)
let reservoir = pumpManager.equilState?.reservoirLevel

// Connection status
let isConnected = pumpManager.bleManager.isConnected

// Pump status
let status = pumpManager.status
```

## Alert System

### Alert Types

- **reservoirLow**: Reservoir ≤ 10U
- **reservoirCritical**: Reservoir ≤ 5U
- **batteryLow**: Battery ≤ 20%
- **batteryCritical**: Battery ≤ 10%
- **pumpExpiring**: < 12 hours remaining
- **pumpExpired**: Service duration exceeded
- **occlusion**: Delivery obstruction detected
- **pumpError**: General pump error
- **communicationError**: BLE communication issue

### Handling Alerts

```swift
extension MyViewController: EquilPumpManagerDelegate {
    func pumpManager(_ manager: EquilPumpManager, didReceiveAlert alert: EquilAlert) {
        switch alert {
        case .reservoirLow:
            // Show UI alert
            showAlert("Low Reservoir", "Please change pump soon")
            
        case .batteryCritical:
            // Show critical alert
            showCriticalAlert("Critical Battery", "Change pump immediately!")
            
        default:
            // Handle other alerts
            break
        }
        
        // Acknowledge alert
        manager.acknowledgeAlert(alert)
    }
}
```

## Automatic Updates

The pump manager automatically:
- Updates status every 60 seconds
- Checks for alerts every 30 seconds
- Monitors reservoir levels
- Tracks battery percentage
- Calculates time until expiration
- Sends notifications for critical events

## Security

- All communication is encrypted with AES-256-GCM
- Passwords are hashed with SHA-256
- Random nonces for each encryption
- CRC validation on all packets
- Secure key storage in Keychain (recommended)

## Testing

### Unit Tests

```bash
# Run tests
xcodebuild test -scheme EquilKit -destination 'platform=iOS Simulator,name=iPhone 14'
```

### Integration Testing

1. **Pairing Test**: Verify pump pairing with valid credentials
2. **Bolus Test**: Deliver small test bolus (0.1U)
3. **Temp Basal Test**: Set and cancel temp basal
4. **Suspend/Resume Test**: Verify delivery control
5. **Alert Test**: Trigger low reservoir/battery alerts
6. **Reconnection Test**: Verify automatic reconnection

## Troubleshooting

### Connection Issues

- Ensure Bluetooth is enabled
- Check pump is within range (< 10 meters)
- Verify pump is not paired with another device
- Try forgetting and re-pairing the pump

### Encryption Errors

- Verify password is correct
- Check serial number format
- Ensure device key is properly stored

### Communication Timeouts

- Check Bluetooth signal strength
- Reduce distance to pump
- Restart Bluetooth on phone
- Restart pump if necessary

## Safety Considerations

⚠️ **IMPORTANT SAFETY NOTES**

1. **Testing Required**: Extensive testing with saline before insulin use
2. **Backup Plan**: Always have backup insulin delivery method
3. **Monitoring**: Regularly check pump status and glucose levels
4. **Alerts**: Never ignore critical alerts
5. **Expiration**: Change pump before expiration time
6. **Battery**: Monitor battery level closely
7. **Reservoir**: Refill before running low

## Known Limitations

1. No support for extended bolus (can be added)
2. UI components need to be created
3. Persistent storage needs implementation
4. History sync not yet implemented
5. Some error codes need mapping

## Future Enhancements

- [ ] Extended bolus support
- [ ] Complete UI implementation
- [ ] History synchronization
- [ ] Advanced error handling
- [ ] Pump diagnostics
- [ ] Firmware update support
- [ ] Multi-language support
- [ ] Accessibility improvements

## Contributing

When contributing to EquilKit:

1. Follow Swift style guidelines
2. Add unit tests for new features
3. Update documentation
4. Test thoroughly with real pump
5. Consider safety implications

## License

This implementation is based on:
- AndroidAPS Equil implementation (GPL-3.0)
- iAPS OmniBLE implementation (GPL-3.0)

## Credits

- AndroidAPS team for Equil protocol implementation
- iAPS/LoopKit team for pump manager architecture
- Equil for pump hardware

## Support

For issues and questions:
- GitHub Issues: [Create an issue]
- Discord: iAPS community
- Documentation: This README

## Version History

### v1.0.0 (Initial Release)
- Complete BLE communication
- Pairing and encryption
- Bolus and basal delivery
- Temp basal support
- Suspend/resume functionality
- Reservoir monitoring with alerts
- Battery monitoring with alerts
- Expiration tracking
- Comprehensive notification system
- Automatic status updates
- Alert management system

---

**⚠️ DISCLAIMER**: This is experimental software for managing insulin delivery. Use at your own risk. Always have backup insulin delivery methods available. Consult with your healthcare provider before use.