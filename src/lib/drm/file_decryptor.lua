---
--- Kobo KDRM File Decryption
--- Decrypts individual files and content keys using AES-ECB.
---
--- This module handles:
--- 1. Decrypting base64-encoded content keys with user key
--- 2. Decrypting file content with content keys
--- 3. Removing PKCS7 padding from decrypted data
---
--- Uses openssl command-line tool for AES-128-ECB decryption.
---

local logger = require("logger")
local sha2 = require("ffi/sha2")

local FileDecryptor = {}

---
--- Decrypt data using AES-128-ECB via openssl command.
--- @param encrypted_data string: Data to decrypt
--- @param key string: 16-byte AES key
--- @return string|nil: Decrypted data, or nil on failure
local function aes_decrypt_ecb(encrypted_data, key)
    if #key ~= 16 then
        logger.warn("FileDecryptor: AES key must be 16 bytes, got", #key)

        return nil
    end

    if #encrypted_data == 0 then
        logger.warn("FileDecryptor: Cannot decrypt empty data")

        return nil
    end

    local temp_encrypted = os.tmpname()
    local file = io.open(temp_encrypted, "wb")
    if not file then
        logger.warn("FileDecryptor: Failed to create temp file for encrypted data")

        return nil
    end

    file:write(encrypted_data)
    file:close()

    local key_hex = ""
    for i = 1, #key do
        key_hex = key_hex .. string.format("%02x", string.byte(key, i))
    end

    local temp_output = os.tmpname()
    local cmd = string.format(
        "openssl enc -d -aes-128-ecb -K %s -in %q -out %q -nopad 2>/dev/null",
        key_hex,
        temp_encrypted,
        temp_output
    )
    local result = os.execute(cmd)

    local decrypted = nil
    if result == 0 or result == true then
        file = io.open(temp_output, "rb")
        if file then
            decrypted = file:read("*a")
            file:close()
        end
    end

    os.remove(temp_encrypted)
    os.remove(temp_output)

    if not decrypted or #decrypted == 0 then
        logger.warn("FileDecryptor: openssl decryption failed")

        return nil
    end

    return decrypted
end

---
--- Decrypt a base64-encoded content key using the user key.
--- @param encrypted_key_b64 string: Base64-encoded encrypted key
--- @param user_key string: 16-byte user key
--- @return string|nil: Decrypted content key (16 bytes), or nil on failure
function FileDecryptor:decryptContentKey(encrypted_key_b64, user_key)
    logger.dbg("FileDecryptor: Decrypting content key")

    local encrypted_key = sha2.base64_to_bin(encrypted_key_b64)
    if not encrypted_key then
        logger.warn("FileDecryptor: Failed to decode base64 content key")

        return nil
    end

    logger.dbg("FileDecryptor: Encrypted key length:", #encrypted_key)

    local decrypted = aes_decrypt_ecb(encrypted_key, user_key)
    if not decrypted then
        logger.warn("FileDecryptor: AES decryption failed for content key")

        return nil
    end

    logger.dbg("FileDecryptor: Decrypted content key length:", #decrypted)

    if #decrypted >= 16 then
        return decrypted:sub(1, 16)
    end

    logger.warn("FileDecryptor: Decrypted content key too short:", #decrypted)

    return nil
end

---
--- Remove PKCS7 padding from decrypted data.
--- @param data string: Padded data
--- @return string|nil: Unpadded data, or nil if invalid padding
function FileDecryptor:pkcs7Unpad(data)
    if #data == 0 then
        logger.warn("FileDecryptor: Cannot unpad empty data")

        return nil
    end

    local padding_length = string.byte(data, #data)

    if padding_length > #data or padding_length > 16 or padding_length == 0 then
        logger.warn("FileDecryptor: Invalid PKCS7 padding length:", padding_length)

        return nil
    end

    for i = #data - padding_length + 1, #data do
        if string.byte(data, i) ~= padding_length then
            logger.warn("FileDecryptor: Invalid PKCS7 padding bytes")

            return nil
        end
    end

    return data:sub(1, #data - padding_length)
end

---
--- Decrypt file content using a content key.
--- @param encrypted_content string: Encrypted file data
--- @param content_key string: 16-byte content key
--- @return string|nil: Decrypted file content, or nil on failure
function FileDecryptor:decryptFileContent(encrypted_content, content_key)
    logger.dbg("FileDecryptor: Decrypting file content, size:", #encrypted_content)

    local decrypted = aes_decrypt_ecb(encrypted_content, content_key)
    if not decrypted then
        logger.warn("FileDecryptor: AES decryption failed for file content")

        return nil
    end

    logger.dbg("FileDecryptor: Decrypted data size (with padding):", #decrypted)

    local unpadded = self:pkcs7Unpad(decrypted)
    if not unpadded then
        logger.warn("FileDecryptor: Failed to remove PKCS7 padding")

        return nil
    end

    logger.dbg("FileDecryptor: Successfully decrypted file, final size:", #unpadded)

    return unpadded
end

return FileDecryptor
