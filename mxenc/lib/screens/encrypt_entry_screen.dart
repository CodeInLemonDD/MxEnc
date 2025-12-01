import 'package:flutter/material.dart';
import 'comic_editor_screen.dart';
import 'rich_editor_screen.dart';
import '../rust_bridge.dart';

class EncryptEntryScreen extends StatelessWidget {
  final RustBridge rustBridge;

  const EncryptEntryScreen({super.key, required this.rustBridge});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('选择加密类型')),
      body: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Card(
              elevation: 2,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              child: InkWell(
                borderRadius: BorderRadius.circular(12),
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => ComicEditorScreen(rustBridge: rustBridge),
                    ),
                  );
                },
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Row(
                    children: [
                      Container(
                        width: 56,
                        height: 56,
                        decoration: BoxDecoration(
                          color: theme.colorScheme.primaryContainer,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Icon(Icons.collections, color: theme.colorScheme.onPrimaryContainer),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: const [
                            Text('漫画创作（多图分章节）', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                            SizedBox(height: 6),
                            Text('管理章节与多张图片，导出为加密漫画 .mxenc'),
                          ],
                        ),
                      ),
                      const Icon(Icons.chevron_right),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(height: 16),
            Card(
              elevation: 2,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              child: InkWell(
                borderRadius: BorderRadius.circular(12),
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => RichEditorScreen(rustBridge: rustBridge),
                    ),
                  );
                },
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Row(
                    children: [
                      Container(
                        width: 56,
                        height: 56,
                        decoration: BoxDecoration(
                          color: theme.colorScheme.secondaryContainer,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Icon(Icons.menu_book, color: theme.colorScheme.onSecondaryContainer),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: const [
                            Text('富文本小说（插图混排）', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                            SizedBox(height: 6),
                            Text('使用富文本编辑器创作并导出加密小说 .mxenc'),
                          ],
                        ),
                      ),
                      const Icon(Icons.chevron_right),
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
