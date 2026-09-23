import 'package:flutter/services.dart';
import 'dart:convert';

import '../../../rust/api.dart' as native_api;

class LinuxWindowHandleService {
  const LinuxWindowHandleService();

  static const _channel = MethodChannel('com.velstech.postcraft/window');

  Future<String> parentWindow() async {
    final handle = await _channel.invokeMethod<String>('getParentWindow');
    // Wayland portals permit an empty parent for an app-owned request. X11
    // returns an x11:<XID> handle from the GTK runner.
    return handle ?? '';
  }

  Future<Map<String, dynamic>> startWaylandSession({
    required String sessionHandle,
  }) async {
    final parent = await parentWindow();
    final raw = await native_api.startWaylandScreencast(
      sessionHandle: sessionHandle,
      parentWindow: parent,
    );
    return Map<String, dynamic>.from(jsonDecode(raw) as Map);
  }
}
