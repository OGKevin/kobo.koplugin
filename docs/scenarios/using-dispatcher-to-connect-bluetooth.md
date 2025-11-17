# Bluetooth Dispatcher Integration

## Goal

Quickly connect to paired Bluetooth devices through dispatcher actions. Use gestures, profiles, or
other dispatcher-aware features to trigger connections to your Bluetooth remotes, keyboards, or page
turners.

## Use Case

You have a paired Bluetooth device and want to:

- Connect to it with a single gesture
- Trigger device connections from other KOReader plugins or profiles
- Avoid navigating menus to connect to frequently-used devices

## Benefits

### Streamlined Connectivity

- One gesture to connect to your Bluetooth device
- Automatic connection if Bluetooth is off (plugin enables it first)

## How It Works

### Automatic Registration

When KOReader starts, the plugin automatically registers dispatcher actions for all your paired
Bluetooth devices. Each device gets a unique action id based on its MAC address.

You can find the registered actions in the dispatcher system under the "Device" category.

### What Happens When You Trigger the Action

1. The plugin checks if Bluetooth is enabled
2. If disabled, it automatically turns Bluetooth on
3. It attempts to connect to the device
4. You see a confirmation message

## Setup

### Prerequisites

- At least one Bluetooth device paired with your Kobo
- Kobo Plugin installed and enabled in KOReader

For instructions on how to pair a Bluetooth device, see the
[Bluetooth feature documentation](../features/bluetooth.md).

## Using with Gestures and Profiles

Any KOReader feature that supports dispatcher actions can trigger device connections. Check your
gesture system or profile documentation for how to assign dispatcher actions.

## Next Steps

- Review [Bluetooth feature documentation](../features/bluetooth.md) for pairing and managing
  devices
