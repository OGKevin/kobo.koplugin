--- Kobo KDRM Key Derivation
--- Derives user decryption keys from device serial and user ID using the obok approach.
---
--- This module implements the key hierarchy:
--- 1. Hash Key + Device Serial -> Device ID (SHA256)
--- 2. Device ID + User ID -> User Key (SHA256, second 16 bytes)
local SHA2 = require("ffi/sha2")
local logger = require("logger")

local KeyDerivation = {}

--- Known hash keys used by Kobo for device ID derivation
KeyDerivation.HASH_KEYS = { "88b3a2e13", "XzUhGYdFp", "NoCanLook", "QJhwzAtXL" }

---
--- Derive device ID from hash key and serial number.
--- @param hash_key string: Kobo hash key (one of HASH_KEYS)
--- @param serial string: Device serial number
--- @return string: Device ID as 64 hex characters
function KeyDerivation:deriveDeviceId(hash_key, serial)
    local input = hash_key .. serial
    local hash = SHA2.sha256(input)

    return hash
end

---
--- Derive user key from device ID and user ID.
--- Takes the second half (last 32 hex chars = 16 bytes) of SHA256(device_id + user_id).
--- @param device_id string: Device ID (64 hex characters)
--- @param user_id string: User UUID from database
--- @return string: User key as 16-byte binary string
function KeyDerivation:deriveUserKey(device_id, user_id)
    local input = device_id .. user_id
    local hash = SHA2.sha256(input)

    local user_key_hex = hash:sub(33, 64)

    local user_key_bytes = {}
    for i = 1, #user_key_hex, 2 do
        local byte_hex = user_key_hex:sub(i, i + 1)
        local byte_val = tonumber(byte_hex, 16)
        table.insert(user_key_bytes, string.char(byte_val))
    end

    return table.concat(user_key_bytes)
end

---
--- Try all known hash keys to find the one that produces a working user key.
--- Calls test_fn with each candidate user key until one returns true.
--- @param serial string: Device serial number
--- @param user_id string: User UUID from database
--- @param test_fn function: Function that tests if a user key works, returns boolean
--- @return string|nil: Working user key (16 bytes), or nil if none found
--- @return string|nil: Hash key that worked, or nil if none found
function KeyDerivation:findWorkingKey(serial, user_id, test_fn)
    for _, hash_key in ipairs(self.HASH_KEYS) do
        logger.dbg("KeyDerivation: Trying hash key:", hash_key)

        local device_id = self:deriveDeviceId(hash_key, serial)
        local user_key = self:deriveUserKey(device_id, user_id)

        if test_fn(user_key) then
            logger.dbg("KeyDerivation: SUCCESS with hash key:", hash_key)

            return user_key, hash_key
        end

        logger.dbg("KeyDerivation: Failed with hash key:", hash_key)
    end

    logger.warn("KeyDerivation: No working hash key found after trying all", #self.HASH_KEYS, "keys")

    return nil, nil
end

return KeyDerivation
