import 'dart:io';
import 'package:appwrite/appwrite.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:permission_handler/permission_handler.dart' as ph;
import '../constants/appwrite_constants.dart';
import '../../config/environment.dart';
import 'appwrite_service.dart';

/// Service for uploading images to Appwrite Storage
class ImageUploadService {
  final Storage _storage;

  ImageUploadService(this._storage);

  /// Pick an image from gallery or camera
  static Future<File?> pickImage({
    ImageSource source = ImageSource.gallery,
    int maxWidth = 1024,
    int maxHeight = 1024,
    int quality = 85,
  }) async {
    try {
      // Request appropriate permission before opening picker
      if (source == ImageSource.camera) {
        final status = await ph.Permission.camera.request();
        if (!status.isGranted) {
          if (kDebugMode) debugPrint('[ImageUploadService] Camera permission denied');
          return null;
        }
      } else {
        // Gallery — request photos or storage based on Android version
        var status = await ph.Permission.photos.request();
        if (!status.isGranted) {
          status = await ph.Permission.storage.request();
          if (!status.isGranted) {
            if (kDebugMode) debugPrint('[ImageUploadService] Photo access denied');
            return null;
          }
        }
      }

      final picker = ImagePicker();
      final picked = await picker.pickImage(
        source: source,
        maxWidth: maxWidth.toDouble(),
        maxHeight: maxHeight.toDouble(),
        imageQuality: quality,
      );
      if (picked != null) {
        return File(picked.path);
      }
    } catch (e) {
      if (kDebugMode) debugPrint('[ImageUploadService] pickImage error: $e');
    }
    return null;
  }

  /// Upload a menu item image to Appwrite Storage
  /// Returns the file URL on success, null on failure
  Future<String?> uploadMenuItemImage(File file, {String? fileId}) async {
    return _uploadToBucket(
      AppwriteConstants.menuItemImagesBucket,
      file,
      fileId: fileId,
    );
  }

  /// Upload a restaurant image to Appwrite Storage
  Future<String?> uploadRestaurantImage(File file, {String? fileId}) async {
    return _uploadToBucket(
      AppwriteConstants.restaurantImagesBucket,
      file,
      fileId: fileId,
    );
  }

  /// Upload a review photo to Appwrite Storage
  Future<String?> uploadReviewPhoto(File file, {String? fileId}) async {
    return _uploadToBucket(
      AppwriteConstants.reviewPhotosBucket,
      file,
      fileId: fileId,
    );
  }

  /// Delete a file from a bucket by its file ID
  Future<bool> deleteFile(String bucketId, String fileId) async {
    try {
      await _storage.deleteFile(bucketId: bucketId, fileId: fileId);
      return true;
    } catch (e) {
      if (kDebugMode) debugPrint('[ImageUploadService] deleteFile error: $e');
      return false;
    }
  }

  /// Get the preview URL for a file
  static String getFilePreviewUrl(String bucketId, String fileId) {
    return '${Environment.appwritePublicEndpoint}/storage/buckets/$bucketId/files/$fileId/preview?project=${Environment.appwriteProjectId}&width=400&height=400&gravity=center&quality=80';
  }

  /// Get the view URL for a file (full resolution)
  static String getFileViewUrl(String bucketId, String fileId) {
    return '${Environment.appwritePublicEndpoint}/storage/buckets/$bucketId/files/$fileId/view?project=${Environment.appwriteProjectId}';
  }

  /// Internal upload helper
  Future<String?> _uploadToBucket(
    String bucketId,
    File file, {
    String? fileId,
  }) async {
    try {
      final id = fileId ?? ID.unique();
      final result = await _storage.createFile(
        bucketId: bucketId,
        fileId: id,
        file: InputFile.fromPath(
          path: file.path,
          filename: '${id}_${DateTime.now().millisecondsSinceEpoch}.jpg',
        ),
      );

      // Return the preview URL for the uploaded file
      return getFilePreviewUrl(bucketId, result.$id);
    } catch (e) {
      if (kDebugMode) debugPrint('[ImageUploadService] upload error: $e');
      return null;
    }
  }
}

/// Image upload service provider
final imageUploadServiceProvider = Provider<ImageUploadService>((ref) {
  final storage = ref.watch(appwriteStorageProvider);
  return ImageUploadService(storage);
});
