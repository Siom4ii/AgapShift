import 'dart:collection';
import 'dart:io';
import 'dart:math' as math;

import 'package:image/image.dart' as img;

void main(List<String> args) {
  final inputPath = args.isNotEmpty ? args[0] : 'branding/agapshift_logo_lockup.png';
  final outputPath = args.length > 1 ? args[1] : 'branding/agapshift_logo_mark.png';

  final bytes = File(inputPath).readAsBytesSync();
  final src = img.decodeImage(bytes);
  if (src == null) {
    stderr.writeln('Failed to decode: ');
    exitCode = 2;
    return;
  }

  final image = src.convert(numChannels: 4);
  final w = image.width;
  final h = image.height;

  // Learn bg color from corners + edge midpoints.
  int sr = 0, sg = 0, sb = 0, samples = 0;
  void sample(int x, int y) {
    final p = image.getPixel(x, y);
    sr += p.r.toInt();
    sg += p.g.toInt();
    sb += p.b.toInt();
    samples++;
  }

  sample(0, 0);
  sample(w - 1, 0);
  sample(0, h - 1);
  sample(w - 1, h - 1);
  sample(w ~/ 2, 0);
  sample(w ~/ 2, h - 1);
  final bgR = sr ~/ samples;
  final bgG = sg ~/ samples;
  final bgB = sb ~/ samples;

  const tol = 40;
  bool nearBg(int r, int g, int b) {
    return (r - bgR).abs() <= tol && (g - bgG).abs() <= tol && (b - bgB).abs() <= tol;
  }

  // Flood-fill background connected to the outer edges.
  final q = ListQueue<(int, int)>();
  final seen = List<int>.filled(w * h, 0);
  void push(int x, int y) {
    if (x < 0 || y < 0 || x >= w || y >= h) return;
    final i = y * w + x;
    if (seen[i] == 1) return;
    seen[i] = 1;
    final p = image.getPixel(x, y);
    if (p.a == 0) return;
    final r = p.r.toInt();
    final g = p.g.toInt();
    final b = p.b.toInt();
    if (!nearBg(r, g, b)) return;
    q.add((x, y));
  }

  push(0, 0);
  push(w - 1, 0);
  push(0, h - 1);
  push(w - 1, h - 1);
  push(w ~/ 2, 0);
  push(w ~/ 2, h - 1);
  push(0, h ~/ 2);
  push(w - 1, h ~/ 2);

  while (q.isNotEmpty) {
    final (x, y) = q.removeFirst();
    image.setPixelRgba(x, y, 0, 0, 0, 0);
    push(x + 1, y);
    push(x - 1, y);
    push(x, y + 1);
    push(x, y - 1);
  }

  // Crop to icon-only area (top ~72% of content bbox, then square crop).
  int minX = w, minY = h, maxX = 0, maxY = 0;
  for (var y = 0; y < h; y++) {
    for (var x = 0; x < w; x++) {
      final p = image.getPixel(x, y);
      if (p.a == 0) continue;
      if (x < minX) minX = x;
      if (y < minY) minY = y;
      if (x > maxX) maxX = x;
      if (y > maxY) maxY = y;
    }
  }

  img.Image out = image;
  if (minX < maxX && minY < maxY) {
    final bboxW = (maxX - minX + 1);
    final bboxH = (maxY - minY + 1);
    final iconH = (bboxH * 0.72).round();
    final square = math.min(bboxW, iconH);
    final cropX = minX + ((bboxW - square) ~/ 2);
    final cropY = minY;
    out = img.copyCrop(out, x: cropX, y: cropY, width: square, height: square);
  }

  final outBytes = img.encodePng(out, level: 6);
  File(outputPath).writeAsBytesSync(outBytes);
  stdout.writeln('Wrote:  (x)');
}
