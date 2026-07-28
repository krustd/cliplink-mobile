import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:clip_link_mobile/main.dart';
import 'package:clip_link_mobile/providers/app_state.dart';

void main() {
  testWidgets('App renders device selection screen', (tester) async {
    final appState = AppState();
    await tester.pumpWidget(
      ChangeNotifierProvider.value(
        value: appState,
        child: const ClipLinkApp(),
      ),
    );
    await tester.pump();
    expect(find.byType(AppBar), findsOneWidget);
    // Clean up timers from discovery service
    appState.stopScan();
    appState.dispose();
  });
}
