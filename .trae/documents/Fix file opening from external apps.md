I will fix the issue where the app cannot open `.mxenc` files from file managers or system share by:

1.  **Refining `AndroidManifest.xml`**:
    *   Splitting the merged `VIEW` intent filter into separate, distinct filters for `file` and `content` schemes. This avoids ambiguity and ensures Android correctly matches intents from various file managers.
    *   Ensuring `file` scheme handles both generic (`*/*`) and unspecified MIME types.
    *   Ensuring `content` scheme handles generic MIME types.

2.  **Updating `main.dart`**:
    *    improving the `_handleSharedFile` logic to safely handle file paths.
    *   Preventing `Uri.decodeFull` from corrupting raw file paths that might contain `%` characters (unless they are actually URI-encoded).
    *   Correctly handling `file://` and `content://` prefixes.
