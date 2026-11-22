import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:receive_sharing_intent/receive_sharing_intent.dart';
import 'package:share_plus/share_plus.dart';

import 'services/app_log.dart';
import 'services/download_service.dart';
import 'services/instagram_resolver.dart';
import 'services/update_service.dart';
import 'widgets/update_bottom_sheet.dart';

void main() {
  runApp(const ReelSaverApp());
}

class ReelSaverApp extends StatelessWidget {
  const ReelSaverApp({super.key});

  @override
  Widget build(BuildContext context) {
    const seed = Color(0xFFD62976); // rosa/magenta stile Instagram
    return MaterialApp(
      title: 'Reel Saver',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: seed),
        useMaterial3: true,
      ),
      darkTheme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: seed,
          brightness: Brightness.dark,
        ),
        useMaterial3: true,
      ),
      home: const HomeScreen(),
    );
  }
}

enum _Phase { idle, working, done, error }

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final _resolver = InstagramResolver();
  final _downloader = DownloadService();
  final _update = UpdateService();
  final _controller = TextEditingController();

  StreamSubscription<List<SharedMediaFile>>? _sub;

  _Phase _phase = _Phase.idle;
  String _message = '';
  double? _progress;
  DownloadResult? _result;

  @override
  void initState() {
    super.initState();
    _initShareIntent();
    WidgetsBinding.instance.addPostFrameCallback((_) => _checkForUpdate());
  }

  Future<void> _checkForUpdate() async {
    final info = await _update.check();
    if (!mounted || info == null) return;
    await UpdateBottomSheet.show(context, info, _update);
  }

  void _initShareIntent() {
    // App già aperta: nuovo contenuto condiviso.
    _sub = ReceiveSharingIntent.instance.getMediaStream().listen(
      _handleShared,
      onError: (_) {},
    );

    // App lanciata da una condivisione.
    ReceiveSharingIntent.instance.getInitialMedia().then((files) {
      _handleShared(files);
      ReceiveSharingIntent.instance.reset();
    }).catchError((_) {
      // Nessuna condivisione iniziale / canale non disponibile: ignora.
    });
  }

  void _handleShared(List<SharedMediaFile> files) {
    if (files.isEmpty) return;
    String? text;
    for (final f in files) {
      if (f.path.contains('instagram.com')) {
        text = f.path;
        break;
      }
      if (f.type == SharedMediaType.text || f.type == SharedMediaType.url) {
        text ??= f.path;
      }
    }
    if (text == null) return;
    _controller.text = text;
    _process(text);
  }

  Future<void> _pasteFromClipboard() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    if (data?.text != null && data!.text!.isNotEmpty) {
      _controller.text = data.text!;
    }
  }

  Future<void> _shareLog() async {
    await SharePlus.instance.share(
      ShareParams(text: AppLog.dump(), subject: 'Reel Saver — log'),
    );
  }

  Future<void> _copyLog() async {
    await Clipboard.setData(ClipboardData(text: AppLog.dump()));
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Log copiato negli appunti')),
      );
    }
  }

  Future<void> _process(String url) async {
    FocusScope.of(context).unfocus();
    AppLog.section('Nuovo download');
    setState(() {
      _phase = _Phase.working;
      _message = 'Analizzo il link…';
      _progress = null;
      _result = null;
    });

    try {
      final media = await _resolver.resolve(url);

      if (!mounted) return;
      setState(() {
        _message = 'Scarico il video…';
        _progress = 0;
      });

      final result = await _downloader.downloadAndSave(
        videoUrl: media.videoUrl,
        shortcode: media.shortcode,
        onProgress: (p) {
          if (mounted) setState(() => _progress = p);
        },
      );

      if (!mounted) return;
      setState(() {
        _phase = _Phase.done;
        _result = result;
      });
    } on ResolveException catch (e) {
      _fail(e.message);
    } on DownloadException catch (e) {
      _fail(e.message);
    } catch (e) {
      _fail('Si è verificato un errore imprevisto.\n$e');
    }
  }

  void _fail(String msg) {
    if (!mounted) return;
    setState(() {
      _phase = _Phase.error;
      _message = msg;
    });
  }

  Future<void> _share() async {
    final path = _result?.filePath;
    if (path == null) return;
    await SharePlus.instance.share(
      ShareParams(
        files: [XFile(path, mimeType: 'video/mp4')],
        text: 'Condiviso con Reel Saver',
      ),
    );
  }

  void _reset() {
    setState(() {
      _phase = _Phase.idle;
      _message = '';
      _progress = null;
      _result = null;
      _controller.clear();
    });
  }

  @override
  void dispose() {
    _sub?.cancel();
    _controller.dispose();
    _resolver.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Reel Saver'),
        centerTitle: true,
        backgroundColor: theme.colorScheme.primaryContainer,
        actions: [
          IconButton(
            tooltip: 'Esporta log diagnostico',
            icon: const Icon(Icons.bug_report_outlined),
            onPressed: _shareLog,
          ),
        ],
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: 8),
              Icon(Icons.movie_creation_outlined,
                  size: 56, color: theme.colorScheme.primary),
              const SizedBox(height: 12),
              Text(
                'Incolla o condividi un link di Instagram',
                textAlign: TextAlign.center,
                style: theme.textTheme.titleMedium,
              ),
              const SizedBox(height: 4),
              Text(
                'Solo reel/post pubblici',
                textAlign: TextAlign.center,
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: theme.colorScheme.outline),
              ),
              const SizedBox(height: 24),
              TextField(
                controller: _controller,
                decoration: InputDecoration(
                  labelText: 'Link Instagram',
                  hintText: 'https://www.instagram.com/reel/…',
                  border: const OutlineInputBorder(),
                  suffixIcon: IconButton(
                    tooltip: 'Incolla',
                    icon: const Icon(Icons.content_paste),
                    onPressed: _pasteFromClipboard,
                  ),
                ),
                keyboardType: TextInputType.url,
                maxLines: 2,
                minLines: 1,
              ),
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: _phase == _Phase.working
                    ? null
                    : () {
                        final url = _controller.text.trim();
                        if (url.isNotEmpty) _process(url);
                      },
                icon: const Icon(Icons.download),
                label: const Padding(
                  padding: EdgeInsets.symmetric(vertical: 12),
                  child: Text('Scarica e salva'),
                ),
              ),
              const SizedBox(height: 28),
              _buildStatus(theme),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildStatus(ThemeData theme) {
    switch (_phase) {
      case _Phase.idle:
        return const SizedBox.shrink();

      case _Phase.working:
        return Column(
          children: [
            LinearProgressIndicator(value: _progress),
            const SizedBox(height: 12),
            Text(
              _progress != null
                  ? '$_message ${(_progress! * 100).toStringAsFixed(0)}%'
                  : _message,
              textAlign: TextAlign.center,
            ),
          ],
        );

      case _Phase.done:
        final saved = _result?.savedToGallery ?? false;
        return Card(
          color: theme.colorScheme.secondaryContainer,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                Icon(Icons.check_circle,
                    color: theme.colorScheme.primary, size: 40),
                const SizedBox(height: 8),
                Text(
                  saved
                      ? 'Video salvato nella galleria (album "Reel Saver").'
                      : 'Video scaricato. Non è stato possibile salvarlo in galleria, ma puoi condividerlo.',
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: FilledButton.icon(
                        onPressed: _share,
                        icon: const Icon(Icons.share),
                        label: const Text('Condividi'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: _reset,
                        icon: const Icon(Icons.refresh),
                        label: const Text('Nuovo'),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );

      case _Phase.error:
        return Card(
          color: theme.colorScheme.errorContainer,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                Icon(Icons.error_outline,
                    color: theme.colorScheme.error, size: 40),
                const SizedBox(height: 8),
                Text(_message, textAlign: TextAlign.center),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: _shareLog,
                        icon: const Icon(Icons.ios_share, size: 18),
                        label: const Text('Esporta log'),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: _copyLog,
                        icon: const Icon(Icons.copy, size: 18),
                        label: const Text('Copia log'),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                FilledButton.icon(
                  onPressed: _reset,
                  icon: const Icon(Icons.refresh),
                  label: const Text('Riprova'),
                ),
              ],
            ),
          ),
        );
    }
  }
}
