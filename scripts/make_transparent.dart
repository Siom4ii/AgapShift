import 'dart:collection';
import 'dart:io';

import 'package:image/image.dart' as img;

void main(List<String> args) {
  final inputPath = args.isNotEmpty ? args[0] : 'branding/agapshift_logo_lockup_whitebg.png';
  final outputPath = args.length > 1 ? args[1] : 'branding/agapshift_logo_lockup_transparent.png';

  final bytes = File(inputPath).readAsBytesSync();
  final src0 = img.decodeImage(bytes);
  if (src0 == null) {
    stderr.writeln('Failed to decode: ' + inputPath);
    exitCode = 2;
    return;
  }

  final src = src0.convert(numChannels: 4);
  final w = src.width;
  final h = src.height;

  // Learn background color from corners + mid edges.
  int sr = 0, sg = 0, sb = 0, samples = 0;
  void sample(int x, int y) {
    final p = src.getPixel(x, y);
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
  sample(0, h ~/ 2);
  sample(w - 1, h ~/ 2);

  final bgR = sr ~/ samples;
  final bgG = sg ~/ samples;
  final bgB = sb ~/ samples;

  // Slightly higher tolerance for JPEG-ish edge noise.
  const tol = 28;
  bool nearBg(int r, int g, int b) {
    return (r - bgR).abs() <= tol && (g - bgG).abs() <= tol && (b - bgB).abs() <= tol;
  }

  final q = ListQueue<(int, int)>();
  final seen = List<int>.filled(w * h, 0);
  void push(int x, int y) {
    if (x < 0 || y < 0 || x >= w || y >= h) return;
    final i = y * w + x;
    if (seen[i] == 1) return;
    seen[i] = 1;
    final p = src.getPixel(x, y);
    if (p.a == 0) return;
    final r = p.r.toInt();
    final g = p.g.toInt();
    final b = p.b.toInt();
    if (!nearBg(r, g, b)) return;
    q.add((x, y));
  }

  // Seed edges.
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
    src.setPixelRgba(x, y, 0, 0, 0, 0);
    push(x + 1, y);
    push(x - 1, y);
    push(x, y + 1);
    push(x, y - 1);
  }

  final out = img.encodePng(src, level: 6);
  File(outputPath).writeAsBytesSync(out);
  stdout.writeln('Wrote ' + outputPath);
}
