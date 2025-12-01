import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'dart:io';
import 'package:mxenc/screens/bookshelf_screen.dart';
import 'dart:typed_data';
import '../utils/storage_service.dart';
import '../utils/dynamic_watermark.dart';

class ImagePreviewScreen extends StatefulWidget {
  final BookshelfItem item;
  final Uint8List? imageData; // 实际应用中应该传入解密后的图片数据

  const ImagePreviewScreen({super.key, required this.item, this.imageData});

  @override
  State<ImagePreviewScreen> createState() => _ImagePreviewScreenState();
}

class _ImagePreviewScreenState extends State<ImagePreviewScreen> {
  // 图片缩放和位置控制
  final TransformationController _controller = TransformationController();
  Offset _initialFocalPoint = Offset.zero;
  Offset _previousOffset = Offset.zero;
  double _scale = 1.0;
  double _previousScale = 1.0;
  bool _isLoading = false;
  bool _hasError = false;
  String _errorMessage = '';
  bool _isInShelf = false;

  @override
  void initState() {
    super.initState();
    // 启用防截图功能
    _enableSecureMode();
    // 加载图片数据
    _loadImageData();
    _checkInShelf();
  }

  Future<void> _checkInShelf() async {
    try {
      final items = await StorageService.loadShelf();
      _isInShelf = items.any(
        (e) =>
            e['filePath'] == widget.item.filePath &&
            (e['isNovel'] == false || e['isNovel'] == null),
      );
      if (mounted) setState(() {});
    } catch (_) {}
  }

  @override
  void dispose() {
    // 释放资源
    _controller.dispose();
    // 禁用防截图功能（如果需要）
    // _disableSecureMode();
    super.dispose();
  }

  // 启用防截图模式
  void _enableSecureMode() {
    // 在不同平台启用防截图功能
    // 实际应用中需要通过平台通道实现
    // 例如在Android上设置FLAG_SECURE
  }

  // 加载图片数据
  void _loadImageData() {
    setState(() {
      _isLoading = true;
      _hasError = false;
    });

    Future(() async {
      try {
        if (widget.imageData != null) {
          setState(() {
            _isLoading = false;
          });
          return;
        }
        // 对书架中的图片类型，直接使用封面副本进行预览，不读取加密文件本体
        if (!widget.item.isNovel) {
          if (mounted) {
            setState(() {
              _isLoading = false;
              _hasError = false;
            });
          }
          return;
        }
        // 小说类型不在此页面处理
        if (mounted) {
          setState(() {
            _isLoading = false;
            _hasError = true;
            _errorMessage = '图片数据加载失败';
          });
        }
      } catch (e) {
        if (mounted) {
          setState(() {
            _isLoading = false;
            _hasError = true;
            _errorMessage = '图片数据加载失败';
          });
        }
      }
    });
  }

  // 重置缩放和位置
  void _resetZoom() {
    setState(() {
      _controller.value = Matrix4.identity();
      _scale = 1.0;
      _previousScale = 1.0;
      _previousOffset = Offset.zero;
    });
  }

  // 处理双击缩放
  void _handleDoubleTap() {
    double next;
    if (_scale < 1.5) {
      next = 2.0;
    } else if (_scale < 3.0) {
      next = 4.0;
    } else {
      next = 1.0;
    }
    setState(() {
      _scale = next;
      _previousScale = next;
      _controller.value = Matrix4.identity()..scale(_scale);
    });
  }

  // 处理保存到书架
  Future<void> _handleSaveToBookshelf() async {
    try {
      final id = StorageService.newId();
      final item = {
        'id': id,
        'title': widget.item.title,
        'author': widget.item.author,
        'coverPath': widget.item.coverPath,
        'filePath': widget.item.filePath,
        'isNovel': false,
        'importTime': DateTime.now().toIso8601String(),
        'creationTime': null,
      };
      await StorageService.saveShelfItem(item);
      if (mounted) {
        setState(() {
          _isInShelf = true;
        });
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('已保存到书架')));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('保存失败: $e')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.item.title),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _resetZoom,
            tooltip: '重置缩放',
          ),
          if (!_isInShelf)
            IconButton(
              icon: const Icon(Icons.bookmark_add),
              onPressed: _handleSaveToBookshelf,
              tooltip: '保存到书架',
            ),
        ],
        elevation: 0,
      ),
      body: _isLoading
          ? _buildLoadingState()
          : _hasError
          ? _buildErrorState()
          : _buildImageDisplay(),
      // 添加动态水印
      floatingActionButton: _buildWatermarkInfo(),
    );
  }

  // 构建加载状态
  Widget _buildLoadingState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: const [
          CircularProgressIndicator(),
          SizedBox(height: 16),
          Text('图片加载中...'),
        ],
      ),
    );
  }

  // 构建错误状态
  Widget _buildErrorState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.error_outline, size: 64, color: Colors.red),
          const SizedBox(height: 16),
          Text(_errorMessage),
          const SizedBox(height: 16),
          ElevatedButton(onPressed: _loadImageData, child: const Text('重试')),
        ],
      ),
    );
  }

  // 构建图片显示
  Widget _buildImageDisplay() {
    return Stack(
      children: [
        // 图片显示区域
        InteractiveViewer.builder(
          transformationController: _controller,
          onInteractionStart: (details) {
            _initialFocalPoint = details.focalPoint;
            // 修复Vector3到Offset的转换
            final translation = _controller.value.getTranslation();
            _previousOffset = Offset(translation.x, translation.y);
          },
          onInteractionUpdate: (details) {
            // 更新缩放
            _scale = _previousScale * details.scale;
            // 更新位置
            final offset =
                _previousOffset + details.focalPoint - _initialFocalPoint;
            _controller.value = Matrix4.identity()
              ..translate(offset.dx, offset.dy)
              ..scale(_scale);
          },
          onInteractionEnd: (_) {
            _previousScale = _scale;
            final translation = _controller.value.getTranslation();
            _previousOffset = Offset(translation.x, translation.y);
            // 限制最大缩放
            if (_scale > 5.0) {
              setState(() {
                _scale = 5.0;
                _previousScale = 5.0;
                _controller.value = Matrix4.identity()
                  ..translate(_previousOffset.dx, _previousOffset.dy)
                  ..scale(_scale);
              });
            }
          },
          builder: (context, controller) {
            return GestureDetector(
              onDoubleTap: _handleDoubleTap,
              child: Stack(
                children: [
                  Container(
                    color: Colors.black,
                    alignment: Alignment.center,
                    child: (() {
                      if (widget.imageData != null) {
                        return Image.memory(
                          widget.imageData!,
                          fit: BoxFit.contain,
                          filterQuality: FilterQuality.high,
                          excludeFromSemantics: true,
                        );
                      }
                      final cover = widget.item.coverPath;
                      if (cover.startsWith('assets/')) {
                        return Image.asset(cover, fit: BoxFit.contain);
                      }
                      try {
                        final f = File(cover);
                        if (f.existsSync()) {
                          return Image.file(
                            f,
                            fit: BoxFit.contain,
                            filterQuality: FilterQuality.high,
                          );
                        }
                      } catch (_) {}
                      return const SizedBox();
                    })(),
                  ),
                  Positioned.fill(
                    child: Builder(
                      builder: (context) {
                        final dev = (widget.item.authorDeviceId ?? '')
                            .toString();
                        final masked = dev.isNotEmpty && dev.length > 8
                            ? '${dev.substring(0, 4)}****${dev.substring(dev.length - 4)}'
                            : (dev.isEmpty ? 'MxEnc 受保护内容' : dev);
                        return DynamicWatermark(
                          receiverId: masked,
                          opacity: 0.2,
                        );
                      },
                    ),
                  ),
                ],
              ),
            );
          },
        ),
        // 图片信息
        Positioned(
          top: 16,
          left: 16,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.6),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Text(
              '${widget.item.title} - ${widget.item.author}',
              style: const TextStyle(color: Colors.white, fontSize: 12),
            ),
          ),
        ),
      ],
    );
  }

  // 构建水印信息提示
  Widget _buildWatermarkInfo() {
    return Positioned(
      bottom: 16,
      right: 16,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: Colors.black.withOpacity(0.6),
          borderRadius: BorderRadius.circular(16),
        ),
        child: const Text(
          '此图片受保护，禁止保存和截图',
          style: TextStyle(color: Colors.white, fontSize: 12),
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
      style: TextStyle(color: Color.fromRGBO(255, 255, 255, 0.3), fontSize: 12),
    );
    final textPainter = TextPainter(
      text: textSpan,
      textDirection: TextDirection.ltr,
    );
    textPainter.layout();

    // 绘制多个水印，覆盖整个屏幕
    final stepX = 150.0;
    final stepY = 100.0;
    for (double x = -stepX / 2; x < size.width; x += stepX) {
      for (double y = -stepY / 2; y < size.height; y += stepY) {
        canvas.save();
        canvas.translate(x, y);
        canvas.rotate(-0.3); // 旋转水印
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
