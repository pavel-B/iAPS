# Equil Pump Integration Guide for iAPS

## Quick Start

This guide will help you integrate the EquilKit module into your iAPS project and get it running in Xcode.

## Prerequisites

- Xcode 14.0 or later
- iOS 15.0 or later
- Swift 5.7 or later
- Valid Apple Developer account (for device testing)
- Equil pump hardware for testing

## Step-by-Step Integration

### Step 1: Open the Project

```bash
cd /Users/pavelbrusnicky/Desktop/iaps_new
open FreeAPS.xcodeproj
```

### Step 2: Add EquilKit to Xcode

1. In Xcode, right-click on the project root in the Navigator
2. Select "Add Files to 'FreeAPS'..."
3. Navigate to and select the `EquilKit` folder
4. Ensure these options are checked:
   - ✅ Copy items if needed
   - ✅ Create groups
   - ✅ Add to targets: FreeAPS
5. Click "Add"

### Step 3: Update Build Settings

1. Select the FreeAPS project in Navigator
2. Select the FreeAPS target
3. Go to "Build Settings"
4. Search for "Swift Language Version"
5. Ensure it's set to "Swift 5" or later

### Step 4: Add Required Frameworks

The following frameworks are required (most are already included):

- **CoreBluetooth** (for BLE communication)
- **CryptoKit** (for encryption, iOS 13+)
- **CommonCrypto** (for hashing)
- **UserNotifications** (for alerts)
- **LoopKit** (already in iAPS)

To verify frameworks:
1. Select FreeAPS target
2. Go to "General" tab
3. Scroll to "Frameworks, Libraries, and Embedded Content"
4. Ensure CoreBluetooth.framework is present

### Step 5: Update Info.plist

Add Bluetooth permissions to `FreeAPS/Info.plist`:

```xml
<key>NSBluetoothAlwaysUsageDescription</key>
<string>iAPS needs Bluetooth to communicate with your Equil insulin pump for continuous glucose monitoring and insulin delivery.</string>

<key>NSBluetoothPeripheralUsageDescription</key>
<string>iAPS needs Bluetooth to communicate with your Equil insulin pump.</string>

<key>UIBackgroundModes</key>
<array>
    <string>bluetooth-central</string>
    <string>bluetooth-peripheral</string>
</array>
```

### Step 6: Register Equil Pump Manager

Find the file where pump managers are registered (typically in the app initialization or pump manager factory).

Add the import:
```swift
import EquilKit
```

Register the pump manager:
```swift
// In your pump manager registration code
let equilManager = EquilPumpManager(state: EquilPumpManagerState())
pumpManagers.append(equilManager)
```

### Step 7: Build the Project

1. Select your target device or simulator
2. Press Cmd+B to build
3. Fix any compilation errors (see Troubleshooting below)

### Step 8: Run on Device

⚠️ **Important**: Bluetooth functionality requires a real iOS device. Simulators have limited BLE support.

1. Connect your iOS device
2. Select it as the build target
3. Press Cmd+R to run
4. Grant Bluetooth permissions when prompted

## File Structure After Integration

```
iAPS/
├── FreeAPS/
│   ├── Sources/
│   │   ├── Application/
│   │   ├── Modules/
│   │   └── ...
│   └── Info.plist (updated)
├── EquilKit/                    ← NEW
│   ├── Models/
│   │   ├── EquilPod.swift
│   │   └── EquilState.swift
│   ├── Bluetooth/
│   │   ├── EquilBLEManager.swift
│   │   └── EquilEncryption.swift
│   ├── Commands/
│   │   ├── EquilCommand.swift
│   │   └── EquilCommands.swift
│   ├── PumpManager/
│   │   └── EquilPumpManager.swift
│   ├── UI/
│   └── README.md
├── OmniBLE/
├── OmniKit/
└── ...
```

## Testing the Integration

### 1. Verify Compilation

```bash
# From terminal
cd /Users/pavelbrusnicky/Desktop/iaps_new
xcodebuild -project FreeAPS.xcodeproj -scheme FreeAPS -destination 'platform=iOS Simulator,name=iPhone 14' clean build
```

### 2. Test Bluetooth Permissions

Run the app and check that:
- Bluetooth permission dialog appears
- App can scan for BLE devices
- No crashes related to BLE

### 3. Test Pump Discovery

With an Equil pump nearby:
- Navigate to pump settings
- Select "Add Pump" → "Equil"
- Verify pump appears in scan results

### 4. Test Pairing (with caution)

⚠️ **Use saline or empty pump for initial testing**

1. Select your Equil pump from scan results
2. Enter pump serial number
3. Enter pump password
4. Verify successful pairing
5. Check pump status displays correctly

## Common Integration Issues

### Issue 1: Module 'EquilKit' not found

**Solution:**
1. Verify EquilKit folder is added to project
2. Check target membership (select any EquilKit file, check File Inspector)
3. Clean build folder (Cmd+Shift+K)
4. Rebuild project

### Issue 2: Cannot find type 'EquilPumpManager' in scope

**Solution:**
1. Ensure `import EquilKit` is at top of file
2. Verify EquilKit files are included in target
3. Check for compilation errors in EquilKit files

### Issue 3: Bluetooth permission denied

**Solution:**
1. Verify Info.plist has correct keys
2. Delete app and reinstall
3. Check iOS Settings → Privacy → Bluetooth

### Issue 4: CryptoKit not available

**Solution:**
1. Ensure deployment target is iOS 13.0 or later
2. Check in Build Settings → Deployment → iOS Deployment Target

### Issue 5: LoopKit types not found

**Solution:**
1. Ensure LoopKit is properly integrated in iAPS
2. Check LoopKit import in EquilPumpManager.swift
3. Verify LoopKit framework is linked

## Code Signing

For device testing:

1. Select FreeAPS target
2. Go to "Signing & Capabilities"
3. Select your Team
4. Ensure "Automatically manage signing" is checked
5. Verify Bundle Identifier is unique

## Running on Device

### First Run Checklist

- [ ] Bluetooth is enabled on device
- [ ] Location services enabled (required for BLE on iOS)
- [ ] App has Bluetooth permissions
- [ ] Equil pump is charged and nearby
- [ ] Using saline or empty pump for testing

### Pairing Process

1. Launch iAPS
2. Navigate to Settings → Pump
3. Select "Add Pump"
4. Choose "Equil"
5. Follow pairing wizard:
   - Scan for pump
   - Select your pump
   - Enter serial number (format: XXXXX)
   - Enter password
   - Wait for pairing confirmation
6. Verify pump status:
   - Battery level displayed
   - Reservoir level shown
   - Connection status: Connected

## Monitoring and Debugging

### Enable Logging

Add to your debug configuration:

```swift
// In AppDelegate or similar
#if DEBUG
OSLog.default.logLevel = .debug
#endif
```

### View Logs

1. Open Console.app on Mac
2. Connect iOS device
3. Filter by "EquilKit" or "EquilBLE"
4. Monitor connection and command logs

### Key Log Messages

- `"Attempting to connect to device"` - Connection starting
- `"Connected to pump"` - Successful connection
- `"Sending command with X packets"` - Command transmission
- `"Response complete, processing"` - Command response received
- `"Status updated: Battery X%, Reservoir Y units"` - Status update

## Performance Optimization

### Battery Life

- Status updates every 60 seconds (configurable)
- Alert checks every 30 seconds (configurable)
- BLE connection maintained in background

### Memory Usage

- Efficient packet handling
- Automatic cleanup of completed commands
- State persistence recommended

## Security Best Practices

1. **Password Storage**
   - Store pump password in Keychain
   - Never log passwords
   - Use secure string handling

2. **Encryption Keys**
   - Keys generated per session
   - Proper key derivation (SHA-256)
   - Secure random number generation

3. **Data Protection**
   - Enable Data Protection in capabilities
   - Use encrypted storage for sensitive data

## Next Steps

After successful integration:

1. **Create UI Components**
   - Pump pairing wizard
   - Status display screen
   - Settings interface
   - Alert management UI

2. **Add Persistence**
   - Save pump state to disk
   - Implement state restoration
   - History tracking

3. **Enhance Error Handling**
   - User-friendly error messages
   - Retry logic for failed commands
   - Graceful degradation

4. **Testing**
   - Unit tests for commands
   - Integration tests with mock pump
   - Real-world testing with saline

5. **Documentation**
   - User guide
   - Troubleshooting guide
   - Safety information

## Support Resources

- **EquilKit README**: `/EquilKit/README.md`
- **iAPS Documentation**: Check main iAPS docs
- **LoopKit Documentation**: https://loopkit.github.io/LoopKit/
- **Apple BLE Guide**: https://developer.apple.com/bluetooth/

## Safety Reminders

⚠️ **CRITICAL SAFETY INFORMATION**

1. **Testing Phase**
   - Use saline solution only
   - Never test with insulin initially
   - Verify all functions work correctly

2. **Medical Device**
   - This is experimental software
   - Not FDA approved
   - Use at your own risk

3. **Backup Plan**
   - Always have backup insulin delivery
   - Monitor glucose levels closely
   - Have emergency supplies ready

4. **Healthcare Provider**
   - Consult your doctor before use
   - Regular medical supervision
   - Report any issues immediately

## Troubleshooting Checklist

If something doesn't work:

- [ ] Clean build folder (Cmd+Shift+K)
- [ ] Delete derived data
- [ ] Restart Xcode
- [ ] Restart iOS device
- [ ] Check all files are in target
- [ ] Verify Info.plist permissions
- [ ] Check Bluetooth is enabled
- [ ] Verify pump is charged
- [ ] Check pump is not paired elsewhere
- [ ] Review Console logs for errors

## Getting Help

If you encounter issues:

1. Check this guide thoroughly
2. Review EquilKit README
3. Check Console logs
4. Search existing issues
5. Create detailed bug report with:
   - Xcode version
   - iOS version
   - Error messages
   - Steps to reproduce
   - Console logs

---

**Last Updated**: June 2026
**Version**: 1.0.0
**Compatibility**: iAPS 3.x, iOS 15.0+