import 'dart:math' as math;

import '../../domain/models.dart';

/// Fast approximate distance in meters (good enough for “km from you” labels).
int geoDistanceMetersApprox(GeoPoint a, GeoPoint b) {
  final dx = (a.lat - b.lat) * 111000.0;
  final dy = (a.lng - b.lng) * 111000.0;
  return math.sqrt(dx * dx + dy * dy).round();
}
