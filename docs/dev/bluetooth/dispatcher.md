# Bluetooth Dispatcher Integration

This document explains the design decisions behind registering Bluetooth actions and devices as
dispatcher actions and how it integrates with KOReader's lifecycle.

## Overview

The plugin exposes Bluetooth control actions and paired Bluetooth devices as dispatcher actions,
allowing other plugins and features to control Bluetooth state and trigger device connections. This
requires careful handling of device state management and lifecycle coordination.

## Registered Actions

### Bluetooth Control Actions

The plugin registers the following control actions:

| Action ID | Title                      | Description                             |
| --------- | -------------------------- | --------------------------------------- |
| `enable`  | Enable Bluetooth           | Turns Bluetooth on                      |
| `disable` | Disable Bluetooth          | Turns Bluetooth off                     |
| `toggle`  | Toggle Bluetooth           | Toggles Bluetooth on/off based on state |
| `scan`    | Scan for Bluetooth Devices | Starts device scan and shows results    |

These are registered via `registerBluetoothActionsWithDispatcher()` during plugin initialization.

### Device Connection Actions

Each paired device gets a unique action ID based on its MAC address:
`bluetooth_connect_<MAC_WITH_UNDERSCORES>`. These are registered via
`onDispatcherRegisterActions()`.

## Design Decisions

### Device List Persistence

Paired devices are stored in plugin settings rather than queried from Bluetooth in real-time.

**Why:** According to the [Bluetooth investigation](../investigations/bluetooth/00-overview.md),
D-Bus commands return no data when Bluetooth is disabled. This means dispatcher actions would fail
to register at startup if Bluetooth is off. By maintaining a persistent list in settings, actions
are always available regardless of Bluetooth state.

**Implementation:** When Bluetooth is turned on or devices are accessed, the paired device list is
synchronized from the system into `plugin.settings.paired_devices`. This ensures the dispatcher
always has current information.

### Standby Prevention During Bluetooth

When Bluetooth is enabled, the plugin calls `UIManager:preventStandby()` to keep the device awake.

**Why:** MTK Bluetooth hardware requires the system to remain active to maintain connections. If the
device suspends, Bluetooth connections are lost.

**Trade-off:** Users cannot use device suspension while Bluetooth is enabled. This is documented in
the user-facing feature guide so users understand the behavior.

### Action Registration at Startup

Dispatcher actions for Bluetooth control and paired devices are registered during plugin
initialization. Control actions are registered via `registerBluetoothActionsWithDispatcher()`, and
device actions via `onDispatcherRegisterActions()`.

**Why:** The dispatcher needs to know about available actions before user interactions. Registering
at startup ensures all actions are available immediately.

**Benefit:** Users can use dispatcher actions in gestures, profiles, and other automation features
without additional setup.

### Unique Action IDs

Control actions use simple identifiers (`enable`, `disable`, `toggle`, `scan`). Each device gets a
stable action ID based on its MAC address: `bluetooth_connect_<MAC_WITH_UNDERSCORES>`.

**Why:** MAC addresses are unique identifiers that persist across reboots. This ensures the same
device always has the same action ID, allowing users to configure gestures that survive restarts.

## Connection Flow

When a device connection dispatcher action is executed:

1. Plugin checks if Bluetooth is enabled
2. If disabled, it automatically turns Bluetooth on
3. Device connection is attempted
4. User sees status message

This flow is transparent to the dispatcher caller - they simply trigger an action ID without needing
to manage Bluetooth state.

## Control Action Flow

When a Bluetooth control action is executed:

- **enable**: Calls `turnBluetoothOn()`
- **disable**: Calls `turnBluetoothOff(true)` (with popup notification)
- **toggle**: Calls `toggleBluetooth(true)` (with popup notification when turning off)
- **scan**: Calls `scanAndShowDevices()`

The `onBluetoothAction(action_id)` method handles routing to the appropriate method.

## Integration with Investigations

This implementation is based on findings from the
[Bluetooth Control investigation](../investigations/bluetooth/00-overview.md):

- **D-Bus limitations:** Understanding that D-Bus returns no data when Bluetooth is off informed the
  decision to persist device lists in settings
- **Non-idempotent kernel driver:** The investigation's findings about kernel panic on driver
  reloading informed the decision to prevent device suspension while Bluetooth is active, avoiding
  unnecessary driver state changes
- **D-Bus auto-activation:** Knowing that a single method call triggers initialization, the plugin
  optimizes by only calling when necessary

## Related Documentation

- [Bluetooth Control Investigation](../investigations/bluetooth/00-overview.md) - Technical findings
  about Kobo's Bluetooth implementation
- [Bluetooth feature guide](../../features/bluetooth.md) - User-facing documentation
