我已完成相关代码的调研，为您制定了以下 4 个任务的实施计划：

### 1. 解决书架持久化问题
**现状**：目前书架数据存储在 `ApplicationSupportDirectory`，该目录在某些情况下（如应用更新或特定机型清理）可能不稳定。
**方案**：
*   修改 `StorageService`，将存储路径迁移至 `ApplicationDocumentsDirectory`。这是 Android/iOS 上用于存储用户文档的标准持久化目录，数据会随应用备份且不会被系统自动清理。
*   *(注意：此更改会重置现有用户的书架显示，因为读取路径变了)*

### 2. 书架自动保存密码
**现状**：代码中已有 `saveItemPassword` 和 `getItemPassword` 的底层实现，但在书架点击打开书籍的逻辑中，解密成功后没有调用保存密码的方法。
**方案**：
*   修改 `BookshelfScreen` 中的 `_openNovelDetailWithDecrypt` 和 `_openEncryptedContainerDirect` 方法。
*   在解密流程成功完成（`ProgressPhase.done`）后，自动调用 `StorageService.saveItemPassword` 记录密码。
*   下次打开时，现有逻辑会自动读取并使用该密码，实现免密打开。

### 3. 注册 .mxenc 文件打开方式
**现状**：应用未注册文件关联，无法在文件管理器中直接打开 `.mxenc` 文件。
**方案**：
*   **Android 配置**：在 `AndroidManifest.xml` 中添加 `intent-filter`，注册对 `.mxenc` 后缀和 `application/octet-stream` (或特定 mime) 的响应。
*   **依赖库**：引入 `receive_sharing_intent` 插件来监听外部打开文件的意图。
*   **启动逻辑**：在 `main.dart` 中添加监听代码，当检测到应用是通过“打开文件”启动时，自动跳转到解密页面 (`ViewerScreen`) 并预填文件路径。
*   **页面适配**：修改 `ViewerScreen` 以支持接收初始文件路径参数。

### 4. 加密成功弹窗优化
**现状**：加密成功后仅显示 `SnackBar`（底部黑条提示），容易被忽略且无法直接操作。
**方案**：
*   引入 `share_plus` 插件用于系统分享。
*   修改 `EncryptScreen` (文件加密)、`EncryptImageScreen` (图片加密)、`ComicEditorScreen` (漫画导出)、`RichEditorScreen` (小说导出) 四个页面的成功回调。
*   将 `SnackBar` 替换为 `showDialog`，显示“加密成功”标题和文件路径。
*   弹窗下方提供 **“确定”** 和 **“分享文件”** 两个按钮，点击分享可直接调起系统分享面板发送文件。

确认执行此计划后，我将按顺序修改代码。