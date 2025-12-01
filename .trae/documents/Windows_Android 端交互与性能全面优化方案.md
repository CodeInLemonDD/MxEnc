## 目标
- Rich 作品的预览页增加并统一 Novel 的信息展示（标题、作者、简介、标签、字数/章节统计、作者卡片等）。
- 调整 Rich 加密/导出时需要填写的作品信息，保证预览页所需元数据完整。
- 兼容既有 Rich 容器与书架数据，不破坏旧文件；新增字段采用回退策略。

## Manifest 扩展（兼容增量）
- 在 Rich 的 manifest 增加以下作品级字段：
  - `description`（简介/作品概述）
  - `totalWordCount`（正文字数总计，导出时计算并写入）
  - `volumes`（可选分卷结构，缺省时由 `chapters` 平铺）
  - `tags`（已有，保留并统一格式）
  - `authorNickname`、`authorSignature`、`authorAvatarPath`、`authorDeviceId`（已存在，继续使用）
  - `coverRef`（已存在，继续使用）
- 回退策略：旧文件不含 `description/totalWordCount/volumes` 时，预览页显示“暂无简介”，字数与章节统计按 blocks/chapters 动态计算。

## 编辑器采集（rich_editor_screen 调整）
- 对话框/表单增加以下输入：
  - 标题（已存在，保留）
  - 简介/作品描述（新增多行 TextField）
  - 标签（已存在，保留，统一逗号分隔解析）
  - 可选分卷（简化为章节分组选择，首版可不实现分卷录入，先由章节平铺）
- 导出前：
  - 计算 `totalWordCount`：遍历文本块累计字数（中文按字符计数）
  - 写入新增字段到 manifest
  - 保留封面裁剪与作者信息注入逻辑

## 预览页合并（RichReaderScreen 增强）
- 增加顶部/头部信息区：
  - 标题、作者、标签（Chip 列）、简介（description）
  - 统计信息卡：章节总数、总字数（万字显示）、创建时间（creationTime）
  - 作者卡片：头像（authorAvatarPath）、昵称（authorNickname）、签名（authorSignature）
- 目录/章节导航：
  - 若有 `volumes`，按分卷展示章节；否则按 `chapters` 平铺列表（保留现有章节选择）
- 正文/图片渲染保持原有逻辑
- 加入书架：统一调用保存服务（后续将抽象 `ShelfService`，现阶段直接复用当前保存逻辑）

## 文件名与路由
- 保留 Rich 的扩展名（.rich），在 ViewerScreen 中统一使用 `path.basename` 展示，并修正容错仅在空/替换符时回退。
- 从书架进入 Rich 阅读页使用 `pushReplacement`，返回一跳直达书架。

## 兼容与迁移
- 旧 Rich 容器：缺失字段按回退策略显示；无需重新加密即可预览。
- 新导出的 Rich 容器：写入新增字段，预览页完整展示 Novel 风格信息。

## 验证
- Windows/Android 上用包含中文与 emoji 的标题/简介进行导出，预览页正确展示；章节与字数统计正确；从书架进入返回直达书架。
- 无 `description/totalWordCount` 的旧文件预览不报错、显示回退文案与动态统计。

## 后续（可选）
- 若需要分卷录入与管理，增设 Volume 编辑 UI，并在渲染与统计时按 `volumes` 结构实现。
- 抽象 `ShelfService` 与 `FilePickerHelper`，统一保存与导出逻辑，减少重复。