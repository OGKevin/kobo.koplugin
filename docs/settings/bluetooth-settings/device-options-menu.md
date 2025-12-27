# Device Options Menu

When you select a device from the [Paired Devices](./paired-devices.md) list, a menu appears with
options for managing that device.

## Accessing the Device Options Menu

1. Navigate to Settings → Network → Bluetooth → Paired devices
2. Select any device from the list

The options shown depend on the device's current state.

## Available Options

| Option                     | Shows When                                               | Function                                                                                                                                                                                                             |
| -------------------------- | -------------------------------------------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| **Connect**                | Device is not currently connected                        | Establishes a connection to the device. The device will be ready to use with KOReader once connected. Bluetooth must be enabled.                                                                                     |
| **Disconnect**             | Device is currently connected                            | Closes the active connection. The device remains paired but will no longer be actively connected. You can reconnect at any time without needing to pair again.                                                       |
| **Configure Key Bindings** | Device is connected and the plugin supports key bindings | Opens a menu to set up button mappings for remote controls and keyboards. You can assign actions to buttons on your Bluetooth device. See [Key Bindings](./key-bindings.md) for detailed configuration instructions. |
| **Reset Key Bindings**     | The device has existing key binding configurations       | Removes all button mappings for this device. You'll be asked to confirm before the key bindings are cleared.                                                                                                         |
| **Trust**                  | Device is not currently trusted                          | Marks the device as trusted. Trusted devices can connect to your Kobo without requiring confirmation each time they connect.                                                                                         |
| **Untrust**                | Device is currently trusted                              | Removes the trusted status from the device. The device will require confirmation before connecting in the future.                                                                                                    |
| **Forget**                 | Always shown                                             | Removes the device from your paired devices list. This unpairs the device from your Kobo. You'll need to pair it again to use it. The device's key bindings (if any) are also removed.                               |
