import 'dart:io';
import 'package:flutter/services.dart';

/// Helper service for querying and requesting Android 11+ (API 30+)
/// `MANAGE_EXTERNAL_STORAGE` ("All files access") permission via native MethodChannel.
class StoragePermissionService {
  static const MethodChannel _channel =
      MethodChannel('com.harness.agent.harness/storage_permissions');

  /// Checks if the app has permission to manage external storage.
  static Future<bool> hasPermission() async {
    if (!Platform.isAndroid) return true;
    try {
      final res = await _channel
          .invokeMethod<bool>('hasManageExternalStoragePermission');
      return res ?? true;
    } catch (_) {
      return true;
    }
  }

  /// Directs the user to the system "All files access" settings screen for this app.
  static Future<bool> requestPermission() async {
    if (!Platform.isAndroid) return true;
    try {
      final res = await _channel
          .invokeMethod<bool>('requestManageExternalStoragePermission');
      return res ?? true;
    } catch (_) {
      return true;
    }
  }
}

