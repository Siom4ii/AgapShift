import 'dart:io';
import 'package:image/image.dart' as img;

void main(List<String> args) {
  for (final path in args) {
    final bytes = File(path).readAsBytesSync();
    final im0 = img.decodeImage(bytes);
    if (im0 == null) {
      print(path + ': decode failed');
      continue;
    }
    final im = im0.convert(numChannels: 4);
    final w = im.width, h = im.height;
    var minA = 255;
    var maxA = 0;
    var zero = 0;
    for (var y = 0; y < h; y++) {
      for (var x = 0; x < w; x++) {
        final a = im.getPixel(x, y).a.toInt();
        if (a < minA) minA = a;
        if (a > maxA) maxA = a;
        if (a == 0) zero++;
      }
    }
    final total = w * h;
    print(path + ' size=' + w.toString() + 'x' + h.toString() + ' alpha[min,max]=[' + minA.toString() + ',' + maxA.toString() + '] zero=' + zero.toString() + '/' + total.toString());
  }
}
