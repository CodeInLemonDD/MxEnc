I will implement the improvements for `ComicReaderScreen` using `photo_view` and `extended_image` as requested, including the flat image list structure to solve memory and scrolling issues.

### 1. Dependencies
Add the following dependencies to `pubspec.yaml`:
- `photo_view: ^0.14.0`
- `extended_image: ^8.0.2`

### 2. Refactor `ComicReaderScreen`
I will completely rewrite `mxenc/lib/screens/comic_reader_screen.dart` to adopt the new architecture.

**Key Changes:**
- **Data Structure**:
    - Flatten the nested `Chapter -> Images` structure into a single `_flatImages` list.
    - Create a map/helper to convert between "Chapter Index" and "Global Image Index" to support the chapter dropdown navigation.
- **Vertical Reader (Webtoon Mode)**:
    - Replace the `InteractiveViewer + ListView` combo with `ExtendedImageGesturePageView.builder` (vertical).
    - This allows individual image zooming and memory management without the "huge texture" issue.
- **Horizontal Reader**:
    - Use `PhotoViewGallery.builder` for Left-to-Right and Right-to-Left modes.
    - Supports native-like pinch-to-zoom and page snapping.
- **Memory Optimization**:
    - Use `ExtendedMemoryImageProvider` (via `ExtendedImage.memory`) to handle image caching better than `Image.memory`.
    - Retain the logic of reading bytes from the in-memory `payload` using `buffer.asUint8List` (efficient view).
- **Navigation & UI**:
    - Update the bottom slider/dropdown to control the `PageController` using the flattened index.
    - Re-implement the watermark and secure screen protections.
    - Re-implement the "Immersive Mode" (hiding system UI).

### 3. Verification
- Verify that `photo_view` and `extended_image` compile and run correctly.
- Verify vertical scrolling behaves as expected (Webtoon style).
- Verify horizontal zooming works smoothly.
