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

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _maybeLaunchOobe();
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

  @override
  void dispose() {
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
