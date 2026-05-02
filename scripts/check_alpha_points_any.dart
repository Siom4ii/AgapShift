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
    int a(int x,int y)=>im.getPixel(x,y).a.toInt();
    print(path + ' size=' + w.toString() + 'x' + h.toString());
    print(' corners tl=' + a(0,0).toString() + ' tr=' + a(w-1,0).toString() + ' bl=' + a(0,h-1).toString() + ' br=' + a(w-1,h-1).toString());
    print(' mids top=' + a(w~/2,0).toString() + ' bottom=' + a(w~/2,h-1).toString() + ' left=' + a(0,h~/2).toString() + ' right=' + a(w-1,h~/2).toString());
  }
}
