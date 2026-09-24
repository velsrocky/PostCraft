import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/router.dart';
import '../../../core/feedback.dart';
import '../../editor/application/editor_controller.dart';
import '../../projects/application/projects_providers.dart';
import '../application/capture_providers.dart';
import '../domain/capture_result.dart';

/// A context-free capture entry point.
abstract interface class CaptureRunner {
  Future<void> run(CaptureMode mode, {String? targetId});
}

/// Portal-driven capture that runs without a [BuildContext].
///
/// Shared by the in-app buttons and the background global-shortcut handler: it
/// captures, loads the result into the editor, records it as a durable project,
/// navigates to the editor, and reports the outcome through [feedbackProvider].
class CaptureCoordinator implements CaptureRunner {
  const CaptureCoordinator(this._ref);
  final Ref _ref;

  @override
  Future<void> run(CaptureMode mode, {String? targetId}) async {
    final feedback = _ref.read(feedbackProvider.notifier);
    final label = switch (mode) {
      CaptureMode.region => 'Region',
      CaptureMode.screen => 'Screen',
      CaptureMode.display => 'Display',
    };
    try {
      final capture = await _ref
          .read(linuxCaptureServiceProvider)
          .capture(mode, targetId: targetId);
      final image = await _decode(capture.bytes);
      _ref
          .read(editorControllerProvider.notifier)
          .openImage(capture.bytes, image.width, image.height);
      image.dispose();
      final document = _ref.read(editorControllerProvider).document;
      await _ref
          .read(workspaceControllerProvider.notifier)
          .startProject(document, name: '$label capture');
      _ref.read(routerProvider).go('/editor');
      feedback.notify('$label captured');
    } on Object catch (error) {
      feedback.notify('Capture failed: $error');
    }
  }

  static Future<ui.Image> _decode(Uint8List bytes) {
    final completer = Completer<ui.Image>();
    ui.decodeImageFromList(bytes, completer.complete);
    return completer.future;
  }
}

final captureCoordinatorProvider = Provider<CaptureRunner>(
  (ref) => CaptureCoordinator(ref),
);
