// Diagnostic script: runs the app's real InstagramResolver on a URL.
// Usage: dart run tool/try_resolve.dart "<instagram url>"
import 'package:ig_saver/services/instagram_resolver.dart';

Future<void> main(List<String> args) async {
  if (args.isEmpty) {
    print('Pass an Instagram URL.');
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
    print('ERROR: $e');
  } finally {
    r.dispose();
  }
}
