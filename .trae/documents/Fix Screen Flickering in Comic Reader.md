I will fix the flickering issues in `ComicReaderScreen` when flipping pages horizontally and toggling the menu.

### Analysis of the Problem
1. **Menu Toggle Flickering**: This is likely caused by the switching of System UI Modes (`SystemUiMode.immersiveSticky` vs `SystemUiMode.edgeToEdge`). When the menu opens/closes, the system bars (status bar/navigation bar) appear/disappear, forcing a layout recalculation and a visual "jump" or flicker of the entire screen content.
2. **Page Flip Flickering**: The user mentioned "when the page divider passes the center of the screen". This suggests a layout instability or a rebuild triggered by `setState` during the scroll/drag event, or potentially an issue with `PhotoViewGallery`'s state management when crossing page boundaries.

### Solution Plan

#### 1. Fix Menu Toggle Flickering
- **Action**: **Remove the dynamic switching of `SystemUiMode`**.
- **Rationale**: Instead of hiding/showing system bars which causes resize, I will keep the system bars transparent and "draw behind" them (Edge-to-Edge). The menu overlay will simply fade in/out on top of the content without triggering a system UI mode change.
- **Implementation**: Remove `SystemChrome.setEnabledSystemUIMode` calls in `initState`, `dispose`, and the menu toggle logic.

#### 2. Fix Horizontal Flip Flickering
- **Action**: Optimize the `build` method to ensure `PhotoViewGallery` is not being rebuilt unnecessarily.
- **Potential Cause**: If `setState` is called frequently (e.g., for slider updates or index updates) *during* the drag, and the widget tree structure changes or keys are unstable, it might cause a flash.
- **Fix**:
    - Ensure `PhotoViewGallery` has a stable state.
    - Check if `onPageChanged` is triggering a heavy `setState` that affects the gallery itself.
    - Verify `gaplessPlayback` is effectively used (already added).
    - **Crucial**: The user mentioned "when the page divider passes the center". This is exactly when `PageView` switches the "active page" index. If `onPageChanged` triggers a `setState` that rebuilds the `PhotoViewGallery` with a new `pageController` or modifies properties that force a layout pass, it will flicker.
    - **Refinement**: I will ensure `onPageChanged` only updates the `_currentIndex` for the UI (slider/text) but does **not** trigger a rebuild of the `PhotoViewGallery` that would reset its internal state. The `PhotoViewGallery` should be robust enough, but I'll double-check the `PageController` persistence.

### 3. Implementation Steps
1.  **Remove Immersive Mode**: Delete all `SystemChrome` calls in `ComicReaderScreen`.
2.  **Stable Layout**: Ensure the `Stack` structure remains stable. The menu should be just another layer in the stack, not affecting the size of the `ReaderBody`.
3.  **Optimize Rebuilds**: Ensure `setState` for `_currentIndex` doesn't cause the `PhotoViewGallery` to reload images.

### 4. Verification
- Compile and verify.
