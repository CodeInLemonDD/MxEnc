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

  void _reset() {
    _controller.value = Matrix4.identity();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: const Text('裁剪封面', style: TextStyle(color: Colors.white)),
        backgroundColor: Colors.black,
        iconTheme: const IconThemeData(color: Colors.white),
        actions: [
          IconButton(
            onPressed: _reset,
            icon: const Icon(Icons.refresh),
            tooltip: '重置',
          ),
          IconButton(
            onPressed: _isProcessing ? null : _confirm,
            icon: const Icon(Icons.check),
            tooltip: '完成',
          ),
        ],
      ),
      body: Stack(
        children: [
          // 1. Image Layer
          Center(
            child: AspectRatio(
              aspectRatio: 3 / 4,
              child: Container(
                key: _cropKey,
                color: Colors.black,
                child: InteractiveViewer(
                  transformationController: _controller,
                  minScale: 0.5,
                  maxScale: 5.0,
                  boundaryMargin: const EdgeInsets.all(double.infinity),
                  child: Image.file(widget.sourceFile, fit: BoxFit.contain),
                ),
              ),
            ),
          ),
          
          // 2. Overlay Layer (Dimmed background with crop hole)
          IgnorePointer(
            child: LayoutBuilder(
              builder: (context, constraints) {
                return Center(
                  child: AspectRatio(
                    aspectRatio: 3 / 4,
                    child: LayoutBuilder(
                      builder: (ctx, c2) {
                        final w = c2.maxWidth;
                        final cropW = w * 0.8;
                        final cropH = cropW * 4 / 3;
                        
                        return Stack(
                          children: [
                            // Dimmed overlay
                            ColorFiltered(
                              colorFilter: const ColorFilter.mode(
                                Colors.black54,
                                BlendMode.srcOut,
                              ),
                              child: Stack(
                                children: [
                                  Container(
                                    decoration: const BoxDecoration(
                                      color: Colors.black,
                                      backgroundBlendMode: BlendMode.dstOut,
                                    ),
                                  ),
                                  Center(
                                    child: Container(
                                      width: cropW,
                                      height: cropH,
                                      decoration: const BoxDecoration(
                                        color: Colors.white,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            
                            // Crop Border & Grid
                            Center(
                              child: SizedBox(
                                width: cropW,
                                height: cropH,
                                child: CustomPaint(
                                  painter: _GridPainter(),
                                ),
                              ),
                            ),
                          ],
                        );
                      },
                    ),
                  ),
                );
              },
            ),
          ),
          
          // 3. Hint Text
          const Positioned(
            bottom: 30,
            left: 0,
            right: 0,
            child: Center(
              child: Text(
                '拖动并缩放以调整封面区域',
                style: TextStyle(
                  color: Colors.white,
                  shadows: [Shadow(blurRadius: 2, color: Colors.black)],
                ),
              ),
            ),
          ),

          if (_isProcessing)
            Container(
              color: Colors.black54,
              child: const Center(
                child: CircularProgressIndicator(color: Colors.white),
              ),
            ),
        ],
      ),
    );
  }
}

class _GridPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.white.withValues(alpha: 0.5)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;

    final w = size.width;
    final h = size.height;

    // Grid lines
    canvas.drawLine(Offset(w / 3, 0), Offset(w / 3, h), paint);
    canvas.drawLine(Offset(2 * w / 3, 0), Offset(2 * w / 3, h), paint);
    canvas.drawLine(Offset(0, h / 3), Offset(w, h / 3), paint);
    canvas.drawLine(Offset(0, 2 * h / 3), Offset(w, 2 * h / 3), paint);

    // Border
    final borderPaint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;
    canvas.drawRect(Rect.fromLTWH(0, 0, w, h), borderPaint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
