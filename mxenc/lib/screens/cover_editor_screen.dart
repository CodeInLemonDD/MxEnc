import 'dart:io';
import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:image/image.dart' as img;

class CropParams {
  final Uint8List bytes;
  final double viewW;
  final double viewH;
  final double scaleX;
  final double scaleY;
  final double transX;
  final double transY;

  CropParams({
    required this.bytes,
    required this.viewW,
    required this.viewH,
    required this.scaleX,
    required this.scaleY,
    required this.transX,
    required this.transY,
  });
}

Future<Uint8List> _cropImageTask(CropParams params) async {
  final src = img.decodeImage(params.bytes);
  if (src == null) throw Exception('Failed to decode image');
  
  final cropW = params.viewW * 0.8;
  final cropH = cropW * 4 / 3;
  final cropLeft = (params.viewW - cropW) / 2;
  final cropTop = (params.viewH - cropH) / 2;

  final fitScale = math.min(params.viewW / src.width, params.viewH / src.height);
  final dispW = src.width * fitScale;
  final dispH = src.height * fitScale;
  final offsetX = (params.viewW - dispW) / 2;
  final offsetY = (params.viewH - dispH) / 2;

  final childX = (cropLeft - params.transX) / params.scaleX;
  final childY = (cropTop - params.transY) / params.scaleY;
  final childW = cropW / params.scaleX;
  final childH = cropH / params.scaleY;

  final imgX = (childX - offsetX) / fitScale;
  final imgY = (childY - offsetY) / fitScale;
  final imgW = childW / fitScale;
  final imgH = childH / fitScale;

  int x = imgX.round().clamp(0, src.width - 1);
  int y = imgY.round().clamp(0, src.height - 1);
  int w = imgW.round().clamp(1, src.width - x);
  int h = imgH.round().clamp(1, src.height - y);

  final cropped = img.copyCrop(src, x: x, y: y, width: w, height: h);
  
  return Uint8List.fromList(img.encodeJpg(cropped, quality: 90));
}

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
    try {
      final bytes = await widget.sourceFile.readAsBytes();
      final renderBox = _cropKey.currentContext!.findRenderObject() as RenderBox;
      final size = renderBox.size;
      final matrix = _controller.value;

      final out = await compute(_cropImageTask, CropParams(
        bytes: bytes,
        viewW: size.width,
        viewH: size.height,
        scaleX: matrix.storage[0],
        scaleY: matrix.storage[5],
        transX: matrix.storage[12],
        transY: matrix.storage[13],
      ));

      if (mounted) {
        setState(() { _isProcessing = false; });
        Navigator.pop(context, out);
      }
    } catch (e) {
      debugPrint('Error cropping image: $e');
      if (mounted) {
        setState(() { _isProcessing = false; });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('裁剪失败')),
        );
      }
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
