// ignore_for_file: avoid_print
import 'dart:io';
import 'package:image/image.dart' as img;

// Generates app-icon source images from assets/icon/app_icon_src.jpg:
//  - assets/logo.png                     (in-app brand logo)
//  - assets/icon/app_icon.png            (launcher icon master, 1024)
//  - assets/icon/app_icon_foreground.png (Android adaptive foreground,
//    badge scaled into the 66% safe zone on a transparent canvas)
void main() {
  final src = img.decodeJpg(File('assets/icon/app_icon_src.jpg').readAsBytesSync());
  if (src == null) throw StateError('Could not decode app_icon_src.jpg');

  File('assets/logo.png')
      .writeAsBytesSync(img.encodePng(img.copyResize(src, width: 512)));
  File('assets/icon/app_icon.png')
      .writeAsBytesSync(img.encodePng(img.copyResize(src, width: 1024)));

  const size = 1024;
  // flutter_launcher_icons insets the foreground by 16%; at full scale the
  // circular badge lands at ~60% of the icon, inside the 66% safe zone.
  const scale = 1.0;
  final fg = img.Image(width: size, height: size, numChannels: 4);
  final scaled = img.copyResize(src, width: (size * scale).round());
  img.compositeImage(fg, scaled,
      dstX: (size - scaled.width) ~/ 2, dstY: (size - scaled.height) ~/ 2);
  File('assets/icon/app_icon_foreground.png').writeAsBytesSync(img.encodePng(fg));

  final c = src.getPixel(8, 8);
  print('background: #${c.r.toInt().toRadixString(16).padLeft(2, '0')}'
      '${c.g.toInt().toRadixString(16).padLeft(2, '0')}'
      '${c.b.toInt().toRadixString(16).padLeft(2, '0')}');
  print('done');
}
