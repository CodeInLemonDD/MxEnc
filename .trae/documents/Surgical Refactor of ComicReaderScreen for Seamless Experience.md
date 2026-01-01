I will implement the "Surgical Refactor" of the `ComicReaderScreen` to achieve seamless vertical scrolling and global zooming as requested.

### 1. Dependencies
Add `scrollable_positioned_list: ^0.3.8` to `mxenc/pubspec.yaml`.

### 2. Refactor `ComicReaderScreen`
I will completely rewrite `mxenc/lib/screens/comic_reader_screen.dart` with the following key components:

- **Seamless Vertical Scrolling**:
    - Use `ScrollablePositionedList.builder` instead of `ListView` for precise index-based jumping.
    - Set `padding: EdgeInsets.zero` and use `BoxFit.fitWidth` for images to eliminate gaps.
    - Enable `gaplessPlayback: true` in `ExtendedImage` to prevent flickering.
    - Implement `minCacheExtent` to preload images.

- **Global Zoom & Scroll Sync**:
    - Wrap the list in `InteractiveViewer` for global zooming.
    - Use `ItemPositionsListener` to track the currently visible index for the progress bar.
    - **Crucial**: Implement the "Gesture Proxy" logic.
        - Listen to `onInteractionUpdate` in `InteractiveViewer`.
        - When scaled > 1.0, manually calculate the vertical delta (`details.focalPointDelta.dy`) and apply it to the `ItemScrollController` (or `ScrollController` if `ScrollablePositionedList` doesn't support pixel-perfect jump easily, but the user requested `scrollable_positioned_list` for index jumping).
        - *Self-correction*: `ScrollablePositionedList` is great for index jumping but harder for pixel-level smooth scrolling driven by gestures. However, the user explicitly asked for `scrollable_positioned_list` for precise jumps. I will use `ScrollablePositionedList` and its `ItemScrollController` for the main list. For the "zoomed scrolling" logic, `ScrollablePositionedList` might be tricky to "scroll by pixels".
        - *Refined Plan*: The user provided two distinct code blocks. One using `ScrollablePositionedList` for precise jumps, and another discussing "Gesture Proxy" with `ListView`. I will combine the best of both:
            - Use `ScrollablePositionedList` for the main implementation to satisfy the "precise jump" requirement.
            - For the "zoomed scrolling" (Gesture Proxy), `ScrollablePositionedList`'s `ItemScrollController` doesn't support `jumpTo(pixelOffset)`. It supports `jumpTo(index)`.
            - **Decision**: I will use `ScrollablePositionedList` as the primary vertical view. The "zoomed scrolling" feature (pan while zoomed) is natively handled by `InteractiveViewer` if the child is large enough. The user's "Gesture Proxy" suggestion was for `ListView` inside `InteractiveViewer` where `ListView` consumes gestures. If `InteractiveViewer` wraps the whole list and the list is "not scrollable" (physics disabled) while zoomed, `InteractiveViewer` handles the pan.
            - I will implement `ScrollablePositionedList` with `physics: AlwaysScrollableScrollPhysics()` normally. When zoomed, I will disable the list's physics so `InteractiveViewer` handles the pan (X and Y). This is the standard "Zoomable List" pattern.

- **Preloading & Performance**:
    - Use `precacheImage` logic in `_updateIndexFromScroll`.
    - Use `ExtendedImage` with memory cache enabled.

### 3. Verification
- Compile and build the APK to ensure no errors.
