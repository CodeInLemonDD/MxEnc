import 'dart:math';
import 'package:flutter/material.dart';

class DynamicWatermark extends StatefulWidget {
  final String receiverId;
  final double opacity;
  final Widget? child;

  const DynamicWatermark({
    super.key,
    required this.receiverId,
    this.opacity = 0.3,
    this.child,
  });

  @override
  State<DynamicWatermark> createState() => _DynamicWatermarkState();
}

class _DynamicWatermarkState extends State<DynamicWatermark>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _angleAnimation;
  late Animation<double> _opacityAnimation;
  late Animation<Offset> _positionAnimation;

  final Random _random = Random();

  @override
  void initState() {
    super.initState();

    // 创建动画控制器
    _controller = AnimationController(
      duration: const Duration(seconds: 10),
      vsync: this,
    );

    // 初始化动画
    _initAnimations();

    // 启动动画并循环
    _controller.repeat(reverse: true);
  }

  void _initAnimations() {
    // 角度动画 (0-360度)
    _angleAnimation = Tween<double>(
      begin: 0,
      end: 2 * pi,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeInOut));

    // 透明度动画 (基础透明度的±20%)
    final baseOpacity = widget.opacity;
    _opacityAnimation = Tween<double>(
      begin: baseOpacity * 0.8,
      end: baseOpacity * 1.2,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeInOut));

    // 位置动画 (随机移动)
    _positionAnimation = Tween<Offset>(
      begin: Offset(_random.nextDouble() * 0.2, _random.nextDouble() * 0.2),
      end: Offset(_random.nextDouble() * 0.2, _random.nextDouble() * 0.2),
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeInOut));
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        // 子组件（如果有）
        if (widget.child != null) widget.child!,

        // 动态水印层
        AnimatedBuilder(
          animation: _controller,
          builder: (context, child) {
            return CustomPaint(
              painter: WatermarkPainter(
                text: widget.receiverId,
                angle: _angleAnimation.value,
                opacity: _opacityAnimation.value,
                offset: _positionAnimation.value,
              ),
              size: Size.infinite,
            );
          },
        ),
      ],
    );
  }
}

class StaticWatermark extends StatelessWidget {
  final double opacity;
  final String groupText;
  const StaticWatermark({
    super.key,
    this.opacity = 0.1,
    this.groupText = 'QQ群：868140659',
  });

  @override
  Widget build(BuildContext context) {
    final brightness = Theme.of(context).brightness;
    final baseColor = brightness == Brightness.dark
        ? Colors.white.withValues(alpha: opacity)
        : Colors.black.withValues(alpha: opacity);
    return CustomPaint(
      painter: StaticWatermarkPainter(
        text: '未经允许禁止盗用\n$groupText',
        color: baseColor,
      ),
      size: Size.infinite,
    );
  }
}

class StaticWatermarkPainter extends CustomPainter {
  final String text;
  final Color color;
  StaticWatermarkPainter({required this.text, required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final tp = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(color: color, fontSize: 16, height: 1.4),
      ),
      textAlign: TextAlign.center,
      textDirection: TextDirection.ltr,
    );
    tp.layout();
    final stepX = tp.width + 160;
    final stepY = tp.height + 140;
    canvas.save();
    canvas.translate(size.width / 2, size.height / 2);
    canvas.rotate(-0.25);
    canvas.translate(-size.width / 2, -size.height / 2);
    for (double x = -stepX; x < size.width + stepX; x += stepX) {
      for (double y = -stepY; y < size.height + stepY; y += stepY) {
        tp.paint(canvas, Offset(x, y));
      }
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant StaticWatermarkPainter oldDelegate) {
    return oldDelegate.text != text || oldDelegate.color != color;
  }
}

class WatermarkPainter extends CustomPainter {
  final String text;
  final double angle;
  final double opacity;
  final Offset offset;

  WatermarkPainter({
    required this.text,
    required this.angle,
    required this.opacity,
    required this.offset,
  });

  @override
  void paint(Canvas canvas, Size size) {
    // 创建文本绘制器
    final textPainter = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(
          color: Colors.black.withValues(alpha: opacity),
          fontSize: 18,
          fontWeight: FontWeight.bold,
        ),
      ),
      textDirection: TextDirection.ltr,
    );

    // 布局文本
    textPainter.layout();

    // 计算水印网格
    final double textWidth = textPainter.width + 50;
    final double textHeight = textPainter.height + 50;

    // 保存当前画布状态
    canvas.save();

    // 应用旋转
    canvas.translate(size.width / 2, size.height / 2);
    canvas.rotate(angle);
    canvas.translate(-size.width / 2, -size.height / 2);

    // 绘制水印网格
    for (double x = -textWidth; x < size.width + textWidth; x += textWidth) {
      for (
        double y = -textHeight;
        y < size.height + textHeight;
        y += textHeight
      ) {
        final xPos = x + offset.dx * size.width;
        final yPos = y + offset.dy * size.height;
        textPainter.paint(canvas, Offset(xPos, yPos));
      }
    }

    // 恢复画布状态
    canvas.restore();
  }

  @override
  bool shouldRepaint(WatermarkPainter oldDelegate) {
    return oldDelegate.text != text ||
        oldDelegate.angle != angle ||
        oldDelegate.opacity != opacity ||
        oldDelegate.offset != offset;
  }
}
