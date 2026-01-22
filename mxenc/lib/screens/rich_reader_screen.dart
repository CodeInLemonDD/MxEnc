import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:flutter/services.dart';
import 'package:flutter/gestures.dart';
import '../utils/theme_provider.dart';
import '../utils/dynamic_watermark.dart';
import '../utils/platform_secure.dart';
import '../utils/storage_service.dart';
import '../utils/tts_service.dart';

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
  final TtsService _ttsService = TtsService();
  bool _isTtsActive = false;
  int? _currentReadingIndex;
  int _currentSubIndex = 0;
  double _ttsSpeed = 1.0;

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
    _restoreProgress(requestedChapter: widget.initialChapterIndex);
    // Use completion handler to drive the loop securely.
    _ttsService.setCompletionHandler(() async {
      // When one segment finishes, we ensure the queue stays populated.
      // Ideally, the next segment is already queued and playing.
      if (_isTtsActive) {
        _scheduleNextSegment();
      }
    });

    _ttsService.setStartHandler(() {
      if (mounted && _isTtsActive && _pendingUiUpdates.isNotEmpty) {
        final nextState = _pendingUiUpdates.removeAt(0);
        setState(() {
          _currentReadingIndex = nextState[0];
          _currentSubIndex = nextState[1];
        });
      }
    });

    _ttsService.setErrorHandler((msg) {
      if (mounted) _showTtsErrorDialog(msg);
    });
  }

  // FIFO Queue to track segments that have been sent to TTS engine
  // but haven't started playing yet (for UI highlighting sync).
  // Each entry is [blockIndex, subIndex]
  final List<List<int>> _pendingUiUpdates = [];

  // Track what we have QUEUED (sent to engine)
  int? _queuedBlockIndex;
  int _queuedSubIndex = 0;

  Future<void> _scheduleNextSegment() async {
    // Current logic: Called when a segment finishes playing (or starting fresh).
    // GOAL: Keep the TTS engine buffer full.

    final blocks = _chapterBlocks();
    // Use _queuedBlockIndex to determine what to send next, defaulting to current if null
    int processingBlockIdx = _queuedBlockIndex ?? _currentReadingIndex ?? 0;
    int processingSubIdx = _queuedSubIndex;

    // Calculate NEXT target
    int nextSub = processingSubIdx + 1;
    int nextBlockIdx = processingBlockIdx;

    final currentBlockContent =
        blocks[nextBlockIdx]['content']?.toString() ?? '';
    final currentSegments = _splitText(currentBlockContent);

    if (nextSub >= currentSegments.length) {
      // End of block, move to next
      nextSub = 0;
      nextBlockIdx++;
      while (nextBlockIdx < blocks.length &&
          blocks[nextBlockIdx]['type'] != 'text') {
        nextBlockIdx++;
      }
    }

    if (nextBlockIdx >= blocks.length) {
      // End of chapter - nothing more to queue
      return;
    }

    // Update QUEUED state
    _queuedBlockIndex = nextBlockIdx;
    _queuedSubIndex = nextSub;

    final targetContent = blocks[nextBlockIdx]['content']?.toString() ?? '';
    final targetSegments = _splitText(targetContent);

    if (targetSegments.isNotEmpty && nextSub < targetSegments.length) {
      // Add to UI tracking queue
      _pendingUiUpdates.add([nextBlockIdx, nextSub]);

      // Speak (Queued)
      // Note: First segment of a sequence is NOT queued (Flush), subsequent are queued (Add)
      // But _scheduleNextSegment is usually called AFTER the first one is sent via _toggleTts
      // So we default to cached queueing.
      await _ttsService.speak(targetSegments[nextSub], isQueued: true);
    }
  }

  // Helper to start playback reliably from a specific point
  Future<void> _startPlayback(int blockIdx, int subIdx) async {
    // 1. Update UI State
    setState(() {
      _currentReadingIndex = blockIdx;
      _currentSubIndex = subIdx;
      _isTtsActive = true;
    });

    // 2. Clear Queues
    _pendingUiUpdates.clear();

    // 3. Reset Queue Logic
    _queuedBlockIndex = blockIdx;
    _queuedSubIndex = subIdx;

    final blocks = _chapterBlocks();
    if (blockIdx >= blocks.length) return;

    final content = blocks[blockIdx]['content']?.toString() ?? '';
    final segments = _splitText(content);

    if (subIdx < segments.length) {
      // 4. Add initial segment to UI Queue
      _pendingUiUpdates.add([blockIdx, subIdx]);

      // 5. Speak Immediately (Flush)
      await _ttsService.speak(segments[subIdx], isQueued: false);

      // 6. Safety Delay to prevent Android TTS from dropping valid queued items
      // if sent too quickly after a flush.
      if (!mounted || !_isTtsActive) return;
      await Future.delayed(const Duration(milliseconds: 200));

      // 7. Schedule Next
      if (mounted && _isTtsActive) {
        _scheduleNextSegment();
      }
    }
  }

  List<String> _splitText(String text) {
    if (text.isEmpty) return [];
    // Split by common punctuation, keeping delimiters AND following quotes/brackets
    // Logic:
    // 1. Match any non-punctuation characters (sentence body)
    // 2. Match the punctuation [,.\?;!，。？；！\n]
    // 3. Match any following closing quotes or brackets ["”'’\s]* to keep them attached
    final regExp = RegExp(r'[^,.\?;!，。？；！\n]+[,.\?;!，。？；！\n]*["”’\)\uff09]*');
    final matches = regExp.allMatches(text);
    if (matches.isEmpty) return [text];
    return matches
        .map((m) => m.group(0)!)
        .where((s) => s.trim().isNotEmpty)
        .toList();
  }

  void _toggleTts() {
    setState(() {
      _isTtsActive = !_isTtsActive;
      if (_isTtsActive) {
        _overlayVisible = false;

        // Find valid text block starting point
        int startBlock = _currentReadingIndex ?? 0;
        final blocks = _chapterBlocks();
        while (startBlock < blocks.length &&
            blocks[startBlock]['type'] != 'text') {
          startBlock++;
        }

        if (startBlock < blocks.length) {
          // Start via helper (includes safety delay)
          _startPlayback(startBlock, 0);
        }
      } else {
        _ttsService.stop();
        // Clear queue state
        _pendingUiUpdates.clear();
        _queuedBlockIndex = null;
      }
    });
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
        final offset = (p['offset'] as num?)?.toDouble() ?? 0.0;

        // Only restore if no specific chapter was requested OR it matches the requested one
        bool shouldRestore =
            requestedChapter == null || requestedChapter == chIdx;

        if (shouldRestore && mounted) {
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
    _ttsService.stop();
    PlatformSecure.disableSecureScreen();
    super.dispose();
  }

  List<Map<String, dynamic>> _chapterBlocks() {
    if (_chapters.isEmpty) return _blocks;
    final id = _chapters[_chapterIndex]['id']?.toString();
    if (id == null) return [];
    return _blocks.where((b) => b['chapterId']?.toString() == id).toList();
  }

  void _showTtsErrorDialog(String message) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.error_outline, color: Colors.red),
            SizedBox(width: 8),
            Text('听书功能报错'),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              '系统 TTS 引擎返回了以下信息：',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                message,
                style: const TextStyle(fontFamily: 'monospace', fontSize: 13),
              ),
            ),
            const SizedBox(height: 16),
            const Text('请检查手机 TTS 引擎设置或确认是否安装了语音包。'),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('了解'),
          ),
        ],
      ),
    );
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
                    final content = b['content']?.toString() ?? '';
                    final segments = _splitText(content);
                    return Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 8,
                      ),
                      child: Text.rich(
                        TextSpan(
                          children: [
                            for (int i = 0; i < segments.length; i++)
                              TextSpan(
                                text: segments[i],
                                style: TextStyle(
                                  fontSize: 16 * _fontScale,
                                  height: 1.6,
                                  color:
                                      (_isTtsActive &&
                                          _currentReadingIndex == index &&
                                          _currentSubIndex == i)
                                      ? Theme.of(context).colorScheme.primary
                                      : null,
                                  fontWeight:
                                      (_isTtsActive &&
                                          _currentReadingIndex == index &&
                                          _currentSubIndex == i)
                                      ? FontWeight.bold
                                      : null,
                                ),
                                recognizer: TapGestureRecognizer()
                                  ..onTap = () {
                                    if (_isTtsActive) {
                                      // Use helper
                                      _startPlayback(index, i);
                                    } else {
                                      setState(() {
                                        _overlayVisible = !_overlayVisible;
                                      });
                                    }
                                  },
                              ),
                          ],
                        ),
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
                        IconButton(
                          onPressed: _toggleTts,
                          icon: Icon(
                            _isTtsActive ? Icons.headset : Icons.headset_off,
                          ),
                          tooltip: '听书',
                        ),
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
            if (_isTtsActive)
              Positioned(
                bottom: 20,
                left: 20,
                right: 20,
                child: Card(
                  elevation: 8,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 8,
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Row(
                          children: [
                            IconButton(
                              icon: Icon(
                                _isTtsActive ? Icons.pause : Icons.play_arrow,
                              ),
                              onPressed: () {
                                setState(() {
                                  if (_isTtsActive) {
                                    // User wants to pause
                                    _isTtsActive = false;
                                    _ttsService.pause();
                                  } else {
                                    // User wants to resume
                                    _isTtsActive = true;
                                    if (_currentReadingIndex != null) {
                                      // Resume
                                      _startPlayback(
                                        _currentReadingIndex!,
                                        _currentSubIndex,
                                      );
                                    }
                                  }
                                });
                              },
                            ),
                            IconButton(
                              icon: const Icon(Icons.close),
                              onPressed: () {
                                setState(() {
                                  _isTtsActive = false;
                                  _ttsService.stop();
                                  _currentReadingIndex = null;
                                });
                              },
                            ),
                            const Spacer(),
                            const Text('语速:'),
                            SizedBox(
                              width: 120,
                              child: Slider(
                                value: _ttsSpeed,
                                min: 0.5,
                                max: 2.0,
                                divisions: 6,
                                label: _ttsSpeed.toStringAsFixed(1),
                                onChanged: (v) {
                                  setState(() {
                                    _ttsSpeed = v;
                                    _ttsService.setSpeechRate(v);
                                  });
                                },
                              ),
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
      ),
    );
  }
}
