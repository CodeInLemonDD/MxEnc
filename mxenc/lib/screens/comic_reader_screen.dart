import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:flutter/services.dart';
import '../utils/storage_service.dart';
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
    _chapterIndex = widget.initialChapterIndex.clamp(0, _chapters.isEmpty ? 0 : _chapters.length - 1);
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
        'isNovel': false,
        'isComic': true,
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
                  final bytes = widget.payload.sublist(off, off + len);
                  return Padding(
                    padding: const EdgeInsets.all(8.0),
                    child: InteractiveViewer(
                      minScale: 0.5,
                      maxScale: 5.0,
                      child: Image.memory(bytes, fit: BoxFit.contain),
                    ),
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
                        IconButton(
                          onPressed: _addToShelf,
                          icon: const Icon(Icons.bookmark_add),
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
