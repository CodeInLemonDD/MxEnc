import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:flutter/services.dart';
import '../utils/theme_provider.dart';
import '../utils/dynamic_watermark.dart';
import '../utils/platform_secure.dart';
import '../utils/storage_service.dart';

class RichReaderScreen extends StatefulWidget {
  final Map<String, dynamic> manifest;
  final Uint8List payload;
  final int start;
  final String sourcePath;
  final String? password;
  final int initialChapterIndex;
  final String? itemId;
  const RichReaderScreen({
    super.key,
    required this.manifest,
    required this.payload,
    required this.start,
    required this.sourcePath,
    this.password,
    this.initialChapterIndex = 0,
    this.itemId,
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
    _restoreProgress();
  }

  Future<void> _restoreProgress() async {
    if (widget.itemId == null) return;
    try {
      final items = await StorageService.loadShelf();
      final item = items.firstWhere((e) => e['id'] == widget.itemId, orElse: () => {});
      if (item.isNotEmpty && item['readProgress'] != null) {
        final p = item['readProgress'];
        final chIdx = (p['chapterIndex'] as int?) ?? 0;
        final offset = (p['offset'] as num?)?.toDouble() ?? 0.0;
        
        if (mounted) {
          if (chIdx != _chapterIndex) {
            setState(() {
              _chapterIndex = chIdx;
            });
          }
          // Restore scroll offset
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (_scrollController.hasClients) {
              _scrollController.jumpTo(offset);
            }
          });
        }
      }
    } catch (e) {
      debugPrint('Restore rich progress failed: $e');
    }
  }

  @override
  void dispose() {
    if (widget.itemId != null) {
      StorageService.updateReadProgress(widget.itemId!, {
        'chapterIndex': _chapterIndex,
        'offset': _scrollController.hasClients ? _scrollController.offset : 0.0,
      });
    }

    _scrollController.dispose();
    PlatformSecure.disableSecureScreen();
    super.dispose();
  }

  List<Map<String, dynamic>> _chapterBlocks() {
    if (_chapters.isEmpty) return _blocks;
    final id = _chapters[_chapterIndex]['id']?.toString();
    if (id == null) return [];
    return _blocks.where((b) => b['chapterId']?.toString() == id).toList();
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
            if (blocks.isEmpty)
              Center(
                child: Text(
                  '本章节无内容\n(Debug: ${_chapters.isNotEmpty ? _chapters[_chapterIndex]['id'] : 'NoID'})',
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.grey),
                ),
              )
            else
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
                                _chapterIndex = (_chapterIndex - 1).clamp(
                                  0,
                                  _chapters.length - 1,
                                );
                              });
                            }
                          },
                          icon: const Icon(Icons.skip_previous),
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
