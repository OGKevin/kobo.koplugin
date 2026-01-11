# Bluetooth D-Bus Adapter Architecture

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
