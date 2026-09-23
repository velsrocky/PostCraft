import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Ephemeral user-facing messages that can be raised without a
/// [BuildContext] (for example from a background global-shortcut handler).
///
/// The [nonce] guarantees a fresh value per call even for identical text so
/// listeners fire every time.
class FeedbackController extends Notifier<(String, int)?> {
  int _nonce = 0;

  @override
  (String, int)? build() => null;

  void notify(String message) => state = (message, ++_nonce);
}

final feedbackProvider = NotifierProvider<FeedbackController, (String, int)?>(
  FeedbackController.new,
);
