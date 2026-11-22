import 'package:flutter/material.dart';

import '../services/update_service.dart';

/// Bottomsheet mostrato all'avvio quando è disponibile una nuova versione.
/// Scarica l'APK con avanzamento e lancia l'installer di sistema.
class UpdateBottomSheet extends StatefulWidget {
  const UpdateBottomSheet({
    super.key,
    required this.info,
    required this.service,
  });

  final UpdateInfo info;
  final UpdateService service;

  /// Helper per mostrarlo.
  static Future<void> show(
    BuildContext context,
    UpdateInfo info,
    UpdateService service,
  ) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      isDismissible: true,
      showDragHandle: true,
      builder: (_) => UpdateBottomSheet(info: info, service: service),
    );
  }

  @override
  State<UpdateBottomSheet> createState() => _UpdateBottomSheetState();
}

class _UpdateBottomSheetState extends State<UpdateBottomSheet> {
  bool _downloading = false;
  double _progress = 0;
  String? _error;

  Future<void> _start() async {
    setState(() {
      _downloading = true;
      _progress = 0;
      _error = null;
    });
    try {
      final path = await widget.service.downloadApk(
        widget.info.apkUrl,
        onProgress: (p) {
          if (mounted) setState(() => _progress = p);
        },
      );
      await widget.service.install(path);
      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      if (mounted) {
        setState(() {
          _downloading = false;
          _error = 'Download non riuscito. Riprova.\n$e';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final info = widget.info;
    return Padding(
      padding: EdgeInsets.only(
        left: 20,
        right: 20,
        top: 4,
        bottom: MediaQuery.of(context).viewInsets.bottom + 24,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(Icons.system_update, color: theme.colorScheme.primary),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Nuova versione disponibile',
                  style: theme.textTheme.titleLarge,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            'Versione ${info.versionName}',
            style: theme.textTheme.titleSmall
                ?.copyWith(color: theme.colorScheme.outline),
          ),
          if (info.notes != null && info.notes!.trim().isNotEmpty) ...[
            const SizedBox(height: 14),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: theme.colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(info.notes!.trim()),
            ),
          ],
          const SizedBox(height: 20),
          if (_error != null) ...[
            Text(_error!,
                style: TextStyle(color: theme.colorScheme.error)),
            const SizedBox(height: 12),
          ],
          if (_downloading) ...[
            LinearProgressIndicator(value: _progress),
            const SizedBox(height: 10),
            Text(
              'Scarico… ${(_progress * 100).toStringAsFixed(0)}%',
              textAlign: TextAlign.center,
            ),
          ] else
            FilledButton.icon(
              onPressed: _start,
              icon: const Icon(Icons.download),
              label: const Padding(
                padding: EdgeInsets.symmetric(vertical: 12),
                child: Text('Scarica e installa'),
              ),
            ),
          const SizedBox(height: 8),
          if (!_downloading)
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Più tardi'),
            ),
        ],
      ),
    );
  }
}
