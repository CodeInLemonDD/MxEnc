I will create a Python script `analyze_mxenc.py` to analyze the structure of the `.mxenc` files.

The script will:
1.  **Define the File Structure**: Based on the `MXENC20` format (Magic, Filename, Type, Metadata, Salt, Nonce, Ciphertext).
2.  **Parse & Validate**:
    *   Read and verify the "Magic" header.
    *   Extract and print the original filename and file type.
    *   Extract and print metadata (if any).
    *   Show the Salt and Nonce (used for encryption).
    *   Calculate the size of the encrypted data and check if the file is truncated.
3.  **Compare Files**: Run the analysis on both `windows.mxenc` (working) and `安卓.mxenc` (broken) to identify structural differences (e.g., file truncation, corrupted headers, or version mismatches).

This script will provide a detailed breakdown of why the Android version is failing to decrypt.