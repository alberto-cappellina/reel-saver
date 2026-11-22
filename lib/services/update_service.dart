import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:open_filex/open_filex.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';

import 'app_log.dart';

/// Informazioni sulla versione remota disponibile.
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

/// Controlla la presenza di aggiornamenti leggendo un piccolo file JSON
/// pubblicato accanto all'APK, scarica il nuovo APK e lancia l'installer.
class UpdateService {
  UpdateService({Dio? dio}) : _dio = dio ?? Dio();

  final Dio _dio;

  /// URL del JSON con i metadati dell'ultima versione pubblicata.
  ///
  /// Si configura a build-time:
  ///   flutter build apk --release --dart-define=UPDATE_URL=https://tuo-host/version.json
  ///
  /// Se non configurato (stringa vuota), l'auto-update è semplicemente
  /// disattivato: [check] ritorna sempre null.
  static const String versionUrl = String.fromEnvironment('UPDATE_URL');

  /// true se l'app è stata compilata con un UPDATE_URL.
  static bool get isConfigured => versionUrl.isNotEmpty;

  /// Ritorna le info sull'update se la versione remota è più recente, altrimenti
  /// null. Non lancia mai: in caso di errore (offline, JSON assente) ritorna null.
  Future<UpdateInfo?> check() async {
    if (!isConfigured) {
      AppLog.add('Update: nessun UPDATE_URL configurato, controllo saltato');
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

  /// Scarica l'APK nella cache dell'app e ne restituisce il percorso.
  Future<String> downloadApk(
    String url, {
    required void Function(double progress) onProgress,
  }) async {
    final dir = await getTemporaryDirectory();
    final path = '${dir.path}/update.apk';
    // Rimuove un eventuale download parziale precedente.
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

  /// Apre l'APK scaricato: Android mostra il suo installer di sistema.
  Future<void> install(String apkPath) async {
    await OpenFilex.open(
      apkPath,
      type: 'application/vnd.android.package-archive',
    );
  }
}
