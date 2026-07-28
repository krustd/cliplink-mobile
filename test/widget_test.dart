import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:clip_link_mobile/main.dart';
import 'package:clip_link_mobile/providers/app_state.dart';

void main() {
  testWidgets('App renders device selection screen', (tester) async {
    await tester.pumpWidget(
      ChangeNotifierProvider(
        create: (_) => AppState(),
        child: const ClipLinkApp(),
      ),
    );
    // Just verify the scaffold is rendered with the app bar title
    expect(find.byType(AppBar), findsOneWidget);
  });
}
