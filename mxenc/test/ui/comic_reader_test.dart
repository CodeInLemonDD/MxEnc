import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mxenc/screens/comic_reader_screen.dart';
import 'dart:typed_data';
import 'package:provider/provider.dart';
import 'package:mxenc/utils/theme_provider.dart';

void main() {
  testWidgets('Comic reader list key changes with chapter', (tester) async {
    final manifest = {
      'title': 'Test',
      'chapters': [
        {'title': 'C1', 'images': <int>[]},
        {'title': 'C2', 'images': <int>[]},
      ],
      'imagesIndex': <Map<String, dynamic>>[],
    };
    await tester.pumpWidget(ChangeNotifierProvider(
      create: (_) => ThemeProvider(),
      child: MaterialApp(home: ComicReaderScreen(
        manifest: manifest,
        payload: Uint8List(0),
        start: 0,
        sourcePath: '/tmp/a.mxenc',
      )),
    ));

    final listFinder = find.byType(ListView);
    PageStorageKey key1 = tester.widget<ListView>(listFinder).key! as PageStorageKey;
    expect('${key1.value}', contains('chapter_0'));

    await tester.tap(find.byType(GestureDetector));
    await tester.pump();
    await tester.tap(find.byIcon(Icons.skip_next));
    await tester.pump();
    PageStorageKey key2 = tester.widget<ListView>(listFinder).key! as PageStorageKey;
    expect('${key2.value}', contains('chapter_1'));

    await tester.tap(find.byIcon(Icons.skip_previous));
    await tester.pump();
    PageStorageKey key3 = tester.widget<ListView>(listFinder).key! as PageStorageKey;
    expect('${key3.value}', contains('chapter_0'));
  });
}
