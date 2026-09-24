import 'dart:typed_data';

import 'package:flutter/material.dart';

class SharePayload {
  const SharePayload({this.pngBytes, this.filePath, required this.title});

  final Uint8List? pngBytes;
  final String? filePath;
  final String title;
}

enum ShareResultKind { opened, copied, saved, copiedPath, cancelled, failed }

class ShareResult {
  const ShareResult({required this.kind, required this.message});

  final ShareResultKind kind;
  final String message;
}

abstract interface class ShareDestination {
  String get id;
  String get label;
  IconData get icon;
  Future<ShareResult> share(SharePayload payload);
}
