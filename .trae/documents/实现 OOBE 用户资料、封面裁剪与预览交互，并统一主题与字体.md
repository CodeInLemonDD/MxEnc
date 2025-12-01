## OOBE 用户资料与持久化
- 新增 `mxenc/lib/screens/oobe_screen.dart`：头像选择（本地文件或 `assets/default_avatar.jpg`）、昵称、个签，表单校验与美观布局（MD3 Card、Rounded corners）。
- 新增 `mxenc/lib/utils/user_service.dart`：读写 `SharedPreferences`（`user_avatar_path`、`user_nickname`、`user_signature`、`oobe_done`）。
- 启动时在 `main.dart` 检查：若授权用户且资料未完成，强制进入 OOBE；未授权则资料可选，OOBE可跳过。
- 创作页 `novel_upload_screen.dart` 检查：若授权且资料未完成，则拦截并导航至 OOBE；完成后再返回创作页。
- 在创作导出时，把作者资料写入 JSON：`authorNickname`、`authorSignature`、`authorAvatarPath`（`assets` 路径或本地文件）。
- 解密读取并在详情页展示作者信息（昵称/个签/头像），替换当前“奇幻小说作家”占位（`novel_detail_screen.dart`）。

## 封面裁剪编辑（固定比例）
- 新增 `mxenc/lib/screens/cover_editor_screen.dart`：
  - 显示选中原图，固定 3:4 裁剪框（可拖动/缩放裁剪框内图像），实时预览。
  - 使用 `image` 包进行裁剪与缩放，输出 JPEG/PNG 字节。
- 在 `novel_upload_screen.dart` 中：
  - `_pickCover()` 选择图片后进入裁剪页，得到裁剪字节并回填；导出时将裁剪后的字节作为头部 `metadata`（现有管道已支持）。

## 图片预览交互优化
- 优化 `image_preview_screen.dart`：
  - 双击缩放在 1.0 ↔ 2.0 ↔ 4.0 三档切换，增加当前缩放比例指示；
  - 增加“重置”与“适应屏幕”操作；保持 `InteractiveViewer` 的自由缩放/移动。
  - 已存在书架时隐藏“加入到书架”按钮（已完成基础逻辑，继续完善 UX 文案）。

## 主题与字体统一
- 修复主题色更改无效：
  - 扩展 `ThemeProvider` 支持 `seedColor` 读写（持久化于 `SharedPreferences`），`MaterialApp` 使用 `ColorScheme.fromSeed(seedColor: provider.seedColor)`。
  - 在“我的”或设置页加入主题色选择器（几组预设颜色）。
- 字体与字重统一：
  - 在 `ThemeData` 中定制 `textTheme`（标题/正文的字号与字重），全局使用 `theme.textTheme.*`。
  - 替换硬编码 `TextStyle` 为语义化主题引用，涵盖首页/详情/阅读/书架等关键页面。

## 首页进入动画
- 在 `main.dart` 的首页 `_buildHomePage()` 加入淡入 + 轻微缩放的进入动画（Logo、标题与按钮组按序列动画出现），使用 `AnimatedOpacity/AnimatedScale` 或 `FadeTransition/ScaleTransition`。

## 数据读写与展示对接
- 创作 JSON 字段新增：`tags`（已完成）、`authorNickname`、`authorSignature`、`authorAvatarPath`。导出时并入；解密时解析并在详情页展示。

## 验证
- Windows/Android：
  - 授权用户首次启动进入 OOBE；填写后可创作并在详情页显示真实作者资料与裁剪封面。
  - 未授权可跳过 OOBE，资料为可选；创作入口仍受权限控制。
  - 主题色选择后全局生效，重启仍保留；深色/浅色与主题色叠加正常。
  - 图片预览双击多档缩放、自由移动与重置操作顺畅；已在书架时按钮隐藏。
  - 首页进入动画自然、风格统一。

若确认，我将按以上方案分步实现这些改动，并进行两端验证。