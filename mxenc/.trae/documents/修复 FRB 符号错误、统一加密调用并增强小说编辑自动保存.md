## 修复目标
- 解决导出加密报错：Failed to lookup symbol `frb_pde_ffi_dispatcher_primary`（DLL 未导出 FRB 所需符号）
- 统一 Dart→Rust 调用，避免混用两套绑定导致类型不匹配（`Uint8List` vs `U8`）
- 修复图片加密链路（类型与元数据）
- 为小说创作者提供长时间创作体验：工作区、自动保存、崩溃恢复、导出加密

## 方案概述
### 1) 生成并编译 Rust 端绑定（消除符号缺失）
- 在 `rust_core` 执行 FRB 生成（Dart+Rust 两端）：
  - `flutter_rust_bridge_codegen generate --rust-root . --rust-input crate --dart-output ../lib/bridge_generated/ --rust-output src/frb_generated.rs`
- 编译：`cargo build --release`
- 启动前完整重启 Flutter（不要热重启），确保装载最新 `mxenc_core.dll`

### 2) 统一 Dart 调用到 `lib/bridge_generated/lib.dart`
- 将 `rust_bridge.dart` 全部改用 `lib.dart` 的 API（参数为 `List<int>/Uint8List/int`），不再使用 `crypto.dart` 的 `U8`（RustOpaque）类型，避免运行时类型不匹配
- 封装：
  - `encryptFile`、`encryptFileWithMetadata(fileType:int, metadata:Uint8List?)`
  - `decryptFile`
  - `parseMxencHeader/Extended/FullHeader`（返回 `(String,int[,Uint8List])`）
- 类型适配：`MxEncFileType ↔ int`（0/1/2/255）

### 3) 图片加密修复
- 加密图片页：明确传入 `fileType=image`，`metadata=null`，保持原始扩展名
- 解密页：根据 `file_type` 为图片则直接 `Image.memory`，小说则从完整头部元数据（封面字节）显示预览

### 4) 小说编辑自动保存与工作区
- 工作区结构：`app_data/workspaces/<novel_id>/`
  - `novel.json`（标题、作者、简介、标签）
  - `chapters/`（每章单独文件）
  - `cover.jpg`（可选）
  - `autosave/`（快照）
- 自动保存：
  - 文本编辑防抖 2s 保存；每 30s 强制快照到 `autosave/`
  - 启动时检测未合并的快照，提供恢复
- 导出加密：
  - 合并工作区为结构化 JSON（正文为明文字节）；封面字节作为 `metadata` 写入头部
  - 调用统一的 `encryptFileWithMetadata(fileType=novel)` 导出 `<title>.novel.mxenc`

### 5) 书架与导入（基础贯通）
- 解密页“保存到书架”：写入索引 JSON（id、type、title、author、created_at/imported_at、path）；封面缓存到 `app_data/covers/<id>.jpg`
- 书架页筛选/排序使用索引字段

### 6) 验证
- FRB 符号检查通过，Dart/Rust 哈希一致
- 图片加密→解密预览链路正常
- 小说编辑→自动保存/恢复→导出→解密显示封面→详情/阅读链路正常

### 里程碑
- 阶段1：FRB 生成与编译，移除混用绑定，统一 `rust_bridge.dart`
- 阶段2：图片加密与解密预览修复
- 阶段3：小说编辑工作区与自动保存、导出加密
- 阶段4：书架索引与封面缓存打通，联调与测试