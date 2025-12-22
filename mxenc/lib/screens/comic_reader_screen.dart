import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:flutter/services.dart';
import '../utils/theme_provider.dart';
import '../utils/dynamic_watermark.dart';
import '../utils/platform_secure.dart';

class ComicReaderScreen extends StatefulWidget {
  final Map<String, dynamic> manifest;
  final Uint8List payload;
  final int start;
  final String sourcePath;
  final String? password;
  final int initialChapterIndex;
  const ComicReaderScreen({
    super.key,
    required this.manifest,
    required this.payload,
    required this.start,
    required this.sourcePath,
    this.password,
    this.initialChapterIndex = 0,
  });

  @override
  State<ComicReaderScreen> createState() => _ComicReaderScreenState();
}

class _ComicReaderScreenState extends State<ComicReaderScreen> {
  bool _overlayVisible = false;
  int _chapterIndex = 0;
  final ScrollController _scrollController = ScrollController();

  List<Map<String, dynamic>> get _chapters =>
      (widget.manifest['chapters'] as List<dynamic>? ?? [])
          .cast<Map<String, dynamic>>();
  List<Map<String, dynamic>> get _idx =>
      (widget.manifest['imagesIndex'] as List<dynamic>? ?? [])
          .cast<Map<String, dynamic>>();

  @override
  void initState() {
    super.initState();
    PlatformSecure.enableSecureScreen();
    _chapterIndex = widget.initialChapterIndex.clamp(
      0,
      _chapters.isEmpty ? 0 : _chapters.length - 1,
    );
    _scrollController.addListener(() {
      if (_overlayVisible) {
        setState(() {
          _overlayVisible = false;
        });
      }
    });
  }

  @override
  void dispose() {
    _scrollController.dispose();
    PlatformSecure.disableSecureScreen();
    super.dispose();
  }


  @override
  Widget build(BuildContext context) {
    final themeProvider = Provider.of<ThemeProvider>(context, listen: false);
    final title = (widget.manifest['title']?.toString() ?? '漫画');
    final chapters = _chapters;
    final images = chapters.isEmpty
        ? []
        : (chapters[_chapterIndex]['images'] as List<dynamic>? ?? []);
    return Scaffold(
      body: GestureDetector(
        behavior: HitTestBehavior.deferToChild,
        onTap: () => setState(() {
          _overlayVisible = !_overlayVisible;
        }),
        child: Stack(
          children: [
            ListView.builder(
              key: PageStorageKey(
                'comic_reader_${widget.sourcePath}_chapter_$_chapterIndex',
              ),
              controller: _scrollController,
              physics: const ClampingScrollPhysics(),
              itemCount: images.length,
              itemBuilder: (context, index) {
                final imgRef = images[index];
                final imageId = (imgRef is Map && imgRef.containsKey('id'))
                    ? imgRef['id'] as int
                    : (imgRef as int);
                if (imageId >= 0 && imageId < _idx.length) {
                  final entry = _idx[imageId];
                  final off = (entry['byteOffset'] as int) + widget.start;
                  final len = entry['length'] as int;
                  // 使用 view 而不是 sublist 以避免内存拷贝和提升性能
                  final bytes = widget.payload.buffer.asUint8List(
                    widget.payload.offsetInBytes + off,
                    len,
                  );
                  return Padding(
                    padding: const EdgeInsets.all(8.0),
                    child: _ComicImageItem(bytes: bytes),
                  );
                }
                return const SizedBox.shrink();
              },
            ),
            Positioned.fill(
              child: IgnorePointer(child: const StaticWatermark(opacity: 0.1)),
            ),
            if (_overlayVisible)
              Positioned(
                top: 0,
                left: 0,
                right: 0,
                child: SafeArea(
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 8,
                    ),
                    color: Theme.of(
                      context,
                    ).colorScheme.surface.withValues(alpha: 0.9),
                    child: Row(
                      children: [
                        IconButton(
                          onPressed: () {
                            Navigator.pop(context);
                          },
                          icon: const Icon(Icons.arrow_back),
                        ),
                        Expanded(
                          child: Text(
                            title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        const SizedBox.shrink(),
                      ],
                    ),
                  ),
                ),
              ),
            if (_overlayVisible)
              Positioned(
                bottom: 0,
                left: 0,
                right: 0,
                child: SafeArea(
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 8,
                    ),
                    color: Theme.of(
                      context,
                    ).colorScheme.surface.withValues(alpha: 0.9),
                    child: Row(
                      children: [
                        IconButton(
                          onPressed: () {
                            final isDark = themeProvider.mode == ThemeMode.dark;
                            themeProvider.setDarkMode(!isDark);
                          },
                          icon: const Icon(Icons.nightlight_round),
                        ),
                        Expanded(
                          child: DropdownButton<int>(
                            value: chapters.isEmpty ? null : _chapterIndex,
                            hint: const Text('章节选择'),
                            items: [
                              for (int i = 0; i < chapters.length; i++)
                                DropdownMenuItem(
                                  value: i,
                                  child: Text(
                                    (chapters[i]['title'] ?? '章节').toString(),
                                  ),
                                ),
                            ],
                            onChanged: (v) {
                              if (v != null) {
                                setState(() {
                                  _chapterIndex = v;
                                });
                                WidgetsBinding.instance.addPostFrameCallback((
                                  _,
                                ) {
                                  if (_scrollController.hasClients) {
                                    _scrollController.jumpTo(0);
                                  }
                                });
                              }
                            },
                          ),
                        ),
                        IconButton(
                          onPressed: () {
                            if (chapters.isNotEmpty) {
                              setState(() {
                                _chapterIndex = (_chapterIndex + 1).clamp(
                                  0,
                                  chapters.length - 1,
                                );
                              });
                            }
                            WidgetsBinding.instance.addPostFrameCallback((_) {
                              if (_scrollController.hasClients) {
                                _scrollController.jumpTo(0);
                              }
                            });
                          },
                          icon: const Icon(Icons.skip_next),
                        ),
                        IconButton(
                          onPressed: () {
                            if (chapters.isNotEmpty) {
                              setState(() {
                                _chapterIndex = (_chapterIndex - 1).clamp(
                                  0,
                                  chapters.length - 1,
                                );
                              });
                            }
                            WidgetsBinding.instance.addPostFrameCallback((_) {
                              if (_scrollController.hasClients) {
                                _scrollController.jumpTo(0);
                              }
                            });
                          },
                          icon: const Icon(Icons.skip_previous),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _ComicImageItem extends StatefulWidget {
  final Uint8List bytes;
  const _ComicImageItem({required this.bytes});

  @override
  State<_ComicImageItem> createState() => _ComicImageItemState();
}

class _ComicImageItemState extends State<_ComicImageItem> {
  final TransformationController _controller = TransformationController();
  bool _panEnabled = false;

  @override
  void initState() {
    super.initState();
    _controller.addListener(_onTransformationChange);
  }

  @override
  void dispose() {
    _controller.removeListener(_onTransformationChange);
    _controller.dispose();
    super.dispose();
  }

  void _onTransformationChange() {
    final scale = _controller.value.getMaxScaleOnAxis();
    // 当缩放比例接近1.0时，禁用拖拽，允许列表滚动
    final shouldEnable = scale > 1.05;
    if (_panEnabled != shouldEnable) {
      setState(() {
        _panEnabled = shouldEnable;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return InteractiveViewer(
      transformationController: _controller,
      panEnabled: _panEnabled,
      minScale: 1.0,
      maxScale: 5.0,
      child: Image.memory(
        widget.bytes,
        fit: BoxFit.contain,
        gaplessPlayback: true,
      ),
    );
  }
}
