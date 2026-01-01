根据您的需求，我制定了以下实施计划，涵盖修复导出、优化 UI 和实现排序功能。

## 1. 核心功能修复：mxzip 导出 (StorageService)
我们将增强 `exportSeriesToZip` 方法的健壮性，确保数据完整性和跨平台兼容性。
- **完善打包逻辑**：
  - 增加对自定义封面的支持（不仅仅是 `cover.jpg`，还会检查 `metadata.coverPath`）。
  - 确保生成的 `series.json` 中路径格式标准化（使用 `/` 分隔符），提高跨平台兼容性。
  - 优化 `key.enc` 生成逻辑，确保在未设置密码时正确清理敏感数据。
- **增强交互**：
  - 在导出过程中提供更详细的错误捕获和用户提示。

## 2. 界面重构：分卷预览页 (SeriesDetailScreen)
我们将使用更现代的 Material 3 风格重构页面，提升视觉体验。
- **布局升级**：
  - 使用 `CustomScrollView` 和 `SliverAppBar` 实现可折叠的大标题和封面展示效果。
  - 顶部区域将清晰展示系列标题、作者、总卷数和总大小。
- **列表优化**：
  - 列表项设计升级为卡片式或更精致的 `ListTile`，显示文件大小、格式图标（漫画/小说）。
  - 增加解密状态指示（已解锁/锁定）。

## 3. 新功能：分卷排序
实现直观的拖拽排序功能，确保存储顺序与显示顺序一致。
- **后端支持 (StorageService)**：
  - 添加 `updateSeriesVolumes` 方法，允许直接更新系列的 `volumes` 列表顺序并写入 `series.json`。
- **前端交互 (SeriesDetailScreen)**：
  - 引入 `ReorderableListView`（或在 `Sliver` 中使用 `ReorderableSliverList`）实现拖拽排序。
  - 添加“排序模式”开关或直接支持长按拖拽。
  - 排序完成后自动触发保存，确保下次打开或导出时顺序保持一致。

## 实施步骤
1.  **后端更新**：修改 `lib/utils/storage_service.dart`，添加排序更新方法，优化导出逻辑。
2.  **前端重构**：修改 `lib/screens/series_detail_screen.dart`，重写 `build` 方法以支持 Sliver 布局和拖拽排序。
3.  **验证**：
    - 测试导出功能生成的 zip 包结构是否正确。
    - 测试拖拽排序后，重启应用或导出 zip，顺序是否保持。
    - 检查 UI 在不同屏幕尺寸下的表现。