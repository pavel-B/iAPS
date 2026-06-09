# Xcode Build Instructions for EquilKit Integration

## Current Status ✅

EquilKit has been added to the iAPS repository at `/Users/pavelbrusnicky/Desktop/iAPS/EquilKit`

## Next Steps to Build in Xcode

### Step 1: Open Project

```bash
cd /Users/pavelbrusnicky/Desktop/iAPS
open FreeAPS.xcodeproj
```

### Step 2: Initialize Git Submodules

The dull/faded icons you see are missing git submodules. Fix them:

```bash
cd /Users/pavelbrusnicky/Desktop/iAPS
git submodule update --init --recursive
```

This will download all required dependencies (LoopKit, OmniKit, LibreTransmitter, etc.)

### Step 3: Add EquilKit to Xcode Project

1. **In Xcode Navigator (left panel)**:
   - Right-click on "FreeAPS" project root (blue icon)
   - Select "Add Files to 'FreeAPS'..."

2. **In file picker**:
   - Navigate to: `/Users/pavelbrusnicky/Desktop/iAPS/EquilKit`
   - Select the `EquilKit` folder
   - **Check these options**:
     - ✅ "Copy items if needed"
     - ✅ "Create groups"
     - ✅ Add to targets: FreeAPS
   - Click "Add"

3. **Verify**:
   - EquilKit folder appears in Navigator
   - All .swift files are visible
   - Files have target membership (check File Inspector)

### Step 4: Update Info.plist

Add Bluetooth permissions to `FreeAPS/Info.plist`:

```xml
<key>NSBluetoothAlwaysUsageDescription</key>
<string>iAPS needs Bluetooth to communicate with your Equil insulin pump</string>

<key>UIBackgroundModes</key>
<array>
    <string>bluetooth-central</string>
</array>
```

### Step 5: Clean and Build

1. Clean: Cmd+Shift+K
2. Build: Cmd+B

## Icon Color Meanings

- 🟦 **Bright Blue** = Found and linked correctly
- 🟨 **Dull/Faded** = Missing submodule (run git submodule update)
- 🔴 **Red text** = Error or conflict

## Using EquilKit

After successful build:

```swift
import EquilKit

// Initialize pump manager
let state = EquilState(
    address: "DEVICE-UUID",
    serialNumber: "12345",
    password: "password"
)

let pumpManager = EquilPumpManager(
    state: EquilPumpManagerState(equilState: state)
)

// Monitor status
let reservoir = pumpManager.equilState?.reservoirLevel
let battery = pumpManager.equilState?.battery
```

## Complete Documentation

- **EquilKit/README.md** - Complete API documentation
- **EQUIL_INTEGRATION_GUIDE.md** - Detailed integration guide

## Troubleshooting

### "No such module 'EquilKit'"
- Verify EquilKit folder is added to project
- Check target membership in File Inspector
- Clean and rebuild

### Dull framework icons
```bash
cd /Users/pavelbrusnicky/Desktop/iAPS
git submodule update --init --recursive
```

### Build errors
- Clean build folder (Cmd+Shift+K)
- Delete derived data
- Restart Xcode
- Verify all submodules are initialized

## Features Included

✅ Reservoir monitoring with alerts
✅ Battery display with percentage
✅ Suspend/Resume functionality
✅ Push notifications
✅ Automatic status updates
✅ Complete insulin delivery
✅ AES-256-GCM encryption
✅ BLE communication

---

**Project Location**: `/Users/pavelbrusnicky/Desktop/iAPS/`
**EquilKit Location**: `/Users/pavelbrusnicky/Desktop/iAPS/EquilKit/`