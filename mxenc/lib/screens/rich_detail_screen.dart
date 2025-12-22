import 'dart:typed_data';
import 'dart:io';
import 'package:flutter/material.dart';
import '../utils/storage_service.dart';
import 'rich_reader_screen.dart';

class RichDetailScreen extends StatefulWidget {
  final Map<String, dynamic> manifest;
  final Uint8List payload;
  final int start;
  final String sourcePath;
  final String? password;
  final bool fromShelf;

  const RichDetailScreen({
    super.key,
    required this.manifest,
    required this.payload,
    required this.start,
    required this.sourcePath,
    this.password,
    this.fromShelf = false,
  });

  @override
  State<RichDetailScreen> createState() => _RichDetailScreenState();
}

class _RichDetailScreenState extends State<RichDetailScreen> {
  Map<String, dynamic>? _coverEntry;

  List<Map<String, dynamic>> get _chapters =>
      (widget.manifest['chapters'] as List<dynamic>? ?? [])
          .cast<Map<String, dynamic>>();
  List<Map<String, dynamic>> get _idx =>
      (widget.manifest['resourcesIndex'] as List<dynamic>? ?? [])
          .cast<Map<String, dynamic>>();

  bool _isSaved = false;

  @override
  void initState() {
    super.initState();
    _isSaved = widget.fromShelf;
    final coverRef = widget.manifest['coverRef'];
    if (coverRef is int && coverRef >= 0 && coverRef < _idx.length) {
      _coverEntry = _idx[coverRef];
    }
  }

  Widget _buildCover(double width) {
    if (_coverEntry != null) {
      try {
        final off = (_coverEntry!['byteOffset'] as int) + widget.start;
        final len = _coverEntry!['length'] as int;
        // 确保不会越界
        if (off + len <= widget.payload.length) {
          final bytes = widget.payload.sublist(off, off + len);
          return ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: Image.memory(
              bytes,
              width: width,
              height: width * 1.4,
              fit: BoxFit.cover,
              errorBuilder: (_, __, ___) => Container(
                width: width,
                height: width * 1.4,
                color: Colors.grey[300],
                child: const Icon(Icons.broken_image),
              ),
            ),
          );
        }
      } catch (e) {
        debugPrint('Load cover failed: $e');
      }
    }
    return Container(
      width: width,
      height: width * 1.4,
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(10),
      ),
      child: const Icon(Icons.image, size: 64),
    );
  }

  @override
  Widget build(BuildContext context) {
    final author = (widget.manifest['authorNickname'] ?? '未知作者').toString();
    final signature = (widget.manifest['authorSignature'] ?? '').toString();
    final avatarPath = (widget.manifest['authorAvatarPath'] ?? '').toString();
    final title = (widget.manifest['title'] ?? '作品').toString();
    final theme = Theme.of(context);
    List<String> splitTags(dynamic v) {
      final List<String> out = [];
      if (v is String) {
        out.addAll(
          v
              .split(RegExp(r'[，,]'))
              .map((e) => e.trim())
              .where((e) => e.isNotEmpty),
        );
      } else if (v is List) {
        for (final el in v) {
          final s = (el ?? '').toString();
          out.addAll(
            s
                .split(RegExp(r'[，,]'))
                .map((e) => e.trim())
                .where((e) => e.isNotEmpty),
          );
        }
      }
      return out;
    }

    final tags = splitTags(widget.manifest['tags']);
    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildCover(110),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: theme.textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        ClipRRect(
                          borderRadius: BorderRadius.circular(24),
                          child: SizedBox(
                            width: 48,
                            height: 48,
                            child: (() {
                              if (avatarPath.startsWith('assets/')) {
                                return Image.asset(
                                  avatarPath,
                                  fit: BoxFit.cover,
                                );
                              }
                              try {
                                final f = File(avatarPath);
                                if (avatarPath.isNotEmpty && f.existsSync()) {
                                  return Image.file(f, fit: BoxFit.cover);
                                }
                              } catch (_) {}
                              return Image.asset(
                                'assets/default_avatar.jpg',
                                fit: BoxFit.cover,
                              );
                            })(),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(author, style: theme.textTheme.titleMedium),
                              if (signature.isNotEmpty)
                                Text(
                                  signature,
                                  style: theme.textTheme.bodySmall?.copyWith(
                                    color: theme.colorScheme.onSurface
                                        .withValues(alpha: 0.6),
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          if (tags.isNotEmpty) ...[
            Text('标签', style: theme.textTheme.titleMedium),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final t in tags)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.primary.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(15),
                    ),
                    child: Text(
                      t,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.primary,
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 16),
          ],
          Text('章节', style: theme.textTheme.titleMedium),
          const SizedBox(height: 8),
          ..._chapters.asMap().entries.map((entry) {
            final idx = entry.key;
            final c = entry.value;
            final chTitle = (c['title'] ?? '章节').toString();
            return ListTile(
              title: Text(chTitle),
              trailing: const Icon(Icons.chevron_right),
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => RichReaderScreen(
                      manifest: widget.manifest,
                      payload: widget.payload,
                      start: widget.start,
                      sourcePath: widget.sourcePath,
                      password: widget.password,
                      initialChapterIndex: idx,
                    ),
                  ),
                );
              },
            );
          }),
        ],
      ),
      bottomNavigationBar: _isSaved
          ? null
          : SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: FilledButton.icon(
                  onPressed: () async {
                    final id = StorageService.newId();
                    String coverPath = 'assets/placeholder.png';
                    if (_coverEntry != null) {
                      final off =
                          (_coverEntry!['byteOffset'] as int) + widget.start;
                      final len = _coverEntry!['length'] as int;
                      // 确保不会越界
                      if (off + len <= widget.payload.length) {
                        final bytes = widget.payload.sublist(off, off + len);
                        coverPath =
                            await StorageService.storeCoverBytes(id, bytes);
                      }
                    }
                    final item = {
                      'id': id,
                      'title': title,
                      'author': author,
                      'coverPath': coverPath,
                      'filePath': widget.sourcePath,
                      'isNovel': true,
                      'isRichNovel': true,
                      'importTime': DateTime.now().toIso8601String(),
                      'creationTime': null,
                      'authorDeviceId':
                          (widget.manifest['authorDeviceId'] ?? '').toString(),
                      'authorSignature': signature,
                      'authorAvatarPath': avatarPath,
                      'tags': tags,
                    };
                    await StorageService.saveShelfItem(item);
                    if (!context.mounted) return;
                    setState(() {
                      _isSaved = true;
                    });
                    ScaffoldMessenger.of(
                      context,
                    ).showSnackBar(const SnackBar(content: Text('已保存到书架')));
                  },
                  icon: const Icon(Icons.bookmark_add),
                  label: const Text('添加到书架'),
                ),
              ),
            ),
    );
  }
}
