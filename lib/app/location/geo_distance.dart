import 'dart:math' as math;

import '../../domain/models.dart';

/// Mean Earth radius (meters), consistent with common haversine implementations.
const double _earthRadiusM = 6371008.8;

/// Great-circle distance between two WGS84 coordinates (haversine), in meters.
int geoDistanceMeters(GeoPoint a, GeoPoint b) {
  final lat1 = a.lat * (math.pi / 180.0);
  final lat2 = b.lat * (math.pi / 180.0);
  final dLat = lat2 - lat1;
  final dLng = (b.lng - a.lng) * (math.pi / 180.0);

  final sLat = math.sin(dLat / 2);
  final sLng = math.sin(dLng / 2);
  final h = sLat * sLat + math.cos(lat1) * math.cos(lat2) * sLng * sLng;
  final c = 2 * math.atan2(math.sqrt(h), math.sqrt(1 - h));
  return (_earthRadiusM * c).round();
}
