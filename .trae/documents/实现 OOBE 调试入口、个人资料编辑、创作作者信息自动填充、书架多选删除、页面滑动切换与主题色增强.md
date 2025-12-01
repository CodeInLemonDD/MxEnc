## OOBE 调试与个人资料编辑
- 在“我的”页添加两项：
  - 调试启动 OOBE 按钮（调用 UserService.setOobeDone(false) 并导航到 OobeScreen）
  - 点击个人信息卡片跳转到新个人信息编辑页面（头像、昵称、个签），保存后回写 UserService 并返回。
- 文件与位置：
  - my_profile_screen.dart：添加按钮与卡片 onTap 导航；新增 EditProfileScreen。
  - user_service.dart：复用持久化接口。

## 创作页作者信息自动填充与标签
- 在小说创作页的作品信息处，移除作者昵称与个签的手填项；从 UserService 读取并在导出 JSON 中填写。
- 标签功能现已存在（逗号分隔输入），保留并在导出 JSON 的 tags 字段写入；详情页读取展示（已接好）。
- 文件：novel_upload_screen.dart（读取作者资料填入 JSON）；models/novel.dart（字段已支持）。

## 书架多选删除
- 右上角溢出按钮（“⋮”）切换多选模式 → 图标变为“❌”取消多选。
- 多选模式下：每个项目左上角出现复选框；右下角出现悬浮“删除”按钮；点击删除批量调用 StorageService.removeShelfItem。
- 文件：bookshelf_screen.dart（状态 _multiSelect、_selectedIds；UI 复选框与 FAB；溢出菜单按钮）。

## 页面滑动切换与启动动画
- 启动动画：仅在启动时播放首页渐显动效；通过 SharedPreferences 标记首次显示；后续不再重复。
- 页面切换动画：
  - 允许 PageView 手势滑动（移除 NeverScrollableScrollPhysics）
  - 使用 PageController 与 PageView 自带滑动切换，不强加额外过渡；底部导航保持同步。
- 文件：main.dart（首页动画首启标记；PageView physics 改为默认；onPageChanged 保持）。

## 主题色增强
- 扩充并更换更饱和的预设颜色映射（如 deepPurple、indigo、blue, cyan, teal, green, amber, orange, deepOrange, red, pink, magenta）。
- 修复“部分颜色无效”问题：
  - 检查字符串到颜色映射；当未匹配时默认值。
  - 统一使用 ThemeProvider.setSeedColor，确保 ColorScheme.fromSeed 生效。
- 文件：theme_provider.dart（已支持 seedColor）；my_profile_screen.dart（预设颜色列表与应用逻辑）。

## 验证
- Windows/Android：
  - “我的”页按钮可触发 OOBE；个人信息卡片进入编辑界面并保存。
  - 创作页导出 JSON 自动包含作者昵称与个签；标签在详情页展示。
  - 书架溢出菜单进入多选模式并可批量删除；取消多选恢复正常。
  - 启动时首页播放动画，后续不重复；页面间可滑动切换；底部导航与页面状态同步。
  - 主题色切换到新的预设后明显可见变化，所有预设生效。