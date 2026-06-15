// Nexus temel widget testi.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:nexus/core/theme/app_theme.dart';

void main() {
  testWidgets('Uygulama teması yüklenebiliyor', (WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: NexusTheme.darkTheme,
        home: const Scaffold(
          body: Center(child: Text('Nexus')),
        ),
      ),
    );

    expect(find.text('Nexus'), findsOneWidget);
  });
}
