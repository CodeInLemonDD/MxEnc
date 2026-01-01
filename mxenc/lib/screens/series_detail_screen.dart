import 'package:flutter/material.dart';
import 'package:path/path.dart' as path;
import 'dart:io';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:file_picker/file_picker.dart';
import '../models/series.dart';
import 'bookshelf_screen.dart';
import '../utils/storage_service.dart';
import '../rust_bridge.dart';
import '../widgets/loading_dialog.dart';
// import 'viewer_screen.dart';
import 'comic_detail_screen.dart';
// import 'novel_detail_screen.dart';
import 'rich_detail_screen.dart';
// import '../models/novel.dart';
import '../utils/mxenc_dart.dart';
import 'package:share_plus/share_plus.dart';
import 'cover_editor_screen.dart';

class SeriesDetailScreen extends StatefulWidget {
  final BookshelfItem item;
  final RustBridge rustBridge;

  const SeriesDetailScreen({
    super.key,
    required this.item,
    required this.rustBridge,
  });

  @override
  State<SeriesDetailScreen> createState() => _SeriesDetailScreenState();
}

class _SeriesDetailScreenState extends State<SeriesDetailScreen> {
  SeriesMetadata? _metadata;
  bool _isLoading = true;
  // bool _isEditing = false;
  @override
  void initState() {
    super.initState();
    _loadMetadata();
  }

  Future<void> _loadMetadata() async {
    try {
      final metaFile = File(path.join(widget.item.filePath, 'series.json'));
      if (await metaFile.exists()) {
        final json = jsonDecode(await metaFile.readAsString());
        setState(() {
          _metadata = SeriesMetadata.fromJson(json);
          _isLoading = false;
        });
      } else {
        // 如果没有 series.json，尝试自动生成（针对空文件夹或手动放入的情况）
        setState(() {
          _metadata = SeriesMetadata(
            id: widget.item.id,
            title: widget.item.title,
            author: widget.item.author,
            coverPath: '',
            volumes: [],
            passwords: {},
          );
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint('Load series metadata failed: $e');
      setState(() {
        _isLoading = false;
      });
    }
  }

  Future<void> _openVolume(SeriesVolume volume) async {
    final fullPath = path.join(widget.item.filePath, volume.filename);
    if (!await File(fullPath).exists()) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('文件不存在')),
        );
      }
      return;
    }

    // 尝试获取密码
    String? password = _metadata?.passwords[volume.id];
    
    // 如果没有内部密码，尝试从全局密码库获取
    password ??= await StorageService.getItemPassword(fullPath);

    if (password != null) {
      // 尝试自动解密
      await _decryptAndOpen(fullPath, password, volume.id);
    } else {
      // 需要输入密码
      if (!mounted) return;
      final input = await showDialog<String>(
        context: context,
        builder: (context) {
          final ctrl = TextEditingController();
          return AlertDialog(
            title: const Text('输入密码'),
            content: TextField(
              controller: ctrl,
              obscureText: true,
              autofocus: true,
              decoration: const InputDecoration(
                labelText: '密码',
                border: OutlineInputBorder(),
              ),
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

      if (input != null && input.isNotEmpty) {
        await _decryptAndOpen(fullPath, input, volume.id);
      }
    }
  }

  Future<void> _decryptAndOpen(String filePath, String password, String volumeId) async {
    final controller = LoadingController(0);
    showLoadingDialog(context, controller: controller, label: '解密中');
    controller.set(0.1);

    try {
      final stream = widget.rustBridge.decryptFileByPathWithProgress(
        inputPath: filePath,
        password: password,
      );
      
      Uint8List? decrypted;
      String? filename;
      
      await for (final ev in stream) {
        controller.set(ev.percent);
        if (ev.phase == ProgressPhase.done && ev.data != null) {
          decrypted = ev.data!;
          filename = ev.filename;
        }
      }

      if (mounted && Navigator.canPop(context)) Navigator.pop(context);

      if (decrypted == null) {
        throw Exception('解密失败');
      }

      // 保存密码
      if (_metadata != null) {
        _metadata!.passwords[volumeId] = password;
        final metaFile = File(path.join(widget.item.filePath, 'series.json'));
        await metaFile.writeAsString(jsonEncode(_metadata!.toJson()));
      }

      // 智能识别并打开
      await _dispatchContent(decrypted, filename ?? 'unknown', filePath, password);

    } catch (e) {
      if (mounted && Navigator.canPop(context)) Navigator.pop(context);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('打开失败: $e')),
        );
      }
    }
  }

  Future<void> _dispatchContent(Uint8List decrypted, String filename, String filePath, String password) async {
    if (!mounted) return;

    final ext = path.extension(filename).toLowerCase();
    
    // Helper to open Rich Novel
    Future<bool> tryOpenRich() async {
      try {
        final packed = await compute(unpackRichEntry, decrypted);
        if (packed['manifest'] != null && packed['start'] != null) {
          final manifest = packed['manifest'] as Map<String, dynamic>;
          final start = packed['start'] as int;
          if (!mounted) return true;
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => RichDetailScreen(
                manifest: manifest,
                payload: decrypted,
                start: start,
                sourcePath: filePath,
                password: password,
                fromShelf: true, // Hide add to shelf button
              ),
            ),
          );
          return true;
        }
      } catch (_) {}
      return false;
    }

    // Helper to open Comic
    Future<bool> tryOpenComic() async {
      try {
        final packed = await compute(unpackComicEntry, decrypted);
        if (packed['manifest'] != null && packed['start'] != null) {
          final manifest = packed['manifest'] as Map<String, dynamic>;
          final start = packed['start'] as int;
          if (!mounted) return true;
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => ComicDetailScreen(
                manifest: manifest,
                payload: decrypted,
                start: start,
                sourcePath: filePath,
                password: password,
                fromShelf: true, // Hide add to shelf button
              ),
            ),
          );
          return true;
        }
      } catch (_) {}
      return false;
    }

    // Dispatch based on extension hint
    if (ext == '.comic' || ext == '.mxenc') {
       if (await tryOpenComic()) return;
       if (await tryOpenRich()) return;
    } else {
       // Default order or try both
       // Since user reported comic opened as rich, we prioritize comic if ambiguous?
       // Or strictly check extension?
       // Let's try Comic first if extension is not explicitly rich
       if (await tryOpenComic()) return;
       if (await tryOpenRich()) return;
    }

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('无法识别的文件类型')),
      );
    }
  }

  Future<void> _exportSeries() async {
    // 1. Ask for password (optional)
    final password = await showDialog<String>(
      context: context,
      builder: (context) {
        final ctrl = TextEditingController();
        return AlertDialog(
          title: const Text('导出系列'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('设置密码以保护所有分卷密码（可选）。\n如果留空，导出包将不包含密码，接收者需手动输入各分卷密码。'),
              const SizedBox(height: 16),
              TextField(
                controller: ctrl,
                obscureText: true,
                autofocus: true,
                decoration: const InputDecoration(
                  labelText: '保护密码 (可选)',
                  border: OutlineInputBorder(),
                  helperText: '留空则不加密密码库',
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
              child: const Text('导出'),
            ),
          ],
        );
      },
    );

    if (password == null) return; 
    
    final controller = LoadingController(0);
    if (!mounted) return;
    showLoadingDialog(context, controller: controller, label: '正在打包...');
    
    try {
      final zipPath = await StorageService.exportSeriesToZip(
        widget.item.id,
        password: password.isEmpty ? null : password,
      );
      
      if (mounted) Navigator.pop(context); // Close loading
      
      if (mounted) {
         if (Platform.isWindows) {
            showDialog(
              context: context,
              builder: (context) => AlertDialog(
                title: const Text('导出成功'),
                content: Text('文件已保存至:\n$zipPath'),
                actions: [
                   TextButton(
                     onPressed: () {
                       Process.run('explorer.exe', ['/select,', zipPath]);
                       Navigator.pop(context);
                     },
                     child: const Text('打开位置'),
                   ),
                   TextButton(
                     onPressed: () => Navigator.pop(context),
                     child: const Text('关闭'),
                   ),
                ],
              ),
            );
         } else {
            // Android: Share
            // await Share.shareXFiles([XFile(zipPath)], text: '分享系列: ${_metadata?.title}');
            // Use new SharePlus API
            await SharePlus.instance.share(
              ShareParams(
                files: [XFile(zipPath)], 
                text: '分享系列: ${_metadata?.title}',
              ),
            );
         }
      }
    } catch (e) {
      if (mounted) Navigator.pop(context);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('导出失败: $e')),
        );
      }
    }
  }

  // 处理排序
  void _onReorder(int oldIndex, int newIndex) {
    setState(() {
      if (newIndex > oldIndex) {
        newIndex -= 1;
      }
      final item = _metadata!.volumes.removeAt(oldIndex);
      _metadata!.volumes.insert(newIndex, item);
    });

    // 保存到存储
    if (_metadata != null) {
      StorageService.updateSeriesVolumes(widget.item.id, _metadata!.volumes);
    }
  }

  // 处理封面点击
  Future<void> _onChangeCover() async {
    final picker = FilePicker.platform;
    final result = await picker.pickFiles(
      type: FileType.image,
    );

    if (result != null && result.files.isNotEmpty && result.files.single.path != null) {
      if (!mounted) return;
      
      // 跳转到裁剪页面
      final croppedBytes = await Navigator.push<Uint8List>(
        context,
        MaterialPageRoute(
          builder: (context) => CoverEditorScreen(
            sourceFile: File(result.files.single.path!),
          ),
        ),
      );

      if (croppedBytes == null) return; // 用户取消裁剪

      try {
        // 保存封面到系列目录
        final coverName = 'cover.jpg';
        final targetPath = path.join(widget.item.filePath, coverName);
        await File(targetPath).writeAsBytes(croppedBytes);
        
        // 更新 meta
        if (_metadata != null) {
           _metadata = _metadata!.copyWith(coverPath: coverName); // 相对路径
           final metaFile = File(path.join(widget.item.filePath, 'series.json'));
           await metaFile.writeAsString(jsonEncode(_metadata!.toJson()));
        }

        // 更新书架数据
        // 需要 StorageService 提供更新方法，或者我们手动读写
        // 这里我们可以通过 StorageService.saveShelfItem 来更新，但需要小心覆盖
        // 更简单的是：系列封面在书架中如果不是 assets，就是绝对路径
        final shelfItem = {
           'id': widget.item.id,
           'title': widget.item.title,
           'author': widget.item.author,
           'coverPath': targetPath, // 绝对路径
           'filePath': widget.item.filePath,
           'isNovel': widget.item.isNovel,
           'isSeries': true,
           'importTime': widget.item.importTime.toIso8601String(),
           'creationTime': widget.item.creationTime?.toIso8601String(),
           'tags': widget.item.tags,
        };
        await StorageService.saveShelfItem(shelfItem); // 会自动处理更新

        if (mounted) {
           setState(() {}); // 触发重绘
           ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('封面已更新')));
        }
      } catch (e) {
         if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('更新封面失败: $e')));
         }
      }
    }
  }

  Future<void> _deleteVolume(SeriesVolume volume) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('删除分卷'),
        content: Text('确定要删除 "${volume.title}" 吗？此操作不可撤销。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(
              foregroundColor: Theme.of(context).colorScheme.error,
            ),
            child: const Text('删除'),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    setState(() {
      _isLoading = true;
    });

    try {
      await StorageService.deleteVolumeFromSeries(widget.item.id, volume.id);
      
      setState(() {
        _metadata!.volumes.removeWhere((v) => v.id == volume.id);
        _isLoading = false;
      });
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('已删除')),
        );
      }
    } catch (e) {
      setState(() {
        _isLoading = false;
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('删除失败: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    
    // 获取当前封面路径
    // 优先使用 widget.item.coverPath，但如果我们在本页更新了，可能需要重新获取
    // 由于 saveShelfItem 会更新存储，但不会更新 widget.item
    // 我们可以依赖一个本地状态来显示，或者重新加载 item
    // 简单起见，我们检查本地目录是否有 cover.jpg
    String displayCoverPath = widget.item.coverPath;
    final localCover = File(path.join(widget.item.filePath, 'cover.jpg'));
    if (localCover.existsSync()) {
       displayCoverPath = localCover.path;
    }

    return Scaffold(
      body: NestedScrollView(
        headerSliverBuilder: (context, innerBoxIsScrolled) {
          return [
            SliverAppBar(
              expandedHeight: 200.0,
              floating: false,
              pinned: true,
              actions: [
                IconButton(
                  icon: const Icon(Icons.image),
                  tooltip: '设置封面',
                  onPressed: _onChangeCover,
                ),
                IconButton(
                  icon: const Icon(Icons.download),
                  tooltip: '导出为 .mxzip',
                  onPressed: _exportSeries,
                ),
                IconButton(
                  icon: const Icon(Icons.info_outline),
                  tooltip: '系列信息',
                  onPressed: () {
                    // 显示系列信息
                    showDialog(
                      context: context,
                      builder: (context) => AlertDialog(
                        title: Text(_metadata?.title ?? '未知系列'),
                        content: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('作者: ${_metadata?.author ?? '未知'}'),
                            const SizedBox(height: 8),
                            Text('包含卷数: ${_metadata?.volumes.length ?? 0}'),
                            const SizedBox(height: 8),
                            Text('ID: ${widget.item.id}'),
                          ],
                        ),
                        actions: [
                          TextButton(
                            onPressed: () => Navigator.pop(context),
                            child: const Text('关闭'),
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ],
              flexibleSpace: FlexibleSpaceBar(
                title: Text(
                  widget.item.title,
                  style: TextStyle(
                    color: theme.colorScheme.onSurface,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                centerTitle: true,
                background: Stack(
                  fit: StackFit.expand,
                  children: [
                    // 背景模糊图
                    if (displayCoverPath.isNotEmpty && !displayCoverPath.startsWith('assets/'))
                      Image.file(
                        File(displayCoverPath),
                        fit: BoxFit.cover,
                        opacity: const AlwaysStoppedAnimation(0.3),
                      )
                    else
                      Container(color: theme.colorScheme.surfaceContainerHighest),
                    
                    // 渐变遮罩
                    DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [
                            Colors.transparent,
                            theme.colorScheme.surface.withValues(alpha: 0.8),
                            theme.colorScheme.surface,
                          ],
                        ),
                      ),
                    ),
                    
                    // 信息展示
                    Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const SizedBox(height: 40), // 避开 AppBar
                          // 封面
                          Container(
                            width: 80,
                            height: 110,
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(8),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withValues(alpha: 0.2),
                                  blurRadius: 8,
                                  offset: const Offset(0, 4),
                                ),
                              ],
                            ),
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(8),
                              child: displayCoverPath.startsWith('assets/')
                                  ? Container(
                                      color: theme.colorScheme.tertiaryContainer,
                                      child: Icon(
                                        Icons.folder,
                                        size: 40,
                                        color: theme.colorScheme.onTertiaryContainer,
                                      ),
                                    )
                                  : Image.file(
                                      File(displayCoverPath),
                                      fit: BoxFit.cover,
                                      errorBuilder: (context, error, stackTrace) => Container(
                                        color: theme.colorScheme.tertiaryContainer,
                                        child: Icon(
                                          Icons.folder,
                                          size: 40,
                                          color: theme.colorScheme.onTertiaryContainer,
                                        ),
                                      ),
                                    ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ];
        },
        body: _isLoading
            ? const Center(child: CircularProgressIndicator())
            : _metadata == null || _metadata!.volumes.isEmpty
                ? Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.inbox_outlined,
                          size: 64,
                          color: theme.colorScheme.outline.withValues(alpha: 0.5),
                        ),
                        const SizedBox(height: 16),
                        Text(
                          '文件夹为空',
                          style: theme.textTheme.titleMedium?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          '请从书架将文件移动到此文件夹',
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: theme.colorScheme.outline,
                          ),
                        ),
                      ],
                    ),
                  )
                : ReorderableListView.builder(
                    buildDefaultDragHandles: false,
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 80),
                    itemCount: _metadata!.volumes.length,
                    onReorder: _onReorder,
                    itemBuilder: (context, index) {
                      final vol = _metadata!.volumes[index];
                      final hasPwd = _metadata!.passwords.containsKey(vol.id);
                      final sizeStr = (vol.size / 1024 / 1024).toStringAsFixed(2);
                      
                      return Card(
                        key: ValueKey(vol.id),
                        elevation: 0,
                        color: theme.colorScheme.surfaceContainerLow,
                        margin: const EdgeInsets.only(bottom: 8),
                        child: ListTile(
                          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                          leading: Container(
                            width: 40,
                            height: 40,
                            decoration: BoxDecoration(
                              color: hasPwd 
                                  ? theme.colorScheme.primaryContainer 
                                  : theme.colorScheme.secondaryContainer,
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Icon(
                              hasPwd ? Icons.lock_open : Icons.description_outlined,
                              color: hasPwd 
                                  ? theme.colorScheme.onPrimaryContainer 
                                  : theme.colorScheme.onSecondaryContainer,
                              size: 20,
                            ),
                          ),
                          title: Text(
                            vol.title,
                            style: const TextStyle(fontWeight: FontWeight.w500),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          subtitle: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const SizedBox(height: 4),
                              Text(
                                vol.filename,
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: theme.colorScheme.outline,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              const SizedBox(height: 2),
                              Text(
                                '$sizeStr MB',
                                style: theme.textTheme.labelSmall?.copyWith(
                                  color: theme.colorScheme.outline,
                                ),
                              ),
                            ],
                          ),
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              IconButton(
                                icon: const Icon(Icons.delete_outline, size: 20),
                                onPressed: () => _deleteVolume(vol),
                                color: theme.colorScheme.error.withValues(alpha: 0.7),
                              ),
                              ReorderableDragStartListener(
                                index: index,
                                child: Icon(
                                  Icons.drag_handle,
                                  color: theme.colorScheme.outline,
                                ),
                              ),
                            ],
                          ),
                          onTap: () => _openVolume(vol),
                          onLongPress: () => _deleteVolume(vol),
                        ),
                      );
                    },
                  ),
      ),
    );
  }
}
