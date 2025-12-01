import 'package:flutter/material.dart';
import 'dart:io';
import '../../rust_bridge.dart';
import 'novel_detail_screen.dart';
import 'image_preview_screen.dart';
import 'viewer_screen.dart';
import '../utils/storage_service.dart';
import 'package:flutter/foundation.dart';
import 'comic_reader_screen.dart';
import 'rich_reader_screen.dart';
import '../widgets/loading_dialog.dart';

// 定义书籍/图片项目模型
class BookshelfItem {
  final String id;
  final String title;
  final String author;
  final String coverPath;
  final String filePath;
  final bool isNovel;
  final DateTime importTime;
  final DateTime? creationTime;
  final String? authorSignature;
  final String? authorAvatarPath;
  final String? authorDeviceId;
  final bool? isComic;
  final bool? isRichNovel;

  BookshelfItem({
    required this.id,
    required this.title,
    required this.author,
    required this.coverPath,
    required this.filePath,
    required this.isNovel,
    required this.importTime,
    this.creationTime,
    this.authorSignature,
    this.authorAvatarPath,
    this.authorDeviceId,
    this.isComic,
    this.isRichNovel,
  });
}

// 筛选类型枚举
enum FilterType { all, novels, images }

// 排序类型枚举
enum SortType {
  importTimeDesc,
  importTimeAsc,
  creationTimeDesc,
  creationTimeAsc,
}

class BookshelfScreen extends StatefulWidget {
  final RustBridge rustBridge;

  const BookshelfScreen({super.key, required this.rustBridge});

  @override
  State<BookshelfScreen> createState() => _BookshelfScreenState();
}

class _BookshelfScreenState extends State<BookshelfScreen> {
  List<BookshelfItem> _items = [];
  FilterType _currentFilter = FilterType.all;
  SortType _currentSort = SortType.importTimeDesc;
  bool _multiSelect = false;
  final Set<String> _selectedIds = {};

  @override
  void initState() {
    super.initState();
    // 加载书架数据
    _loadBookshelfItems();
  }

  // 加载书架数据
  void _loadBookshelfItems() async {
    final raw = await StorageService.loadShelf();
    final items = raw
        .map(
          (e) => BookshelfItem(
            id: e['id'],
            title: e['title'],
            author: e['author'],
            coverPath: e['coverPath'],
            filePath: e['filePath'],
            isNovel: e['isNovel'] == true,
            importTime:
                DateTime.tryParse(e['importTime'] ?? '') ?? DateTime.now(),
            creationTime: e['creationTime'] != null
                ? DateTime.tryParse(e['creationTime'])
                : null,
            authorSignature: e['authorSignature'],
            authorAvatarPath: e['authorAvatarPath'],
            authorDeviceId: e['authorDeviceId'],
            isComic: e['isComic'] == true,
            isRichNovel: e['isRichNovel'] == true,
          ),
        )
        .toList();
    if (mounted) {
      setState(() {
        _items = items;
        _applyFiltersAndSort();
      });
    }
  }

  // 应用筛选和排序
  void _applyFiltersAndSort() {
    List<BookshelfItem> filtered = _items;

    // 应用筛选
    switch (_currentFilter) {
      case FilterType.novels:
        filtered = filtered.where((item) => item.isNovel).toList();
        break;
      case FilterType.images:
        filtered = filtered.where((item) => !item.isNovel).toList();
        break;
      default:
        // 全部显示
        break;
    }

    // 应用排序
    switch (_currentSort) {
      case SortType.importTimeAsc:
        filtered.sort((a, b) => a.importTime.compareTo(b.importTime));
        break;
      case SortType.importTimeDesc:
        filtered.sort((a, b) => b.importTime.compareTo(a.importTime));
        break;
      case SortType.creationTimeAsc:
        filtered.sort((a, b) {
          if (a.creationTime == null || b.creationTime == null) return 0;
          return a.creationTime!.compareTo(b.creationTime!);
        });
        break;
      case SortType.creationTimeDesc:
        filtered.sort((a, b) {
          if (a.creationTime == null || b.creationTime == null) return 0;
          return b.creationTime!.compareTo(a.creationTime!);
        });
        break;
    }

    // 更新状态
    setState(() {
      // 在实际应用中，这里应该是更新显示列表，而不是原始数据
    });
  }

  // 切换筛选类型
  void _changeFilter(FilterType type) {
    setState(() {
      _currentFilter = type;
      _applyFiltersAndSort();
    });
  }

  // 切换排序类型
  void _changeSort(SortType type) {
    setState(() {
      _currentSort = type;
      _applyFiltersAndSort();
    });
  }

  // 处理项目点击
  void _onItemTap(BookshelfItem item) {
    if (item.isComic == true || item.isRichNovel == true) {
      _openEncryptedContainerDirect(item);
      return;
    }
    if (item.isNovel) {
      Navigator.push(
        context,
        MaterialPageRoute(builder: (context) => NovelDetailScreen(item: item)),
      );
    } else {
      Navigator.push(
        context,
        MaterialPageRoute(builder: (context) => ImagePreviewScreen(item: item)),
      );
    }
  }

  Future<void> _openEncryptedContainerDirect(BookshelfItem item) async {
    try {
      final pwd = await StorageService.getItemPassword(item.filePath) ?? '';
      String password = pwd;
      if (password.isEmpty) {
        if (!mounted) return;
        final input = await showDialog<String>(
          context: context,
          barrierDismissible: false,
          builder: (context) {
            final ctrl = TextEditingController();
            return AlertDialog(
              title: const Text('输入密码'),
              content: TextField(controller: ctrl, obscureText: true, decoration: const InputDecoration(labelText: '密码')),
              actions: [
                TextButton(onPressed: () => Navigator.pop(context), child: const Text('取消')),
                TextButton(onPressed: () => Navigator.pop(context, ctrl.text), child: const Text('确定')),
              ],
            );
          },
        );
        if (input == null || input.isEmpty) return;
        password = input;
      }

      final fileBytes = await File(item.filePath).readAsBytes();
      final controller = LoadingController(0);
      // 非阻塞加载对话框
      // ignore: discarded_futures
      if (!mounted) return;
      showLoadingDialog(context, controller: controller, label: '解密中');
      controller.set(0.1);
      final result = await widget.rustBridge.decryptFile(mxencData: fileBytes, password: password);
      controller.set(0.9);
      final decrypted = result.$2;

      if (item.isComic == true) {
        final packed = await compute(unpackComicEntry, decrypted);
        final manifest = packed['manifest'] as Map<String, dynamic>;
        final start = packed['start'] as int;
        if (mounted) {
          if (Navigator.canPop(context)) Navigator.pop(context);
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => ComicReaderScreen(
                manifest: manifest,
                payload: decrypted,
                start: start,
                sourcePath: item.filePath,
                password: password,
              ),
            ),
          );
        }
        return;
      }

      if (item.isRichNovel == true) {
        final packed = await compute(unpackRichEntry, decrypted);
        final manifest = packed['manifest'] as Map<String, dynamic>;
        final start = packed['start'] as int;
        if (mounted) {
          if (Navigator.canPop(context)) Navigator.pop(context);
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => RichReaderScreen(
                manifest: manifest,
                payload: decrypted,
                start: start,
                sourcePath: item.filePath,
                password: password,
              ),
            ),
          );
        }
        return;
      }

      if (mounted) {
        if (Navigator.canPop(context)) Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('无法识别的内容类型')));
      }
    } catch (e) {
      if (mounted) {
        if (Navigator.canPop(context)) Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('解密失败: $e')));
      }
    }
  }

  // 长按删除条目
  void _onItemLongPress(BookshelfItem item) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('删除条目'),
        content: const Text('确定删除该内容吗？此操作不可恢复。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await StorageService.removeShelfItem(item.id);
      _loadBookshelfItems();
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('已删除')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    List<BookshelfItem> displayItems = _items;

    // 根据当前筛选条件过滤项目
    switch (_currentFilter) {
      case FilterType.novels:
        displayItems = _items.where((item) => item.isNovel).toList();
        break;
      case FilterType.images:
        displayItems = _items.where((item) => !item.isNovel).toList();
        break;
      default:
        break;
    }

    // 根据当前排序条件排序项目
    displayItems.sort((a, b) {
      switch (_currentSort) {
        case SortType.importTimeAsc:
          return a.importTime.compareTo(b.importTime);
        case SortType.importTimeDesc:
          return b.importTime.compareTo(a.importTime);
        case SortType.creationTimeAsc:
          if (a.creationTime == null || b.creationTime == null) return 0;
          return a.creationTime!.compareTo(b.creationTime!);
        case SortType.creationTimeDesc:
          if (a.creationTime == null || b.creationTime == null) return 0;
          return b.creationTime!.compareTo(a.creationTime!);
      }
    });

    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: const Text('书架'),
        elevation: 0,
        scrolledUnderElevation: 1,
        actions: [
          IconButton(
            icon: Icon(_multiSelect ? Icons.close : Icons.more_vert),
            tooltip: _multiSelect ? '取消多选' : '多选',
            onPressed: () {
              setState(() {
                _multiSelect = !_multiSelect;
                if (!_multiSelect) _selectedIds.clear();
              });
            },
          ),
        ],
      ),
      body: Column(
        children: [
          // 筛选和排序栏
          _buildFilterSortBar(theme),
          // 内容区域
          Expanded(
            child: displayItems.isEmpty
                ? _buildEmptyState(theme)
                : _buildBooksGrid(displayItems, theme),
          ),
        ],
      ),
      floatingActionButton: _multiSelect && _selectedIds.isNotEmpty
          ? FloatingActionButton(
              onPressed: () async {
                for (final id in _selectedIds) {
                  await StorageService.removeShelfItem(id);
                }
                _loadBookshelfItems();
                setState(() {
                  _multiSelect = false;
                  _selectedIds.clear();
                });
              },
              tooltip: '删除选中',
              child: const Icon(Icons.delete),
            )
          : null,
    );
  }

  // 构建筛选和排序栏
  Widget _buildFilterSortBar(ThemeData theme) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        border: Border(
          bottom: BorderSide(
            color: theme.colorScheme.outline.withValues(alpha: 0.12),
            width: 1,
          ),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 筛选按钮组
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                _buildFilterChip('全部', FilterType.all, theme),
                const SizedBox(width: 8),
                _buildFilterChip('小说', FilterType.novels, theme),
                const SizedBox(width: 8),
                _buildFilterChip('图片', FilterType.images, theme),
              ],
            ),
          ),
          const SizedBox(height: 12),
          // 排序按钮组
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                _buildSortChip('导入时间↓', SortType.importTimeDesc, theme),
                const SizedBox(width: 8),
                _buildSortChip('导入时间↑', SortType.importTimeAsc, theme),
                const SizedBox(width: 8),
                _buildSortChip('创作时间↓', SortType.creationTimeDesc, theme),
                const SizedBox(width: 8),
                _buildSortChip('创作时间↑', SortType.creationTimeAsc, theme),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // 构建筛选 Chip
  Widget _buildFilterChip(String label, FilterType type, ThemeData theme) {
    final isSelected = _currentFilter == type;
    return FilterChip(
      label: Text(label),
      selected: isSelected,
      onSelected: (_) => _changeFilter(type),
      selectedColor: theme.colorScheme.primaryContainer,
      checkmarkColor: theme.colorScheme.onPrimaryContainer,
      labelStyle: TextStyle(
        color: isSelected
            ? theme.colorScheme.onPrimaryContainer
            : theme.colorScheme.onSurface,
        fontSize: 13,
        fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
      ),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: BorderSide(
          color: isSelected
              ? theme.colorScheme.primary
              : theme.colorScheme.outline.withValues(alpha: 0.12),
          width: isSelected ? 1.5 : 1,
        ),
      ),
    );
  }

  // 构建排序 Chip
  Widget _buildSortChip(String label, SortType type, ThemeData theme) {
    final isSelected = _currentSort == type;
    return FilterChip(
      label: Text(label),
      selected: isSelected,
      onSelected: (_) => _changeSort(type),
      selectedColor: theme.colorScheme.secondaryContainer,
      checkmarkColor: theme.colorScheme.onSecondaryContainer,
      labelStyle: TextStyle(
        color: isSelected
            ? theme.colorScheme.onSecondaryContainer
            : theme.colorScheme.onSurface,
        fontSize: 12,
        fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
      ),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(
          color: isSelected
              ? theme.colorScheme.secondary
              : theme.colorScheme.outline.withValues(alpha: 0.12),
          width: isSelected ? 1.5 : 1,
        ),
      ),
    );
  }

  // 构建书架网格
  Widget _buildBooksGrid(List<BookshelfItem> items, ThemeData theme) {
    return GridView.builder(
      padding: const EdgeInsets.all(16.0),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        crossAxisSpacing: 16.0,
        mainAxisSpacing: 16.0,
        childAspectRatio: 3 / 4,
      ),
      itemCount: items.length,
      itemBuilder: (context, index) {
        final item = items[index];
        return Stack(
          children: [
            _buildBookItem(item, theme),
            if (_multiSelect)
              Positioned(
                top: 8,
                left: 8,
                child: Checkbox(
                  value: _selectedIds.contains(item.id),
                  onChanged: (v) {
                    setState(() {
                      if (v == true) {
                        _selectedIds.add(item.id);
                      } else {
                        _selectedIds.remove(item.id);
                      }
                    });
                  },
                ),
              ),
          ],
        );
      },
    );
  }

  // 构建单个书籍/图片项目
  Widget _buildBookItem(BookshelfItem item, ThemeData theme) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () => _onItemTap(item),
        onLongPress: () => _onItemLongPress(item),
        borderRadius: BorderRadius.circular(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 封面图片
            Expanded(
              child: Stack(
                children: [
                  Container(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(12),
                      color: theme.colorScheme.surfaceContainerHighest,
                      boxShadow: [
                        BoxShadow(
                          color: theme.colorScheme.shadow.withValues(alpha: 0.1),
                          spreadRadius: 0,
                          blurRadius: 4,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: item.coverPath.startsWith('assets/')
                          ? Container(
                              color: theme.colorScheme.surfaceContainerHighest,
                              child: Center(
                                child: Icon(
                                  item.isNovel ? Icons.menu_book : Icons.image,
                                  size: 48,
                                  color: theme.colorScheme.onSurface.withValues(
                                    alpha: 0.3,
                                  ),
                                ),
                              ),
                            )
                          : (() {
                              try {
                                if (item.coverPath.startsWith('assets/')) {
                                  return Image.asset(
                                    item.coverPath,
                                    fit: BoxFit.cover,
                                    width: double.infinity,
                                    errorBuilder: (context, error, stackTrace) {
                                      return Center(
                                        child: Icon(
                                          item.isNovel
                                              ? Icons.menu_book
                                              : Icons.image,
                                          size: 48,
                                          color: theme.colorScheme.onSurface
                                              .withValues(alpha: 0.3),
                                        ),
                                      );
                                    },
                                  );
                                }
                                final file = File(item.coverPath);
                                if (file.existsSync()) {
                                  return Image.file(
                                    file,
                                    fit: BoxFit.cover,
                                    width: double.infinity,
                                    errorBuilder: (context, error, stackTrace) {
                                      return Center(
                                        child: Icon(
                                          item.isNovel
                                              ? Icons.menu_book
                                              : Icons.image,
                                          size: 48,
                                          color: theme.colorScheme.onSurface
                                              .withValues(alpha: 0.3),
                                        ),
                                      );
                                    },
                                  );
                                }
                              } catch (_) {}
                              return Center(
                                child: Icon(
                                  item.isNovel ? Icons.menu_book : Icons.image,
                                  size: 48,
                                  color: theme.colorScheme.onSurface.withValues(
                                    alpha: 0.3,
                                  ),
                                ),
                              );
                            })(),
                    ),
                  ),
                  // 类型标签
                  Positioned(
                    top: 8,
                    right: 8,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: item.isNovel
                            ? theme.colorScheme.primary
                            : theme.colorScheme.secondary,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        item.isNovel ? '小说' : '图片',
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w600,
                          color: item.isNovel
                              ? theme.colorScheme.onPrimary
                              : theme.colorScheme.onSecondary,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            // 标题和作者信息
            Padding(
              padding: const EdgeInsets.only(top: 8.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    item.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 4),
                  if (item.isNovel)
                    Text(
                      item.author,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurface.withValues(
                          alpha: 0.6,
                        ),
                      ),
                    )
                  else
                    Row(
                      children: [
                        ClipRRect(
                          borderRadius: BorderRadius.circular(10),
                          child: SizedBox(
                            width: 20,
                            height: 20,
                            child: (() {
                              final path = (item.authorAvatarPath ?? '')
                                  .toString();
                              if (path.isNotEmpty &&
                                  path.startsWith('assets/')) {
                                return Image.asset(path, fit: BoxFit.cover);
                              }
                              try {
                                if (path.isNotEmpty) {
                                  final f = File(path);
                                  if (f.existsSync()) {
                                    return Image.file(f, fit: BoxFit.cover);
                                  }
                                }
                              } catch (_) {}
                              return Image.asset(
                                'assets/default_avatar.jpg',
                                fit: BoxFit.cover,
                              );
                            })(),
                          ),
                        ),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                item.author,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: theme.textTheme.bodySmall?.copyWith(
                                  fontWeight: FontWeight.w600,
                                  color: theme.colorScheme.onSurface,
                                ),
                              ),
                              if ((item.authorSignature ?? '').isNotEmpty)
                                Text(
                                  item.authorSignature!,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: theme.textTheme.bodySmall?.copyWith(
                                    color: theme.colorScheme.onSurface
                                        .withValues(alpha: 0.6),
                                    fontSize: 11,
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
      ),
    );
  }

  // 构建空状态
  Widget _buildEmptyState(ThemeData theme) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: theme.colorScheme.surfaceContainerHighest,
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.library_books_outlined,
                size: 64,
                color: theme.colorScheme.onSurface.withValues(alpha: 0.4),
              ),
            ),
            const SizedBox(height: 24),
            Text(
              '书架空空如也',
              style: theme.textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.w600,
                color: theme.colorScheme.onSurface,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              '解密文件后点击「保存到书架」添加内容',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 32),
            FilledButton.icon(
              onPressed: () {
                // 导航到解密页面
                Navigator.pushNamed(context, '/decrypt');
              },
              icon: const Icon(Icons.lock_open),
              label: const Text('去解密'),
              style: FilledButton.styleFrom(
                padding: const EdgeInsets.symmetric(
                  horizontal: 24,
                  vertical: 12,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
