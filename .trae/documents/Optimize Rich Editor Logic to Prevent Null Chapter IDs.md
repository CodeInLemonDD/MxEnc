# RichEditorScreen Optimization Plan

The rich editor has logic flaws where content blocks can be created with a `null` `chapterId` if no chapter is selected or created. This results in content that exists in the file but is invisible in the reader (which filters by chapter ID).

## Goals
1.  **Ensure Initial State**: Automatically create a default chapter when entering the editor.
2.  **Guard Content Creation**: Ensure a valid chapter exists and is selected before adding text or images.
3.  **Sanitize Export**: Before exporting, assign any orphaned blocks (null chapterId) to the first available chapter to prevent data loss.
4.  **Safe Deletion**: When deleting a chapter, handle its content more gracefully (or at least ensure the UI state remains consistent).

## Implementation Steps

### 1. Initialize Default Chapter
Modify `_RichEditorScreenState` to add an `initState` method:
- Check if `_chapters` is empty.
- If empty, create a default "Chapter 1".
- Set `_currentChapterIndex` to 0.

### 2. Auto-Create/Select Chapter on Add
Modify `_addText` and `_addImage`:
- Check if `_currentChapterIndex` is invalid (< 0) or `_chapters` is empty.
- If so, call `_addChapter()` (or manually create one) and update `_currentChapterIndex` before adding the block.

### 3. Export Sanitization
Modify `_exportEncrypted`:
- Before packaging `manifest`, iterate through `_blocks`.
- If a block has `chapterId == null`:
    - If `_chapters` is empty, create a default chapter.
    - Assign the block's `chapterId` to the first chapter's ID.
- This ensures no content is "lost" in the null void.

### 4. Chapter Management Logic
Modify `_manageChapters` (deletion logic):
- When a chapter is deleted, if `_chapters` becomes empty, reset `_currentChapterIndex` to -1.
- (Optional but recommended) If the user deletes the last remaining chapter, automatically create a new empty one to keep the editor usable.

## Verification
- **Test 1**: Enter editor -> Add text -> Export. (Should work without manually adding chapter).
- **Test 2**: Delete all chapters -> Add text -> Export. (Should auto-create chapter and export valid file).
- **Test 3**: Analyze exported file (using the previous analysis script) to ensure `chapterId` is never null.
