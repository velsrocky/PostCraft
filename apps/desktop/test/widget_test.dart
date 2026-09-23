import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:postcraft/src/app/postcraft_app.dart';
import 'package:postcraft/src/features/capture/application/capture_providers.dart';
import 'package:postcraft/src/rust/lib.dart';

void main() {
  testWidgets('opens the PostCraft editing workspace', (tester) async {
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          captureCapabilitiesProvider.overrideWith(
            (ref) async => const PlatformCapabilities(
              desktopCapture: false,
              windowCapture: false,
              systemAudioCapture: false,
              globalShortcuts: false,
              clipboardImageWrite: false,
              waylandScreencast: false,
              microphoneCapture: false,
              captureReason: 'test',
            ),
          ),
        ],
        child: const PostCraftApp(),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('PostCraft'), findsOneWidget);
    expect(find.text('Capture & edit'), findsOneWidget);
    expect(find.text('Capture something great'), findsOneWidget);
    expect(find.text('Select region'), findsOneWidget);
    expect(find.text('Open an image'), findsOneWidget);
    expect(
      find.textContaining('XDG Screenshot portal is unavailable'),
      findsOneWidget,
    );
  });
}
