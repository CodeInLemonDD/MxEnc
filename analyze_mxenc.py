import struct
import os
import sys

def parse_mxenc(file_path):
    print(f"--- Analyzing: {file_path} ---")
    
    if not os.path.exists(file_path):
        print(f"Error: File not found: {file_path}")
        return

    file_size = os.path.getsize(file_path)
    print(f"File Size: {file_size} bytes")

    try:
        with open(file_path, 'rb') as f:
            # 1. Magic (7 bytes)
            magic = f.read(7)
            if len(magic) < 7:
                print("Error: File too short for Magic header")
                return
            
            print(f"Magic: {magic} (Hex: {magic.hex()})")
            
            if magic != b'MXENC20':
                print("Warning: Magic is not MXENC20! Checking for MXENC10...")
                if magic == b'MXENC10':
                    print("Format is v1.0 (MXENC10).")
                    # Handle v1 logic if needed, but assuming v2 based on context
                else:
                    print("Error: Unknown Magic format.")
            
            # 2. Filename Length (4 bytes, Big Endian)
            fname_len_data = f.read(4)
            if len(fname_len_data) < 4:
                print("Error: Truncated at Filename Length")
                return
            fname_len = struct.unpack('>I', fname_len_data)[0]
            print(f"Filename Length: {fname_len}")

            # 3. Filename (N bytes)
            if fname_len > 1024: # Sanity check
                print(f"Warning: Filename length {fname_len} seems unusually large.")
            
            filename_bytes = f.read(fname_len)
            if len(filename_bytes) < fname_len:
                print(f"Error: Truncated at Filename. Expected {fname_len}, got {len(filename_bytes)}")
                return
            
            try:
                filename = filename_bytes.decode('utf-8')
                print(f"Filename: {filename}")
            except UnicodeDecodeError:
                print(f"Filename (Raw): {filename_bytes}")
                print("Error: Filename is not valid UTF-8")

            # 4. File Type (1 byte)
            file_type_data = f.read(1)
            if len(file_type_data) < 1:
                print("Error: Truncated at File Type")
                return
            file_type = file_type_data[0]
            print(f"File Type: {file_type}")

            # 5. Metadata Length (4 bytes, Big Endian)
            meta_len_data = f.read(4)
            if len(meta_len_data) < 4:
                print("Error: Truncated at Metadata Length")
                return
            meta_len = struct.unpack('>I', meta_len_data)[0]
            print(f"Metadata Length: {meta_len}")

            # 6. Metadata (M bytes)
            if meta_len > 10 * 1024 * 1024: # Sanity check (e.g. 10MB limit)
                print(f"Warning: Metadata length {meta_len} seems unusually large.")

            if meta_len > 0:
                meta_bytes = f.read(meta_len)
                if len(meta_bytes) < meta_len:
                    print(f"Error: Truncated at Metadata. Expected {meta_len}, got {len(meta_bytes)}")
                    return
                # Try to decode metadata if it's text/json
                try:
                    meta_str = meta_bytes.decode('utf-8')
                    print(f"Metadata: {meta_str}")
                except:
                    print(f"Metadata (Hex): {meta_bytes.hex()[:50]}...")
            else:
                print("Metadata: (None)")

            # 7. Salt (32 bytes)
            salt = f.read(32)
            if len(salt) < 32:
                print(f"Error: Truncated at Salt. Expected 32, got {len(salt)}")
                return
            print(f"Salt: {salt.hex()}")

            # 8. Nonce (12 bytes)
            nonce = f.read(12)
            if len(nonce) < 12:
                print(f"Error: Truncated at Nonce. Expected 12, got {len(nonce)}")
                return
            print(f"Nonce: {nonce.hex()}")

            # 9. Ciphertext (Remainder)
            current_pos = f.tell()
            remaining = file_size - current_pos
            print(f"Ciphertext Size: {remaining} bytes")
            
            if remaining == 0:
                print("Warning: No ciphertext found (empty content?).")
            elif remaining < 16: # GCM tag is usually 16 bytes
                print("Warning: Ciphertext is suspiciously small (less than 16 bytes for GCM tag).")
            else:
                print("Structure seems valid.")

    except Exception as e:
        print(f"Unexpected error: {e}")
    
    print("\n")

if __name__ == "__main__":
    files_to_check = [
        r"c:\Users\17993\Projects\MxEnc-Alpha-2.0.0\windows.mxenc",
        r"c:\Users\17993\Projects\MxEnc-Alpha-2.0.0\安卓.mxenc"
    ]
    
    for f in files_to_check:
        parse_mxenc(f)
