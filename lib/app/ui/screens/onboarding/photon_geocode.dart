import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';

/// Forward geocode using [Photon](https://photon.komoot.io) (OpenStreetMap-based).
/// Works from Flutter Web (CORS) and mobile without API keys.
Future<LatLng?> geocodeAddressQuery(String query) async {
  final trimmed = query.trim();
  if (trimmed.length < 3) return null;
  try {
    final uri = Uri.https('photon.komoot.io', '/api/', {
      'q': trimmed,
      'limit': '1',
    });
    final resp = await http
        .get(uri, headers: {'Accept': 'application/json'})
        .timeout(const Duration(seconds: 12));
    if (resp.statusCode != 200) return null;
    final data = jsonDecode(resp.body);
    if (data is! Map<String, dynamic>) return null;
    final features = data['features'];
    if (features is! List || features.isEmpty) return null;
    final first = features[0];
    if (first is! Map<String, dynamic>) return null;
    final geometry = first['geometry'];
    if (geometry is! Map<String, dynamic>) return null;
    final coords = geometry['coordinates'];
    if (coords is! List || coords.length < 2) return null;
    final lon = (coords[0] as num).toDouble();
    final lat = (coords[1] as num).toDouble();
    if (lat.abs() > 90 || lon.abs() > 180) return null;
    return LatLng(lat, lon);
  } catch (_) {
    return null;
  }
}
