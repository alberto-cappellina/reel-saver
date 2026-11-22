import 'dart:convert';

import 'package:cookie_jar/cookie_jar.dart';
import 'package:dio/dio.dart';
import 'package:dio_cookie_manager/dio_cookie_manager.dart';

import 'app_log.dart';

/// Risultato della risoluzione di un contenuto Instagram.
class ResolvedMedia {
  ResolvedMedia({
    required this.videoUrl,
    required this.shortcode,
    this.thumbnailUrl,
  });

  final String videoUrl;
  final String shortcode;
  final String? thumbnailUrl;
}

class ResolveException implements Exception {
  ResolveException(this.message);
  final String message;
  @override
  String toString() => message;
}

/// Risolve un URL pubblico di Instagram (reel/post) nel link diretto al video,
/// interamente lato client (nessun backend).
///
/// Metodo (replica dell'estrattore sloggato di yt-dlp):
///   1. GET https://www.instagram.com/  -> stabilisce la sessione (cookie).
///   2. GET https://www.instagram.com/p/{shortcode}/ con header "da browser"
///      (in particolare `Sec-Fetch-Mode: navigate`): la pagina incorpora i dati
///      del media nei blocchi `data-sjs`, da cui si estraggono le
///      `video_versions` (file .mp4 progressivo H.264 + audio).
///   3. Fallback: endpoint GraphQL e `api/v1/media/{pk}/info/`.
///
/// Nota: Instagram può cambiare in qualsiasi momento; per questo ci sono più
/// strategie e un log diagnostico esportabile ([AppLog]).
class InstagramResolver {
  InstagramResolver() {
    _dio = Dio(BaseOptions(
      connectTimeout: const Duration(seconds: 20),
      receiveTimeout: const Duration(seconds: 25),
      followRedirects: true,
      validateStatus: (s) => s != null && s < 500,
    ));
    _dio.interceptors.add(CookieManager(_cookies));
  }

  late final Dio _dio;
  final CookieJar _cookies = CookieJar();
  String? _lsdToken;

  static const String _appId = '936619743392459';
  static const String _ua =
      'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 '
      '(KHTML, like Gecko) Chrome/149.0.0.0 Safari/537.36';
  static const String _encChars =
      'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_';

  static final RegExp _shortcodeRe =
      RegExp(r'instagram\.com/(?:reels?|p|tv)/([A-Za-z0-9_-]+)');
  static final RegExp _sjsRe =
      RegExp(r'<script\b[^>]+\bdata-sjs>(\{.+?\})</script>', dotAll: true);

  // Header "da browser" — Sec-Fetch-Mode: navigate è decisivo: senza, Instagram
  // serve solo il guscio della pagina senza i dati del media.
  Map<String, String> get _browserHeaders => {
        'User-Agent': _ua,
        'Accept':
            'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8',
        'Accept-Language': 'en-us,en;q=0.5',
        'Sec-Fetch-Mode': 'navigate',
      };

  Map<String, String> get _apiHeaders => {
        'User-Agent': _ua,
        'X-IG-App-ID': _appId,
        'X-ASBD-ID': '359341',
        'X-IG-WWW-Claim': '0',
        'Origin': 'https://www.instagram.com',
        'Accept': '*/*',
        'Sec-Fetch-Mode': 'navigate',
      };

  /// Punto d'ingresso principale.
  Future<ResolvedMedia> resolve(String rawUrl) async {
    AppLog.section('Risoluzione Instagram');
    final url = _firstInstagramUrl(rawUrl);
    AppLog.add('Input: "${_short(rawUrl)}" -> url: ${url ?? "NESSUNO"}');
    if (url == null) {
      throw ResolveException(
          'Non ho trovato un link di Instagram nel testo condiviso.');
    }

    final shortcode = await _extractShortcode(url);
    AppLog.add('shortcode: ${shortcode ?? "NON TROVATO"}');
    if (shortcode == null) {
      throw ResolveException(
          'Non riesco a identificare il reel/post da questo link.');
    }
    final pk = _shortcodeToPk(shortcode);
    AppLog.add('media_id (pk): $pk');

    await _setupSession();

    // 1) Pagina del post (metodo principale, verificato).
    final fromPage = await _tryPostPage(shortcode);
    if (fromPage != null) return fromPage;

    // 2) GraphQL.
    final fromGraphql = await _tryGraphql(pk, shortcode, url);
    if (fromGraphql != null) return fromGraphql;

    // 3) Endpoint media info.
    final fromInfo = await _tryMediaInfo(pk, shortcode);
    if (fromInfo != null) return fromInfo;

    AppLog.add('ESITO: nessuna strategia ha trovato il video.');
    throw ResolveException(
      'Impossibile estrarre il video. Il contenuto potrebbe essere privato, '
      'rimosso, oppure Instagram ha cambiato le sue pagine. Usa "Esporta log" '
      'per i dettagli; riprova più tardi se è un rate-limit.',
    );
  }

  // --- Sessione -------------------------------------------------------------

  Future<void> _setupSession() async {
    try {
      final resp = await _dio.get<String>(
        'https://www.instagram.com/',
        options:
            Options(headers: _browserHeaders, responseType: ResponseType.plain),
      );
      final html = resp.data ?? '';
      _lsdToken = _firstGroup(
            RegExp(r'"LSD",\[\],\{"token":"([^"]+)"').firstMatch(html),
          ) ??
          _firstGroup(RegExp(r'"l":"([^"]+)"').firstMatch(html));
      final csrf = await _csrfToken();
      AppLog.add('Sessione: status ${resp.statusCode}, '
          'csrftoken ${csrf != null ? "ok" : "assente"}, '
          'lsd ${_lsdToken != null ? "ok" : "assente"}');
    } catch (e) {
      AppLog.add('Sessione: ERRORE ${_err(e)}');
    }
  }

  Future<String?> _csrfToken() async {
    final cookies =
        await _cookies.loadForRequest(Uri.parse('https://www.instagram.com/'));
    for (final c in cookies) {
      if (c.name == 'csrftoken') return c.value;
    }
    return null;
  }

  // --- Strategie ------------------------------------------------------------

  Future<ResolvedMedia?> _tryPostPage(String shortcode) async {
    final urlStr = 'https://www.instagram.com/p/$shortcode/';
    try {
      final resp = await _dio.get<String>(
        urlStr,
        options:
            Options(headers: _browserHeaders, responseType: ResponseType.plain),
      );
      final html = resp.data ?? '';
      final blocks = _sjsRe.allMatches(html).length;
      final cands = <_Cand>[];
      String? thumb;
      for (final m in _sjsRe.allMatches(html)) {
        final raw = m.group(1);
        if (raw == null) continue;
        try {
          final json = jsonDecode(raw);
          _collect(json, cands);
          thumb ??= _findThumb(json);
        } catch (_) {}
      }
      final best = _best(cands);
      AppLog.add('Pagina /p/: status ${resp.statusCode}, '
          '${html.length} byte, $blocks blocchi data-sjs, '
          '${cands.length} candidati video -> ${best != null ? "TROVATO" : "niente"}');
      if (best != null) {
        return ResolvedMedia(
            videoUrl: best, shortcode: shortcode, thumbnailUrl: thumb);
      }
      // Ultima spiaggia: og:video nel markup.
      final og = _firstGroup(
          RegExp(r'property="og:video"\s+content="([^"]+)"').firstMatch(html));
      if (og != null && og.startsWith('http')) {
        AppLog.add('Pagina /p/: trovato og:video');
        return ResolvedMedia(videoUrl: og, shortcode: shortcode);
      }
    } catch (e) {
      AppLog.add('Pagina /p/: ERRORE ${_err(e)}');
    }
    return null;
  }

  Future<ResolvedMedia?> _tryGraphql(
      String pk, String shortcode, String refererUrl) async {
    try {
      final csrf = await _csrfToken();
      final resp = await _dio.post(
        'https://www.instagram.com/api/graphql',
        data: {
          'lsd': _lsdToken ?? '',
          'fb_api_caller_class': 'RelayModern',
          'fb_api_req_friendly_name':
              'PolarisLoggedOutDesktopWWWPostRootContentQuery',
          'server_timestamps': 'true',
          'variables': jsonEncode({'media_id': pk}),
          'doc_id': '27130156389949648',
        },
        options: Options(
          contentType: Headers.formUrlEncodedContentType,
          responseType: ResponseType.json,
          headers: {
            ..._apiHeaders,
            'X-FB-Friendly-Name':
                'PolarisLoggedOutDesktopWWWPostRootContentQuery',
            if (csrf != null) 'X-CSRFToken': csrf,
            if (_lsdToken != null) 'X-FB-LSD': _lsdToken!,
            'X-Requested-With': 'XMLHttpRequest',
            'Referer': refererUrl,
          },
        ),
      );
      final media = _buildFromJson(_asJson(resp.data), shortcode);
      AppLog.add('GraphQL: status ${resp.statusCode} -> '
          '${media != null ? "TROVATO" : "niente"}');
      return media;
    } catch (e) {
      AppLog.add('GraphQL: ERRORE ${_err(e)}');
      return null;
    }
  }

  Future<ResolvedMedia?> _tryMediaInfo(String pk, String shortcode) async {
    try {
      final resp = await _dio.get(
        'https://www.instagram.com/api/v1/media/$pk/info/',
        options: Options(headers: _apiHeaders, responseType: ResponseType.json),
      );
      final media = _buildFromJson(_asJson(resp.data), shortcode);
      AppLog.add('media/info: status ${resp.statusCode} -> '
          '${media != null ? "TROVATO" : "niente"}');
      return media;
    } catch (e) {
      AppLog.add('media/info: ERRORE ${_err(e)}');
      return null;
    }
  }

  ResolvedMedia? _buildFromJson(dynamic json, String shortcode) {
    if (json == null) return null;
    final cands = <_Cand>[];
    _collect(json, cands);
    final best = _best(cands);
    if (best == null) return null;
    return ResolvedMedia(
      videoUrl: best,
      shortcode: shortcode,
      thumbnailUrl: _findThumb(json),
    );
  }

  // --- Parsing ricorsivo ----------------------------------------------------

  void _collect(dynamic node, List<_Cand> out) {
    if (node is Map) {
      final vv = node['video_versions'];
      if (vv is List) {
        for (final v in vv) {
          if (v is Map && v['url'] is String) {
            final w = (v['width'] is num) ? (v['width'] as num).toInt() : 0;
            final h = (v['height'] is num) ? (v['height'] as num).toInt() : 0;
            out.add(_Cand(v['url'] as String, w * h));
          }
        }
      }
      final vu = node['video_url'];
      if (vu is String && vu.startsWith('http')) {
        out.add(_Cand(vu, 1));
      }
      for (final val in node.values) {
        _collect(val, out);
      }
    } else if (node is List) {
      for (final e in node) {
        _collect(e, out);
      }
    }
  }

  String? _best(List<_Cand> cands) {
    if (cands.isEmpty) return null;
    cands.sort((a, b) => b.score.compareTo(a.score));
    return cands.first.url;
  }

  String? _findThumb(dynamic node) {
    if (node is Map) {
      for (final key in const ['display_url', 'thumbnail_url', 'thumbnail_src']) {
        final v = node[key];
        if (v is String && v.startsWith('http')) return v;
      }
      final iv = node['image_versions2'];
      if (iv is Map && iv['candidates'] is List) {
        for (final c in (iv['candidates'] as List)) {
          if (c is Map && c['url'] is String) return c['url'] as String;
        }
      }
      for (final val in node.values) {
        final found = _findThumb(val);
        if (found != null) return found;
      }
    } else if (node is List) {
      for (final e in node) {
        final found = _findThumb(e);
        if (found != null) return found;
      }
    }
    return null;
  }

  // --- Utilità --------------------------------------------------------------

  String? _firstGroup(RegExpMatch? m) => m?.group(1);

  String _short(String s) => s.length > 80 ? '${s.substring(0, 80)}…' : s;

  String _err(Object e) {
    if (e is DioException) {
      return '${e.type.name} ${e.response?.statusCode ?? ""} ${e.message ?? ""}'
          .trim();
    }
    return e.toString();
  }

  String? _firstInstagramUrl(String text) {
    final m = RegExp(r'https?://[^\s]*instagram\.com/[^\s]+').firstMatch(text);
    return m?.group(0)?.replaceAll(RegExp(r'[)\]\s]+$'), '');
  }

  Future<String?> _extractShortcode(String url) async {
    final direct = _shortcodeRe.firstMatch(url);
    if (direct != null) return direct.group(1);
    try {
      final resp = await _dio.get<String>(
        url,
        options:
            Options(headers: _browserHeaders, responseType: ResponseType.plain),
      );
      final finalUrl = resp.realUri.toString();
      final m1 = _shortcodeRe.firstMatch(finalUrl);
      if (m1 != null) return m1.group(1);
      final m2 = _shortcodeRe.firstMatch(resp.data ?? '');
      if (m2 != null) return m2.group(1);
    } catch (e) {
      AppLog.add('Redirect shortcode: ERRORE ${_err(e)}');
    }
    return null;
  }

  String _shortcodeToPk(String shortcode) {
    var code = shortcode;
    if (code.length > 28) code = code.substring(0, code.length - 28);
    var pk = BigInt.zero;
    final base = BigInt.from(64);
    for (final ch in code.split('')) {
      final idx = _encChars.indexOf(ch);
      if (idx < 0) continue;
      pk = pk * base + BigInt.from(idx);
    }
    return pk.toString();
  }

  dynamic _asJson(dynamic data) {
    if (data is String) {
      try {
        return jsonDecode(data);
      } catch (_) {
        return null;
      }
    }
    return data;
  }

  void dispose() => _dio.close(force: true);
}

class _Cand {
  _Cand(this.url, this.score);
  final String url;
  final int score;
}
