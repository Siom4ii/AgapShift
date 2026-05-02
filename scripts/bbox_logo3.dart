import 'dart:io';
import 'package:image/image.dart' as img;

void main() {
  final bytes = File('branding/logo3.png').readAsBytesSync();
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
    print('no opaque pixels');
    return;
  }
  final bw = (maxX - minX + 1);
  final bh = (maxY - minY + 1);
  print('image=' + w.toString() + 'x' + h.toString());
  print('bbox=[' + minX.toString() + ',' + minY.toString() + ']-[' + maxX.toString() + ',' + maxY.toString() + '] size=' + bw.toString() + 'x' + bh.toString());
  print('fill ratio=' + (bw * bh / (w * h)).toStringAsFixed(4));
}
