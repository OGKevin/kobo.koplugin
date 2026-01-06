#!/usr/bin/env python3
"""
Proof of Concept: Kobo DRM Removal
This script demonstrates decrypting a Kobo KEPUB/EPUB book using credentials
and content keys from the native Kobo database.

Based on the obok.py approach from DeDRM_tools.

Requirements: pip install pycryptodome
"""

import binascii
import sqlite3
import hashlib
import base64
import zipfile
import sys
from pathlib import Path
from Crypto.Cipher import AES

# Known hash keys used by Kobo for device ID derivation
KOBO_HASH_KEYS = ["88b3a2e13", "XzUhGYdFp", "NoCanLook", "QJhwzAtXL"]


def get_device_serial(kobo_dir):
    """Extract device serial from version file."""
    version_file = Path(kobo_dir) / "version"
    if not version_file.exists():
        raise FileNotFoundError(f"Version file not found: {version_file}")

    content = version_file.read_text().strip()
    # Format: serial,version,version,version,version,platform_id
    parts = content.split(",")
    if len(parts) >= 1:
        return parts[0]

    raise ValueError("Could not parse device serial from version file")


def get_user_id(db_path):
    """Extract UserID from Kobo database."""
    conn = sqlite3.connect(db_path)
    cursor = conn.cursor()
    cursor.execute("SELECT UserID FROM user")
    result = cursor.fetchone()
    conn.close()

    if not result:
        raise ValueError("No user credentials found in database")

    return result[0]


def get_content_keys(db_path, volume_id):
    """Extract content keys for a specific book from Kobo database."""
    conn = sqlite3.connect(db_path)
    cursor = conn.cursor()
    cursor.execute(
        "SELECT elementId, elementKey FROM content_keys WHERE volumeId = ?",
        (volume_id,),
    )
    results = cursor.fetchall()
    conn.close()

    # Return as dictionary: elementId -> elementKey
    return {element_id: element_key for element_id, element_key in results}


def derive_user_key(serial, user_id, hash_key):
    """
    Derive the user decryption key using the obok approach.

    Key derivation:
    1. deviceid = SHA256(hash_key + serial)
    2. userkey = SHA256(deviceid + user_id)[32:] (second half = 16 bytes)
    """
    # Step 1: Derive device ID from hash key and serial
    device_id = hashlib.sha256((hash_key + serial).encode("ascii")).hexdigest()

    # Step 2: Derive user key from device ID and user ID
    user_key_hex = hashlib.sha256((device_id + user_id).encode("ascii")).hexdigest()

    # Use second half (last 32 hex chars = 16 bytes)
    user_key = binascii.a2b_hex(user_key_hex[32:])

    return user_key


def decrypt_content_key(encrypted_key_b64, master_key):
    """Decrypt a content key using the master key."""
    # Decode base64 encrypted key
    encrypted_key = base64.b64decode(encrypted_key_b64)

    # Decrypt using AES-ECB
    cipher = AES.new(master_key, AES.MODE_ECB)
    decrypted_key = cipher.decrypt(encrypted_key)

    return decrypted_key


def pkcs7_unpad(data):
    """Remove PKCS7 padding from decrypted data."""
    padding_length = data[-1]
    return data[:-padding_length]


def decrypt_file_content(encrypted_content, content_key):
    """Decrypt file content using the content key."""
    # Decrypt using AES-ECB
    cipher = AES.new(content_key, AES.MODE_ECB)
    decrypted_content = cipher.decrypt(encrypted_content)

    # Remove PKCS7 padding
    return pkcs7_unpad(decrypted_content)


def decrypt_book(input_epub, output_epub, user_key, content_keys_map):
    """Decrypt an entire EPUB/KEPUB book."""
    print(f"Decrypting: {input_epub}")
    print(f"Output: {output_epub}")
    print(f"User key: {user_key.hex()}")

    # Decrypt content keys
    decrypted_keys = {}
    for element_id, encrypted_key_b64 in content_keys_map.items():
        decrypted_keys[element_id] = decrypt_content_key(encrypted_key_b64, user_key)

    print(f"Decrypted {len(decrypted_keys)} content keys")

    # Process EPUB
    files_decrypted = 0
    files_copied = 0

    with zipfile.ZipFile(input_epub, "r") as zip_in:
        with zipfile.ZipFile(output_epub, "w", zipfile.ZIP_DEFLATED) as zip_out:
            for file_info in zip_in.infolist():
                file_path = file_info.filename
                file_content = zip_in.read(file_path)

                # Normalize path (forward slashes)
                normalized_path = file_path.replace("\\", "/")

                # Check if this file needs decryption
                if normalized_path in decrypted_keys:
                    try:
                        # Decrypt the file
                        content_key = decrypted_keys[normalized_path]
                        decrypted_content = decrypt_file_content(
                            file_content, content_key
                        )
                        zip_out.writestr(file_info, decrypted_content)
                        files_decrypted += 1
                        print(f"  Decrypted: {normalized_path}")
                    except Exception as e:
                        print(f"  ERROR decrypting {normalized_path}: {e}")
                        # Write original if decryption fails
                        zip_out.writestr(file_info, file_content)
                else:
                    # Copy unencrypted file as-is
                    zip_out.writestr(file_info, file_content)
                    files_copied += 1

    print(f"\nSummary:")
    print(f"  Files decrypted: {files_decrypted}")
    print(f"  Files copied: {files_copied}")
    print(f"  Total files: {files_decrypted + files_copied}")
    print(f"\nDecrypted book saved to: {output_epub}")


def main():
    # Configuration
    KOBO_DIR = "/tmp/.kobo"
    DB_PATH = f"{KOBO_DIR}/KoboReader.sqlite"
    VOLUME_ID = "48f6ea8d-bb42-499b-944a-ff211dce3379"
    INPUT_EPUB = f"{KOBO_DIR}/kepub/{VOLUME_ID}"
    OUTPUT_EPUB = "/tmp/decrypted_book.epub"

    print("=" * 60)
    print("Kobo DRM Removal - Proof of Concept")
    print("=" * 60)
    print()

    try:
        # Step 1: Get device serial from version file
        print("Step 1: Reading device serial...")
        serial = get_device_serial(KOBO_DIR)
        print(f"  Serial: {serial}")
        print()

        # Step 2: Get user ID from database
        print("Step 2: Reading user ID from Kobo database...")
        user_id = get_user_id(DB_PATH)
        print(f"  UserID: {user_id}")
        print()

        # Step 3: Get content keys for the book
        print("Step 3: Reading content keys for book...")
        content_keys = get_content_keys(DB_PATH, VOLUME_ID)
        print(f"  Found {len(content_keys)} encrypted files")
        print()

        if not content_keys:
            print("ERROR: No content keys found for this book.")
            sys.exit(1)

        # Step 4: Try each hash key to find the correct user key
        print("Step 4: Deriving user key and decrypting book...")
        success = False

        for hash_key in KOBO_HASH_KEYS:
            print(f"  Trying hash key: {hash_key}")
            user_key = derive_user_key(serial, user_id, hash_key)

            # Try to decrypt the first content key and verify
            first_element = next(iter(content_keys.keys()))
            first_key_b64 = content_keys[first_element]

            try:
                decrypted_content_key = decrypt_content_key(first_key_b64, user_key)

                # Read first encrypted file and try to decrypt
                with zipfile.ZipFile(INPUT_EPUB, "r") as z:
                    encrypted_content = z.read(first_element)
                    decrypted = decrypt_file_content(encrypted_content, decrypted_content_key)

                    # Check if decryption produced valid content
                    if (
                        b"<?xml" in decrypted[:100]
                        or b"<html" in decrypted[:100]
                        or b"\xff\xd8\xff" in decrypted[:10]
                    ):
                        print(f"  SUCCESS with hash key: {hash_key}")
                        decrypt_book(INPUT_EPUB, OUTPUT_EPUB, user_key, content_keys)
                        success = True
                        break
            except Exception:
                continue

        if not success:
            print("ERROR: Could not decrypt with any known hash key")
            sys.exit(1)

        print()
        print("=" * 60)
        print("SUCCESS! Book decrypted successfully.")
        print("=" * 60)

    except FileNotFoundError as e:
        print(f"ERROR: File not found - {e}")
        sys.exit(1)
    except Exception as e:
        print(f"ERROR: {e}")
        import traceback

        traceback.print_exc()
        sys.exit(1)


if __name__ == "__main__":
    main()
