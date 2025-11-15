---
-- Parser for D-Bus Bluetooth device information.
-- Extracts device data from GetManagedObjects output.

local DeviceParser = {}

---
-- Parses D-Bus GetManagedObjects output to extract Bluetooth device information.
-- @param dbus_output string Raw output from GetManagedObjects command
-- @return table Array of device information tables, each containing:
--   - path: Device object path
--   - address: MAC address
--   - name: Device name (or empty string if not available)
--   - paired: Boolean indicating if device is paired
--   - connected: Boolean indicating if device is connected
function DeviceParser.parseDiscoveredDevices(dbus_output)
    local devices = {}

    if not dbus_output or dbus_output == "" then
        return devices
    end

    local current_device = nil
    local in_device_section = false
    local last_property = nil

    for line in dbus_output:gmatch("[^\r\n]+") do
        local dev_path = line:match('object path "(/org/bluez/hci0/dev_[%w_]+)"')

        if dev_path then
            if current_device then
                table.insert(devices, current_device)
            end

            current_device = {
                path = dev_path,
                address = "",
                name = "",
                paired = false,
                connected = false,
            }
            in_device_section = true
            last_property = nil
        elseif current_device and in_device_section then
            if line:match('string "Address"') then
                last_property = "Address"
            elseif line:match('string "Name"') then
                last_property = "Name"
            elseif line:match('string "Paired"') then
                last_property = "Paired"
            elseif line:match('string "Connected"') then
                last_property = "Connected"
            end

            if last_property == "Address" then
                local addr_value = line:match('variant%s+string "([%w:]+)"')

                if addr_value then
                    current_device.address = addr_value
                    last_property = nil
                end
            elseif last_property == "Name" then
                local name_value = line:match('variant%s+string "([^"]*)"')

                if name_value then
                    current_device.name = name_value
                    last_property = nil
                end
            elseif last_property == "Paired" then
                local paired_value = line:match("variant%s+boolean (%w+)")

                if paired_value then
                    current_device.paired = (paired_value == "true")
                    last_property = nil
                end
            elseif last_property == "Connected" then
                local connected_value = line:match("variant%s+boolean (%w+)")

                if connected_value then
                    current_device.connected = (connected_value == "true")
                    last_property = nil
                end
            end
        end
    end

    if current_device then
        table.insert(devices, current_device)
    end

    return devices
end

return DeviceParser
