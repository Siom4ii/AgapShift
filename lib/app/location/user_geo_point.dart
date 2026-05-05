import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:geolocator/geolocator.dart';

import '../../domain/models.dart';

/// Best-effort current device position. Returns null if services are off,
/// permission is denied, or lookup fails (no UI — callers decide messaging).
Future<GeoPoint?> tryGetCurrentUserGeoPoint() async {
  try {
    if (!kIsWeb) {
      final on = await Geolocator.isLocationServiceEnabled();
      if (!on) {
        return null;
      }
    }
    var perm = await Geolocator.checkPermission();
    if (perm == LocationPermission.denied) {
      perm = await Geolocator.requestPermission();
    }
    if (perm == LocationPermission.denied ||
        perm == LocationPermission.deniedForever) {
      return null;
    }
    final pos = await Geolocator.getCurrentPosition(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.high,
        timeLimit: Duration(seconds: 20),
      ),
    );
    return GeoPoint(lat: pos.latitude, lng: pos.longitude);
  } catch (_) {
    return null;
  }
}
