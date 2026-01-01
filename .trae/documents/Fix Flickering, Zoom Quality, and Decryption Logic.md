I will address the user's issues regarding horizontal flickering, high-resolution zoom, decryption progress stuck on error, and password persistence.

### 1. ComicReaderScreen: Horizontal Flickering & High-Res Zoom
*   **Fix Flickering**: The flickering during page transitions (when the divider crosses the center) is likely due to the `PageView` rebuilding or `setState` triggering prematurely. I will ensure `onPageChanged` doesn't trigger a heavy rebuild. The current `PhotoViewGallery` setup is generally good, but I'll double-check `gaplessPlayback` is active for horizontal mode (it was missing in `_buildHorizontalReader`'s provider).
*   **High-Res Zoom**: Currently, images are downsampled to screen width using `cacheWidth`. When zoomed in, they look blurry.
    *   **Solution**: Implement a dynamic resolution strategy.
    *   Load images with `cacheWidth` (downsampled) by default for the list/gallery.
    *   When `InteractiveViewer` or `PhotoView` scale exceeds 1.0 (zoomed in), trigger a reload of the **original resolution** image for that specific page.
    *   *Refined Plan*: Since reloading on the fly might be slow, a better approach for "Zoom" is to use `PhotoView`'s `loadingBuilder` or simply allow `ExtendedImage` to load the full image *if* the user is in a "Detail Mode". However, reloading the same image byte array with different `cacheWidth` is efficient enough.
    *   *Implementation*: In `_buildSeamlessImage` (Vertical) and `_buildHorizontalReader`, I will check the `_transformationController` scale. But since `ListView` items are built on demand, reacting to global zoom for individual items is tricky.
    *   **Better Approach**: For horizontal mode (`PhotoView`), it handles zooming internally. I will **remove `cacheWidth` from the horizontal reader** (or set it to `null`) to allow full resolution, as horizontal mode only renders 1-3 images at a time (current, prev, next), so memory pressure is lower than a vertical list of 100 images. Vertical mode must keep downsampling for performance, but horizontal can afford full res.

### 2. ViewerScreen: Decryption Progress & Password Saving
*   **Fix Progress Stuck**: In `ViewerScreen`, the `_decryptFile` method catches errors but doesn't close the loading dialog. I will add a `finally` block or ensure `Navigator.pop` is called in the `catch` block to dismiss the dialog on error.
*   **Fix Password Saving**: The user says password isn't saved to bookshelf.
    *   **Investigation**: `ViewerScreen` passes `password` to `ComicDetailScreen`. `ComicDetailScreen` saves it to `StorageService` when "Add to Bookshelf" is clicked.
    *   **Root Cause**: It's possible `ViewerScreen` isn't passing the *correct* password variable (e.g., passing a null or empty string instead of the input controller's text).
    *   **Fix**: Verify `ViewerScreen` passes the actual password text to `ComicDetailScreen` and `RichDetailScreen`. Ensure `StorageService.saveItemPassword` is called correctly.

### 3. Execution Plan
1.  **ViewerScreen**:
    *   Modify `_decryptFile` to ensure `Navigator.pop` on error.
    *   Verify password passing logic.
2.  **ComicReaderScreen**:
    *   **Horizontal Mode**: Remove `cacheWidth` from `ExtendedMemoryImageProvider` in `_buildHorizontalReader` to enable full-resolution zooming. This also likely fixes "flickering" if the flickering was caused by constant re-decoding of downsampled images.
    *   **Vertical Mode**: Keep downsampling for list performance. (User specifically mentioned "Image enlarged", which usually implies the horizontal "view single page" mode or the interactive zoom. For vertical, if they zoom huge, it might still be blurry, but we can't easily fix that without tiling).

### 4. Verification
*   Compile and verify.
