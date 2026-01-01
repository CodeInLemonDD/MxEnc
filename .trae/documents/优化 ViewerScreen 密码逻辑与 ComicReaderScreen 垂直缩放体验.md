# 实施计划：优化 ViewerScreen 与 ComicReaderScreen

## 1. ViewerScreen 优化

**目标**：确保密码传递给所有详情页，并完善解密失败的错误检测。

*   **修改文件**：`mxenc/lib/screens/viewer_screen.dart`
*   **具体行动**：
    1.  **密码传递**：在跳转到 `ComicDetailScreen` 和 `RichDetailScreen` 的 `MaterialPageRoute` 中，添加 `password: _passwordController.text` 参数。
    2.  **错误检测**：
        *   在 `_decryptFile` 方法的循环结束后，检查是否成功解密。如果未成功且未捕获异常，手动设置错误信息“解密失败，可能是密码错误”。
        *   在 `catch` 块中，放宽错误信息的匹配条件，确保用户能看到明确的提示。

## 2. ComicReaderScreen 垂直模式优化

**目标**：实现垂直滚动模式下的整体缩放（长图体验），而非单图缩放。

*   **修改文件**：`mxenc/lib/screens/comic_reader_screen.dart`
*   **具体行动**：
    1.  **状态管理**：
        *   新增 `TransformationController _verticalTransformController` 用于控制垂直模式下的整体缩放。
        *   新增 `AnimationController` 用于实现平滑缩放动画。
        *   新增 `ScrollPhysics _verticalPhysics`，根据缩放比例在 `AlwaysScrollableScrollPhysics`（可滚动）和 `NeverScrollableScrollPhysics`（不可滚动）之间切换。
    2.  **重构垂直模式 UI**：
        *   使用 `InteractiveViewer` 包裹 `ListView`。
        *   `InteractiveViewer` 使用 `_verticalTransformController`。
        *   监听 `_verticalTransformController` 的变化，当 `scale > 1.0` 时禁用 `ListView` 滚动。
    3.  **双击缩放支持**：
        *   在最外层的 `GestureDetector` 中添加 `onDoubleTap` 回调。
        *   当处于垂直模式时，双击触发 `InteractiveViewer` 的放大/复原。
    4.  **图片组件调整**：
        *   修改 `_ComicImageItem`，增加 `enableZoom` 参数。
        *   垂直模式下传入 `enableZoom: false`（禁用单图缩放），水平模式下传入 `true`。

## 3. 验证计划

*   **ViewerScreen**：
    *   使用错误密码尝试解密，确认是否弹出提示。
    *   使用正确密码解密漫画/富文本，进入详情页后点击“保存到书架”，确认密码是否被保存。
*   **ComicReaderScreen**：
    *   切换到垂直模式，尝试双击屏幕，确认是否整体放大。
    *   放大状态下尝试拖动，确认是否可以平移查看长图的各个部分。
    *   放大状态下尝试滚动列表，确认列表滚动是否被禁用（避免冲突）。
    *   恢复原大后，确认列表是否可以正常滚动。
    *   切换到水平模式，确认单图缩放功能依然正常。