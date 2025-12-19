I will implement the following changes to fix the bookshelf refresh issue, button visibility, and UI occlusions:

1.  **Fix Bookshelf Refresh Issue (`BookshelfScreen.dart`):**
    *   Modify all navigation calls (in `_onItemTap`, `_openNovelDetailWithDecrypt`, `_openEncryptedContainerDirect`, and the empty state "Go to Decrypt" button) to `await` the result.
    *   Call `_loadBookshelfItems()` immediately after the navigation returns. This ensures the list refreshes automatically when you return from viewing or saving a new item.

2.  **Optimize "Save to Bookshelf" Button (`NovelDetailScreen.dart`):**
    *   Add a `fromShelf` parameter to the `NovelDetailScreen` constructor.
    *   In `BookshelfScreen`, pass `fromShelf: true` when opening a novel.
    *   In `NovelDetailScreen`, add logic to hide the "Save to Bookshelf" button if:
        *   It was opened from the bookshelf (`widget.fromShelf` is true).
        *   OR the user just successfully saved it (track with a local `_isSaved` state).

3.  **UI/UX Optimizations:**
    *   **Prevent Occlusion:** In `BookshelfScreen`, increase the bottom padding of the `GridView` (to 80px) to ensure the last row of items is not covered by the "Delete" Floating Action Button when in selection mode.
    *   **State Feedback:** In `NovelDetailScreen`, update the UI immediately after saving to remove the save button, providing better feedback.
