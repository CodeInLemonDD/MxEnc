import 'dart:io';
import 'dart:typed_data';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:image/image.dart' as img;

class CoverEditorScreen extends StatefulWidget {
  final File sourceFile;
  const CoverEditorScreen({super.key, required this.sourceFile});
  @override
  State<CoverEditorScreen> createState() => _CoverEditorScreenState();
}

class _CoverEditorScreenState extends State<CoverEditorScreen> {
  final TransformationController _controller = TransformationController();
  final GlobalKey _cropKey = GlobalKey();
  bool _isProcessing = false;

  Future<void> _confirm() async {
    setState(() { _isProcessing = true; });
    final bytes = await widget.sourceFile.readAsBytes();
    final src = img.decodeImage(bytes)!;
    final renderBox = _cropKey.currentContext!.findRenderObject() as RenderBox;
    final size = renderBox.size;
    final matrix = _controller.value;
    final scaleX = matrix.storage[0];
    final scaleY = matrix.storage[5];
    final transX = matrix.storage[12];
    final transY = matrix.storage[13];
    final viewW = size.width;
    final viewH = size.height;
    final cropW = viewW * 0.8;
    final cropH = cropW * 4 / 3;
    final cropLeft = (viewW - cropW) / 2;
    final cropTop = (viewH - cropH) / 2;
    // BoxFit.contain 显示时的基础缩放与居中偏移
    final fitScale = math.min(viewW / src.width, viewH / src.height);
    final dispW = src.width * fitScale;
    final dispH = src.height * fitScale;
    final offsetX = (viewW - dispW) / 2;
    final offsetY = (viewH - dispH) / 2;

    // 将裁剪框从视图坐标映射到图像像素坐标：
    // 先去除交互变换的平移与缩放得到子坐标，再去除 BoxFit 的偏移与基础缩放
    final childX = (cropLeft - transX) / scaleX;
    final childY = (cropTop - transY) / scaleY;
    final childW = cropW / scaleX;
    final childH = cropH / scaleY;

    final imgX = (childX - offsetX) / fitScale;
    final imgY = (childY - offsetY) / fitScale;
    final imgW = childW / fitScale;
    final imgH = childH / fitScale;

    int x = imgX.round().clamp(0, src.width - 1);
    int y = imgY.round().clamp(0, src.height - 1);
    int w = imgW.round().clamp(1, src.width - x);
    int h = imgH.round().clamp(1, src.height - y);
    final cropped = img.copyCrop(src, x: x, y: y, width: w, height: h);
    final out = img.encodeJpg(cropped, quality: 90);
    if (mounted) {
      setState(() { _isProcessing = false; });
      Navigator.pop(context, Uint8List.fromList(out));
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('裁剪封面'), actions: [
        IconButton(onPressed: _isProcessing ? null : _confirm, icon: const Icon(Icons.check))
      ]),
      body: Stack(
        children: [
          Center(
            child: AspectRatio(
              aspectRatio: 3/4,
              child: Container(
                key: _cropKey,
                color: Colors.black,
                child: InteractiveViewer(
                  transformationController: _controller,
                  minScale: 0.5,
                  maxScale: 5.0,
                  child: Image.file(widget.sourceFile, fit: BoxFit.contain),
                ),
              ),
            ),
          ),
          IgnorePointer(
            child: Center(
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final viewW = constraints.maxWidth;
                  final cropW = viewW * 0.8;
                  final cropH = cropW * 4 / 3;
                  return Container(
                    width: cropW,
                    height: cropH,
                    decoration: BoxDecoration(
                      border: Border.all(color: theme.colorScheme.primary, width: 2),
                    ),
                  );
                },
              ),
            ),
          ),
          if (_isProcessing)
            Align(
              alignment: Alignment.bottomCenter,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: LinearProgressIndicator(
                  backgroundColor: theme.colorScheme.surfaceContainerHighest,
                ),
              ),
            ),
        ],
      ),
    );
  }
}
