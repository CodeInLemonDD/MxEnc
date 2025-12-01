import 'package:flutter/material.dart';
import '../models/chapter.dart';
import '../utils/storage_service.dart';
import 'dart:typed_data';
import '../utils/dynamic_watermark.dart';
import '../utils/auth_service.dart';

class NovelReaderScreen extends StatefulWidget {
  final Chapter chapter; // 章节信息
  final String content; // 章节内容
  final String novelTitle; // 小说标题
  final String author; // 作者
  final String? sourceFilePath;
  final Uint8List? coverBytes;

  const NovelReaderScreen({
    super.key,
    required this.chapter,
    required this.content,
    required this.novelTitle,
    required this.author,
    this.sourceFilePath,
    this.coverBytes,
  });

  @override
  State<NovelReaderScreen> createState() => _NovelReaderScreenState();
}

class _NovelReaderScreenState extends State<NovelReaderScreen> {
  // 阅读设置
  double _fontSize = 18.0;
  double _lineHeight = 1.6;
  Color _textColor = Colors.black87;
  Color _backgroundColor = Colors.white;
  bool _isNightMode = false;
  bool _showSettings = false;
  bool _showNavigation = false;
  double _progress = 0.0; // 阅读进度
  String? _deviceId;

  @override
  void initState() {
    super.initState();
    // 启用防截图功能
    _enableSecureMode();
    _loadDeviceId();
  }

  // 滚动控制器
  final ScrollController _scrollController = ScrollController();

  @override
  void dispose() {
    // 释放资源
    _scrollController.dispose();
    // 禁用防截图功能（如果需要）
    // _disableSecureMode();
    super.dispose();
  }

  // 启用防截图模式
  void _enableSecureMode() {
    // 在不同平台启用防截图功能
    // 实际应用中需要通过平台通道实现
  }

  Future<void> _loadDeviceId() async {
    try {
      final id = await AuthService().getDeviceId();
      if (mounted) setState(() { _deviceId = id; });
    } catch (_) {}
  }

  // 切换夜间模式
  void _toggleNightMode() {
    setState(() {
      _isNightMode = !_isNightMode;
      if (_isNightMode) {
        _backgroundColor = Colors.grey[900]!;
        _textColor = Colors.grey[300]!;
      } else {
        _backgroundColor = Colors.white;
        _textColor = Colors.black87;
      }
    });
  }

  // 调整字体大小
  void _changeFontSize(double delta) {
    setState(() {
      _fontSize = double.parse((_fontSize + delta).toStringAsFixed(1));
      // 限制字体大小范围
      if (_fontSize < 12.0) _fontSize = 12.0;
      if (_fontSize > 28.0) _fontSize = 28.0;
    });
  }

  // 调整行高
  void _changeLineHeight(double delta) {
    setState(() {
      _lineHeight = double.parse((_lineHeight + delta).toStringAsFixed(1));
      // 限制行高范围
      if (_lineHeight < 1.0) _lineHeight = 1.0;
      if (_lineHeight > 2.5) _lineHeight = 2.5;
    });
  }

  // 切换设置面板显示
  void _toggleSettings() {
    setState(() {
      _showSettings = !_showSettings;
    });
  }


  // 处理点击屏幕中间区域
  void _handleTapCenter() {
    setState(() {
      _showNavigation = !_showNavigation;
      _showSettings = false;
    });
  }

  // 处理点击屏幕左侧区域（上一页）
  void _handleTapLeft() {
    // 上一页逻辑
    _showToast('上一章');
  }

  // 处理点击屏幕右侧区域（下一页）
  void _handleTapRight() {
    // 下一页逻辑
    _showToast('下一章');
  }

  // 显示提示信息
  void _showToast(String message) {
    final scaffold = ScaffoldMessenger.of(context);
    scaffold.showSnackBar(
      SnackBar(content: Text(message), duration: const Duration(seconds: 1)),
    );
  }

  // 更新阅读进度
  void _updateProgress(double value) {
    setState(() {
      _progress = value;
    });
  }

  // 根据进度滚动到对应位置
  void _scrollToProgress(double progress) {
    if (_scrollController.hasClients) {
      final maxScroll = _scrollController.position.maxScrollExtent;
      final targetPosition = maxScroll * progress;
      _scrollController.animateTo(
        targetPosition,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(icon: const Icon(Icons.arrow_back), onPressed: () => Navigator.pop(context)),
        title: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(widget.novelTitle, style: const TextStyle(fontSize: 16)),
          Text(widget.author, style: const TextStyle(fontSize: 12)),
        ]),
        actions: [
          IconButton(
            icon: const Icon(Icons.bookmark_add),
            tooltip: '保存到书架',
            onPressed: _saveToBookshelf,
          ),
        ],
      ),
      backgroundColor: _backgroundColor,
      body: Stack(
        children: [
          _buildGestureDetector(),
          _buildReaderContent(),
          if (_showNavigation) _buildTopNavigation(),
          if (_showNavigation) _buildBottomNavigation(),
          if (_showSettings) _buildSettingsPanel(),
          if (_deviceId != null)
            DynamicWatermark(
              receiverId: (() {
                final v = _deviceId!;
                return v.length > 8 ? '${v.substring(0,4)}****${v.substring(v.length-4)}' : v;
              })(),
              opacity: 0.25,
            ),
          Positioned(
            left: 12,
            bottom: 12,
            child: Opacity(
              opacity: 0.25,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: _isNightMode ? Colors.black54 : Colors.white70,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  'MxEnc',
                  style: TextStyle(
                    fontSize: 12,
                    color: _isNightMode ? Colors.white70 : Colors.black54,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _saveToBookshelf() async {
    try {
      final id = StorageService.newId();
      String coverPath = 'assets/placeholder.png';
      if (widget.coverBytes != null && widget.coverBytes!.isNotEmpty) {
        coverPath = await StorageService.storeCoverBytes(id, widget.coverBytes!);
      }
      final item = {
        'id': id,
        'title': widget.novelTitle,
        'author': widget.author,
        'coverPath': coverPath,
        'filePath': widget.sourceFilePath ?? '',
        'isNovel': true,
        'importTime': DateTime.now().toIso8601String(),
        'creationTime': null,
      };
      await StorageService.saveShelfItem(item);
      if (mounted) {
        final scaffold = ScaffoldMessenger.of(context);
        scaffold.showSnackBar(const SnackBar(content: Text('已保存到书架')));
      }
    } catch (e) {
      if (mounted) {
        final scaffold = ScaffoldMessenger.of(context);
        scaffold.showSnackBar(SnackBar(content: Text('保存失败: $e')));
      }
    }
  }

  // 构建手势检测区域
  Widget _buildGestureDetector() {
    return GestureDetector(
      onTapUp: (details) {
        final width = MediaQuery.of(context).size.width;
        if (details.globalPosition.dx < width / 3) {
          _handleTapLeft();
        } else if (details.globalPosition.dx > width * 2 / 3) {
          _handleTapRight();
        } else {
          _handleTapCenter();
        }
      },
      child: Container(
        color: Colors.transparent,
        width: double.infinity,
        height: double.infinity,
      ),
    );
  }

  // 构建阅读内容
  Widget _buildReaderContent() {
    return NotificationListener<ScrollEndNotification>(
      onNotification: (notification) {
        // 更新阅读进度
        final scrollPosition = notification.metrics.pixels;
        final maxScroll = notification.metrics.maxScrollExtent;
        if (maxScroll > 0) {
          _updateProgress(scrollPosition / maxScroll);
        }
        return true;
      },
      child: SingleChildScrollView(
        controller: _scrollController,
        padding: const EdgeInsets.fromLTRB(20, 80, 20, 80),
        physics: const AlwaysScrollableScrollPhysics(),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 章节标题
            Center(
              child: Text(
                widget.chapter.title,
                style: TextStyle(
                  fontSize: _fontSize + 4,
                  fontWeight: FontWeight.bold,
                  color: _textColor,
                ),
                textAlign: TextAlign.center,
              ),
            ),
            const SizedBox(height: 24), // 替代margin属性
            // 章节内容
            SelectableText.rich(
              TextSpan(
                text: widget.content,
                style: TextStyle(
                  fontSize: _fontSize,
                  color: _textColor,
                  height: _lineHeight,
                ),
              ),
              enableInteractiveSelection: false, // 使用正确的属性名禁用文本选择
              textAlign: TextAlign.justify,
            ),
            const SizedBox(height: 40), // 底部留白
          ],
        ),
      ),
    );
  }

  // 构建顶部导航栏
  Widget _buildTopNavigation() {
    return Container(
      height: 80,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
              colors: _isNightMode
                  ? [Colors.black87, Colors.black.withValues(alpha: 0.0)]
                  : [Colors.white, Colors.transparent],
        ),
      ),
      padding: const EdgeInsets.fromLTRB(16, 40, 16, 0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          IconButton(
            icon: Icon(Icons.arrow_back, color: _textColor),
            onPressed: () => Navigator.pop(context),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Text(
                widget.novelTitle,
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: _textColor,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              Text(
                widget.author,
                style: TextStyle(
                  fontSize: 12,
                  color: _textColor.withValues(alpha: 0.8),
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
          IconButton(
            icon: Icon(Icons.more_vert, color: _textColor),
            onPressed: () {
              // 更多操作
              _showToast('更多操作');
            },
          ),
        ],
      ),
    );
  }

  // 构建底部导航栏
  Widget _buildBottomNavigation() {
    return Positioned(
      bottom: 0,
      left: 0,
      right: 0,
      height: 80,
      child: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.bottomCenter,
            end: Alignment.topCenter,
            colors: _isNightMode
                ? [Colors.black87, Colors.black.withValues(alpha: 0.0)]
                : [Colors.white, Colors.transparent],
          ),
        ),
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 20),
        child: Column(
          children: [
            // 进度条
            Slider(
              value: _progress,
              onChanged: (value) {
                _updateProgress(value);
                // 滚动到对应的位置
                _scrollToProgress(value);
              },
              activeColor: _isNightMode ? Colors.grey[500] : Colors.blue,
              inactiveColor: _isNightMode ? Colors.grey[700] : Colors.grey[300],
            ),
            // 按钮组
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                IconButton(
                  icon: Icon(Icons.book_outlined, color: _textColor),
                  onPressed: () {
                    // 目录
                    _showToast('打开目录');
                  },
                ),
                IconButton(
                  icon: Icon(Icons.format_size, color: _textColor),
                  onPressed: _toggleSettings,
                ),
                IconButton(
                  icon: Icon(Icons.brightness_6, color: _textColor),
                  onPressed: _toggleNightMode,
                ),
                IconButton(
                  icon: Icon(Icons.favorite_border, color: _textColor),
                  onPressed: () {
                    // 收藏
                    _showToast('收藏成功');
                  },
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  // 构建设置面板
  Widget _buildSettingsPanel() {
    return Positioned(
      bottom: 80,
      left: 0,
      right: 0,
      child: Container(
        color: _isNightMode ? Colors.grey[800] : Colors.white,
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 字体大小设置
            const Text(
              '字体大小',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            Row(
              children: [
                IconButton(
                  icon: const Icon(Icons.text_decrease),
                  onPressed: () => _changeFontSize(-1),
                ),
                Expanded(
                  child: Slider(
                    value: _fontSize,
                    min: 12.0,
                    max: 28.0,
                    onChanged: (value) {
                      setState(() {
                        _fontSize = double.parse(value.toStringAsFixed(1));
                      });
                    },
                    activeColor: _isNightMode ? Colors.grey[500] : Colors.blue,
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.text_increase),
                  onPressed: () => _changeFontSize(1),
                ),
              ],
            ),
            const SizedBox(height: 8),
            // 行高设置
            const Text(
              '行间距',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            Row(
              children: [
                IconButton(
                  icon: const Icon(Icons.vertical_align_center),
                  onPressed: () => _changeLineHeight(-0.1),
                ),
                Expanded(
                  child: Slider(
                    value: _lineHeight,
                    min: 1.0,
                    max: 2.5,
                    onChanged: (value) {
                      setState(() {
                        _lineHeight = double.parse(value.toStringAsFixed(1));
                      });
                    },
                    activeColor: _isNightMode ? Colors.grey[500] : Colors.blue,
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.vertical_distribute),
                  onPressed: () => _changeLineHeight(0.1),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// 动态水印绘制器
class DynamicWatermarkPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    // 绘制动态水印
    // 实际应用中应该包含用户设备ID或其他唯一标识
    final textSpan = const TextSpan(
      text: 'MxEnc 受保护内容',
      style: TextStyle(color: Color.fromRGBO(0, 0, 0, 0.1), fontSize: 14),
    );
    final textPainter = TextPainter(
      text: textSpan,
      textDirection: TextDirection.ltr,
    );
    textPainter.layout();

    // 绘制多个水印，覆盖整个屏幕
    final stepX = 200.0;
    final stepY = 150.0;
    for (double x = -stepX / 2; x < size.width; x += stepX) {
      for (double y = -stepY / 2; y < size.height; y += stepY) {
        canvas.save();
        canvas.translate(x, y);
        canvas.rotate(-0.2); // 旋转水印
        textPainter.paint(canvas, Offset.zero);
        canvas.restore();
      }
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) {
    return true; // 为了简单起见，每次都重绘
  }
}
