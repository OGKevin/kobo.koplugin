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
- **Device-specific subclasses** (MTKBluetooth): Override critical methods only (~5%)

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
- MTK devices → `MTKBluetooth:new()`
- Other devices → `KoboBluetooth:new()` (base instance)

### Adding New Device Support

1. Create `src/lib/bluetooth/implementations/<device>_bluetooth.lua`
2. Extend KoboBluetooth
3. Override 3 required methods (will throw errors if forgotten)
4. Update factory method in `kobo_bluetooth.lua`
5. Add tests in `spec/lib/bluetooth/implementations/<device>_bluetooth_spec.lua`

### Comparison with D-Bus Adapter Pattern

- **D-Bus adapter**: Pure factory (no shared code, completely different implementations)
- **KoboBluetooth**: Template method

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

**Adapters** (`src/lib/bluetooth/adapters/`)

- Device-specific implementations of the interface
- Example: `mtk_adapter.lua` for MTK devices

## Adding a New Adapter

### 1. Create the adapter file

Create `src/lib/bluetooth/adapters/your_adapter.lua`:

```lua
local YourAdapter = {}

function YourAdapter.executeCommands(commands)
    -- Your implementation
end

function YourAdapter.isEnabled()
    -- Your implementation
end

-- Implement all 12 interface methods...
-- See dbus_adapter_interface.lua for the full list

return YourAdapter
```

### 2. Implement all interface methods

Copy method signatures from `dbus_adapter_interface.lua`.

### 3. Update factory detection

Modify `src/lib/bluetooth/dbus_adapter.lua` to detect your device and load your adapter:

```lua
if Device.isYourDeviceType() then
    adapter_instance = require("src/lib/bluetooth/adapters/your_adapter")
```

### 4. Write tests

Create `spec/lib/bluetooth/adapters/your_adapter_spec.lua` following the pattern in
`mtk_adapter_spec.lua`.

## See Also

- [Interface Contract](https://github.com/ogkevin/kobo.koplugin/blob/main/src/lib/bluetooth/dbus_adapter_interface.lua) -
  Method signatures and documentation
