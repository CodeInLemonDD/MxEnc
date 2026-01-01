# 实施计划：优化书架、漫画编辑器及阅读器

根据您的要求，我将对应用进行以下更新，主要包括书架密码逻辑优化、漫画编辑器输入体验改进、以及漫画阅读器的功能增强。

## 1. 书架：移除密码输入限制 & 自动保存密码

**目标**：实现书架内容无密码（或使用已保存密码）直接打开，并在首次保存时同步保存密码。

* **修改文件**：

  * `mxenc/lib/screens/bookshelf_screen.dart`

  * `mxenc/lib/screens/novel_detail_screen.dart`

  * `mxenc/lib/screens/comic_detail_screen.dart`

  * `mxenc/lib/screens/rich_detail_screen.dart`

  * `mxenc/lib/screens/viewer_screen.dart`

* **具体行动**：

  * **书架打开逻辑**：修改 `bookshelf_screen.dart` 中的 `_openNovelDetailWithDecrypt` 和 `_openEncryptedContainerDirect` 方法。优先尝试使用存储的密码进行解密，仅在解密失败时才弹出密码输入框。

  * **漫画/富文本详情页 (`ComicDetailScreen`,** **`RichDetailScreen`)**：

    * 在“添加到书架”的按钮回调中，补充调用 `StorageService.saveItemPassword` 保存密码。

## 2. 漫画编辑器：修复输入法遮挡问题

**目标**：防止键盘弹出时遮挡章节标题输入框。

* **修改文件**：`mxenc/lib/screens/comic_editor_screen.dart`

* **具体行动**：

  * 在 `ListView` 的 `padding` 中加入 `MediaQuery.of(context).viewInsets.bottom`，确保键盘弹出时列表底部留出足够空间，使用户能滚动查看到当前输入框。

## 3. 漫画阅读器：修复滑动、缩放及新增翻页模式

**目标**：解决滑动冲突，启用缩放功能，并增加左右翻页模式。

* **修改文件**：`mxenc/lib/screens/comic_reader_screen.dart`

* **具体行动**：

  * **修复滑动问题**：将 `ListView` 的 `physics` 属性从 `ClampingScrollPhysics` 改为 `AlwaysScrollableScrollPhysics` 或 `BouncingScrollPhysics`，以解决向上滑动时的卡顿或无法滑动问题。

  * **优化缩放功能**：

    * 在 `_ComicImageItem` 中优化 `InteractiveViewer` 配置。

    * 添加双击手势 (`onDoubleTap`) 支持快速放大/还原。

  * **新增翻页模式**：

    * 定义 `ComicReaderMode` 枚举（垂直滚动、从左向右翻页、从右向左翻页）。

    * 在阅读器菜单中添加模式切换选项。

    * 根据选择的模式，在 `ListView`（垂直）和 `PageView`（水平）之间切换构建逻辑。

    * 针对“从右向左”模式，设置 `PageView` 的 `reverse: true`。

## 4. 验证计划

* **书架**：

  * 测试从未加密/已保存密码的文件进入详情页是否不再弹窗。

  * 测试从 `ViewerScreen` 进入详情页并保存到书架后，再次从书架打开是否无需输入密码。

* **编辑器**：

  * 打开漫画编辑器，点击底部章节输入框，确认键盘弹出时内容可滚动至可见区域。

* **阅读器**：

  * 测试垂直模式下向上/向下滑动是否流畅。

  * 测试双击图片是否能放大/还原。

  * 测试切换到左右翻页模式是否正常工作（包括从右向左的日漫模式）。

