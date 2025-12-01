## 总览

* 目标：按 7 大项改进 Flutter+Dart 前端与 Rust 后端，提升跨平台体验（Windows/Android），并补齐测试。

* 方法：在现有架构（Flutter + flutter\_rust\_bridge + Rust）上增量改造，复用已有组件与风格，避免破坏性变更。

## 1) 输入法控制（IME）

* 修复点位：为所有密码输入框增加显式收起键盘与失焦，覆盖加密、图片加密、解密、上传、编辑弹窗等。

  * `mxenc/lib/screens/encrypt_screen.dart:270` 附近的密码/确认密码 TextField

  * `mxenc/lib/screens/encrypt_image_screen.dart:239`

  * `mxenc/lib/screens/viewer_screen.dart:575`

  * `mxenc/lib/screens/novel_upload_screen.dart:829`

  * `mxenc/lib/screens/rich_editor_screen.dart:320`

  * `mxenc/lib/screens/comic_editor_screen.dart:265`

* 具体改造：

  * 为上述 TextField 添加 `onSubmitted` 与 `textInputAction: TextInputAction.done`，回调里执行：`FocusScope.of(context).unfocus()` 与 `SystemChannels.textInput.invokeMethod('TextInput.hide')`。

  * 在“确认/加密/解密”按钮点击前后统一调用 `unfocus()+hide()`，避免残留输入法。

  * 提供一个轻量工具类（如 `KeyboardUtils.hide(context)`）集中封装这两步，减少重复。

* 测试：新增 `test/ui/ime_control_test.dart` 组件测试，模拟输入后触发 `onSubmitted` 与按钮点击，断言 `FocusManager.instance.primaryFocus == null`；在 Windows/Android 运行验证行为一致。

## 2) 解密流程优化与精确进度

* Rust 后端：提供精确进度事件流。

  * 新增 `ProgressEvent { phase, processed, total, percent }`，阶段包含：`ReadHeader/DeriveKey/Decrypt/Decode`。

  * 新增接口 `decrypt_file_with_progress(path, password, sink)`（或字节输入版本），在解密过程中分块处理密文，每处理一段向 sink 发送进度。

  * 解析头与派生密钥也发阶段进度，百分比严格 0–100。

* FRB 桥接：

  * 在 `mxenc/rust_core/src/lib.rs` 暴露 `#[frb]` 的 stream/异步接口（基于 flutter\_rust\_bridge 的 `StreamSink`/channel 支持）。

  * Dart 侧在 `mxenc/lib/bridge_generated/crypto.dart` 暴露为 `Stream<ProgressEvent>`。

* Dart UI：

  * `mxenc/lib/rust_bridge.dart` 增加 `decryptFileWithProgress(...)` 封装。

  * `mxenc/lib/screens/viewer_screen.dart:167` 附近移除人工 `Future.delayed(16ms)` 与手工百分比，改为订阅进度流更新 `_progress` 与 `_progressLabel`，并在“完成”事件时切换预览态。

  * 大 JSON（小说）解析改为 `compute(jsonDecode, data)` 后台 isolate；头部解析与大文件读入尽量交由 Rust 侧完成，避免主线程阻塞。

* 其他卡顿修复：

  * 避免 `readAsBytes()` 后在主线程直接 `setState` 挂载大 `Uint8List`；图片类内容的二进制交由 `Image.memory` 解码线程处理，文本类通过 isolate 解码。

* 测试：

  * Rust 单元测试：对进度计算与阶段顺序断言；大文件（模拟）下 percent 最终为 100。

  * Flutter 组件测试：订阅模拟进度流，断言 UI 百分比与标签随事件正确更新。

## 3) 加载弹窗界面（希望使用md3expressive风格）

* 新增统一组件：`mxenc/lib/widgets/loading_dialog.dart`

  * 内容：圆形 `CircularProgressIndicator` + 百分比文本 + 可选阶段说明；`barrierDismissible:false`。

  * 样式：使用 `ProgressIndicatorTheme` 与项目种子色，确保 Windows/Android 一致显示。

  * 提供 `LoadingController`（`ValueNotifier<double>` 或 `Stream`）便于外部更新。

* 应用：在解密/加密等长耗时流程中用统一弹窗替代散落的局部 `LinearProgressIndicator`；保留顶部线性进度的页面继续沿用但由同一数据源驱动。

* 测试：golden 测试覆盖 0%、50%、100% 三态截图，断言样式与数值。

## 4) 卡密系统：计时与剩余时间显示

* 逻辑：在 `LicenseService` 增加 `decodeLicense()` 返回 `{ deviceId, exp, sig }`；在 UI 计算 `remaining = exp - nowSec`，格式化为 `Xd Xh Xm Xs`。

* 显示：

  * `mxenc/lib/screens/permission_screen.dart` 的卡密激活区块下方显示剩余时间；使用 `Timer.periodic(Duration(seconds:1))` 实时刷新。

  * `mxenc/lib/screens/my_profile_screen.dart` “卡密激活”项旁显示剩余时间摘要。

* 精度：统一使用服务器/本机当前时间（本地），确保向下取整并不出现负数；过期时 UI 变为“已过期”。

* 测试：单元测试覆盖不同 `exp` 场景（刚好到期、剩余 1 秒、跨日），断言显示与状态。

## 5) 界面优化：改进 rich  预览

* 让rich具有 novel 的信息展示（标题、作者、阅读进度滑条、字体/行距设置、夜间模式开关）以及novel的那种详情（detail）页。

* 统一水印与主题：

## 6) 漫画预览问题修复

* 放大缩放：在 `mxenc/lib/screens/comic_reader_screen.dart` 的图片 `itemBuilder` 外包裹 `InteractiveViewer`（参考 `image_preview_screen.dart:238` 的实现），启用双指缩放、拖拽与双击缩放；为 Windows 保持鼠标滚轮与拖拽体验一致。

* 滑动异常与“自动返回顶部”问题：

  * 稳定滚动状态：为每章节使用不同 `PageStorageKey('comic_reader_${sourcePath}_chapter_$index')`，避免跨章节复用导致位置错乱。

  * 仅在显式切换章节时调用 `animateTo(0)`（或 `jumpTo(0)`）；普通 UI 状态切换（如叠层显隐）不重建列表，不改变 `ScrollController`。

  * 如需确保构建后再重置，使用 `addPostFrameCallback` 调用滚动复位。

* 交互优化：统一触控与鼠标的缩放/拖拽阈值与回弹边界，避免突然跳动。

* 测试：组件测试模拟章节切换、滚动、缩放，断言不会意外回到顶部，缩放后仍可正常滚动。

## 7) 其他改进与测试

* 消除重复 UI 元素：抽取通用 `FavoriteButton`、`TopOverlay`/`BottomOverlay` 组件，减少各页面重复代码与功能。

* 跨平台一致性：对关键页面的字号、颜色与间距进行统一；在 Windows/Android 进行手动验收（DP 与像素差异）。

* 测试总体：

  * 功能测试：IME 控制、解密进度 UI、卡密剩余时间、漫画缩放与滚动、统一阅读界面基本行为。

  * 性能测试：构造大文件场景，验证进度刷新与 UI 流畅；在 Dart 层避免主线程重活（compute/isolate）。

  * 兼容性测试：Windows 与 Android 分别运行上述测试与手动交互流程；必要时引入 `integration_test` 做端到端流程。

—— 请确认上述计划，确认后我将分步骤实施（先 UI 小改再 Rust 进度流），并同步提交对应的测试。
