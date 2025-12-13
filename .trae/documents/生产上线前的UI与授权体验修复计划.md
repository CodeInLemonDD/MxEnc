## 删除调试入口
- 移除“我的”页 AppBar 的 OOBE 调试按钮：mxenc/lib/screens/my_profile_screen.dart:218-231
- 删除 Debug 授权开关块（kDebugMode）：mxenc/lib/screens/my_profile_screen.dart:484-487 及 _buildDebugAuthItem 调用

## 授权页粘贴不可用
- 为卡密输入框添加显式“粘贴”按钮（后缀图标，读取剪贴板并写入 controller）：mxenc/lib/screens/permission_screen.dart:218-231 的 TextField 增加 `suffixIcon: IconButton(... Clipboard.getData ...)`
- 保留系统默认粘贴体验，显式按钮保证在 Android/iOS/Windows 均可用

## 授权后“我的”状态不刷新
- 在授权成功时返回路由结果：将 `Navigator.pop(context)` 改为 `Navigator.pop(context, true)`（mxenc/lib/screens/permission_screen.dart:88-91）
- “我的”页“卡密激活”入口改为等待路由结果并回调刷新：`final r = await Navigator.pushNamed(...); if (r == true) _loadUserInfo();`（mxenc/lib/screens/my_profile_screen.dart:404-409）

## “我的”页显示用户头像与昵称并调整文案
- 在状态中新增并加载用户资料：从 `UserService.getNickname()/getAvatarPath()` 读取，写入 `_nickname/_avatarPath`（mxenc/lib/screens/my_profile_screen.dart:41-58 增加读取）
- 头像展示：若 `_avatarPath` 是 assets 用 `Image.asset`，否则用 `Image.file`；缺省回退到 `assets/default_avatar.jpg`
- 文案调整：
  - 标题显示用户名 `_nickname`，无值时显示“未设置用户名”
  - 用户状态“已授权用户/未授权用户”以较小字号显示在用户名下方
  - 删除“拥有全部功能权限/需要作者授权”的第二行说明
- 相关 UI 位置：mxenc/lib/screens/my_profile_screen.dart:268-320（头像与标题区）与 297-302（次级说明删除）

## 验证用例
- 粘贴测试：在授权页长按与点击“粘贴”均生效，整段 Base64URL 卡密能一次性填入
- 授权状态刷新：从“我的”进入授权页，成功后返回立即显示“已授权用户”；从其它入口授权后，回到“我的”也能刷新（路由结果回调）
- 头像与昵称：在“编辑资料”上传头像、设置昵称；返回“我的”显示自定义头像与昵称，状态文案缩小并位于昵称下方
- 调试入口：AppBar 不再显示调试按钮；Debug 授权开关已移除

## 影响范围与风险
- 仅改动“我的”与“授权”两页的 UI/交互，逻辑简单、回退风险低
- 不涉及加密/解密算法与数据持久化；剪贴板读取不引入权限问题

请确认上述方案，确认后我将执行修改、构建并自测上述用例。