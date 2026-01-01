import 'package:file_picker/file_picker.dart';
import '../utils/mxenc_dart.dart';
import 'package:flutter/material.dart';
import 'dart:async';
import 'dart:io';
import '../../rust_bridge.dart';
// import 'novel_detail_screen.dart';
// import 'image_preview_screen.dart';
// import 'viewer_screen.dart';
// import '../models/novel.dart';
import '../utils/storage_service.dart';
import 'package:flutter/foundation.dart';
import 'comic_detail_screen.dart';
import 'rich_detail_screen.dart';
import 'series_detail_screen.dart';
import '../widgets/loading_dialog.dart';
// import '../utils/progress.dart';
// import 'dart:typed_data';

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
  final List<String> tags;
  final bool isSeries; // 是否为文件夹系列

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
    this.tags = const [],
    this.isSeries = false,
  });
}

// 筛选类型枚举
enum FilterType { all, novels, images, series }

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
  
  // 搜索相关
  bool _isSearching = false;
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';
  bool _isLoading = true;
  
  StreamSubscription? _shelfSubscription;

  @override
  void initState() {
    super.initState();
    // 加载书架数据
    _loadBookshelfItems();
    // 监听书架变更
    _shelfSubscription = StorageService.onShelfChanged.listen((_) {
      _loadBookshelfItems();
    });
  }
  
  @override
  void dispose() {
    _shelfSubscription?.cancel();
    _searchController.dispose();
    super.dispose();
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
            isSeries: e['isSeries'] == true,
            tags:
                (e['tags'] as List?)?.map((e) => e.toString()).toList() ?? [],
          ),
        )
        .toList();
    if (mounted) {
      setState(() {
        _items = items;
        _isLoading = false;
        _applyFiltersAndSort();
      });
    }
  }

  // 应用筛选和排序
  void _applyFiltersAndSort() {
    List<BookshelfItem> filtered = _items;

    // 应用搜索
    if (_searchQuery.isNotEmpty) {
      final query = _searchQuery.toLowerCase();
      filtered = filtered.where((item) {
        // 搜索标签
        if (item.tags.any((tag) => tag.toLowerCase().contains(query))) {
          return true;
        }
        // 搜索标题和作者
        if (item.title.toLowerCase().contains(query)) return true;
        if (item.author.toLowerCase().contains(query)) return true;
        return false;
      }).toList();
    }

    // 应用筛选
    switch (_currentFilter) {
      case FilterType.novels:
        // 包含旧版小说和新版富文本小说
        filtered = filtered.where((item) => (item.isNovel || item.isRichNovel == true) && !item.isSeries).toList();
        break;
      case FilterType.images:
        // 排除旧版小说和富文本小说
        filtered = filtered.where((item) => !item.isNovel && item.isRichNovel != true && !item.isSeries).toList();
        break;
      case FilterType.series:
        filtered = filtered.where((item) => item.isSeries).toList();
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
  Future<void> _onItemTap(BookshelfItem item) async {
    if (item.isSeries) {
      // 导航到系列详情页
      await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => SeriesDetailScreen(
            item: item,
            rustBridge: widget.rustBridge,
          ),
        ),
      );
      _loadBookshelfItems();
      return;
    }

    if (item.isNovel) {
      // 尝试自动修复：如果是 RichNovel 被误标为 Novel，尝试解密并打开
      // 先尝试解密
      final result = await _decryptWithRetry(item);
      if (result != null) {
        final (decrypted, password) = result;
        try {
          // 尝试解析为 RichNovel
          final packed = await compute(unpackRichEntry, decrypted);
          if (packed['manifest'] != null) {
             // 确实是 RichNovel，修复元数据
             final updatedItem = {
               'id': item.id,
               'title': item.title,
               'author': item.author,
               'coverPath': item.coverPath,
               'filePath': item.filePath,
               'isNovel': false,
               'isRichNovel': true,
               'importTime': item.importTime.toIso8601String(),
               'creationTime': item.creationTime?.toIso8601String(),
               'authorSignature': item.authorSignature,
               'authorAvatarPath': item.authorAvatarPath,
               'authorDeviceId': item.authorDeviceId,
               'tags': item.tags,
             };
             
             // 保存修复后的元数据
             await StorageService.saveShelfItem(updatedItem, password: password);
             
             // 刷新列表（可选，因为马上要跳走了）
             _loadBookshelfItems();
             
             // 打开详情页
             if (!mounted) return;
             final manifest = packed['manifest'] as Map<String, dynamic>;
             final start = packed['start'] as int;
             await Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => RichDetailScreen(
                    manifest: manifest,
                    payload: decrypted,
                    start: start,
                    sourcePath: item.filePath,
                    password: password,
                    fromShelf: true,
                    itemId: item.id,
                  ),
                ),
             );
             return;
          }
        } catch (_) {
          // 解析失败，不是 RichNovel，继续报错
        }
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('该格式已弃用，无法打开')),
        );
      }
      return;
    } else {
      await _openEncryptedContainerDirect(item);
    }
  }

  Future<(Uint8List, String)?> _decryptWithRetry(BookshelfItem item) async {
    String password = await StorageService.getItemPassword(item.filePath) ?? '';
    bool isFirstAttempt = true;

    while (true) {
      final controller = LoadingController(0);
      if (!mounted) return null;
      showLoadingDialog(context, controller: controller, label: '解密中');
      controller.set(0.05);

      try {
        final stream = widget.rustBridge.decryptFileByPathWithProgress(
          inputPath: item.filePath,
          password: password,
        );
        Uint8List? decrypted;
        await for (final ev in stream) {
          controller.set(ev.percent);
          if (ev.phase == ProgressPhase.done && ev.data != null) {
            decrypted = ev.data!;
          }
        }

        if (mounted && Navigator.canPop(context)) Navigator.pop(context);

        if (decrypted != null) {
          return (decrypted, password);
        } else {
          throw Exception('解密失败：无数据');
        }
      } catch (e) {
        if (mounted && Navigator.canPop(context)) Navigator.pop(context);

        if (!mounted) return null;

        final input = await showDialog<String>(
          context: context,
          barrierDismissible: false,
          builder: (context) {
            final ctrl = TextEditingController();
            return AlertDialog(
              title: const Text('输入密码'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (!isFirstAttempt || password.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8.0),
                      child: Text(
                        '解密失败，请检查密码',
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.error,
                          fontSize: 12,
                        ),
                      ),
                    ),
                  TextField(
                    controller: ctrl,
                    obscureText: true,
                    autofocus: true,
                    decoration: const InputDecoration(
                      labelText: '密码',
                      border: OutlineInputBorder(),
                    ),
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('取消'),
                ),
                TextButton(
                  onPressed: () => Navigator.pop(context, ctrl.text),
                  child: const Text('确定'),
                ),
              ],
            );
          },
        );

        if (input == null) return null;
        password = input;
        isFirstAttempt = false;
      }
    }
  }

  Future<void> _openEncryptedContainerDirect(BookshelfItem item) async {
    final result = await _decryptWithRetry(item);
    if (result == null) return;
    final (decrypted, password) = result;

    // 解密成功，保存密码
    await StorageService.saveItemPassword(item.filePath, password);

    if (item.isComic == true) {
      final Uint8List data = decrypted;
      final packed = await compute(unpackComicEntry, data);
      final manifest = packed['manifest'] as Map<String, dynamic>;
      final start = packed['start'] as int;
      if (mounted) {
        await Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => ComicDetailScreen(
              manifest: manifest,
              payload: data,
              start: start,
              sourcePath: item.filePath,
              password: password,
              fromShelf: true,
              itemId: item.id,
            ),
          ),
        );
        _loadBookshelfItems();
      }
      return;
    }

    if (item.isRichNovel == true) {
      final Uint8List data = decrypted;
      final packed = await compute(unpackRichEntry, data);
      final manifest = packed['manifest'] as Map<String, dynamic>;
      final start = packed['start'] as int;
      if (mounted) {
        await Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => RichDetailScreen(
              manifest: manifest,
              payload: data,
              start: start,
              sourcePath: item.filePath,
              password: password,
              fromShelf: true,
              itemId: item.id,
            ),
          ),
        );
        _loadBookshelfItems();
      }
      return;
    }

    if (mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('无法识别的内容类型')));
    }
  }

  // 长按删除条目或移动到系列
  void _onItemLongPress(BookshelfItem item) async {
    final theme = Theme.of(context);
    final action = await showModalBottomSheet<String>(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (!item.isSeries) ...[
              ListTile(
                leading: const Icon(Icons.drive_file_move_outline),
                title: const Text('移动到文件夹'),
                onTap: () => Navigator.pop(context, 'move'),
              ),
              ListTile(
                leading: const Icon(Icons.file_copy_outlined),
                title: const Text('复制到文件夹'),
                onTap: () => Navigator.pop(context, 'copy'),
              ),
            ],
            ListTile(
              leading: Icon(Icons.delete_outline, color: theme.colorScheme.error),
              title: Text(
                '删除',
                style: TextStyle(color: theme.colorScheme.error),
              ),
              onTap: () => Navigator.pop(context, 'delete'),
            ),
          ],
        ),
      ),
    );

    if (action == 'delete') {
      if (!mounted) return;
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('删除条目'),
          content: Text('确定删除 "${item.title}" 吗？此操作不可恢复。'),
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
    } else if (action == 'move') {
      // 移动逻辑
      await _showMoveToFolderDialog([item], isCopy: false);
    } else if (action == 'copy') {
      // 复制逻辑
      await _showMoveToFolderDialog([item], isCopy: true);
    }
  }

  Future<void> _showMoveToFolderDialog(List<BookshelfItem> items, {required bool isCopy}) async {
    // 筛选出所有文件夹（系列）
    final seriesItems = _items.where((e) => e.isSeries).toList();
    
    if (seriesItems.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('没有可用的文件夹，请先创建一个')),
        );
      }
      return;
    }

    await showModalBottomSheet(
      context: context,
      builder: (sheetCtx) {
        return Column(
          children: [
            const Padding(
              padding: EdgeInsets.all(16.0),
              child: Text('选择目标文件夹', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            ),
            Expanded(
              child: ListView.builder(
                itemCount: seriesItems.length,
                itemBuilder: (ctx, index) {
                  final s = seriesItems[index];
                  return ListTile(
                    leading: const Icon(Icons.folder),
                    title: Text(s.title),
                    onTap: () async {
                      Navigator.pop(sheetCtx);
                      try {
                        for (final item in items) {
                          if (isCopy) {
                            await StorageService.copyItemToSeries(item.id, s.id);
                          } else {
                            await StorageService.moveItemToSeries(item.id, s.id);
                          }
                        }
                        _loadBookshelfItems();
                        if (mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text(
                                isCopy
                                    ? '已复制到 "${s.title}"'
                                    : '已移动到 "${s.title}"',
                              ),
                            ),
                          );
                        }
                      } catch (e) {
                        if (mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(content: Text('${isCopy ? '复制' : '移动'}失败: $e')),
                          );
                        }
                      }
                    },
                  );
                },
              ),
            ),
          ],
        );
      },
    );
  }

  // 创建新文件夹
  Future<void> _createNewFolder() async {
    final controller = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('新建文件夹'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(
            labelText: '文件夹名称',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, controller.text),
            child: const Text('创建'),
          ),
        ],
      ),
    );

    if (name != null && name.trim().isNotEmpty) {
      try {
        await StorageService.createSeries(name.trim());
        _loadBookshelfItems();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('文件夹已创建')),
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('创建失败: $e')),
          );
        }
      }
    }
  }

  Future<void> _importSeries() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['mxzip'],
    );
    if (result == null || result.files.isEmpty) return;
    
    final path = result.files.single.path;
    if (path == null) return;

    final controller = LoadingController(0);
    if (!mounted) return;
    showLoadingDialog(context, controller: controller, label: '正在导入...');
    
    try {
      await StorageService.importSeriesFromZip(path);
      if (mounted) Navigator.pop(context);
      _loadBookshelfItems();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('导入成功')));
      }
    } on SeriesImportException catch (e) {
      if (mounted) Navigator.pop(context); // Close loading
      
      if (e.type == 'password_required' || e.type == 'invalid_password') {
        // Prompt for password
        String? password;
        bool isFirst = e.type == 'password_required';
        while (true) {
          if (!mounted) return;
          final input = await showDialog<String>(
            context: context,
            builder: (context) {
              final ctrl = TextEditingController();
              return AlertDialog(
                title: const Text('输入系列密码'),
                content: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (!isFirst) 
                      Text('密码错误，请重试', style: TextStyle(color: Theme.of(context).colorScheme.error)),
                    TextField(
                      controller: ctrl,
                      obscureText: true,
                      autofocus: true,
                      decoration: const InputDecoration(labelText: '密码'),
                    ),
                  ],
                ),
                actions: [
                  TextButton(onPressed: () => Navigator.pop(context), child: const Text('取消')),
                  TextButton(onPressed: () => Navigator.pop(context, ctrl.text), child: const Text('确定')),
                ],
              );
            },
          );
          
          if (input == null) return; // Cancelled
          password = input;
          
          // Retry import
          if (!mounted) return;
          showLoadingDialog(context, controller: controller, label: '正在导入...');
          try {
            await StorageService.importSeriesFromZip(path, password: password);
            if (mounted) Navigator.pop(context);
            _loadBookshelfItems();
             if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('导入成功')));
             }
            return;
          } on SeriesImportException catch (retryE) {
            if (mounted) Navigator.pop(context);
            if (retryE.type == 'invalid_password') {
              isFirst = false;
              continue;
            } else {
               // Other error
               if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('导入失败: $retryE')));
               }
               return;
            }
          } catch (otherE) {
             if (mounted) Navigator.pop(context);
             if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('导入失败: $otherE')));
             }
             return;
          }
        }
      }
    } catch (e) {
      if (mounted) Navigator.pop(context);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('导入失败: $e')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    List<BookshelfItem> displayItems = _items;

    // 应用搜索
    if (_searchQuery.isNotEmpty) {
      final query = _searchQuery.toLowerCase();
      displayItems = displayItems.where((item) {
        // 搜索标签
        if (item.tags.any((tag) => tag.toLowerCase().contains(query))) {
          return true;
        }
        // 搜索标题和作者
        if (item.title.toLowerCase().contains(query)) return true;
        if (item.author.toLowerCase().contains(query)) return true;
        return false;
      }).toList();
    }

    // 根据当前筛选条件过滤项目
    switch (_currentFilter) {
      case FilterType.novels:
        displayItems = displayItems.where((item) => item.isNovel).toList();
        break;
      case FilterType.images:
        displayItems = displayItems.where((item) => !item.isNovel).toList();
        break;
      case FilterType.series:
        displayItems = displayItems.where((item) => item.isSeries).toList();
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
        title: _isSearching
            ? TextField(
                controller: _searchController,
                autofocus: true,
                style: theme.textTheme.titleMedium,
                decoration: InputDecoration(
                  hintText: '搜索标签、标题或作者',
                  border: InputBorder.none,
                  hintStyle: theme.textTheme.titleMedium?.copyWith(
                    color: theme.colorScheme.onSurface.withValues(alpha: 0.5),
                  ),
                ),
                onChanged: (value) {
                  setState(() {
                    _searchQuery = value;
                    _applyFiltersAndSort();
                  });
                },
              )
            : const Text('书架'),
        elevation: 0,
        scrolledUnderElevation: 1,
        actions: [
          if (_isSearching)
            IconButton(
              icon: const Icon(Icons.close),
              tooltip: '关闭搜索',
              onPressed: () {
                setState(() {
                  _isSearching = false;
                  _searchQuery = '';
                  _searchController.clear();
                  _applyFiltersAndSort();
                });
              },
            )
          else
            IconButton(
              icon: const Icon(Icons.search),
              tooltip: '搜索',
              onPressed: () {
                setState(() {
                  _isSearching = true;
                });
              },
            ),
          IconButton(
            icon: Icon(_multiSelect ? Icons.close : Icons.checklist),
            tooltip: _multiSelect ? '取消多选' : '多选',
            onPressed: () {
              setState(() {
                _multiSelect = !_multiSelect;
                if (!_multiSelect) _selectedIds.clear();
              });
            },
          ),
          PopupMenuButton<String>(
            onSelected: (v) {
              if (v == 'new_folder') {
                _createNewFolder();
              } else if (v == 'import_series') {
                _importSeries();
              }
            },
            itemBuilder: (context) => [
              const PopupMenuItem(
                value: 'new_folder',
                child: Row(
                  children: [
                    Icon(Icons.create_new_folder_outlined),
                    SizedBox(width: 8),
                    Text('新建文件夹'),
                  ],
                ),
              ),
              const PopupMenuItem(
                value: 'import_series',
                child: Row(
                  children: [
                    Icon(Icons.folder_zip_outlined),
                    SizedBox(width: 8),
                    Text('导入系列 (.mxzip)'),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
      body: Column(
        children: [
          // 筛选和排序栏
          _buildFilterSortBar(theme),
          // 内容区域
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : displayItems.isEmpty
                    ? _buildEmptyState(theme)
                    : _buildBooksGrid(displayItems, theme),
          ),
        ],
      ),
      floatingActionButton: null,
      bottomNavigationBar: _multiSelect && _selectedIds.isNotEmpty
          ? BottomAppBar(
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  IconButton(
                    icon: const Icon(Icons.drive_file_move_outline),
                    tooltip: '移动到文件夹',
                    onPressed: () {
                      final items = _items.where((e) => _selectedIds.contains(e.id)).toList();
                      _showMoveToFolderDialog(items, isCopy: false);
                    },
                  ),
                  IconButton(
                    icon: const Icon(Icons.file_copy_outlined),
                    tooltip: '复制到文件夹',
                    onPressed: () {
                      final items = _items.where((e) => _selectedIds.contains(e.id)).toList();
                      _showMoveToFolderDialog(items, isCopy: true);
                    },
                  ),
                  IconButton(
                    icon: const Icon(Icons.delete_outline),
                    color: theme.colorScheme.error,
                    tooltip: '删除选中',
                    onPressed: () async {
                      final confirmed = await showDialog<bool>(
                        context: context,
                        builder: (context) => AlertDialog(
                          title: const Text('删除选中'),
                          content: Text('确定删除选中的 ${_selectedIds.length} 个项目吗？此操作不可恢复。'),
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
                        for (final id in _selectedIds) {
                          await StorageService.removeShelfItem(id);
                        }
                        _loadBookshelfItems();
                        setState(() {
                          _multiSelect = false;
                          _selectedIds.clear();
                        });
                      }
                    },
                  ),
                ],
              ),
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
                const SizedBox(width: 8),
                _buildFilterChip('系列', FilterType.series, theme),
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
      padding: const EdgeInsets.fromLTRB(16.0, 16.0, 16.0, 80.0),
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
                          color: theme.colorScheme.shadow.withValues(
                            alpha: 0.1,
                          ),
                          spreadRadius: 0,
                          blurRadius: 4,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: item.isSeries
                          ? Container(
                              color: theme.colorScheme.tertiaryContainer,
                              child: Center(
                                child: Icon(
                                  Icons.folder,
                                  size: 64,
                                  color: theme.colorScheme.onTertiaryContainer,
                                ),
                              ),
                            )
                          : item.coverPath.startsWith('assets/')
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
                        color: item.isSeries
                            ? theme.colorScheme.tertiary
                            : (item.isNovel
                                ? theme.colorScheme.primary
                                : theme.colorScheme.secondary),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        item.isSeries
                            ? '系列'
                            : (item.isNovel ? '小说' : '图片'),
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w600,
                          color: item.isSeries
                              ? theme.colorScheme.onTertiary
                              : (item.isNovel
                                  ? theme.colorScheme.onPrimary
                                  : theme.colorScheme.onSecondary),
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
                            if (path.isNotEmpty && path.startsWith('assets/')) {
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
              onPressed: () async {
                // 导航到解密页面
                await Navigator.pushNamed(context, '/decrypt');
                _loadBookshelfItems();
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
