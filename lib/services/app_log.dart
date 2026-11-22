import 'package:flutter/foundation.dart';

/// Log diagnostico in-memory, esportabile dall'utente per capire gli errori.
/// Vi scrivono il resolver, il downloader e l'updater.
class AppLog {
  AppLog._();

  static final List<String> _lines = [];
  static const int _max = 600;

  static void add(String message) {
    final ts = DateTime.now().toIso8601String().substring(11, 23);
    _lines.add('[$ts] $message');
    if (_lines.length > _max) _lines.removeRange(0, _lines.length - _max);
    if (kDebugMode) debugPrint('AppLog: $message');
  }

  /// Avvia una nuova sezione (es. un nuovo tentativo di download).
  static void section(String title) {
    add('──────── $title ────────');
  }

  static String dump() => _lines.join('\n');

  static void clear() => _lines.clear();

  static bool get isEmpty => _lines.isEmpty;
}
