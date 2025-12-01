## 编译目标
- Android：优先生成可安装的 release APK；如签名或环境不满足则生成 debug APK 以保证可安装体验。
- Windows：生成可运行的桌面构建（可选）。

## 预检与清理
- 运行依赖检查与清理缓存：
  - `flutter clean`
  - `flutter pub cache clean`
  - `flutter pub get`
- 如果出现 Android 插件路径冲突（D/C 根路径），执行上述清理后重试；必要时在 `android/gradle.properties` 添加 `org.gradle.configuration-cache=false`。

## Android 编译
- Release 构建：`flutter build apk --release`
- 如签名缺失导致无法安装，则：
  - 生成临时 keystore 并签名：`zipalign` + `apksigner`（不改项目配置，只对产物签名）
  - 或回退到 debug 构建：`flutter build apk --debug`
- 安装（已连接设备）：
  - Release：`adb install -r build/app/outputs/flutter-apk/app-release.apk`
  - Debug：`adb install -r build/app/outputs/flutter-apk/app-debug.apk`

## Windows（可选）
- 构建：`flutter build windows`
- 运行验证：`flutter run -d windows`

## 输出与交付
- 提供生成的 APK 路径与大小，并在设备上完成安装验证；如有构建错误，按照日志继续修复直至生成可安装的 APK。