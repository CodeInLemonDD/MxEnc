import 'package:flutter/material.dart';

class LoadingController extends ValueNotifier<double> {
  LoadingController([super.value = 0]);
  void set(double v) => value = v.clamp(0.0, 1.0);
}

Future<void> showLoadingDialog(BuildContext context, {
  required LoadingController controller,
  String? label,
}) async {
  return showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (context) {
      final theme = Theme.of(context);
      return AlertDialog(
        contentPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
        content: ValueListenableBuilder<double>(
          valueListenable: controller,
          builder: (context, v, _) {
            final percent = (v * 100).round();
            return Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label ?? '处理中', style: theme.textTheme.titleMedium?.copyWith(color: theme.colorScheme.onSurface)),
                const SizedBox(height: 12),
                Row(
                  children: [
                    SizedBox(
                      width: 28,
                      height: 28,
                      child: CircularProgressIndicator(value: v == 0 ? null : v),
                    ),
                    const SizedBox(width: 16),
                    Text('$percent%', style: theme.textTheme.labelMedium?.copyWith(color: theme.colorScheme.onSurface)),
                  ],
                ),
              ],
            );
          },
        ),
      );
    },
  );
}
