import 'dart:async' show Timer, unawaited;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:latlong2/latlong.dart';

import 'photon_geocode.dart';

/// Digos City — sensible default for Davao del Sur onboarding.
final LatLng kDefaultDavaoDelSurCenter = LatLng(6.7461, 125.3553);

/// OpenStreetMap tiles with a tappable pin, GPS, and optional address geocode.
class PinnableBusinessMapCard extends StatefulWidget {
  const PinnableBusinessMapCard({
    super.key,
    required this.pin,
    required this.onPinChanged,
    this.addressQueryForGeocode,
    this.accentColor = const Color(0xFF43A047),
  });

  final LatLng? pin;
  final ValueChanged<LatLng> onPinChanged;

  /// When this string changes (e.g. user picked municipality/barangay or typed
  /// street), the map recenters and the pin moves to the best geocode hit.
  final String? addressQueryForGeocode;

  final Color accentColor;

  @override
  State<PinnableBusinessMapCard> createState() =>
      _PinnableBusinessMapCardState();
}

class _PinnableBusinessMapCardState extends State<PinnableBusinessMapCard> {
  final MapController _mapController = MapController();
  bool _locating = false;
  Timer? _geocodeDebounce;
  String? _lastGeocodedQuery;
  /// Bumps when the user uses GPS or taps the map so stale geocode results are ignored.
  int _geocodeSerial = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final q = widget.addressQueryForGeocode?.trim();
      if (q != null && q.isNotEmpty) {
        _scheduleGeocode(q);
      }
    });
  }

  @override
  void didUpdateWidget(PinnableBusinessMapCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    final newQ = widget.addressQueryForGeocode?.trim();
    final oldQ = oldWidget.addressQueryForGeocode?.trim();
    if (newQ == null || newQ.isEmpty) return;
    if (newQ == oldQ) return;
    _scheduleGeocode(newQ);
  }

  @override
  void dispose() {
    _geocodeDebounce?.cancel();
    _mapController.dispose();
    super.dispose();
  }

  void _scheduleGeocode(String q) {
    if (q == _lastGeocodedQuery) return;
    _geocodeDebounce?.cancel();
    _geocodeDebounce = Timer(const Duration(milliseconds: 550), () {
      _geocodeDebounce = null;
      if (!mounted) return;
      unawaited(_runGeocodeQueued(q));
    });
  }

  Future<void> _runGeocodeQueued(String query) async {
    final serial = ++_geocodeSerial;
    final ll = await geocodeAddressQuery(query);
    if (!mounted || ll == null || serial != _geocodeSerial) return;
    final current = widget.addressQueryForGeocode?.trim() ?? '';
    if (query != current) return;
    _lastGeocodedQuery = query;
    widget.onPinChanged(ll);
    SchedulerBinding.instance.addPostFrameCallback((_) {
      if (mounted) _mapController.move(ll, 15);
    });
  }

  void _moveMapTo(LatLng ll, double zoom) {
    SchedulerBinding.instance.addPostFrameCallback((_) {
      if (mounted) _mapController.move(ll, zoom);
    });
  }

  Future<void> _useMyLocation(BuildContext context) async {
    if (_locating) return;
    setState(() => _locating = true);
    try {
      if (!kIsWeb) {
        final serviceOn = await Geolocator.isLocationServiceEnabled();
        if (!serviceOn) {
          if (context.mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Turn on location services to use this feature.'),
              ),
            );
          }
          return;
        }
      }
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                'Location permission is required to use your position.',
              ),
            ),
          );
        }
        return;
      }
      final pos = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 20),
        ),
      );
      final ll = LatLng(pos.latitude, pos.longitude);
      _geocodeSerial++;
      // Let a new typed address geocode again (may move pin off GPS).
      _lastGeocodedQuery = null;
      widget.onPinChanged(ll);
      _moveMapTo(ll, 16);
    } catch (_) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Could not get your location. Tap the map to place a pin.',
            ),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _locating = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final initial = widget.pin ?? kDefaultDavaoDelSurCenter;
    final zoom = widget.pin != null ? 15.0 : 12.0;

    return ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: SizedBox(
        height: 200,
        width: double.infinity,
        child: Stack(
          children: [
            FlutterMap(
              mapController: _mapController,
              options: MapOptions(
                initialCenter: initial,
                initialZoom: zoom,
                onTap: (tapPosition, latlng) {
                  _geocodeSerial++;
                  _lastGeocodedQuery = null;
                  widget.onPinChanged(latlng);
                  final z = _mapController.camera.zoom;
                  _moveMapTo(latlng, z);
                },
              ),
              children: [
                TileLayer(
                  urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                  userAgentPackageName: 'dev.agapshift.nexora',
                ),
                if (widget.pin != null)
                  MarkerLayer(
                    markers: [
                      Marker(
                        point: widget.pin!,
                        width: 44,
                        height: 44,
                        alignment: Alignment.bottomCenter,
                        child: Icon(
                          Icons.location_on_rounded,
                          color: widget.accentColor,
                          size: 44,
                          shadows: const [
                            Shadow(
                              blurRadius: 6,
                              color: Colors.black26,
                              offset: Offset(0, 2),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
              ],
            ),
            Positioned(
              left: 8,
              bottom: 8,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.92),
                  borderRadius: BorderRadius.circular(8),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.08),
                      blurRadius: 6,
                    ),
                  ],
                ),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  child: Text(
                    '© OSM',
                    style: GoogleFonts.inter(
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                      color: const Color(0xFF64748B),
                    ),
                  ),
                ),
              ),
            ),
            Positioned(
              right: 10,
              bottom: 10,
              child: Material(
                color: Colors.white,
                borderRadius: BorderRadius.circular(999),
                elevation: 4,
                shadowColor: Colors.black.withValues(alpha: 0.18),
                child: InkWell(
                  borderRadius: BorderRadius.circular(999),
                  onTap: _locating ? null : () => _useMyLocation(context),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 8,
                    ),
                    child: _locating
                        ? SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: widget.accentColor,
                            ),
                          )
                        : Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Icons.my_location_rounded,
                                size: 14,
                                color: widget.accentColor,
                              ),
                              const SizedBox(width: 6),
                              Text(
                                'Use My Location',
                                style: GoogleFonts.inter(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w800,
                                  color: const Color(0xFF334155),
                                ),
                              ),
                            ],
                          ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
