import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:dio/dio.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:developer' as developer;
import 'dart:io';

class UpdateInfo {
  final String latestVersion;
  final String downloadUrl;
  final String? releaseNotes;
  final bool isRequired; // true = wajib update, false = opsional

  UpdateInfo({
    required this.latestVersion,
    required this.downloadUrl,
    this.releaseNotes,
    this.isRequired = false,
  });

  factory UpdateInfo.fromFirestore(Map<String, dynamic> data) {
    return UpdateInfo(
      latestVersion: data['latest_version'] ?? '1.0.2',
      downloadUrl: data['download_url'] ?? '',
      releaseNotes: data['release_notes'],
      isRequired: data['is_required'] ?? false,
    );
  }
}

class UpdateService {
  static final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  /// Get current app version dari pubspec atau package info
  static Future<String> getCurrentVersion() async {
    try {
      final packageInfo = await PackageInfo.fromPlatform();
      return packageInfo.version; // e.g., "1.0.1"
    } catch (e) {
      return '1.0.2'; // Default fallback
    }
  }

  /// Check latest version dari Firestore
  /// Database path: /app_config/version
  static Future<UpdateInfo?> checkForUpdates() async {
    try {
      final currentVersion = await getCurrentVersion();
      
      // Fetch dari Firestore collection 'app_config' document 'version'
      final doc = await _firestore.collection('app_config').doc('version').get();
      
      if (!doc.exists) {
        return null; // No update config found
      }

      final updateInfo = UpdateInfo.fromFirestore(doc.data() as Map<String, dynamic>);
      
      // Compare versions: jika latest > current, return update info
      if (_compareVersions(updateInfo.latestVersion, currentVersion) > 0) {
        return updateInfo;
      }
      
      return null; // Already latest version
    } catch (e) {
      // Log error ke console tapi tetap silent
      developer.log(
        'Check updates error: $e',
        name: 'UpdateService.checkForUpdates',
        error: e,
      );
      return null;
    }
  }

  /// Compare two version strings
  /// Returns: 1 if v1 > v2, -1 if v1 < v2, 0 if equal
  static int _compareVersions(String v1, String v2) {
    final parts1 = v1.split('.').map(int.parse).toList();
    final parts2 = v2.split('.').map(int.parse).toList();

    final maxLength = parts1.length > parts2.length ? parts1.length : parts2.length;

    for (int i = 0; i < maxLength; i++) {
      final p1 = i < parts1.length ? parts1[i] : 0;
      final p2 = i < parts2.length ? parts2[i] : 0;

      if (p1 > p2) return 1;
      if (p1 < p2) return -1;
    }

    return 0; // equal
  }

  /// Launch download/install link with progress callback
  /// For GitHub Release URLs: Download APK then show install dialog
  static Future<void> launchDownloadUrl(String url, {Function(double)? onProgress, Function(String)? onDownloadComplete}) async {
    try {
      if (url.contains('github.com') && url.contains('/releases/')) {
        // Download GitHub release APK to device
        final filePath = await _downloadAndInstallApk(url, onProgress: onProgress);
        
        // Callback ketika download selesai, sebelum install
        onDownloadComplete?.call(filePath);
      } else {
        // For other URLs, try to open directly
        if (await canLaunchUrl(Uri.parse(url))) {
          await launchUrl(
            Uri.parse(url),
            mode: LaunchMode.externalApplication,
          );
        } else {
          throw 'Tidak dapat membuka link download: $url';
        }
      }
    } catch (e) {
      rethrow;
    }
  }

  /// Download APK dari GitHub Release ke folder Documents/update
  /// File akan tersimpan di: /storage/emulated/0/Documents/update/ (sama seperti kupon & Excel)
  static Future<String> _downloadAndInstallApk(String downloadUrl, {Function(double)? onProgress}) async {
    try {
      // Gunakan path yang sama seperti app gunakan untuk kupon & Excel files
      // /storage/emulated/0/Documents/PilotFinance untuk kupon
      // /storage/emulated/0/Documents/update untuk APK update
      final updateDir = Directory('/storage/emulated/0/Documents/update');
      
      // Create folder jika belum ada
      if (!await updateDir.exists()) {
        await updateDir.create(recursive: true);
      }
      
      final fileName = 'pilot_finance_update.apk';
      final filePath = '${updateDir.path}/$fileName';

      developer.log(
        'Starting APK download from: $downloadUrl',
        name: 'UpdateService._downloadAndInstallApk',
      );
      developer.log(
        'Save location: $filePath',
        name: 'UpdateService._downloadAndInstallApk',
      );

      // Download APK menggunakan Dio dengan progress tracking
      final dio = Dio();
      
      await dio.download(
        downloadUrl,
        filePath,
        onReceiveProgress: (received, total) {
          if (total != -1) {
            double progress = received / total;
            onProgress?.call(progress);
          }
        },
      );
      
      developer.log(
        'APK download completed, file saved to: $filePath',
        name: 'UpdateService._downloadAndInstallApk',
      );

      // Return file path untuk next step
      return filePath;
      
    } catch (e) {
      final errorMsg = 'Gagal download APK: $e';
      // Log ke console/terminal
      developer.log(
        errorMsg,
        name: 'UpdateService._downloadAndInstallApk',
        error: e,
      );
      throw errorMsg;
    }
  }

  /// Detect APK file di folder update
  /// Returns file path jika ada, null jika tidak ada
  static Future<String?> detectPendingApkUpdate() async {
    try {
      final updateDir = Directory('/storage/emulated/0/Documents/update');
      
      // Check if directory exists
      if (!await updateDir.exists()) {
        return null;
      }

      // Look for APK file
      final apkFile = File('${updateDir.path}/pilot_finance_update.apk');
      
      if (await apkFile.exists()) {
        developer.log(
          'Found pending APK update: ${apkFile.path}',
          name: 'UpdateService.detectPendingApkUpdate',
        );
        return apkFile.path;
      }

      return null;
    } catch (e) {
      developer.log(
        'Error detecting APK update: $e',
        name: 'UpdateService.detectPendingApkUpdate',
        error: e,
      );
      return null;
    }
  }

  /// Install APK from file path
  /// Assumes file already exists
  static Future<void> installApkFromFile(String filePath) async {
    try {
      developer.log(
        'Installing APK from: $filePath',
        name: 'UpdateService.installApkFromFile',
      );

      // Call MethodChannel to launch installer
      final platform = MethodChannel('com.pilotrepair.pilot_finance/update');
      final bool result = await platform.invokeMethod(
        'installApk',
        {'path': filePath},
      );

      if (!result) {
        throw 'Installation method returned false';
      }

      developer.log(
        'APK installation initiated',
        name: 'UpdateService.installApkFromFile',
      );
    } on PlatformException catch (e) {
      final errorMsg = 'Error installing APK: ${e.message}';
      developer.log(
        errorMsg,
        name: 'UpdateService.installApkFromFile',
        error: e,
      );
      throw errorMsg;
    }
  }

  /// Delete APK file setelah install berhasil
  static Future<void> deleteApkFile(String filePath) async {
    try {
      final file = File(filePath);
      
      if (await file.exists()) {
        await file.delete();
        developer.log(
          'APK file deleted: $filePath',
          name: 'UpdateService.deleteApkFile',
        );
      }
    } catch (e) {
      developer.log(
        'Error deleting APK file: $e',
        name: 'UpdateService.deleteApkFile',
        error: e,
      );
      // Don't throw, just log - delete failure tidak perlu block
    }
  }

  /// Simpan versi sebelum update dimulai ke SharedPreferences
  static Future<void> saveVersionBeforeUpdate() async {
    try {
      final currentVersion = await getCurrentVersion();
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('version_before_update', currentVersion);
      
      developer.log(
        'Saved version before update: $currentVersion',
        name: 'UpdateService.saveVersionBeforeUpdate',
      );
    } catch (e) {
      developer.log(
        'Error saving version before update: $e',
        name: 'UpdateService.saveVersionBeforeUpdate',
        error: e,
      );
    }
  }

  /// Check apakah versi berubah setelah update (instalasi berhasil)
  /// Return true jika versi baru lebih tinggi dari versi sebelum update
  static Future<bool> isVersionUpdated() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final versionBeforeUpdate = prefs.getString('version_before_update');
      
      if (versionBeforeUpdate == null) {
        developer.log(
          'No previous version found in SharedPreferences',
          name: 'UpdateService.isVersionUpdated',
        );
        return false;
      }
      
      final currentVersion = await getCurrentVersion();
      
      developer.log(
        'Comparing versions - Before: $versionBeforeUpdate, Current: $currentVersion',
        name: 'UpdateService.isVersionUpdated',
      );
      
      // Simple string comparison (assumes semantic versioning)
      // For proper comparison, bisa implement semantic version parsing
      if (currentVersion != versionBeforeUpdate) {
        developer.log(
          'Version updated successfully! $versionBeforeUpdate → $currentVersion',
          name: 'UpdateService.isVersionUpdated',
        );
        
        // Clear the saved version after successful update
        await prefs.remove('version_before_update');
        
        return true;
      }
      
      return false;
    } catch (e) {
      developer.log(
        'Error checking if version updated: $e',
        name: 'UpdateService.isVersionUpdated',
        error: e,
      );
      return false;
    }
  }

  /// Get versi sebelum update
  static Future<String?> getVersionBeforeUpdate() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getString('version_before_update');
    } catch (e) {
      return null;
    }
  }

  /// Save current version ke Firestore (optional, untuk tracking)
  /// Path: /app_usage/last_version
  static Future<void> saveVersionCheck(String version) async {
    try {
      await _firestore.collection('app_usage').doc('last_version').set({
        'version': version,
        'checked_at': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    } catch (e) {
      // Silently handle version check save errors
    }
  }
}
