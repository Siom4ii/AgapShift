import 'dart:io';
import 'package:image/image.dart' as img;

void main() {
  final bytes = File('branding/agapshift_logo_mark.png').readAsBytesSync();
  final im0 = img.decodeImage(bytes);
  if (im0 == null) throw 'decode failed';
  final im = im0.convert(numChannels: 4);
  int a(int x, int y) => im.getPixel(x, y).a.toInt();
  final w = im.width;
  final h = im.height;
  print('size=' + w.toString() + 'x' + h.toString());
  print(
    'alpha corners: tl=' +
        a(0, 0).toString() +
        ' tr=' +
        a(w - 1, 0).toString() +
        ' bl=' +
        a(0, h - 1).toString() +
        ' br=' +
        a(w - 1, h - 1).toString(),
  );
  print(
    'alpha mid edges: top=' +
        a(w ~/ 2, 0).toString() +
        ' bottom=' +
        a(w ~/ 2, h - 1).toString() +
        ' left=' +
        a(0, h ~/ 2).toString() +
        ' right=' +
        a(w - 1, h ~/ 2).toString(),
  );
}
