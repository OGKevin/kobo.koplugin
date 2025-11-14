# Bluetooth Input Device Mapping

## Overview

This document describes how Bluetooth HID (Human Interface Device) input devices are mapped to
`/dev/input/eventN` device nodes on Kobo devices, and how to programmatically detect them.

## Device Path Structure

When a Bluetooth HID device connects (keyboard, gamepad, remote, etc.), the Linux kernel creates:

1. **Character device**: `/dev/input/eventN` (where N is typically 4 or higher)
2. **Sysfs entry**: `/sys/class/input/eventN` (symlink to device)
3. **Input device**: `/sys/class/input/inputM` (underlying input device)

### Example: Connected Gamepad

```bash
$ ls -la /sys/class/input/event4
lrwxrwxrwx 1 root root 0 Nov 15 16:36 event4 -> \
  ../../devices/virtual/misc/uhid/0005:2DC8:9021.0004/input/input7/event4
```

**Key observations:**

- Path contains `uhid` → indicates Bluetooth/USB HID device
- Format: `uhid/<BUS>:<VENDOR>:<PRODUCT>.<INSTANCE>/input/inputN/eventN`
- HID ID: `0005:2DC8:9021.0004`
  - `0005` = Bus ID (Bluetooth)
  - `2DC8` = Vendor ID
  - `9021` = Product ID
  - `0004` = Instance number

### Built-in Kobo Devices

For comparison, built-in devices use platform paths:

```bash
event0 -> ../../devices/platform/ntx_event0/input/input0/event0           # E-ink touch
event1 -> ../../devices/platform/1001e000.i2c/i2c-2/2-0010/input/input1/event1  # I2C device
event2 -> ../../devices/platform/1001e000.i2c/i2c-2/2-001e/input/input2/event2  # I2C device
event3 -> ../../devices/platform/10019000.i2c/i2c-1/1-004b/bd71828-pwrkey.6.auto/input/input3/event3  # Power button
```

These paths do **not** contain `uhid`, making them easy to distinguish from Bluetooth devices.

## Detection Strategy

### Identifying Bluetooth Input Devices

To detect Bluetooth input devices, scan `/sys/class/input/` for symlinks containing `uhid`:

```bash
#!/bin/bash
# Find all Bluetooth input devices

for event in /sys/class/input/event*; do
    # Read symlink target
    target=$(readlink "$event")

    # Check if it contains 'uhid'
    if echo "$target" | grep -q "uhid"; then
        event_num=$(basename "$event")
        echo "Bluetooth device: /dev/input/$event_num"
    fi
done
```

**Output example:**

```text
Bluetooth device: /dev/input/event4
```

## Correlation Challenge

The D-Bus Bluetooth interface does **not** provide a direct mapping between Bluetooth MAC addresses
and `/dev/input/` paths.

**D-Bus provides:**

```text
Address: E4:17:D8:EC:04:1E
Name: 8BitDo Micro gamepad
Modalias: ""  ← Empty!
```

**Kernel provides:**

```text
HID ID: 0005:2DC8:9021.0004
Path: /dev/input/event4
```

**No direct correlation exists** between the MAC address from D-Bus and the HID device ID from the
kernel.

### Why Modalias is Empty

The `Modalias` field in BlueZ typically contains vendor/product IDs, but on Kobo's MTK chipset it's
empty. Likely reasons:

1. **Custom BlueZ wrapper**: Kobo uses `com.kobo.mtk.bluedroid` instead of standard `org.bluez`
2. **Limited D-Bus exposure**: MTK implementation doesn't expose full device properties
3. **HID profile timing**: Modalias may not be populated until after full HID connection

## Potential Correlation Methods

### 1. Device Name Matching

Device names are available in sysfs and can be matched against D-Bus device names:

```bash
$ cat /sys/class/input/event4/device/name
8BitDo Micro gamepad
```

**D-Bus device name:**

```text
Name: "8BitDo Micro gamepad"
```

**Sysfs device name:**

```text
/sys/class/input/event4/device/name: "8BitDo Micro gamepad"
```

When these names match exactly, a direct correlation can be established between the Bluetooth MAC
address (from D-Bus) and the input device path (from kernel).

## References

- Linux Input Subsystem: `/Documentation/input/input.txt` in kernel source
- BlueZ HID profile documentation
- `uhid` kernel module: `/Documentation/hid/uhid.txt`
- [D-Bus BlueZ API](https://git.kernel.org/pub/scm/bluetooth/bluez.git/tree/doc/device-api.txt)
