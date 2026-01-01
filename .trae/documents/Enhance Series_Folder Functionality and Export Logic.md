# Phase 1: Core Logic & Data Model Updates
## 1. Update Data Models (`lib/models/series.dart`)
- **Modify `SeriesVolume`**: Add `List<String> tags` field to store tags for items inside folders. Update `fromJson`/`toJson`.

## 2. Enhance Storage Service (`lib/utils/storage_service.dart`)
- **Preserve Tags**: Update `moveItemToSeries` and `copyItemToSeries` to transfer tags from `BookshelfItem` to `SeriesVolume`.
- **Background Compression**: Move zip compression logic to a static top-level function to run via `compute` (Isolate), preventing UI blocking.
- **Robust Export**: Ensure `series.json` is explicitly added to the zip archive.
- **Save As Logic**: Update export function to accept a destination path or return a stream/bytes, allowing "Save As" functionality.

# Phase 2: Series Detail Screen Improvements
## 1. Export Functionality (`lib/screens/series_detail_screen.dart`)
- **UI Update**: Replace the current auto-save export with a "Save As" flow (FilePicker).
- **Non-blocking**: Use the new background compression service with a loading indicator.

## 2. Folder Management
- **Sorting**: Implement `ReorderableListView` to allow users to reorder volumes.
- **Deletion**: Add functionality to delete individual volumes from a series (updating `series.json` and deleting the file).

# Phase 3: Bookshelf Enhancements
## 1. Advanced Search & Filtering (`lib/screens/bookshelf_screen.dart`)
- **Deep Search**: Modify `_loadBookshelfItems` to (asynchronously) load `series.json` for Series items, enabling search to match tags of items *inside* folders.
- **Series Filter**: Add a "Series" (系列) filter chip.

## 2. Multi-select Operations
- **Batch Actions**: Add "Move to Folder" and "Copy to Folder" actions to the multi-select mode.
- **UI**: Update the selection toolbar to include these new options.

# Phase 4: Android Manifest & Configuration
- **File Association**: (Already partially checked) Ensure `.mxzip` is correctly handled if further tweaks are needed (User mentioned "qq", usually requires `content://` uri support handling which is often handled by `receive_sharing_intent` or similar, but for "opening" files, `file_picker` or standard intent handling in `MainActivity` might be needed. *Note: The user's prompt regarding manifest was in the context of "maybe you need to modify...", I will double check if the current configuration is sufficient for opening files from other apps.*) -> *Self-correction: The previous turn handled Manifest. I will focus on the logic implementation.*
