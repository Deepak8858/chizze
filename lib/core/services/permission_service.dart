import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:permission_handler/permission_handler.dart';

/// Centralized permission manager for all runtime permissions.
///
/// Uses [permission_handler] under the hood and exposes simple
/// `ensure*()` methods that request if needed and return a bool.
class PermissionService {
  // ─── Location ─────────────────────────────────────────────

  /// Request foreground (when-in-use) location permission.
  /// Returns `true` if granted.
  Future<bool> ensureLocationPermission() async {
    var status = await Permission.locationWhenInUse.status;
    if (status.isGranted) return true;

    status = await Permission.locationWhenInUse.request();
    return status.isGranted;
  }

  /// Request "always" (background) location permission.
  /// Must be called **after** `ensureLocationPermission()` succeeds because
  /// Android requires foreground location first.
  Future<bool> ensureBackgroundLocationPermission() async {
    // Foreground first
    final foreground = await ensureLocationPermission();
    if (!foreground) return false;

    var status = await Permission.locationAlways.status;
    if (status.isGranted) return true;

    status = await Permission.locationAlways.request();
    return status.isGranted;
  }

  // ─── Camera ───────────────────────────────────────────────

  /// Request camera permission. Returns `true` if granted.
  Future<bool> ensureCameraPermission() async {
    var status = await Permission.camera.status;
    if (status.isGranted) return true;

    status = await Permission.camera.request();
    return status.isGranted;
  }

  // ─── Photos / Storage ────────────────────────────────────

  /// Request photo / media-images permission. Returns `true` if granted.
  Future<bool> ensurePhotosPermission() async {
    var status = await Permission.photos.status;
    if (status.isGranted) return true;

    status = await Permission.photos.request();
    if (status.isGranted) return true;

    // Fallback for older Android (< 13) where photos maps to storage
    status = await Permission.storage.status;
    if (status.isGranted) return true;
    status = await Permission.storage.request();
    return status.isGranted;
  }

  // ─── Notifications ───────────────────────────────────────

  /// Request notification permission (Android 13+ / iOS).
  Future<bool> ensureNotificationPermission() async {
    var status = await Permission.notification.status;
    if (status.isGranted) return true;

    status = await Permission.notification.request();
    return status.isGranted;
  }

  // ─── Phone ──────────────────────────────────────────────

  /// Request phone-call permission.
  Future<bool> ensurePhonePermission() async {
    var status = await Permission.phone.status;
    if (status.isGranted) return true;

    status = await Permission.phone.request();
    return status.isGranted;
  }

  // ─── Batch ──────────────────────────────────────────────

  /// Request the essential permissions up-front after login:
  ///   • Location (foreground)
  ///   • Notifications
  ///
  /// Returns a map of permission → granted.
  Future<Map<String, bool>> requestEssentialPermissions() async {
    final results = <String, bool>{};
    results['location'] = await ensureLocationPermission();
    results['notifications'] = await ensureNotificationPermission();
    return results;
  }

  /// Request delivery-partner specific permissions:
  ///   • Location (always / background)
  ///   • Notifications
  Future<Map<String, bool>> requestDeliveryPermissions() async {
    final results = <String, bool>{};
    results['backgroundLocation'] =
        await ensureBackgroundLocationPermission();
    results['notifications'] = await ensureNotificationPermission();
    return results;
  }

  // ─── Helpers ────────────────────────────────────────────

  /// Check whether a permission is permanently denied and the user must
  /// go to Settings to enable it. Optionally show a dialog.
  Future<bool> isPermanentlyDenied(Permission permission) async {
    return await permission.isPermanentlyDenied;
  }

  /// Open the device settings page so the user can enable a permission
  /// that was permanently denied.
  Future<bool> openSettings() async {
    return await openAppSettings();
  }

  /// Show a dialog explaining why a permission is required and link
  /// to Settings if permanently denied.
  Future<void> showPermissionDialog(
    BuildContext context, {
    required String title,
    required String message,
  }) async {
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              openSettings();
            },
            child: const Text('Open Settings'),
          ),
        ],
      ),
    );
  }
}

/// Global provider for [PermissionService].
final permissionServiceProvider = Provider<PermissionService>((ref) {
  return PermissionService();
});
