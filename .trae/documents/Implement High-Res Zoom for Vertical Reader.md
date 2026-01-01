I will implement dynamic high-resolution image loading for the vertical reader mode in `ComicReaderScreen`.

### Strategy: "Lazy High-Res Reload"
True "Tiling" (Region Decoding) requires native library support which is complex to add at this stage. Instead, I will implement a **"Zoom-Triggered Reload"** mechanism:

1.  **State Tracking**: Track the zoom state via `TransformationController`.
2.  **Trigger Condition**: When `scale > 1.0` (or a threshold like 1.5), switch the image provider strategy.
3.  **Implementation**:
    *   Introduce a `_isHighResMode` boolean state.
    *   Listen to `_transformationController`.
    *   When user zooms in significantly (e.g., scale > 1.5), set `_isHighResMode = true`.
    *   When user zooms out (scale < 1.1), set `_isHighResMode = false`.
    *   In `_buildSeamlessImage`, use this flag to decide whether to pass `cacheWidth` (low res) or `null` (full res) to `ExtendedMemoryImageProvider`.
4.  **Preserving Position**:
    *   Since `ScrollablePositionedList` relies on item indices, reloading the image widget *might* cause a layout shift if the aspect ratio changes (unlikely for comics) or if the loading placeholder size differs.
    *   **Crucial**: The `ExtendedImage` already handles the image data. Changing the provider key (cache settings) will trigger a reload. To prevent visual "jumping" or white flash, `gaplessPlayback: true` is essential (already enabled).
    *   **Optimization**: To avoid reloading *all* visible images at once, I will rely on the fact that `setState` triggers the rebuild.

### Detailed Steps
1.  Add `bool _isHighRes = false;` to state.
2.  Update `_onTransformationChange`:
    *   Check `scale`.
    *   If `scale > 2.0` and `!_isHighRes`: `setState(() => _isHighRes = true);`
    *   If `scale < 1.2` and `_isHighRes`: `setState(() => _isHighRes = false);` (Hysteresis to prevent flickering).
3.  Update `_buildSeamlessImage`:
    *   Pass `cacheWidth: _isHighRes ? null : _devicePixelWidth`.
    *   When `_isHighRes` is true, `ExtendedImage` loads the full-resolution image.
    *   **Important**: This works because `ExtendedImage` caches by key. The key includes `cacheWidth`. Changing it treats it as a new image. `gaplessPlayback` will show the old low-res image until the high-res one is ready.

### Impact Analysis
*   **Memory**: High-res mode will consume significantly more memory. This is acceptable because it only happens when the user *intentionally* zooms in to see details, and usually they zoom into a specific area. However, since it's a list, *all* visible images will reload to high res. This might cause a memory spike.
*   **Performance**: There might be a slight delay when zooming in as the high-res images decode.
*   **User Experience**: User gets clear details when zooming, and smooth scrolling (low res) when zoomed out.

### Verification
*   Compile and test logic.
