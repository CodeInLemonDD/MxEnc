import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:flutter/services.dart';
import '../utils/storage_service.dart';
import '../utils/theme_provider.dart';
import '../utils/dynamic_watermark.dart';
import '../utils/platform_secure.dart';

class RichReaderScreen extends StatefulWidget {
  final Map<String, dynamic> manifest;
  final Uint8List payload;
  final int start;
  final String sourcePath;
  final String? password;
  final int initialChapterIndex;
  const RichReaderScreen({
    super.key,
    required this.manifest,
    required this.payload,
    required this.start,
    required this.sourcePath,
    this.password,
    this.initialChapterIndex = 0,
  });

  @override
  State<RichReaderScreen> createState() => _RichReaderScreenState();
}

class _RichReaderScreenState extends State<RichReaderScreen> {
  bool _overlayVisible = false;
  double _fontScale = 1.0;
  int _chapterIndex = 0;
  final ScrollController _scrollController = ScrollController();

  List<Map<String, dynamic>> get _blocks =>
      (widget.manifest['blocks'] as List<dynamic>? ?? [])
          .cast<Map<String, dynamic>>();
  List<Map<String, dynamic>> get _chapters =>
      (widget.manifest['chapters'] as List<dynamic>? ?? [])
          .cast<Map<String, dynamic>>();
  List<Map<String, dynamic>> get _idx =>
      (widget.manifest['resourcesIndex'] as List<dynamic>? ?? [])
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

  List<Map<String, dynamic>> _chapterBlocks() {
    if (_chapters.isEmpty) return _blocks;
    final id = _chapters[_chapterIndex]['id'];
    return _blocks.where((b) => b['chapterId'] == id).toList();
  }

  Future<void> _addToShelf() async {
    try {
      final id = StorageService.newId();
      final title = (widget.manifest['title'] ?? '未命名').toString();
      String coverPath = 'assets/placeholder.png';
      final coverRef = widget.manifest['coverRef'];
      if (coverRef is int && coverRef >= 0 && coverRef < _idx.length) {
        final entry = _idx[coverRef];
        final off = (entry['byteOffset'] as int) + widget.start;
        final len = entry['length'] as int;
        final bytes = widget.payload.sublist(off, off + len);
        coverPath = await StorageService.storeCoverBytes(id, bytes);
      } else {
        final bd = await rootBundle.load('assets/logo.jpg');
        final def = bd.buffer.asUint8List();
        coverPath = await StorageService.storeCoverBytes(id, def);
      }
      final item = {
        'id': id,
        'title': title,
        'author': (widget.manifest['authorNickname'] ?? '未知作者').toString(),
        'coverPath': coverPath,
        'filePath': widget.sourcePath,
        'isNovel': true,
        'isRichNovel': true,
        'importTime': DateTime.now().toIso8601String(),
        'creationTime': null,
        'authorDeviceId': (widget.manifest['authorDeviceId'] ?? '').toString(),
        'authorSignature': (widget.manifest['authorSignature'] ?? '')
            .toString(),
        'authorAvatarPath': (widget.manifest['authorAvatarPath'] ?? '')
            .toString(),
      };
      await StorageService.saveShelfItem(item);
      try {
        final pwd = widget.password;
        if (pwd != null && pwd.isNotEmpty) {
          await StorageService.saveItemPassword(widget.sourcePath, pwd);
        }
      } catch (_) {}
      if (mounted) {
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
    final themeProvider = Provider.of<ThemeProvider>(context, listen: false);
    final title = (widget.manifest['title']?.toString() ?? '作品');
    final blocks = _chapterBlocks();
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
                'rich_reader_${widget.sourcePath}_$_chapterIndex',
              ),
              controller: _scrollController,
              physics: const ClampingScrollPhysics(),
              itemCount: blocks.length,
              itemBuilder: (context, index) {
                final b = blocks[index];
                if (b['type'] == 'text') {
                  return Padding(
                    padding: const EdgeInsets.all(12),
                    child: Text(
                      (b['content']?.toString() ?? ''),
                      style: TextStyle(fontSize: 16 * _fontScale, height: 1.6),
                    ),
                  );
                } else {
                  final ref = b['ref'];
                  Map<String, dynamic>? entry;
                  if (ref is Map && ref.containsKey('byteOffset')) {
                    entry = Map<String, dynamic>.from(ref);
                  } else if (ref is int && ref >= 0 && ref < _idx.length) {
                    entry = _idx[ref];
                  }
                  if (entry != null) {
                    final off = (entry['byteOffset'] as int) + widget.start;
                    final len = entry['length'] as int;
                    // 确保不会越界
                    if (off + len <= widget.payload.length) {
                      final bytes = widget.payload.buffer.asUint8List(
                        widget.payload.offsetInBytes + off,
                        len,
                      );
                      return Padding(
                        padding: const EdgeInsets.all(8.0),
                        child: Image.memory(
                          bytes,
                          fit: BoxFit.contain,
                          gaplessPlayback: true,
                        ),
                      );
                    }
                  }
                  return const SizedBox.shrink();
                }
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
                        IconButton(
                          onPressed: _addToShelf,
                          icon: const Icon(Icons.bookmark_add),
                        ),
                        IconButton(
                          onPressed: () {
                            showModalBottomSheet(
                              context: context,
                              builder: (context) {
                                double temp = _fontScale;
                                return StatefulBuilder(
                                  builder: (context, setStateSheet) {
                                    return Container(
                                      padding: const EdgeInsets.all(16),
                                      child: Column(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          const Text('调整字号'),
                                          Slider(
                                            value: temp,
                                            min: 0.8,
                                            max: 2.0,
                                            onChanged: (v) {
                                              setStateSheet(() {
                                                temp = v;
                                              });
                                            },
                                            onChangeEnd: (v) {
                                              setState(() {
                                                _fontScale = v;
                                              });
                                            },
                                          ),
                                        ],
                                      ),
                                    );
                                  },
                                );
                              },
                            );
                          },
                          icon: const Icon(Icons.text_fields),
                        ),
                        Expanded(
                          child: DropdownButton<int>(
                            value: _chapters.isEmpty ? null : _chapterIndex,
                            hint: const Text('章节选择'),
                            items: [
                              for (int i = 0; i < _chapters.length; i++)
                                DropdownMenuItem(
                                  value: i,
                                  child: Text(
                                    (_chapters[i]['title'] ?? '章节').toString(),
                                  ),
                                ),
                            ],
                            onChanged: (v) {
                              if (v != null) {
                                setState(() {
                                  _chapterIndex = v;
                                });
                              }
                            },
                          ),
                        ),
                        IconButton(
                          onPressed: () {
                            if (_chapters.isNotEmpty) {
                              setState(() {
                                _chapterIndex = (_chapterIndex + 1).clamp(
                                  0,
                                  _chapters.length - 1,
                                );
                              });
                            }
                          },
                          icon: const Icon(Icons.skip_next),
                        ),
                        IconButton(
                          onPressed: () {
                            if (_chapters.isNotEmpty) {
                              setState(() {
                                _chapterIndex = (_chapterIndex - 1).clamp(
                                  0,
                                  _chapters.length - 1,
                                );
                              });
                            }
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
