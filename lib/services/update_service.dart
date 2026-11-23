import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:open_filex/open_filex.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';

import 'app_log.dart';

/// Information about the available remote version.
class UpdateInfo {
  UpdateInfo({
    required this.versionCode,
    required this.versionName,
    required this.apkUrl,
    this.notes,
  });

  final int versionCode;
  final String versionName;
  final String apkUrl;
  final String? notes;
}

/// Checks for updates by reading a small JSON file published next to the APK,
/// downloads the new APK and launches the installer.
class UpdateService {
  UpdateService({Dio? dio}) : _dio = dio ?? Dio();

  final Dio _dio;

  /// URL of the JSON holding the metadata of the latest published version.
  ///
  /// Configured at build time:
  ///   flutter build apk --release --dart-define=UPDATE_URL=https://your-host/version.json
  ///
  /// If not configured (empty string), auto-update is simply disabled:
  /// [check] always returns null.
  static const String versionUrl = String.fromEnvironment('UPDATE_URL');

  /// true if the app was built with an UPDATE_URL.
  static bool get isConfigured => versionUrl.isNotEmpty;

  /// Returns update info if the remote version is newer, otherwise null.
  /// Never throws: on error (offline, missing JSON) it returns null.
  Future<UpdateInfo?> check() async {
    if (!isConfigured) {
      AppLog.add('Update: no UPDATE_URL configured, check skipped');
      return null;
    }
    try {
      final pkg = await PackageInfo.fromPlatform();
      final currentCode = int.tryParse(pkg.buildNumber) ?? 0;

      final resp = await _dio.get(
        versionUrl,
        queryParameters: {'t': DateTime.now().millisecondsSinceEpoch},
        options: Options(
          responseType: ResponseType.plain,
          headers: {'Cache-Control': 'no-cache'},
          receiveTimeout: const Duration(seconds: 15),
          sendTimeout: const Duration(seconds: 15),
        ),
      );

      final data = jsonDecode(resp.data as String) as Map<String, dynamic>;
      final code = (data['versionCode'] as num?)?.toInt() ?? 0;
      final apkUrl = data['apkUrl'] as String?;
      if (code <= currentCode || apkUrl == null || apkUrl.isEmpty) {
        return null;
      }
      return UpdateInfo(
        versionCode: code,
        versionName: (data['versionName'] as String?) ?? '$code',
        apkUrl: apkUrl,
        notes: data['notes'] as String?,
      );
    } catch (_) {
      return null;
    }
  }

  /// Downloads the APK into the app cache and returns its path.
  Future<String> downloadApk(
    String url, {
    required void Function(double progress) onProgress,
  }) async {
    final dir = await getTemporaryDirectory();
    final path = '${dir.path}/update.apk';
    // Remove any previous partial download.
    final f = File(path);
    if (await f.exists()) await f.delete();

    await _dio.download(
      url,
      path,
      onReceiveProgress: (r, t) {
        if (t > 0) onProgress(r / t);
      },
      options: Options(receiveTimeout: const Duration(minutes: 5)),
    );
    return path;
  }

  /// Opens the downloaded APK: Android shows its system installer.
  Future<void> install(String apkPath) async {
    await OpenFilex.open(
      apkPath,
      type: 'application/vnd.android.package-archive',
    );
  }
}
