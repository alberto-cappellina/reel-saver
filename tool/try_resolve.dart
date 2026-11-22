// Script di diagnostica: esegue il vero InstagramResolver dell'app su un URL.
// Uso: dart run tool/try_resolve.dart "<url instagram>"
import 'package:ig_saver/services/instagram_resolver.dart';

Future<void> main(List<String> args) async {
  if (args.isEmpty) {
    print('Passa un URL Instagram.');
    return;
  }
  final r = InstagramResolver();
  try {
    final m = await r.resolve(args.first);
    print('OK');
    print('shortcode: ${m.shortcode}');
    print('video_url: ${m.videoUrl}');
    print('thumbnail: ${m.thumbnailUrl}');
  } catch (e) {
    print('ERRORE: $e');
  } finally {
    r.dispose();
  }
}
