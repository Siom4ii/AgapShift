import 'dart:io';
import 'dart:math' as math;
import 'package:image/image.dart' as img;

void main() {
  final inPath = 'branding/logo3.png';
  final outPath = 'branding/logo3_cropped.png';

  final bytes = File(inPath).readAsBytesSync();
  final im0 = img.decodeImage(bytes);
  if (im0 == null) throw 'decode failed';
  final im = im0.convert(numChannels: 4);
  final w = im.width, h = im.height;

  var minX = w, minY = h, maxX = 0, maxY = 0;
  var any = false;
  for (var y = 0; y < h; y++) {
    for (var x = 0; x < w; x++) {
      if (im.getPixel(x, y).a.toInt() == 0) continue;
      any = true;
      if (x < minX) minX = x;
      if (y < minY) minY = y;
      if (x > maxX) maxX = x;
      if (y > maxY) maxY = y;
    }
  }
  if (!any) {
    stderr.writeln('no opaque pixels');
    exitCode = 2;
    return;
  }

  // Add a small padding and then square-crop centered.
  const pad = 18;
  minX = math.max(0, minX - pad);
  minY = math.max(0, minY - pad);
  maxX = math.min(w - 1, maxX + pad);
  maxY = math.min(h - 1, maxY + pad);

  final bw = (maxX - minX + 1);
  final bh = (maxY - minY + 1);
  final square = math.max(bw, bh);

  final cx = minX + bw ~/ 2;
  final cy = minY + bh ~/ 2;

  var cropX = cx - square ~/ 2;
  var cropY = cy - square ~/ 2;
  cropX = math.max(0, math.min(cropX, w - square));
  cropY = math.max(0, math.min(cropY, h - square));

  final out = img.copyCrop(im, x: cropX, y: cropY, width: square, height: square);
  File(outPath).writeAsBytesSync(img.encodePng(out, level: 6));
  stdout.writeln('Wrote ' + outPath + ' ' + out.width.toString() + 'x' + out.height.toString());
}
