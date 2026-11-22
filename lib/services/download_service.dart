import 'dart:io';

import 'package:dio/dio.dart';
import 'package:gal/gal.dart';
import 'package:path_provider/path_provider.dart';

import 'app_log.dart';

/// Esito del download: file locale (per la condivisione) + flag salvataggio.
class DownloadResult {
  DownloadResult({required this.filePath, required this.savedToGallery});
  final String filePath;
  final bool savedToGallery;
}

class DownloadException implements Exception {
  DownloadException(this.message);
  final String message;
  @override
  String toString() => message;
}

/// Scarica il video sul dispositivo e lo salva nella galleria.
class DownloadService {
  DownloadService({Dio? dio}) : _dio = dio ?? Dio();

  final Dio _dio;

  static const String _albumName = 'Reel Saver';

  /// Scarica [videoUrl] mostrando l'avanzamento, salva in galleria e
  /// restituisce il percorso locale (utile per la condivisione).
  Future<DownloadResult> downloadAndSave({
    required String videoUrl,
    required String shortcode,
    required void Function(double progress) onProgress,
  }) async {
    final dir = await getTemporaryDirectory();
    final fileName =
        'reel_${shortcode}_${DateTime.now().millisecondsSinceEpoch}.mp4';
    final filePath = '${dir.path}/$fileName';

    final host = Uri.tryParse(videoUrl)?.host ?? '?';
    AppLog.add('Download: avvio da host $host');
    try {
      await _dio.download(
        videoUrl,
        filePath,
        onReceiveProgress: (received, total) {
          if (total > 0) onProgress(received / total);
        },
        options: Options(
          headers: const {
            'User-Agent':
                'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 '
                    '(KHTML, like Gecko) Chrome/149.0.0.0 Safari/537.36',
          },
          responseType: ResponseType.bytes,
          followRedirects: true,
          receiveTimeout: const Duration(minutes: 5),
        ),
      );
    } on DioException catch (e) {
      AppLog.add('Download: ERRORE ${e.type.name} '
          '${e.response?.statusCode ?? ""} ${e.message ?? ""}');
      throw DownloadException('Errore durante il download: ${e.message}');
    }

    final file = File(filePath);
    if (!await file.exists() || await file.length() == 0) {
      AppLog.add('Download: file vuoto');
      throw DownloadException('Il file scaricato è vuoto.');
    }
    AppLog.add('Download: ok, ${await file.length()} byte');

    bool saved = false;
    try {
      final hasAccess = await Gal.hasPermission(toAlbum: true);
      if (!hasAccess) {
        await Gal.requestPermission(toAlbum: true);
      }
      await Gal.putVideo(filePath, album: _albumName);
      saved = true;
      AppLog.add('Galleria: salvato in album "$_albumName"');
    } on GalException catch (e) {
      // Il video è comunque scaricato e condivisibile: non blocchiamo tutto.
      saved = false;
      AppLog.add('Galleria: ERRORE ${e.type.message}');
    }

    return DownloadResult(filePath: filePath, savedToGallery: saved);
  }
}
