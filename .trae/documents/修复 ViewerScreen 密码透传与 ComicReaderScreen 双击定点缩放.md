# 实施计划：修复密码透传与双击缩放定位

## 1. 修复密码透传问题 (ViewerScreen & DetailScreens)

**目标**：确保从 `ViewerScreen` 进入 `ComicDetailScreen` 和 `RichDetailScreen` 时，密码能正确传递，且在保存到书架时被正确保存。

*   **问题分析**：之前的修改已经添加了 `password` 参数传递，但用户反馈“密码透传不正常”。
    *   检查发现：在 `ViewerScreen.dart` 中，跳转 `ComicDetailScreen` 和 `RichDetailScreen` 的 `MaterialPageRoute` 构造中，虽然添加了 `password` 参数，但参数值使用的是 `_passwordController.text`。如果用户解密后修改了输入框内容（虽然不太可能，因为解密时会隐藏键盘并显示加载），或者在某些边缘情况下（如自动尝试解密成功），`_passwordController` 可能为空。
    *   **修正方案**：在 `_decryptFile` 方法中，使用局部变量保存解密成功的密码（即 `_passwordController.text`），并在跳转时使用该变量。同时，确保在自动解密逻辑中（`initState` -> `_parseHeader` -> `_decryptFile`），如果是因为检测到保存的密码而自动解密，`_passwordController.text` 已经被正确赋值。
    *   **补充检查**：确认 `ComicDetailScreen` 和 `RichDetailScreen` 的 `initState` 中是否正确初始化了 `_isSaved` 状态，以及保存逻辑是否使用了 `widget.password`。

*   **修改文件**：`mxenc/lib/screens/viewer_screen.dart`
*   **具体行动**：
    *   在 `_decryptFile` 中，解密成功后，明确使用当前的密码值传递给 Detail 页面。

## 2. 优化双击放大体验 (ComicReaderScreen)

**目标**：实现“双击哪里放大哪里”的精准缩放体验。

*   **问题分析**：当前实现是简单的 `scale(2.5)`，默认以视图中心为缩放原点。`InteractiveViewer` 的 `TransformationController` 控制的是整个视图的变换矩阵。
*   **算法逻辑**：
    1.  获取双击点的屏幕坐标 `tapPosition`。
    2.  计算该点在当前变换下的场景坐标（Scene Coordinate）。
    3.  构建一个新的矩阵：将场景中的该点平移到视图中心（或保持在手指下），同时应用缩放。
    4.  更符合直觉的逻辑是：**保持双击点在屏幕上的位置不变，进行缩放**。
    *   公式：`Translate(x, y) * Scale(s) * Translate(-x, -y)` 是以 (x,y) 为中心的缩放。但 `InteractiveViewer` 的矩阵是 `Scene -> Viewport` 的变换。
    *   我们需要计算一个新的 Matrix4，使得：`NewMatrix.transform(ScenePoint) == ViewportPoint`。
    *   实际上，`InteractiveViewer` 提供了 `toScene` 方法。
    *   **简化方案**：利用 `Matrix4` 的操作。先将双击点平移到原点，缩放，再平移回去。但由于要累加到现有变换上，需要小心处理。
    *   **最终方案**：
        *   获取双击位置 `local`。
        *   计算当前 Scene 中的点：`scenePoint = controller.toScene(local)`。
        *   计算目标矩阵：`Matrix4.identity()..translate(local.dx, local.dy)..scale(targetScale)..translate(-scenePoint.dx, -scenePoint.dy)`。
        *   或者更简单：`Matrix4.identity()..translate(-scenePoint.dx * targetScale + local.dx, -scenePoint.dy * targetScale + local.dy)..scale(targetScale)`。

*   **修改文件**：`mxenc/lib/screens/comic_reader_screen.dart`
*   **具体行动**：
    *   在 `GestureDetector` 中添加 `onDoubleTapDown` 回调，捕获 `TapDownDetails` 以获取点击位置。
    *   重写 `_handleVerticalDoubleTap` 和 `_zoomInVertical`，引入点击位置参数。
    *   在 `_ComicImageItem` 中同样应用此逻辑（针对水平模式的单图缩放）。

## 3. 验证计划

*   **密码透传**：
    *   在 `ViewerScreen` 输入密码解密漫画。
    *   跳转到 `ComicDetailScreen`。
    *   点击“保存到书架”。
    *   回到书架，直接点击该漫画，确认是否无需输入密码直接打开。
*   **双击缩放**：
    *   在垂直模式下，双击屏幕左上角。
    *   预期：视图放大，且左上角的内容依然在可视区域内（或接近）。
    *   在水平模式下，双击图片右下角。
    *   预期：图片放大，且右下角的内容被放大并在屏幕内。