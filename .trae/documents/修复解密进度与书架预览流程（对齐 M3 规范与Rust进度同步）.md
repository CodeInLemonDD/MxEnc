## 问题与目标

* 解密大文件时进度不动、耗时长：对话框阻塞、主线程重活、无真实进度来源。

* 书架预览跳转流程：从书架进入会先打开 viewer\_screen，返回时停留在它，期望直接返回书架且流程不经过 viewer\_screen。

## 方案总览

* 后端：为 Rust 解密实现精确进度流（阶段与字节进度）并通过 FRB 暴露为 `Stream<ProgressEvent>`。

* 前端：所有解密/加密流程使用非阻塞 M3 加载弹窗，按真实进度更新；重构书架点击行为，直接在书架页触发解密并导航到最终阅读页，返回时回到书架。

* 样式：统一 Material 3 进度指示器主题（颜色/密度），组件语义化与无障碍友好。

## Rust 后端（进度流）

* 新增结构：`ProgressEvent { phase: 'ReadHeader'|'DeriveKey'|'Decrypt'|'Decode'|'Save', processed: u64, total: u64, percent: f32 }`。

* 新增接口：`decrypt_file_with_progress(path: String, password: String, sink: StreamSink<ProgressEvent>) -> DecryptResult`。

  * 头解析、密钥派生设定阶段权重（或真实总量可用时给定 total）。

  * 解密阶段按分块读取/解密，周期性 `sink.add(ProgressEvent)`。

  * 完成时返回 `(filename, decrypted_bytes)`。

* FRB 暴露：在 `lib.rs` 添加 `#[frb]` 流接口，生成 Dart `Stream<ProgressEvent>`。

## Dart 前端（桥接与UI）

* `RustBridge`：添加 `decryptFileWithProgress(...)` 返回 `(Stream<ProgressEvent>, Future<DecryptResult>)` 的封装；保留现有同步接口作为回退。

* M3 加载弹窗：重构 `loading_dialog.dart` 为非阻塞 `M3LoadingDialog`，显示：主文案、圆形进度（确定/不确定）、百分比；使用 `ProgressIndicatorTheme`；添加 `Semantics(label/value)`。

* 进度驱动：订阅 Rust 进度流 → 更新控制器与线性进度；移除所有 `Future.delayed(...)` 伪推进。

* 主线程优化：继续将 JSON 解码等重活搬到 `compute(...)`；避免将大 `Uint8List` 直接 setState（图片由 `Image.memory` 管理解码线程）。

## 书架预览流程重构

* `BookshelfScreen::_onItemTap`：

  * 对 `isComic`/`isRichNovel` 项：在书架页显示 M3 加载弹窗，调用 `rustBridge.decryptFileWithProgress(...)` 解密；完成后直接 `Navigator.push` 到 `ComicReaderScreen`/`RichReaderScreen`；不经过 `ViewerScreen`；返回时自动回到书架。

  * `isNovel` 保持现状（进入 `NovelDetailScreen`）。

* 清理：移除对这两类内容的 `pushReplacement(ViewerScreen)`；确保回退栈顶部始终是书架。

## 样式一致性（Material 3）

* 主题：在 `ThemeData(useMaterial3: true)` 下统一 `progressIndicatorTheme`：

  * `color: colorScheme.primary`

  * `linearTrackColor: colorScheme.surfaceContainerHighest`

  * `circularTrackColor: colorScheme.surfaceContainerHigh`

  * `linearMinHeight: 4`

* 组件：

  * 圆形进度大小 `24dp`、`strokeWidth: 4`；文本使用 `titleMedium`/`labelMedium`。

  * 顶部线性进度保留但统一高度与颜色。

## 测试与验证

* 非阻塞对话框：显示后业务逻辑继续推进，百分比按事件增长到 100%，最终自动关闭；组件测试覆盖。

* 书架流程：点击漫画/富文本后直接显示加载并进入阅读页，返回不出现 `ViewerScreen`；路由测试覆盖。

* 大文件解密：模拟大密文，验证 Rust 进度流驱动 UI，不再卡在 0%，总体耗时合理。

* 视觉快照（Windows/Android尺寸）：验证 M3 样式一致性。

## 交付节奏

* 先落地 Rust 进度流与 Dart 订阅；

* 重构书架点击逻辑与 UI 弹窗；

* 完成测试与 lint 处理（优先修复进度与导航问题）。

如确认，我将开始实施以上改动并提交对应的代码与测试。
