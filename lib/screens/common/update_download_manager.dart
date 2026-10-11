import 'dart:async';
import 'dart:io';

import 'package:flutter_download_manager/flutter_download_manager.dart';
import 'package:http/http.dart' as http;

/// Drop-in replacement for package:flutter_download_manager's DownloadManager.
///
/// The package's Dio-based downloader does not reliably follow redirects
/// (e.g. GitHub release asset URLs 302 to a signed CDN URL), leaving update
/// downloads stalled at 0%. This implementation follows redirects manually
/// and streams the response body to disk with progress reporting.
///
/// It reuses the package's [DownloadTask], [DownloadRequest] and
/// [DownloadStatus] types so the existing update-screen UI works unchanged.
class UpdateDownloadManager {
  final Map<String, DownloadTask> _tasks = {};
  final Map<String, _ActiveDownload> _active = {};

  DownloadTask? getDownload(String url) => _tasks[url];

  static String getFileNameFromUrl(String url) {
    final uri = Uri.tryParse(url);
    if (uri == null) return 'download.apk';
    final segments = uri.pathSegments;
    if (segments.isEmpty) return 'download.apk';
    return segments.last;
  }

  Future<DownloadTask?> addDownload(String url, String savePath) async {
    if (url.isEmpty) return null;
    // Cancel any previous attempt for this URL.
    await _cancelActive(url);
    final request = DownloadRequest(url, savePath);
    final task = DownloadTask(request);
    _tasks[url] = task;
    _startDownload(task);
    return task;
  }

  Future<void> pauseDownload(String url) async {
    final task = _tasks[url];
    if (task == null) return;
    await _cancelActive(url);
    if (task.status.value == DownloadStatus.downloading ||
        task.status.value == DownloadStatus.queued) {
      task.status.value = DownloadStatus.paused;
    }
  }

  Future<void> resumeDownload(String url) async {
    final task = _tasks[url];
    if (task == null) return;
    if (task.status.value != DownloadStatus.paused &&
        task.status.value != DownloadStatus.failed) {
      return;
    }
    await _cancelActive(url);
    _startDownload(task);
  }

  Future<void> removeDownload(String url) async {
    await _cancelActive(url);
    _tasks.remove(url);
  }

  Future<void> _cancelActive(String url) async {
    final active = _active.remove(url);
    if (active != null) {
      await active.cancel();
    }
  }

  void _startDownload(DownloadTask task) {
    final url = task.request.url;
    final savePath = task.request.path;
    task.status.value = DownloadStatus.downloading;
    final active = _ActiveDownload();
    _active[url] = active;
    _runDownload(task, active).then((_) {
      _active.remove(url);
    });
  }

  Future<void> _runDownload(DownloadTask task, _ActiveDownload active) async {
    final url = task.request.url;
    final savePath = task.request.path;
    final client = http.Client();
    try {
      // Follow redirects manually (up to 5), keeping the final URL.
      var current = url;
      http.StreamedResponse? response;
      for (var i = 0; i < 6; i++) {
        if (active.cancelled) return;
        final req = http.Request('GET', Uri.parse(current));
        req.followRedirects = false;
        req.headers[HttpHeaders.userAgentHeader] =
            'Mozilla/5.0 (Linux; Android 14) AppleWebKit/537.36';
        // Resume from where we left off, if we have a partial file.
        final partial = File('$savePath.partial');
        var startAt = 0;
        if (await partial.exists()) {
          startAt = await partial.length();
          if (startAt > 0) {
            req.headers[HttpHeaders.rangeHeader] = 'bytes=$startAt-';
          }
        }
        response = await client.send(req).timeout(
              const Duration(seconds: 30),
            );
        if (response.statusCode >= 300 && response.statusCode < 400) {
          final location = response.headers['location'];
          await response.stream.drain();
          if (location == null || location.isEmpty) {
            throw HttpException('Redirect without location header');
          }
          // Resolve relative redirects against the current URL.
          current = Uri.parse(current).resolve(location).toString();
          response = null;
          continue;
        }
        break;
      }
      final res = response;
      if (res == null) {
        throw HttpException('Too many redirects');
      }
      if (res.statusCode != 200 && res.statusCode != 206) {
        await res.stream.drain();
        throw HttpException('Download failed: HTTP ${res.statusCode}');
      }

      final total = res.contentLength ?? -1;
      // If we sent a Range request but got 200 (not 206), the server ignored
      // it — start the file over.
      final partial = File('$savePath.partial');
      var downloaded = 0;
      if (res.statusCode == 200 && await partial.exists()) {
        final existing = await partial.length();
        if (existing > 0) {
          // Server ignored our range; discard partial to avoid corruption.
          await partial.delete();
        }
      } else if (res.statusCode == 206) {
        downloaded = await partial.exists() ? await partial.length() : 0;
      }
      final expectedTotal =
          total == -1 ? -1 : total + (res.statusCode == 206 ? downloaded : 0);

      final sink = partial.openWrite(mode: FileMode.writeOnlyAppend);
      try {
        await for (final chunk in res.stream) {
          if (active.cancelled) {
            await sink.close();
            return;
          }
          sink.add(chunk);
          downloaded += chunk.length;
          if (expectedTotal > 0) {
            task.progress.value =
                (downloaded / expectedTotal).clamp(0.0, 1.0);
          }
        }
        await sink.flush();
        await sink.close();
      } catch (_) {
        try {
          await sink.close();
        } catch (_) {}
        rethrow;
      }

      if (active.cancelled) return;
      await partial.rename(savePath);
      task.progress.value = 1.0;
      task.status.value = DownloadStatus.completed;
    } catch (e) {
      if (active.cancelled) return;
      task.status.value = DownloadStatus.failed;
    } finally {
      client.close();
    }
  }
}

class _ActiveDownload {
  bool cancelled = false;
  Future<void> cancel() async {
    cancelled = true;
  }
}
