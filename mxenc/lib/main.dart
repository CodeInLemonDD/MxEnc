import 'package:flutter/material.dart';
import 'dart:io';
import 'screens/comic_editor_screen.dart';
import 'screens/rich_editor_screen.dart';
import 'rust_bridge.dart';
import 'package:provider/provider.dart';
import 'utils/theme_provider.dart';
import 'screens/encrypt_screen.dart';
import 'screens/viewer_screen.dart';
import 'screens/permission_screen.dart';
import 'screens/bookshelf_screen.dart';
import 'screens/my_profile_screen.dart';
import 'screens/encrypt_entry_screen.dart';
import 'screens/encrypt_image_screen.dart';
import 'screens/novel_upload_screen.dart';
import 'utils/auth_service.dart';
import 'screens/oobe_screen.dart';
import 'utils/user_service.dart';

import 'package:receive_sharing_intent/receive_sharing_intent.dart';
import 'dart:async';
import 'package:flutter/services.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // 初始化Rust桥接
  final rustBridge = await RustBridge.init();

  runApp(
    ChangeNotifierProvider(
      create: (_) => ThemeProvider()..load(),
      child: MyApp(rustBridge: rustBridge),
    ),
  );
}

class MyApp extends StatelessWidget {
  final RustBridge rustBridge;

  const MyApp({super.key, required this.rustBridge});

  @override
  Widget build(BuildContext context) {
    final themeProvider = Provider.of<ThemeProvider>(context);
    List<String> fallback;
    if (Platform.isWindows) {
      fallback = ['Segoe UI', 'Microsoft YaHei', 'Noto Sans'];
    } else if (Platform.isAndroid) {
      fallback = ['Roboto', 'Noto Sans'];
    } else if (Platform.isIOS || Platform.isMacOS) {
      fallback = ['SF Pro', 'Noto Sans'];
    } else {
      fallback = ['Noto Sans'];
    }
    return MaterialApp(
      title: '猫鸮加密',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: themeProvider.seedColor ?? Colors.deepPurple,
        ),
        useMaterial3: true,
        progressIndicatorTheme: ProgressIndicatorThemeData(
          color: Colors.deepPurple,
          linearTrackColor: Colors.deepPurple.withValues(alpha: 0.15),
          circularTrackColor: Colors.deepPurple.withValues(alpha: 0.12),
        ),
        textTheme: TextTheme(
          headlineLarge: TextStyle(
            fontSize: 28,
            fontWeight: FontWeight.w700,
            fontFamilyFallback: fallback,
          ),
          headlineMedium: TextStyle(
            fontSize: 24,
            fontWeight: FontWeight.w700,
            fontFamilyFallback: fallback,
          ),
          titleLarge: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.w600,
            fontFamilyFallback: fallback,
          ),
          titleMedium: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w600,
            fontFamilyFallback: fallback,
          ),
          bodyLarge: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w500,
            fontFamilyFallback: fallback,
          ),
          bodyMedium: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w500,
            fontFamilyFallback: fallback,
          ),
          bodySmall: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w400,
            fontFamilyFallback: fallback,
          ),
        ),
      ),
      darkTheme: ThemeData.dark(useMaterial3: true),
      themeMode: themeProvider.mode,
      home: MainPage(rustBridge: rustBridge),
      routes: {
        '/encrypt': (context) => EncryptScreen(rustBridge: rustBridge),
        '/encrypt_entry': (context) =>
            EncryptEntryScreen(rustBridge: rustBridge),
        '/encrypt_image': (context) =>
            EncryptImageScreen(rustBridge: rustBridge),
        '/novel_upload': (context) => NovelUploadScreen(rustBridge: rustBridge),
        '/decrypt': (context) => ViewerScreen(rustBridge: rustBridge),
        '/permission': (context) => const PermissionScreen(),
        '/library': (context) => BookshelfScreen(rustBridge: rustBridge),
        '/profile': (context) => const MyProfileScreen(),
        '/comic_editor': (context) => const ComicEditorScreen(),
        '/rich_editor': (context) => const RichEditorScreen(),
      },
    );
  }
}

class MainPage extends StatefulWidget {
  final RustBridge rustBridge;

  const MainPage({super.key, required this.rustBridge});

  @override
  State<MainPage> createState() => _MainPageState();
}

class _MainPageState extends State<MainPage> {
  int _selectedIndex = 0;
  final AuthService _authService = AuthService();
  final UserService _userService = UserService();

  // 页面控制器
  final PageController _pageController = PageController(initialPage: 0);
  StreamSubscription? _intentSub;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _maybeLaunchOobe();
      _initIntentListener();
    });
  }

  void _initIntentListener() {
    // 监听应用运行时接收到的分享意图
    _intentSub = ReceiveSharingIntent.instance.getMediaStream().listen((List<SharedMediaFile> value) {
      if (value.isNotEmpty) {
        _handleSharedFile(value.first.path);
      }
    }, onError: (err) {
      debugPrint("getIntentDataStream error: $err");
    });

    // 检查应用启动时的分享意图
    ReceiveSharingIntent.instance.getInitialMedia().then((List<SharedMediaFile> value) {
      if (value.isNotEmpty) {
        _handleSharedFile(value.first.path);
      }
    });
  }

  Future<void> _maybeLaunchOobe() async {
    try {
      final done = await _userService.isOobeDone();
      final complete = await _userService.isProfileComplete();
      if (!done || !complete) {
        if (!mounted) return;
        await Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const OobeScreen()),
        );
      }
    } catch (_) {}
  }

  void _handleSharedFile(String path) async {
    if (!mounted) return;
    String decodedPath = path;
    bool isContentUri = path.startsWith('content://');
    bool isFileUri = path.startsWith('file://');

    // 处理路径解码
    if (isFileUri) {
      try {
        decodedPath = Uri.parse(path).toFilePath();
      } catch (_) {
        // Fallback for malformed file URIs
        String p = path.substring(7);
        decodedPath = Uri.decodeFull(p);
      }
    } else if (!isContentUri) {
      // 原始路径，不做 decodeFull，除非它看起来像是有 URL 编码
      // 很多时候插件返回的是绝对路径 /storage/...
      // 如果路径包含 %，尝试解码，但要小心误伤
      // 安全策略：如果解码后文件存在，则使用解码后的，否则使用原始的
      try {
        if (path.contains('%')) {
          String tryDecoded = Uri.decodeFull(path);
          if (File(tryDecoded).existsSync()) {
            decodedPath = tryDecoded;
          }
        }
      } catch (_) {}
    }

    // 如果是 content:// URI，或者文件不存在（可能是未处理的 content uri），尝试复制到临时文件
    if (isContentUri ||
        decodedPath.startsWith('content://') ||
        (!File(decodedPath).existsSync() && path.contains('content://'))) {
      try {
        // 使用 MethodChannel 调用原生代码复制文件
        final channel = MethodChannel('com.maoxiao.mxenc/file_utils');
        final String? tempPath =
            await channel.invokeMethod('copyContentUri', {'uri': path});
        if (tempPath != null) {
          decodedPath = tempPath;
        }
      } catch (e) {
        debugPrint('Failed to copy content uri: $e');
        // 继续尝试使用原始路径，虽然可能会失败
      }
    }

    if (!mounted) return;

    // 获取原始文件名用于显示
    String? displayName;
    try {
      if (path.startsWith('content://')) {
        // 尝试从URI中提取文件名
        final uri = Uri.parse(path);
        final lastSegment = uri.pathSegments.lastOrNull;
        if (lastSegment != null && lastSegment.isNotEmpty) {
          displayName = Uri.decodeFull(lastSegment);
        }
      } else {
        displayName = path.split('/').last;
        if (displayName.contains('%')) {
          displayName = Uri.decodeFull(displayName);
        }
      }
    } catch (_) {}

    // 导航到解密页面并传入文件
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => ViewerScreen(
          rustBridge: widget.rustBridge,
          initialFile: File(decodedPath),
          importedName: displayName,
        ),
      ),
    );
  }

  @override
  void dispose() {
    _intentSub?.cancel();
    _pageController.dispose();
    super.dispose();
  }

  void _onItemTapped(int index) {
    setState(() {
      _selectedIndex = index;
      _pageController.jumpToPage(index);
    });
  }

  void _handleEncryptPress() async {
    bool hasPermission = await _authService.isPremiumUser();
    if (!mounted) return;
    if (hasPermission) {
      Navigator.pushNamed(context, '/encrypt_entry');
    } else {
      Navigator.pushNamed(context, '/permission');
    }
  }

  void _handleDecryptPress() {
    // 进入解密页面
    Navigator.pushNamed(context, '/decrypt');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: PageView(
        controller: _pageController,
        onPageChanged: (index) {
          setState(() {
            _selectedIndex = index;
          });
        },
        physics: const PageScrollPhysics(),
        children: [
          // 首页
          _buildHomePage(),

          // 书架页面
          BookshelfScreen(rustBridge: widget.rustBridge),

          // 我的页面
          MyProfileScreen(),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _selectedIndex,
        onDestinationSelected: _onItemTapped,
        destinations: const [
          NavigationDestination(icon: Icon(Icons.home), label: '首页'),
          NavigationDestination(icon: Icon(Icons.library_books), label: '书架'),
          NavigationDestination(icon: Icon(Icons.person), label: '我的'),
        ],
      ),
    );
  }

  Widget _buildHomePage() {
    final theme = Theme.of(context);
    // 首启渐显控制：只在第一次启动显示动画
    // 简化：通过内存标记，后续会在Settings中持久化

    return Center(
      child: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const SizedBox(height: 32),
              // Logo - 使用图片，如果没有则显示占位符
              TweenAnimationBuilder<double>(
                tween: Tween(begin: 0, end: 1),
                duration: const Duration(milliseconds: 600),
                curve: Curves.easeOut,
                builder: (context, v, child) {
                  return Opacity(
                    opacity: v,
                    child: Transform.scale(
                      scale: 0.95 + 0.05 * v,
                      child: Container(
                        width: 120,
                        height: 120,
                        decoration: BoxDecoration(
                          color: theme.colorScheme.primaryContainer,
                          borderRadius: BorderRadius.circular(28),
                        ),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(28),
                          child: Image.asset(
                            'assets/logo.jpg',
                            width: 120,
                            height: 120,
                            fit: BoxFit.cover,
                            errorBuilder: (context, error, stackTrace) {
                              return Center(
                                child: Text(
                                  '猫鸮',
                                  style: TextStyle(
                                    fontSize: 40,
                                    fontWeight: FontWeight.bold,
                                    color: theme.colorScheme.onPrimaryContainer,
                                  ),
                                ),
                              );
                            },
                          ),
                        ),
                      ),
                    ),
                  );
                },
              ),
              const SizedBox(height: 32),
              TweenAnimationBuilder<double>(
                tween: Tween(begin: 0, end: 1),
                duration: const Duration(milliseconds: 700),
                builder: (context, v, child) {
                  return Opacity(
                    opacity: v,
                    child: Text(
                      '猫鸮加密',
                      style: theme.textTheme.headlineMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                        color: theme.colorScheme.onSurface,
                      ),
                    ),
                  );
                },
              ),
              const SizedBox(height: 8),
              Text(
                '安全、便捷的文件加密工具',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
                ),
              ),
              const SizedBox(height: 48),

              // 加密按钮
              TweenAnimationBuilder<double>(
                tween: Tween(begin: 0, end: 1),
                duration: const Duration(milliseconds: 800),
                builder: (context, v, child) {
                  return Opacity(
                    opacity: v,
                    child: SizedBox(
                      width: double.infinity,
                      child: FilledButton.icon(
                        onPressed: _handleEncryptPress,
                        icon: const Icon(Icons.lock),
                        label: const Text('我要加密'),
                        style: FilledButton.styleFrom(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 24,
                            vertical: 16,
                          ),
                        ),
                      ),
                    ),
                  );
                },
              ),
              const SizedBox(height: 16),

              // 解密按钮
              TweenAnimationBuilder<double>(
                tween: Tween(begin: 0, end: 1),
                duration: const Duration(milliseconds: 900),
                builder: (context, v, child) {
                  return Opacity(
                    opacity: v,
                    child: SizedBox(
                      width: double.infinity,
                      child: OutlinedButton.icon(
                        onPressed: _handleDecryptPress,
                        icon: const Icon(Icons.lock_open),
                        label: const Text('我要解密'),
                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 24,
                            vertical: 16,
                          ),
                        ),
                      ),
                    ),
                  );
                },
              ),
              const SizedBox(height: 32),
            ],
          ),
        ),
      ),
    );
  }
}
