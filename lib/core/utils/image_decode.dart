import 'package:flutter/widgets.dart';

/// Physical-pixel decode cap for an [Image.asset] rendered at [logicalSize]
/// logical pixels on one axis (pass to `cacheWidth` or `cacheHeight`).
///
/// Most Lumi PNGs (blobs 328px, mascots 863–6,145px) are far larger than
/// their rendered size; without `cacheWidth` Flutter decodes the full bitmap
/// and scales on the GPU, costing decode CPU and image-cache RAM — worst on
/// low-end Android. Pass only a width so `BoxFit.contain`/`cover` keep the
/// aspect ratio.
int decodeCacheSize(BuildContext context, double logicalSize) {
  return (logicalSize * MediaQuery.devicePixelRatioOf(context)).round();
}
