# Rich Editor Refactoring Plan

This plan aims to refactor the `RichEditorScreen` to improve UI aesthetics, user experience, and code maintainability, addressing the issues identified in the previous observation.

## Core Design Philosophy
- **Clean & Focused**: Remove visual clutter. The editor should focus on content.
- **Contextual**: Operations should appear where they are needed, not cluttering the global interface.
- **Robust**: Ensure state consistency (especially chapter/block relationships) and rendering performance.

## Key Changes

### 1. Structure & Layout
- **Remove Redundant Top Actions**: Clean up the `AppBar`. Keep only "Export/Save" and "Chapter Management". Move content insertion actions to a dedicated floating or bottom bar.
- **Unified Bottom Toolbar**: Replace the cluttered `BottomNavigationBar` with a sleek, consistent toolbar that handles:
    - Current Chapter Indicator (clickable to switch).
    - "Add Text" / "Add Image" buttons (prominent).
    - "Add Chapter" (secondary).
- **Keyboard Handling**: Wrap the body in a `GestureDetector` to dismiss the keyboard on tap outside.

### 2. List Rendering Optimization
- **Filtered List**: Instead of rendering all blocks and hiding them with `Offstage`/`SizedBox`, create a derived list `_currentChapterBlocks` in the `build` method.
    - **Benefit**: `ListView` only builds widgets for the current chapter, fixing performance and scrollbar issues.
- **Keys**: Assign `ValueKey` (using a unique block ID) to each block widget to preserve state during reordering or deletion.

### 3. Block UI Refactoring
- **Clean Cards**: Remove the "mini-toolbar" (Insert Above, Delete) from inside every card.
- **Context Menu**: Implement a "Long Press" or "Trailing Icon" menu for block operations:
    - **Delete**: Remove the block.
    - **Insert Above/Below**: Add new content relative to this block.
    - **Move Up/Down**: (Optional but nice) Reorder blocks.
- **Visuals**: Use lighter shadows, rounded corners, and better spacing for a modern look.

### 4. Logic & State Safety
- **Block Identification**: Add a unique `id` to each block upon creation. This is crucial for `Key`s and reliable deletion.
- **Chapter Sync**: Ensure the "Current Chapter" display always reflects the actual state.
- **Safe Deletion**: (Already improved in previous step, but will be integrated into new UI).

## Implementation Steps

1.  **Data Model Enhancement**:
    - Update `_addText`/`_addImage` to assign a unique UUID to each new block.
    - Ensure existing blocks (if any) get IDs if missing.

2.  **UI - AppBar & BottomBar**:
    - **AppBar**: Title "Rich Editor", Actions: [Chapter List], [Save/Export].
    - **BottomBar**: A custom `Container` with a `Row`:
        - Left: `DropdownButton` (or `InkWell`) for Chapter Selection (showing current chapter title).
        - Right: `IconButton`s for Add Text, Add Image.

3.  **UI - Main List**:
    - Filter `_blocks` to `currentBlocks` based on `_currentChapterIndex`.
    - Use `ListView.builder` on `currentBlocks`.
    - **Crucial**: Pass `ValueKey(block['id'])` to each item.

4.  **UI - Block Item**:
    - Create a helper widget `_buildBlockItem(Map block, int index)`.
    - **Text Block**: A clean `TextFormField` (multiline).
    - **Image Block**: An `Image.file` with rounded corners.
    - **Interactions**:
        - Wrap in `InkWell` or use a `PopupMenuButton` in the trailing position for "Delete", "Insert Before", etc.

5.  **Refinement**:
    - Add padding and consistent spacing.
    - Test keyboard interaction (ensure toolbar doesn't cover input).

## Verification
- Check that switching chapters instantly updates the view with correct content.
- Verify that deleting a block removes the *correct* block (thanks to Keys).
- Verify no "overflow" errors on small screens.
