import 'package:flutter/material.dart';
import 'dart:io';
import 'package:mxenc/screens/bookshelf_screen.dart';
import 'package:mxenc/models/chapter.dart';
import '../models/novel.dart';
import 'novel_reader_screen.dart';
import '../utils/storage_service.dart';

// 定义分卷模型
class Volume {
  final String id;
  final String title;
  final List<Chapter> chapters;
  final bool isLocked;

  Volume({
    required this.id,
    required this.title,
    required this.chapters,
    this.isLocked = false,
  });
}

class NovelDetailScreen extends StatefulWidget {
  final BookshelfItem item;
  final NovelData? novel;

  const NovelDetailScreen({super.key, required this.item, this.novel});

  @override
  State<NovelDetailScreen> createState() => _NovelDetailScreenState();
}

class _NovelDetailScreenState extends State<NovelDetailScreen> {
  List<Volume> _volumes = [];
  List<String> _tags = [];
  int _totalWordCount = 0;
  final Map<String, String> _chapterContentById = {};
  bool _showDirectory = true;

  @override
  void initState() {
    super.initState();
    _loadNovelData();
  }

  Widget _buildCoverImage(String path) {
    try {
      final file = File(path);
      if (file.existsSync()) {
        return Image.file(file, fit: BoxFit.cover);
      }
    } catch (_) {}
    return Image.asset(path, fit: BoxFit.cover);
  }

  void _loadNovelData() {
    final novel = widget.novel;
    if (novel == null || novel.chapters.isEmpty) {
      setState(() {
        _volumes = [];
        _totalWordCount = 0;
        _tags = [];
      });
      return;
    }
    final chapters = <Chapter>[];
    int total = 0;
    for (var i = 0; i < novel.chapters.length; i++) {
      final nc = novel.chapters[i];
      final id = 'ch_${i + 1}';
      final wc = nc.content.length;
      total += wc;
      chapters.add(Chapter(id: id, title: nc.title, wordCount: wc));
      _chapterContentById[id] = nc.content;
    }
    setState(() {
      _volumes = [Volume(id: 'v1', title: '正文', chapters: chapters)];
      _totalWordCount = total;
      _tags = novel.tags;
    });
  }

  // 切换显示模式
  void _toggleDisplayMode() {
    setState(() {
      _showDirectory = !_showDirectory;
    });
  }

  // 处理章节点击
  void _onChapterTap(Chapter chapter) {
    final content = _chapterContentById[chapter.id] ?? '';
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => NovelReaderScreen(
          chapter: chapter,
          content: content,
          novelTitle: widget.item.title,
          author: widget.item.author,
          sourceFilePath: widget.item.filePath,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.item.title), elevation: 0, actions: [
        IconButton(
          icon: const Icon(Icons.bookmark_add),
          tooltip: '加入到书架',
          onPressed: _addToShelf,
        )
      ]),
      body: Column(
        children: [
          // 信息栏
          _buildInfoBar(),
          // 导航栏
          _buildNavigationBar(),
          // 内容区域
          Expanded(
            child: _showDirectory ? _buildDirectory() : _buildAuthorInfo(),
          ),
        ],
      ),
    );
  }

  // 构建信息栏
  Widget _buildInfoBar() {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(16.0),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        boxShadow: [
          BoxShadow(
            color: theme.colorScheme.shadow.withOpacity(0.1),
            spreadRadius: 0,
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 封面
          Container(
            width: 100,
            height: 140,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(8),
              color: theme.colorScheme.surfaceContainerHighest,
              boxShadow: [
                BoxShadow(
                  color: theme.colorScheme.shadow.withOpacity(0.1),
                  spreadRadius: 0,
                  blurRadius: 4,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: _buildCoverImage(widget.item.coverPath),
            ),
          ),
          // 信息
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(left: 16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    widget.item.title,
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '作者：${widget.item.author}',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.onSurface.withValues(alpha: 0.7),
                    ),
                  ),
                  const SizedBox(height: 8),
                  // 标签
                  SizedBox(
                    height: 30,
                    child: ListView.builder(
                      scrollDirection: Axis.horizontal,
                      itemCount: _tags.length,
                      itemBuilder: (context, index) {
                        return Container(
                          margin: const EdgeInsets.only(right: 8),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: theme.colorScheme.primary.withOpacity(0.12),
                            borderRadius: BorderRadius.circular(15),
                          ),
                          child: Text(
                            _tags[index],
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.primary,
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Text(
                        '分卷：${_volumes.length}',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
                        ),
                      ),
                      const SizedBox(width: 16),
                      Text(
                        '章节数：${_volumes.fold(0, (sum, volume) => sum + volume.chapters.length)}',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '字数：${(_totalWordCount / 10000).toStringAsFixed(1)}万',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  // 构建导航栏（很扁的菜单栏）
  Widget _buildNavigationBar() {
    final theme = Theme.of(context);
    return Container(
      height: 40,
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        border: Border(
          bottom: BorderSide(
            color: theme.colorScheme.outline.withOpacity(0.12),
          ),
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: GestureDetector(
              onTap: () {
                if (!_showDirectory) {
                  _toggleDisplayMode();
                }
              },
              child: Container(
                alignment: Alignment.center,
                decoration: _showDirectory
                    ? BoxDecoration(
                        border: Border(
                          bottom: BorderSide(
                            color: theme.colorScheme.primary,
                            width: 2,
                          ),
                        ),
                      )
                    : null,
                child: Text(
                  '目录',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: _showDirectory
                        ? theme.colorScheme.primary
                        : theme.colorScheme.onSurface.withOpacity(0.6),
                    fontWeight: _showDirectory
                        ? FontWeight.w600
                        : FontWeight.normal,
                  ),
                ),
              ),
            ),
          ),
          Expanded(
            child: GestureDetector(
              onTap: () {
                if (_showDirectory) {
                  _toggleDisplayMode();
                }
              },
              child: Container(
                alignment: Alignment.center,
                decoration: !_showDirectory
                    ? BoxDecoration(
                        border: Border(
                          bottom: BorderSide(
                            color: theme.colorScheme.primary,
                            width: 2,
                          ),
                        ),
                      )
                    : null,
                child: Text(
                  '相关',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: !_showDirectory
                        ? theme.colorScheme.primary
                        : theme.colorScheme.onSurface.withOpacity(0.6),
                    fontWeight: !_showDirectory
                        ? FontWeight.w600
                        : FontWeight.normal,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // 构建目录
  Widget _buildDirectory() {
    return ListView.builder(
      itemCount: _volumes.length,
      itemBuilder: (context, volumeIndex) {
        final volume = _volumes[volumeIndex];
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 分卷标题
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(color: Theme.of(context).colorScheme.surfaceContainerLowest),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    volume.title,
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: Theme.of(context).colorScheme.onSurface,
                    ),
                  ),
                  Text(
                    '${volume.chapters.length}章',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.6),
                    ),
                  ),
                ],
              ),
            ),
            // 章节列表
            Column(
              children: volume.chapters.map((chapter) {
                return GestureDetector(
                  onTap: () => _onChapterTap(chapter),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 12,
                    ),
                    decoration: BoxDecoration(
                      border: Border(
                        bottom: BorderSide(color: Theme.of(context).colorScheme.outlineVariant),
                      ),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Expanded(
                          child: Text(
                            chapter.title,
                            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                              color: chapter.isLocked
                                  ? Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.38)
                                  : Theme.of(context).colorScheme.onSurface,
                            ),
                          ),
                        ),
                        Text(
                          '${chapter.wordCount}字',
                          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.6),
                          ),
                        ),
                        if (chapter.isLocked) ...[
                          const SizedBox(width: 4),
                          Icon(
                            Icons.lock_outline,
                            size: 16,
                            color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.38),
                          ),
                        ],
                      ],
                    ),
                  ),
                );
              }).toList(),
            ),
          ],
        );
      },
    );
  }

  // 构建作者信息
  Widget _buildAuthorInfo() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 作者信息卡片
          Card(
            elevation: 2,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(30),
                        child: SizedBox(
                          width: 60,
                          height: 60,
                          child: (() {
                            final path = (widget.novel?.authorAvatarPath ?? 'assets/default_avatar.jpg');
                            if (path.startsWith('assets/')) {
                              return Image.asset(path, fit: BoxFit.cover);
                            }
                            try {
                              final f = File(path);
                              if (f.existsSync()) return Image.file(f, fit: BoxFit.cover);
                            } catch (_) {}
                            return Image.asset('assets/default_avatar.jpg', fit: BoxFit.cover);
                          })(),
                        ),
                      ),
                      const SizedBox(width: 16),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(((widget.novel?.authorNickname ?? '').isNotEmpty ? widget.novel!.authorNickname! : widget.item.author),
                              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                          const SizedBox(height: 4),
                          Text(((widget.novel?.authorSignature ?? '').isNotEmpty ? widget.novel!.authorSignature! : '奇幻小说作家'),
                              style: TextStyle(fontSize: 14, color: Colors.grey[600])),
                        ],
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  // 作者简介
                  Text(
                    widget.novel?.description ?? '暂无简介',
                    style: TextStyle(
                      fontSize: 14,
                      height: 1.6,
                      color: Colors.grey[700],
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          // 作品信息
          const Text(
            '作品信息',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 12),
          Card(
            elevation: 2,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildInfoRow(
                    '创作时间',
                    widget.item.creationTime?.toString().substring(0, 10) ??
                        '未知',
                  ),
                  _buildInfoRow(
                    '总字数',
                    '${(_totalWordCount / 10000).toStringAsFixed(1)}万字',
                  ),
                  _buildInfoRow('更新状态', '连载中'),
                  _buildInfoRow(
                    '最后更新',
                    DateTime.now()
                        .subtract(const Duration(days: 1))
                        .toString()
                        .substring(0, 10),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _addToShelf() async {
    try {
      final id = widget.item.id;
      final item = {
        'id': id,
        'title': widget.item.title,
        'author': widget.item.author,
        'coverPath': widget.item.coverPath,
        'filePath': widget.item.filePath,
        'isNovel': true,
        'importTime': DateTime.now().toIso8601String(),
        'creationTime': null,
        'tags': _tags,
        'authorDeviceId': ((widget.novel?.authorDeviceId ?? '')).toString(),
      };
      await StorageService.saveShelfItem(item);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('已加入到书架')));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('加入失败: $e')));
      }
    }
  }

  // 构建信息行
  Widget _buildInfoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12.0),
      child: Row(
        children: [
          SizedBox(
            width: 80,
            child: Text(
              label,
              style: TextStyle(fontSize: 14, color: Colors.grey[600]),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(fontSize: 14, color: Colors.black87),
            ),
          ),
        ],
      ),
    );
  }
}
