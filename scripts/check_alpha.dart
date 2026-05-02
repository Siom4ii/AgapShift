import 'dart:io';
import 'package:image/image.dart' as img;

void main(List<String> args) {
  final path = args.isNotEmpty ? args[0] : 'branding/agapshift_logo_mark.png';
  final bytes = File(path).readAsBytesSync();
  final im = img.decodeImage(bytes);
  if (im == null) {
    stderr.writeln('decode failed');
    exitCode = 2;
    return;
  }
  final rgba = im.convert(numChannels: 4);
  var zero = 0;
  final total = rgba.width * rgba.height;
  for (var y = 0; y < rgba.height; y++) {
    for (var x = 0; x < rgba.width; x++) {
      if (rgba.getPixel(x, y).a == 0) zero++;
    }
  }
  stdout.writeln('alphaZero=$zero total=$total ratio=${(zero / total).toStringAsFixed(4)}');
}
