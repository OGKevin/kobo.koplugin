# Bluetooth Control Investigation

**Device:** Kobo Libra Colour (MTK Bluetooth chipset)

## Overview

This investigation documents how to control Bluetooth on Kobo e-readers from the system level,
enabling programmatic control without Nickel's UI. The investigation focuses on understanding the
D-Bus interface, service initialization, and safe shutdown procedures.

## Key Findings

### Custom D-Bus Wrapper

Kobo does **NOT** expose the standard `org.bluez` D-Bus service. Instead, all BlueZ operations are
routed through `com.kobo.mtk.bluedroid`.

**Evidence:**

```bash
# Standard BlueZ name does NOT exist
$ dbus-send --system --dest=org.freedesktop.DBus \
    /org/freedesktop/DBus \
    org.freedesktop.DBus.GetNameOwner \
    string:org.bluez
Error: Could not get owner of name 'org.bluez': no such name

# Kobo's wrapper only returns adapter properties after Bluetooth is started
$ dbus-send --system --dest=com.kobo.mtk.bluedroid \
    /org/bluez/hci0 \
    org.freedesktop.DBus.Properties.GetAll \
    string:org.bluez.Adapter1
# (Returns properties only if Bluetooth is running)
```

### D-Bus Auto-Activation

Analysis of Nickel's Bluetooth initialization (strace, 7678 lines) revealed:

**Timeline:**

```
15:18:19.863 - Nickel calls BluedroidManager1.On()
15:18:19.947 - D-Bus auto-starts service (84ms later)
15:18:22.986 - Adapter ready (3.1 seconds after start)
```

A single D-Bus method call triggers the entire initialization via D-Bus auto-activation from
`/usr/share/dbus-1/system-services/com.kobo.mtk.bluedroid.service`.

### Non-Idempotent Kernel Driver

<div class="warning">
MTK kernel modules (`wmt_drv`, `wmt_cdev_bt`, etc.) have non-idempotent
initialization. Unloading and reloading causes NULL pointer dereference kernel panic.
</div>

See [Known Issues](./05-known-issues.md) for details.

## Navigation

- [Architecture](./01-architecture.md) - Stack components and D-Bus services
- [Initialization](./02-initialization.md) - How to start Bluetooth
- [Operations](./03-operations.md) - Scan, connect, status commands
- [Shutdown](./04-shutdown.md) - Safe shutdown procedure
- [Known Issues](./05-known-issues.md) - Kernel panic investigation
- [Input Device Mapping](./06-input-device-mapping.md) - Mapping Bluetooth devices to
  `/dev/input/eventN`

## References

- [KOReader Issue #12739](https://github.com/koreader/koreader/issues/12739) - Kernel panic on exit
- [NickelMenu PR #152](https://github.com/pgaskin/NickelMenu/pull/152) - libnickel integration
