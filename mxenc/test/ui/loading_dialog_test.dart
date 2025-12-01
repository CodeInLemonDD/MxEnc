import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mxenc/widgets/loading_dialog.dart';

void main() {
  testWidgets('LoadingDialog shows and updates percent', (tester) async {
    final controller = LoadingController(0);
    await tester.pumpWidget(MaterialApp(home: Builder(builder: (context) {
      return Scaffold(
        body: Center(
          child: ElevatedButton(
            onPressed: () => showLoadingDialog(context, controller: controller, label: '测试'),
            child: const Text('Show'),
          ),
        ),
      );
    })));

    await tester.tap(find.text('Show'));
    await tester.pump();
    expect(find.text('测试'), findsOneWidget);
    expect(find.text('0%'), findsOneWidget);

    controller.set(0.5);
    await tester.pump();
    expect(find.text('50%'), findsOneWidget);

    controller.set(1.0);
    await tester.pump();
    expect(find.text('100%'), findsOneWidget);
  });
}
