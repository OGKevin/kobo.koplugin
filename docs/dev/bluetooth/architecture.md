# Bluetooth Architecture

This document describes the two architectural patterns used in the Bluetooth implementation:

1. **KoboBluetooth** - Template Method pattern for device-specific Bluetooth implementations
2. **D-Bus Adapter** - Adapter pattern for D-Bus communication layer

---

## KoboBluetooth Architecture - Template Method Pattern

The KoboBluetooth class uses the Template Method pattern to provide a reusable Bluetooth
implementation where device-specific subclasses override only critical methods.

### Pattern Used

- **Base class** (KoboBluetooth): Generic Bluetooth logic (~95% of code)
- **Device-specific subclasses** (`BlueZBluetooth`, `MTKBluetooth`): Override critical methods only
  (~5%)

### Method Classification

**Generic Methods (in base class)**:

- UI methods (menus, footer, scan results)
- Device manager interactions
- Auto-detection/connect logic
- Settings management
- Event handlers
- ~60 methods remain unchanged

**Device-Specific Methods (must override - throw error in base)**:

- `isDeviceSupported()` - Device detection
- `turnBluetoothOn()` - Power-on sequence (MTK requires WiFi)
- `turnBluetoothOff()` - Power-off sequence

### Factory Pattern

- `KoboBluetooth.create()` detects device type and returns appropriate instance
- BlueZ devices (`Kobo_io`, `Kobo_cadmus`) → `BlueZBluetooth:new()`
- MTK devices → `MTKBluetooth:new()`
- Other devices → `KoboBluetooth:new()` (base instance)

### Adding New Device Support

**BlueZ chip (same `org.bluez` ops, different bring-up)**:

1. Add `src/lib/bluetooth/adapters/<chip>_adapter.lua` that returns
   `BlueZAdapter:new({ name, COMMANDS_ON, COMMANDS_OFF })`
2. Wire the model in `dbus_adapter.lua`
3. Extend `BlueZBluetooth:isDeviceSupported()` / `KoboBluetooth.create()` if needed
4. Add adapter specs for the ON/OFF command sequence

**Non-BlueZ stack (e.g. MTK)**:

1. Create `src/lib/bluetooth/implementations/<device>_bluetooth.lua`
2. Extend KoboBluetooth and override the 3 required methods
3. Add a full D-Bus adapter implementing `dbus_adapter_interface.lua`
4. Update factories and tests

### Comparison with D-Bus Adapter Pattern

- **D-Bus adapter**: Factory selecting chip/stack adapters (BlueZ chips share `bluez_adapter.lua`)
- **KoboBluetooth**: Template method for UI/lifecycle behavior

---

## Bluetooth D-Bus Adapter Architecture

The Bluetooth D-Bus layer uses an **adapter pattern** to support device-specific implementations
while maintaining a consistent interface.

## Components

**Factory** (`src/lib/bluetooth/dbus_adapter.lua`)

- Detects device type and loads the appropriate adapter
- Caches adapter instance using singleton pattern

**Interface** (`src/lib/bluetooth/dbus_adapter_interface.lua`)

- Defines the contract all adapters must implement
- 12 required methods with consistent signatures
- Each unimplemented method throws an error

**Shared BlueZ helper** (`src/lib/bluetooth/adapters/bluez_adapter.lua`)

- Implements all `org.bluez` discovery/connect/trust operations
- `BlueZAdapter:new({ name, COMMANDS_ON, COMMANDS_OFF })` builds a full adapter

**Chip adapters** (`src/lib/bluetooth/adapters/`)

- `libra2_adapter.lua` / `sage_adapter.lua` — BlueZ chip bring-up only
- `mtk_adapter.lua` — full MTK stack implementation

## Adding a New BlueZ Chip Adapter

### 1. Create the thin adapter file

```lua
local BlueZAdapter = require("src/lib/bluetooth/adapters/bluez_adapter")

return BlueZAdapter:new({
    name = "YourChip",
    COMMANDS_ON = { --[[ chip power-on shell sequence ]] },
    COMMANDS_OFF = { --[[ chip power-off shell sequence ]] },
})
```

### 2. Update factory detection

Modify `src/lib/bluetooth/dbus_adapter.lua` to load your adapter for the device model.

### 3. Write tests

Create `spec/lib/bluetooth/adapters/your_adapter_spec.lua` asserting the ON/OFF command sequence
(UART path, rfkill/module, no wrong-chip commands).

## See Also

- [Interface Contract](https://github.com/ogkevin/kobo.koplugin/blob/main/src/lib/bluetooth/dbus_adapter_interface.lua) -
  Method signatures and documentation
- [Bluetooth investigations](../investigations/bluetooth/00-overview.md)
