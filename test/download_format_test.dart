import 'package:better_player_plus/better_player.dart';
import 'package:flixquest/functions/video_utils.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('VideoUtils.inferDownloadFormat', () {
    test('declared manifest formats win over the URL', () {
      expect(
        VideoUtils.inferDownloadFormat(
          declaredFormat: BetterPlayerVideoFormat.dash,
          url: 'https://cdn.example/video.m3u8',
        ),
        'dash',
      );
      expect(
        VideoUtils.inferDownloadFormat(
          declaredFormat: BetterPlayerVideoFormat.hls,
          url: 'https://cdn.example/video.mp4',
        ),
        'hls',
      );
    });

    test('manifest extensions in the URL win without a declaration', () {
      expect(
        VideoUtils.inferDownloadFormat(
          declaredFormat: null,
          url: 'https://cdn.example/master.mpd?token=abc',
        ),
        'dash',
      );
      expect(
        VideoUtils.inferDownloadFormat(
          declaredFormat: null,
          url: 'https://cdn.example/playlist.m3u8?token=abc',
        ),
        'hls',
      );
    });

    test('anything else is progressive, including signed extension-less URLs',
        () {
      expect(
        VideoUtils.inferDownloadFormat(
          declaredFormat: null,
          url: 'https://cdn.example/stream/abc123?token=signed&expires=99',
        ),
        'progressive',
      );
      expect(
        VideoUtils.inferDownloadFormat(
          declaredFormat: BetterPlayerVideoFormat.other,
          url: 'https://cdn.example/video.mp4?token=signed',
        ),
        'progressive',
      );
    });
  });
}
