import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mxenc/utils/keyboard_utils.dart';

class TestWidget extends StatelessWidget {
  const TestWidget({super.key});
  @override
  Widget build(BuildContext context) {
    final ctrl = TextEditingController();
    final node = FocusNode();
    return MaterialApp(
      home: Scaffold(
        body: Column(
          children: [
            TextField(
              key: const Key('password'),
              controller: ctrl,
              focusNode: node,
              textInputAction: TextInputAction.done,
              onSubmitted: (_) => KeyboardUtils.hide(context),
            ),
            ElevatedButton(
              key: const Key('confirm'),
              onPressed: () => KeyboardUtils.hide(context),
              child: const Text('OK'),
            ),
          ],
        ),
      ),
    );
  }
}

void main() {
  testWidgets('Keyboard hides on submitted', (tester) async {
    await tester.pumpWidget(const TestWidget());
    final field = find.byKey(const Key('password'));
    await tester.tap(field);
    await tester.pumpAndSettle();
    final node = (tester.widget(field) as TextField).focusNode!;
    expect(node.hasFocus, isTrue);
    await tester.enterText(field, '123');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
    expect(node.hasFocus, isFalse);
  });

  testWidgets('Keyboard hides on button press', (tester) async {
    await tester.pumpWidget(const TestWidget());
    final field = find.byKey(const Key('password'));
    await tester.tap(field);
    await tester.pumpAndSettle();
    final node = (tester.widget(field) as TextField).focusNode!;
    expect(node.hasFocus, isTrue);
    await tester.tap(find.byKey(const Key('confirm')));
    await tester.pumpAndSettle();
    expect(node.hasFocus, isFalse);
  });
}
