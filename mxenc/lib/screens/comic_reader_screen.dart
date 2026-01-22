import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:flutter/services.dart';
import 'package:photo_view/photo_view.dart';
import 'package:photo_view/photo_view_gallery.dart';
import 'package:extended_image/extended_image.dart';
import 'package:scrollable_positioned_list/scrollable_positioned_list.dart';
import '../utils/theme_provider.dart';
import '../utils/dynamic_watermark.dart';
import '../utils/platform_secure.dart';
import '../utils/storage_service.dart';

enum ComicReaderMode { vertical, leftToRight, rightToLeft }

class ComicReaderScreen extends StatefulWidget {
  final Map<String, dynamic> manifest;
  final Uint8List payload;
  final int start;
  final String sourcePath;
  final String? password;
  final int initialChapterIndex;
  final String? itemId;

  const ComicReaderScreen({
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
  State<ComicReaderScreen> createState() => _ComicReaderScreenState();
}

class _ComicReaderScreenState extends State<ComicReaderScreen>
    with SingleTickerProviderStateMixin {
  bool _overlayVisible = false;
  int _currentIndex = 0; // Current image index within the current chapter
  int _chapterIndex = 0; // Current chapter index

  // Controllers
  final ItemScrollController _itemScrollController = ItemScrollController();
  final ItemPositionsListener _itemPositionsListener =
      ItemPositionsListener.create();
  late PageController _horizontalController;
  final TransformationController _transformationController =
      TransformationController();

  ComicReaderMode _readerMode = ComicReaderMode.vertical;

  // To handle physics conflict between Zoom and Scroll
  ScrollPhysics _verticalPhysics = const AlwaysScrollableScrollPhysics();

  // Cache settings
  int? _devicePixelWidth;
  bool _isHighRes = false;

  // Image Bytes Cache to prevent flickering
  final Map<int, Uint8List> _imageCache = {};

  List<Map<String, dynamic>> get _chapters =>
      (widget.manifest['chapters'] as List<dynamic>? ?? [])
          .cast<Map<String, dynamic>>();

  List<Map<String, dynamic>> get _idx =>
      (widget.manifest['imagesIndex'] as List<dynamic>? ?? [])
          .cast<Map<String, dynamic>>();

  List<dynamic> get _currentChapterImages {
    if (_chapters.isEmpty || _chapterIndex >= _chapters.length) return [];
    return (_chapters[_chapterIndex]['images'] as List<dynamic>? ?? []);
  }

  // Double tap animation controller
  late AnimationController _doubleTapAnimationController;
  Animation<Matrix4>? _doubleTapAnimation;

  @override
  void initState() {
    super.initState();
    PlatformSecure.enableSecureScreen();
    _initData();

    // Initialize double tap animation controller
    _doubleTapAnimationController =
        AnimationController(
          vsync: this,
          duration: const Duration(milliseconds: 200),
        )..addListener(() {
          _transformationController.value = _doubleTapAnimation!.value;
        });

    // Memory Optimization: Increase cache size for reader session
    PaintingBinding.instance.imageCache.maximumSizeBytes = 300 * 1024 * 1024;

    // Initialize horizontal controller
    _horizontalController = PageController(initialPage: _currentIndex);

    // Listen to vertical scroll positions to update index and preload
    _itemPositionsListener.itemPositions.addListener(_updateIndexFromScroll);

    // Listen to transformation changes to toggle scroll physics
    _transformationController.addListener(_onTransformationChange);

    // Immersive mode removed to prevent flickering
    // SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);

    _restoreProgress(requestedChapter: widget.initialChapterIndex);
  }

  Future<void> _restoreProgress({int? requestedChapter}) async {
    if (widget.itemId == null) return;
    try {
      final items = await StorageService.loadShelf();
      final item = items.firstWhere(
        (e) => e['id'] == widget.itemId,
        orElse: () => {},
      );
      if (item.isNotEmpty && item['readProgress'] != null) {
        final p = item['readProgress'];
        final chIdx = (p['chapterIndex'] as int?) ?? 0;
        final imgIdx = (p['imageIndex'] as int?) ?? 0;

        // Only restore if no specific chapter was requested OR it matches the requested one
        bool shouldRestore =
            requestedChapter == null || requestedChapter == chIdx;

        if (shouldRestore &&
            (chIdx != _chapterIndex || imgIdx != _currentIndex)) {
          if (mounted) {
            _onChapterChanged(chIdx);
            setState(() {
              _currentIndex = imgIdx;
            });

            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (_readerMode == ComicReaderMode.vertical) {
                if (_itemScrollController.isAttached) {
                  _itemScrollController.jumpTo(index: imgIdx);
                }
              } else {
                if (_horizontalController.hasClients) {
                  _horizontalController.jumpToPage(imgIdx);
                }
              }
            });
          }
        }
      }
    } catch (e) {
      debugPrint('Restore comic progress failed: $e');
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Calculate device pixel width for downsampling
    if (_devicePixelWidth == null) {
      final mediaQuery = MediaQuery.of(context);
      _devicePixelWidth = (mediaQuery.size.width * mediaQuery.devicePixelRatio)
          .toInt();
    }
  }

  void _initData() {
    _chapterIndex = widget.initialChapterIndex.clamp(
      0,
      (_chapters.length - 1).clamp(0, 9999),
    );
    _currentIndex = 0;
  }

  @override
  void dispose() {
    if (widget.itemId != null) {
      StorageService.updateReadProgress(widget.itemId!, {
        'chapterIndex': _chapterIndex,
        'imageIndex': _currentIndex,
      });
    }

    _doubleTapAnimationController.dispose();
    // SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    _horizontalController.dispose();
    _itemPositionsListener.itemPositions.removeListener(_updateIndexFromScroll);
    _transformationController.removeListener(_onTransformationChange);
    _transformationController.dispose();
    PlatformSecure.disableSecureScreen();

    // Clear local cache
    _imageCache.clear();

    // CRITICAL: Manually clear image cache to release memory for other screens (e.g. Bookshelf covers)
    PaintingBinding.instance.imageCache.clear();
    PaintingBinding.instance.imageCache.clearLiveImages();

    super.dispose();
  }

  void _onTransformationChange() {
    final scale = _transformationController.value.getMaxScaleOnAxis();

    // 1. Handle Scroll Physics
    // If zoomed in (scale > 1.0), disable list scrolling so InteractiveViewer handles panning
    if (scale > 1.05) {
      if (_verticalPhysics is! NeverScrollableScrollPhysics) {
        setState(() {
          _verticalPhysics = const NeverScrollableScrollPhysics();
        });
      }
    } else {
      if (_verticalPhysics is! AlwaysScrollableScrollPhysics) {
        setState(() {
          _verticalPhysics = const AlwaysScrollableScrollPhysics();
        });
      }
    }

    // 2. Handle High-Res Mode (Hysteresis)
    // Switch to high-res when zoomed in significantly (> 2.0x) to see details
    // Switch back to low-res (downsampled) when zoomed out (< 1.2x) for performance
    if (scale > 2.0 && !_isHighRes) {
      setState(() {
        _isHighRes = true;
      });
    } else if (scale < 1.2 && _isHighRes) {
      setState(() {
        _isHighRes = false;
      });
    }
  }

  void _updateIndexFromScroll() {
    if (_readerMode != ComicReaderMode.vertical) return;

    final positions = _itemPositionsListener.itemPositions.value;
    if (positions.isNotEmpty) {
      final visibleItems = positions
          .where((p) => p.itemTrailingEdge > 0 && p.itemLeadingEdge < 1)
          .toList();

      if (visibleItems.isNotEmpty) {
        visibleItems.sort(
          (a, b) => a.itemLeadingEdge.compareTo(b.itemLeadingEdge),
        );
        final firstVisible = visibleItems.first;
        int targetIndex = firstVisible.index;

        if (_currentIndex != targetIndex) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) {
              setState(() {
                _currentIndex = targetIndex;
              });
              _precacheImages(targetIndex);
            }
          });
        }
      }
    }
  }

  void _precacheImages(int index) {
    final images = _currentChapterImages;
    for (int i = 1; i <= 2; i++) {
      if (index + i < images.length) {
        _doPrecache(images[index + i]);
      }
      if (index - i >= 0) {
        _doPrecache(images[index - i]);
      }
    }
  }

  void _doPrecache(dynamic imgRef) {
    final bytes = _getImageBytes(imgRef);
    if (bytes != null && _devicePixelWidth != null) {
      // Use cacheWidth to prevent OOM
      precacheImage(ExtendedMemoryImageProvider(bytes), context);
    }
  }

  void _onChapterChanged(int index) {
    if (index < 0 || index >= _chapters.length) return;

    setState(() {
      _chapterIndex = index;
      _currentIndex = 0;
      // Reset zoom when changing chapter
      _transformationController.value = Matrix4.identity();
    });

    if (_readerMode == ComicReaderMode.vertical) {
      _itemScrollController.jumpTo(index: 0);
    } else {
      if (_horizontalController.hasClients) {
        _horizontalController.jumpToPage(0);
      }
    }
  }

  Uint8List? _getImageBytes(dynamic imgRef) {
    final imageId = (imgRef is Map && imgRef.containsKey('id'))
        ? imgRef['id'] as int
        : (imgRef is int ? imgRef : -1);

    if (imageId >= 0 && imageId < _idx.length) {
      // Return cached bytes if available
      if (_imageCache.containsKey(imageId)) {
        return _imageCache[imageId];
      }

      final entry = _idx[imageId];
      final off = (entry['byteOffset'] as int) + widget.start;
      final len = entry['length'] as int;
      final bytes = widget.payload.buffer.asUint8List(
        widget.payload.offsetInBytes + off,
        len,
      );

      // Cache the bytes
      _imageCache[imageId] = bytes;
      return bytes;
    }
    return null;
  }

  void _handleDoubleTap(TapDownDetails details) {
    if (_doubleTapAnimationController.isAnimating) return;

    final double scale = _transformationController.value.getMaxScaleOnAxis();
    final Matrix4 endMatrix;

    if (scale > 1.0) {
      // Zoom out to 1.0
      endMatrix = Matrix4.identity();
    } else {
      // Zoom in to 2.5x at the tapped position
      final double targetScale = 2.5;
      final Offset tapPosition = details.localPosition;

      // Calculate translation to keep the tap position focused
      // We want the point under the finger to remain under the finger after zoom
      // P_screen = P_world * scale + translate
      // We want P_screen to be same, but scale changes from 1.0 to 2.5
      // So translate must change.

      final double x = -tapPosition.dx * (targetScale - 1);
      final double y = -tapPosition.dy * (targetScale - 1);

      endMatrix = Matrix4(
        targetScale,
        0,
        0,
        0,
        0,
        targetScale,
        0,
        0,
        0,
        0,
        1,
        0,
        x,
        y,
        0,
        1,
      );
    }

    _doubleTapAnimation =
        Matrix4Tween(
          begin: _transformationController.value,
          end: endMatrix,
        ).animate(
          CurveTween(
            curve: Curves.easeInOut,
          ).animate(_doubleTapAnimationController),
        );

    _doubleTapAnimationController.forward(from: 0);
  }

  @override
  Widget build(BuildContext context) {
    final themeProvider = Provider.of<ThemeProvider>(context, listen: false);
    final title = (widget.manifest['title']?.toString() ?? '漫画');
    final chapters = _chapters;
    final currentImages = _currentChapterImages;

    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          // Reader Layer
          GestureDetector(
            onDoubleTapDown: _readerMode == ComicReaderMode.vertical
                ? _handleDoubleTap
                : null,
            onTap: () => setState(() => _overlayVisible = !_overlayVisible),
            child: _buildReaderBody(currentImages),
          ),

          // Watermark Layer
          Positioned.fill(
            child: IgnorePointer(child: const StaticWatermark(opacity: 0.1)),
          ),

          // Overlay Layer (Top Bar)
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
                        onPressed: () => Navigator.pop(context),
                        icon: const Icon(Icons.arrow_back),
                      ),
                      Expanded(
                        child: Text(
                          title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),

          // Overlay Layer (Bottom Bar)
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
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // Mode Switching
                      SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const Text('阅读模式：'),
                            const SizedBox(width: 8),
                            ChoiceChip(
                              label: const Text('垂直'),
                              selected: _readerMode == ComicReaderMode.vertical,
                              onSelected: (v) {
                                if (v) {
                                  setState(() {
                                    _readerMode = ComicReaderMode.vertical;
                                    _transformationController.value =
                                        Matrix4.identity();
                                  });
                                  // Sync position to vertical reader
                                  WidgetsBinding.instance.addPostFrameCallback((
                                    _,
                                  ) {
                                    if (_itemScrollController.isAttached) {
                                      _itemScrollController.jumpTo(
                                        index: _currentIndex,
                                      );
                                    }
                                  });
                                }
                              },
                            ),
                            const SizedBox(width: 8),
                            ChoiceChip(
                              label: const Text('从左向右'),
                              selected:
                                  _readerMode == ComicReaderMode.leftToRight,
                              onSelected: (v) {
                                if (v) {
                                  setState(
                                    () => _readerMode =
                                        ComicReaderMode.leftToRight,
                                  );
                                  // Sync position to horizontal reader
                                  WidgetsBinding.instance.addPostFrameCallback((
                                    _,
                                  ) {
                                    if (_horizontalController.hasClients) {
                                      _horizontalController.jumpToPage(
                                        _currentIndex,
                                      );
                                    }
                                  });
                                }
                              },
                            ),
                            const SizedBox(width: 8),
                            ChoiceChip(
                              label: const Text('从右向左'),
                              selected:
                                  _readerMode == ComicReaderMode.rightToLeft,
                              onSelected: (v) {
                                if (v) {
                                  setState(
                                    () => _readerMode =
                                        ComicReaderMode.rightToLeft,
                                  );
                                  // Sync position to horizontal reader
                                  WidgetsBinding.instance.addPostFrameCallback((
                                    _,
                                  ) {
                                    if (_horizontalController.hasClients) {
                                      _horizontalController.jumpToPage(
                                        _currentIndex,
                                      );
                                    }
                                  });
                                }
                              },
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 8),

                      // Progress Slider
                      Row(
                        children: [
                          Text('${_currentIndex + 1}/${currentImages.length}'),
                          Expanded(
                            child: Slider(
                              value: _currentIndex.toDouble(),
                              min: 0,
                              max: (currentImages.length - 1).toDouble().clamp(
                                0,
                                double.infinity,
                              ),
                              onChanged: (v) {
                                final targetIndex = v.toInt();
                                if (_readerMode == ComicReaderMode.vertical) {
                                  _itemScrollController.jumpTo(
                                    index: targetIndex,
                                  );
                                } else {
                                  _horizontalController.jumpToPage(targetIndex);
                                }
                                setState(() => _currentIndex = targetIndex);
                              },
                            ),
                          ),
                        ],
                      ),

                      // Chapter Controls
                      Row(
                        children: [
                          IconButton(
                            onPressed: () {
                              final isDark =
                                  themeProvider.mode == ThemeMode.dark;
                              themeProvider.setDarkMode(!isDark);
                            },
                            icon: const Icon(Icons.nightlight_round),
                          ),
                          Expanded(
                            child: DropdownButton<int>(
                              value: chapters.isEmpty ? null : _chapterIndex,
                              hint: const Text('章节选择'),
                              isExpanded: true,
                              items: [
                                for (int i = 0; i < chapters.length; i++)
                                  DropdownMenuItem(
                                    value: i,
                                    child: Text(
                                      (chapters[i]['title'] ?? '章节').toString(),
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                              ],
                              onChanged: (v) {
                                if (v != null) _onChapterChanged(v);
                              },
                            ),
                          ),
                          IconButton(
                            onPressed: () {
                              if (chapters.isNotEmpty) {
                                _onChapterChanged(
                                  (_chapterIndex - 1).clamp(
                                    0,
                                    chapters.length - 1,
                                  ),
                                );
                              }
                            },
                            icon: const Icon(Icons.skip_previous),
                          ),
                          IconButton(
                            onPressed: () {
                              if (chapters.isNotEmpty) {
                                _onChapterChanged(
                                  (_chapterIndex + 1).clamp(
                                    0,
                                    chapters.length - 1,
                                  ),
                                );
                              }
                            },
                            icon: const Icon(Icons.skip_next),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildReaderBody(List<dynamic> currentImages) {
    if (currentImages.isEmpty) {
      return const Center(
        child: Text('本章无图片', style: TextStyle(color: Colors.white)),
      );
    }

    if (_readerMode == ComicReaderMode.vertical) {
      return _buildVerticalReader(currentImages);
    } else {
      return _buildHorizontalReader(currentImages);
    }
  }

  Widget _buildVerticalReader(List<dynamic> currentImages) {
    return InteractiveViewer(
      transformationController: _transformationController,
      maxScale: 4.0,
      minScale: 1.0,
      child: ScrollablePositionedList.builder(
        key: PageStorageKey(
          'comic_reader_v_${widget.sourcePath}_$_chapterIndex',
        ),
        itemCount: currentImages.length,
        itemScrollController: _itemScrollController,
        itemPositionsListener: _itemPositionsListener,
        physics: _verticalPhysics,
        padding: EdgeInsets.zero,
        // Performance Optimization: Reduce preloading extent to save memory
        minCacheExtent: 600,
        itemBuilder: (context, index) {
          return _buildSeamlessImage(currentImages[index]);
        },
      ),
    );
  }

  Widget _buildSeamlessImage(dynamic imgRef) {
    final bytes = _getImageBytes(imgRef);
    if (bytes == null) return const SizedBox(height: 300);

    return ExtendedImage.memory(
      bytes,
      fit: BoxFit.fitWidth,
      gaplessPlayback: true,
      // Downsampling: decode to screen width to save memory
      // If _isHighRes is true (zoomed in), disable downsampling (cacheWidth: null) to show full detail
      cacheWidth: _isHighRes ? null : _devicePixelWidth,
      // Performance: use low filter quality for comics unless in high-res mode
      filterQuality: _isHighRes ? FilterQuality.medium : FilterQuality.low,
      enableMemoryCache: true,
      clearMemoryCacheWhenDispose: true,
      loadStateChanged: (state) {
        if (state.extendedImageLoadState == LoadState.loading) {
          return const SizedBox(
            height: 600,
            child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
          );
        }
        return null;
      },
    );
  }

  Widget _buildHorizontalReader(List<dynamic> currentImages) {
    return PhotoViewGallery.builder(
      key: PageStorageKey('comic_reader_h_${widget.sourcePath}_$_chapterIndex'),
      scrollPhysics: const BouncingScrollPhysics(),
      builder: (BuildContext context, int index) {
        final imgRef = currentImages[index];
        final bytes = _getImageBytes(imgRef);
        return PhotoViewGalleryPageOptions(
          imageProvider: bytes != null
              // Horizontal mode: Load full resolution for better zoom quality
              ? ExtendedMemoryImageProvider(bytes)
              : const AssetImage('assets/placeholder.png') as ImageProvider,
          initialScale: PhotoViewComputedScale.contained,
          minScale: PhotoViewComputedScale.contained,
          maxScale: PhotoViewComputedScale.covered * 2.5,
          heroAttributes: PhotoViewHeroAttributes(tag: index),
          // Higher quality for zoom
          filterQuality: FilterQuality.medium,
        );
      },
      itemCount: currentImages.length,
      loadingBuilder: (context, event) => const Center(
        child: SizedBox(
          width: 20.0,
          height: 20.0,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
      ),
      backgroundDecoration: const BoxDecoration(color: Colors.black),
      pageController: _horizontalController,
      onPageChanged: (index) {
        setState(() => _currentIndex = index);
        // Manual precache for next pages
        _precacheImages(index);
      },
      reverse: _readerMode == ComicReaderMode.rightToLeft,
    );
  }
}
