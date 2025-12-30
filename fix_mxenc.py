import struct
import os
import shutil

def fix_mxenc(file_path):
    print(f"--- Attempting to fix: {file_path} ---")
    
    if not os.path.exists(file_path):
        print(f"Error: File not found: {file_path}")
        return

    # Create a backup
    backup_path = file_path + ".bak"
    shutil.copy2(file_path, backup_path)
    print(f"Backup created at: {backup_path}")

    try:
        with open(file_path, 'r+b') as f:
            # 1. Magic (7 bytes)
            magic = f.read(7)
            if magic != b'MXENC20':
                print("Error: Not a valid MXENC20 file.")
                return
            
            # 2. Filename Length (4 bytes, Big Endian)
            fname_len_data = f.read(4)
            fname_len = struct.unpack('>I', fname_len_data)[0]
            
            # 3. Filename (N bytes)
            filename_bytes = f.read(fname_len)
            filename = filename_bytes.decode('utf-8', errors='ignore')
            print(f"Original Filename: {filename}")

            # 4. File Type (1 byte)
            type_pos = f.tell()
            file_type_data = f.read(1)
            file_type = file_type_data[0]
            print(f"Current File Type: {file_type}")

            # Check if fix is needed
            if file_type == 255:
                print("Detected incorrect File Type (255).")
                if filename.lower().endswith('.rich'):
                    print("Filename ends with .rich. Fixing File Type to 4 (RichNovel)...")
                    f.seek(type_pos)
                    f.write(b'\x04')
                    print("Success! File Type updated to 4.")
                else:
                    print("Warning: Filename does not end with .rich, but Type is 255.")
                    choice = input("Do you want to force set Type to 4 (RichNovel)? (y/n): ")
                    if choice.lower() == 'y':
                        f.seek(type_pos)
                        f.write(b'\x04')
                        print("Success! File Type updated to 4.")
                    else:
                        print("Skipped.")
            elif file_type == 4:
                print("File Type is already 4 (RichNovel). No fix needed.")
            else:
                print(f"File Type is {file_type}. No fix needed.")

    except Exception as e:
        print(f"Unexpected error: {e}")
        # Restore backup if failed
        shutil.copy2(backup_path, file_path)
        print("Restored from backup due to error.")
    
    print("\n")

if __name__ == "__main__":
    file_to_fix = r"c:\Users\17993\Projects\MxEnc-Alpha-2.0.0\安卓.mxenc"
    fix_mxenc(file_to_fix)
