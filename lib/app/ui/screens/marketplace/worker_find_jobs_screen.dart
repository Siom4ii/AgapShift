import 'dart:math' as math;
import 'dart:ui' show ImageFilter;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:latlong2/latlong.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../../domain/business_identity.dart';
import '../../../../domain/enums.dart';
import '../../../../domain/models.dart';
import '../../../marketplace/marketplace_repository.dart';
import '../../../notifications/notification_repository.dart';
import '../../../location/davao_del_sur_scope.dart';
import '../../../location/geo_distance.dart';
import '../../../location/user_geo_point.dart';
import '../../../session/app_actor_id.dart';
import '../../../session/session_controller.dart';
import '../../../supabase/supabase_config.dart';
import '../../theme/agap_colors.dart';
import '../notifications/notifications_screen.dart';
import 'worker_gig_details_screen.dart';

const Color _findJobsPurple = Color(0xFF7C3AED);
const Color _findJobsPurpleDeep = Color(0xFF6D28D9);

class WorkerFindJobsScreen extends StatefulWidget {
  const WorkerFindJobsScreen({
    super.key,
    required this.repo,
    required this.notifications,
    required this.session,
    this.onNotificationsFlowDone,
  });

  final MarketplaceRepository repo;
  final NotificationRepository notifications;
  final SessionController session;
  /// Called after returning from [NotificationsScreen] (updates shell badge).
  final Future<void> Function()? onNotificationsFlowDone;

  @override
  State<WorkerFindJobsScreen> createState() => _WorkerFindJobsScreenState();
}

class _WorkerFindJobsScreenState extends State<WorkerFindJobsScreen> {
  static const _categories = <_CategorySpec>[
    _CategorySpec(label: 'All', key: ''),
    _CategorySpec(label: 'Warehouse', key: 'warehouse'),
    _CategorySpec(label: 'Food Service', key: 'food'),
    _CategorySpec(label: 'Retail', key: 'retail'),
    _CategorySpec(label: 'Events', key: 'event'),
  ];

  final _search = TextEditingController();
  String _selectedCategoryKey = '';
  bool _loading = true;
  String? _error;

  List<Gig> _items = const [];
  int _unread = 0;
  Map<String, String> _businessNames = const {};
  Map<String, bool> _businessVerified = const {};
  Set<String> _appliedGigIds = const {};
  final Set<String> _savedGigIds = <String>{};
  bool _usedDeviceGpsForSearch = false;

  GeoPoint _searchCenter = DavaoDelSurScope.defaultCenter;
  String _locationSubtitle = DavaoDelSurScope.fallbackLocationLabel;

  final MapController _mapController = MapController();
  LatLng _mapCenter = LatLng(
    DavaoDelSurScope.defaultCenter.lat,
    DavaoDelSurScope.defaultCenter.lng,
  );
  int _radiusM = 5000;
  int _minPay = 0;

  @override
  void initState() {
    super.initState();
    _search.addListener(() => setState(() {}));
    _bootstrap();
  }

  Future<void> _bootstrap() async {
    await _resolveSearchCenter();
    await _load();
  }

  /// Returns true if the device position was used.
  Future<bool> _resolveSearchCenter() async {
    final g = await tryGetCurrentUserGeoPoint();
    if (!mounted) {
      return false;
    }
    if (g != null && DavaoDelSurScope.contains(g)) {
      setState(() {
        _searchCenter = g;
        _mapCenter = LatLng(g.lat, g.lng);
        _usedDeviceGpsForSearch = true;
        _locationSubtitle = 'Near your location · ${DavaoDelSurScope.regionLabel}';
      });
      SchedulerBinding.instance.addPostFrameCallback((_) {
        if (mounted) _mapController.move(_mapCenter, 13);
      });
      return true;
    }
    if (g != null && !DavaoDelSurScope.contains(g)) {
      setState(() {
        _searchCenter = DavaoDelSurScope.defaultCenter;
        _mapCenter = LatLng(
          DavaoDelSurScope.defaultCenter.lat,
          DavaoDelSurScope.defaultCenter.lng,
        );
        _usedDeviceGpsForSearch = false;
        _locationSubtitle = DavaoDelSurScope.outsideRegionListLabel;
      });
      SchedulerBinding.instance.addPostFrameCallback((_) {
        if (mounted) _mapController.move(_mapCenter, 13);
      });
      return false;
    }
    setState(() {
      _searchCenter = DavaoDelSurScope.defaultCenter;
      _mapCenter = LatLng(
        DavaoDelSurScope.defaultCenter.lat,
        DavaoDelSurScope.defaultCenter.lng,
      );
      _usedDeviceGpsForSearch = false;
      _locationSubtitle = DavaoDelSurScope.fallbackLocationLabel;
    });
    SchedulerBinding.instance.addPostFrameCallback((_) {
      if (mounted) _mapController.move(_mapCenter, 13);
    });
    return false;
  }

  @override
  void dispose() {
    _search.dispose();
    _mapController.dispose();
    super.dispose();
  }

  String? _apiCategory() {
    switch (_selectedCategoryKey) {
      case 'warehouse':
        return 'Warehouse';
      case 'food':
        return 'Food Service';
      case 'retail':
        return 'Retail';
      case 'event':
        return 'Events';
      default:
        return null;
    }
  }

  Future<void> _recenterOnMyLocation() async {
    try {
      if (!kIsWeb) {
        final on = await Geolocator.isLocationServiceEnabled();
        if (!on) {
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Turn on location services to use this feature.'),
            ),
          );
          return;
        }
      }
      var perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied) {
        perm = await Geolocator.requestPermission();
      }
      if (perm == LocationPermission.denied ||
          perm == LocationPermission.deniedForever) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Location permission is required to use your position.'),
          ),
        );
        return;
      }
      final pos = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 20),
        ),
      );
      if (!mounted) return;
      final gp = GeoPoint(lat: pos.latitude, lng: pos.longitude);
      if (!DavaoDelSurScope.contains(gp)) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(DavaoDelSurScope.outsideRegionListLabel)),
        );
        return;
      }
      setState(() {
        _searchCenter = gp;
        _mapCenter = LatLng(pos.latitude, pos.longitude);
        _usedDeviceGpsForSearch = true;
        _locationSubtitle = 'Near your location · ${DavaoDelSurScope.regionLabel}';
      });
      SchedulerBinding.instance.addPostFrameCallback((_) {
        if (mounted) _mapController.move(_mapCenter, 14);
      });
      await _load();
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not get your location. Try again.')),
      );
    }
  }

  void _showMapFiltersSheet() {
    var radius = _radiusM;
    var minPay = _minPay;
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setModal) {
            return Padding(
              padding: EdgeInsets.only(
                left: 20,
                right: 20,
                bottom: MediaQuery.paddingOf(ctx).bottom + 20,
                top: 8,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text('Map search', style: Theme.of(ctx).textTheme.titleLarge),
                  const SizedBox(height: 16),
                  DropdownButtonFormField<int>(
                    value: radius,
                    decoration: const InputDecoration(labelText: 'Radius'),
                    items: const [
                      DropdownMenuItem(value: 1000, child: Text('1 km')),
                      DropdownMenuItem(value: 3000, child: Text('3 km')),
                      DropdownMenuItem(value: 5000, child: Text('5 km')),
                      DropdownMenuItem(value: 10000, child: Text('10 km')),
                    ],
                    onChanged: (v) => setModal(() => radius = v ?? radius),
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<int>(
                    value: minPay,
                    decoration: const InputDecoration(labelText: 'Minimum pay'),
                    items: const [
                      DropdownMenuItem(value: 0, child: Text('Any pay')),
                      DropdownMenuItem(value: 50000, child: Text('≥ ₱500')),
                      DropdownMenuItem(value: 80000, child: Text('≥ ₱800')),
                      DropdownMenuItem(value: 100000, child: Text('≥ ₱1000')),
                    ],
                    onChanged: (v) => setModal(() => minPay = v ?? minPay),
                  ),
                  const SizedBox(height: 20),
                  FilledButton(
                    onPressed: () {
                      setState(() {
                        _radiusM = radius;
                        _minPay = minPay;
                      });
                      Navigator.pop(ctx);
                      _load();
                    },
                    child: const Text('Apply'),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  List<Marker> _gigMarkers(BuildContext context) {
    return [
      for (final g in _filtered.take(40))
        Marker(
          point: LatLng(g.location.lat, g.location.lng),
          width: 76,
          height: 92,
          alignment: Alignment.bottomCenter,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () async {
              await Navigator.of(context).push<void>(
                MaterialPageRoute<void>(
                  builder: (_) => WorkerGigDetailsScreen(
                    repo: widget.repo,
                    notifications: widget.notifications,
                    session: widget.session,
                    gigId: g.id,
                  ),
                ),
              );
              if (context.mounted) await _load();
            },
            child: _FindJobsMapPin(gig: g),
          ),
        ),
    ];
  }

  Future<({Map<String, String> names, Map<String, bool> verified})>
      _fetchBusinessProfiles(Iterable<String> ids) async {
    final unique = ids.toSet().where((e) => e.isNotEmpty).toList();
    final names = <String, String>{for (final id in unique) id: 'Business'};
    final verified = <String, bool>{for (final id in unique) id: false};
    if (!SupabaseConfig.isConfigured || unique.isEmpty) {
      return (names: names, verified: verified);
    }
    try {
      final rows = await Supabase.instance.client
          .from('profiles')
          .select('id,identity_snapshot,account_status')
          .inFilter('id', unique);
      for (final raw in rows as List<dynamic>) {
        final m = Map<String, dynamic>.from(raw as Map);
        final id = m['id'] as String?;
        if (id == null) continue;
        final biz = businessIdentityFromProfileIdentitySnapshot(
          m['identity_snapshot'],
        );
        if (biz != null && biz.displayName.trim().isNotEmpty) {
          names[id] = biz.displayName.trim();
        }
        verified[id] =
            (m['account_status'] as String?) == AccountStatus.verified.name;
      }
    } catch (_) {}
    return (names: names, verified: verified);
  }

  Future<void> _load({bool refreshUserPosition = false}) async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      if (refreshUserPosition) {
        final located = await _resolveSearchCenter();
        if (mounted && !located) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                'Could not update your location. Showing ${DavaoDelSurScope.regionLabel} listings.',
              ),
            ),
          );
        }
      }
      final items = await widget.repo.listOpenJobsFeed(
        sortCenter: _searchCenter,
        minPayAmount: _minPay == 0 ? null : _minPay,
        category: _apiCategory(),
      );
      final apps = await widget.repo.listApplications();
      final uid = appActorId(widget.session, mockFallback: '');
      final applied = apps
          .where((a) => a.workerId == uid)
          .map((a) => a.gigId)
          .toSet();
      final profiles = await _fetchBusinessProfiles(items.map((g) => g.businessId));

      final notifs = uid.isEmpty
          ? <AppNotification>[]
          : await widget.notifications.listForUser(uid);
      final unread = notifs.where((n) => n.readAt == null).length;

      if (mounted) {
        setState(() {
          _items = items;
          _appliedGigIds = applied;
          _businessNames = profiles.names;
          _businessVerified = profiles.verified;
          _unread = unread;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _error = '$e');
      }
    }
    if (mounted) {
      setState(() => _loading = false);
    }
  }

  List<Gig> get _filtered {
    final q = _search.text.trim().toLowerCase();
    return _items.where((g) {
      if (q.isEmpty) return true;
      final biz = (_businessNames[g.businessId] ?? '').toLowerCase();
      return g.title.toLowerCase().contains(q) ||
          g.addressLabel.toLowerCase().contains(q) ||
          g.category.toLowerCase().contains(q) ||
          (biz.isNotEmpty && biz.contains(q));
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final count = _filtered.length;
    final bottomInset = MediaQuery.paddingOf(context).bottom;
    final listBottomPad = 28.0 + bottomInset;

    return LayoutBuilder(
      builder: (context, constraints) {
        return Stack(
          clipBehavior: Clip.none,
          fit: StackFit.expand,
          children: [
            Positioned.fill(
              child: Stack(
                children: [
                  Positioned.fill(
                    child: FlutterMap(
                      mapController: _mapController,
                      options: MapOptions(
                        initialCenter: _mapCenter,
                        initialZoom: 13,
                        interactionOptions: const InteractionOptions(
                          flags: InteractiveFlag.all,
                        ),
                      ),
                      children: [
                        TileLayer(
                          urlTemplate:
                              'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                          userAgentPackageName: 'dev.agapshift.nexora',
                        ),
                        MarkerLayer(markers: _gigMarkers(context)),
                      ],
                    ),
                  ),
                  Positioned(
                    left: 8,
                    bottom: MediaQuery.paddingOf(context).bottom + 8,
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
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 4,
                        ),
                        child: Text(
                          '© OpenStreetMap',
                          style: GoogleFonts.inter(
                            fontSize: 10,
                            fontWeight: FontWeight.w600,
                            color: AgapColors.textMuted,
                          ),
                        ),
                      ),
                    ),
                  ),
                  if (_error != null)
                    Positioned(
                      left: 12,
                      right: 12,
                      top: 8,
                      child: Material(
                        borderRadius: BorderRadius.circular(12),
                        color: Colors.red.shade50,
                        child: Padding(
                          padding: const EdgeInsets.all(10),
                          child: Text(
                            _error!,
                            style: TextStyle(
                              color: Colors.red.shade900,
                              fontSize: 12,
                            ),
                          ),
                        ),
                      ),
                    ),
                  Positioned(
                    right: 10,
                    top: MediaQuery.paddingOf(context).top + 6,
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(18),
                      child: BackdropFilter(
                        filter: ImageFilter.blur(sigmaX: 14, sigmaY: 14),
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.52),
                            borderRadius: BorderRadius.circular(18),
                            border: Border.all(
                              color: Colors.white.withValues(alpha: 0.75),
                            ),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withValues(alpha: 0.08),
                                blurRadius: 16,
                                offset: const Offset(0, 6),
                              ),
                            ],
                          ),
                          child: Padding(
                            padding: const EdgeInsets.all(6),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                _GlassMapIconButton(
                                  icon: Icons.my_location_rounded,
                                  onPressed: _recenterOnMyLocation,
                                ),
                                const SizedBox(height: 8),
                                _GlassMapIconButton(
                                  icon: Icons.tune_rounded,
                                  onPressed: _showMapFiltersSheet,
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            DraggableScrollableSheet(
              initialChildSize: 0.63,
              minChildSize: 0.26,
              maxChildSize: 0.94,
              builder: (context, scrollController) {
                return Container(
                  decoration: BoxDecoration(
                    color: AgapColors.pageBackground,
                    borderRadius: const BorderRadius.vertical(
                      top: Radius.circular(22),
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.12),
                        blurRadius: 24,
                        offset: const Offset(0, -4),
                      ),
                    ],
                  ),
                  child: Column(
                    children: [
                      const SizedBox(height: 10),
                      Container(
                        width: 40,
                        height: 4,
                        decoration: BoxDecoration(
                          color: AgapColors.borderSubtle,
                          borderRadius: BorderRadius.circular(999),
                        ),
                      ),
                      Expanded(
                        child: RefreshIndicator(
                          color: _findJobsPurple,
                          onRefresh: () => _load(refreshUserPosition: true),
                          child: ListView(
                            controller: scrollController,
                            physics: const AlwaysScrollableScrollPhysics(),
                            padding: EdgeInsets.fromLTRB(
                              20,
                              12,
                              20,
                              listBottomPad,
                            ),
                            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Find Jobs',
                          style: GoogleFonts.inter(
                            fontSize: 26,
                            fontWeight: FontWeight.w800,
                            color: const Color(0xFF111827),
                            letterSpacing: -0.3,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Padding(
                              padding: const EdgeInsets.only(top: 1),
                              child: Icon(
                                Icons.place_outlined,
                                size: 17,
                                color: AgapColors.textMuted,
                              ),
                            ),
                            const SizedBox(width: 4),
                            Expanded(
                              child: Text(
                                _locationSubtitle,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: GoogleFonts.inter(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w500,
                                  height: 1.35,
                                  color: AgapColors.textMuted,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  _NotifButton(
                    unread: _unread,
                    onTap: () async {
                      await Navigator.of(context).push<void>(
                        MaterialPageRoute<void>(
                          builder: (_) => NotificationsScreen(
                            repo: widget.notifications,
                            session: widget.session,
                          ),
                        ),
                      );
                      if (!context.mounted) {
                        return;
                      }
                      await widget.onNotificationsFlowDone?.call();
                      await _load();
                    },
                  ),
                ],
              ),
              const SizedBox(height: 18),
              _SearchField(controller: _search),
              const SizedBox(height: 14),
              SizedBox(
                height: 46,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  clipBehavior: Clip.none,
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  itemBuilder: (context, i) {
                    final spec = _categories[i];
                    final selected = spec.key == _selectedCategoryKey;
                    return _Chip(
                      label: spec.label,
                      selected: selected,
                      onTap: () {
                        setState(() => _selectedCategoryKey = spec.key);
                        _load();
                      },
                    );
                  },
                  separatorBuilder: (_, __) => const SizedBox(width: 8),
                  itemCount: _categories.length,
                ),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: Text.rich(
                      TextSpan(
                        style: GoogleFonts.inter(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: AgapColors.textMuted,
                        ),
                        children: [
                          TextSpan(
                            text: _loading
                                ? 'Loading jobs…'
                                : '$count jobs found near you',
                          ),
                          if (!_loading && count > 0) ...[
                            TextSpan(
                              text: '  ·  ',
                              style: GoogleFonts.inter(
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                                color: const Color(0xFFCBD5E1),
                              ),
                            ),
                            TextSpan(
                              text: '$count matches',
                              style: GoogleFonts.inter(
                                fontSize: 13,
                                fontWeight: FontWeight.w800,
                                color: _findJobsPurpleDeep,
                              ),
                            ),
                          ],
                        ],
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              if (_error != null)
                _ErrorCard(message: _error!, onRetry: _load)
              else if (_loading)
                Padding(
                  padding: const EdgeInsets.only(top: 36),
                  child: Center(
                    child: CircularProgressIndicator(color: _findJobsPurple),
                  ),
                )
              else if (_filtered.isEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 48),
                  child: Center(
                    child: Text(
                      'No open jobs nearby yet.',
                      style: GoogleFonts.inter(
                        color: AgapColors.textMuted,
                        fontWeight: FontWeight.w600,
                        fontSize: 15,
                      ),
                    ),
                  ),
                )
              else
                ...List.generate(math.min(_filtered.length, 20), (i) {
                  final g = _filtered[i];
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 14),
                    child: _JobCard(
                      gig: g,
                      businessName:
                          _businessNames[g.businessId] ?? 'Business',
                      employerVerified:
                          _businessVerified[g.businessId] ?? false,
                      applied: _appliedGigIds.contains(g.id),
                      saved: _savedGigIds.contains(g.id),
                      distanceUsesGps: _usedDeviceGpsForSearch,
                      distanceKm:
                          geoDistanceMeters(_searchCenter, g.location) /
                              1000.0,
                      onBookmark: () {
                        setState(() {
                          if (_savedGigIds.contains(g.id)) {
                            _savedGigIds.remove(g.id);
                          } else {
                            _savedGigIds.add(g.id);
                          }
                        });
                      },
                      onTap: () async {
                        await Navigator.of(context).push<void>(
                          MaterialPageRoute<void>(
                            builder: (_) => WorkerGigDetailsScreen(
                              repo: widget.repo,
                              notifications: widget.notifications,
                              session: widget.session,
                              gigId: g.id,
                            ),
                          ),
                        );
                        if (context.mounted) await _load();
                      },
                    ),
                  );
                }),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
          ],
        );
      },
    );
  }
}

class _GlassMapIconButton extends StatelessWidget {
  const _GlassMapIconButton({
    required this.icon,
    required this.onPressed,
  });

  final IconData icon;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white.withValues(alpha: 0.45),
      shape: const CircleBorder(),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onPressed,
        child: SizedBox(
          width: 44,
          height: 44,
          child: Icon(icon, color: const Color(0xFF1E3A5F), size: 22),
        ),
      ),
    );
  }
}

class _FindJobsMapPin extends StatelessWidget {
  const _FindJobsMapPin({required this.gig});

  final Gig gig;

  @override
  Widget build(BuildContext context) {
    final hourly = _mapHourlyPhp(gig);
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(10),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.12),
                blurRadius: 8,
                offset: const Offset(0, 3),
              ),
            ],
          ),
          child: Text(
            '₱${hourly.toStringAsFixed(0)}/hr',
            style: GoogleFonts.inter(
              fontWeight: FontWeight.w800,
              fontSize: 13,
              color: AgapColors.primaryBright,
            ),
          ),
        ),
        const SizedBox(height: 2),
        Container(
          padding: const EdgeInsets.all(10),
          decoration: const BoxDecoration(
            color: AgapColors.primary,
            shape: BoxShape.circle,
          ),
          child: Icon(
            _mapCategoryIcon(gig.category),
            color: Colors.white,
            size: 18,
          ),
        ),
      ],
    );
  }
}

double _mapHourlyPhp(Gig g) {
  var hours = g.endAt.difference(g.startAt).inMinutes / 60.0;
  if (hours < 0.25) hours = 8.0;
  return (g.pay.amount / 100.0) / hours;
}

IconData _mapCategoryIcon(String c) {
  final l = c.toLowerCase();
  if (l.contains('warehouse')) return Icons.inventory_2_rounded;
  if (l.contains('food')) return Icons.restaurant_rounded;
  if (l.contains('retail')) return Icons.storefront_rounded;
  return Icons.work_rounded;
}

class _CategorySpec {
  const _CategorySpec({required this.label, required this.key});
  final String label;
  final String key;
}

class _NotifButton extends StatelessWidget {
  const _NotifButton({required this.unread, required this.onTap});

  final int unread;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Stack(
      clipBehavior: Clip.none,
      children: [
        InkWell(
          borderRadius: BorderRadius.circular(999),
          onTap: onTap,
          child: Ink(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: Colors.white,
              shape: BoxShape.circle,
              border: Border.all(color: AgapColors.borderSubtle),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.04),
                  blurRadius: 10,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Icon(
              Icons.notifications_outlined,
              color: AgapColors.primaryBright,
            ),
          ),
        ),
        if (unread > 0)
          Positioned(
            right: -2,
            top: -2,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: const Color(0xFFEF4444),
                borderRadius: BorderRadius.circular(999),
                border: Border.all(color: Colors.white, width: 2),
              ),
              child: Text(
                unread > 99 ? '99+' : '$unread',
                style: GoogleFonts.inter(
                  fontSize: 10,
                  fontWeight: FontWeight.w800,
                  color: Colors.white,
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class _SearchField extends StatefulWidget {
  const _SearchField({required this.controller});

  final TextEditingController controller;

  @override
  State<_SearchField> createState() => _SearchFieldState();
}

class _SearchFieldState extends State<_SearchField> {
  late final FocusNode _focus = FocusNode();

  void _onControllerChanged() => setState(() {});

  @override
  void initState() {
    super.initState();
    _focus.addListener(() => setState(() {}));
    widget.controller.addListener(_onControllerChanged);
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onControllerChanged);
    _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final focused = _focus.hasFocus;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      curve: Curves.easeOutCubic,
      height: 48,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: focused ? _findJobsPurple : const Color(0xFFE5E7EB),
          width: focused ? 2 : 1,
        ),
        boxShadow: [
          BoxShadow(
            color: focused
                ? _findJobsPurple.withValues(alpha: 0.22)
                : Colors.black.withValues(alpha: 0.04),
            blurRadius: focused ? 18 : 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      padding: const EdgeInsets.symmetric(horizontal: 14),
      child: Row(
        children: [
          Icon(
            Icons.search_rounded,
            color: focused ? _findJobsPurple : AgapColors.textMuted,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: TextField(
              focusNode: _focus,
              controller: widget.controller,
              decoration: InputDecoration(
                isDense: true,
                filled: true,
                fillColor: Colors.transparent,
                hintText: 'Search jobs, companies…',
                hintStyle: GoogleFonts.inter(color: AgapColors.textMuted),
                border: InputBorder.none,
                enabledBorder: InputBorder.none,
                focusedBorder: InputBorder.none,
                errorBorder: InputBorder.none,
                focusedErrorBorder: InputBorder.none,
                contentPadding: EdgeInsets.zero,
              ),
              style: GoogleFonts.inter(
                fontWeight: FontWeight.w600,
                color: const Color(0xFF111827),
              ),
            ),
          ),
          if (widget.controller.text.trim().isNotEmpty)
            IconButton(
              tooltip: 'Clear',
              onPressed: () => widget.controller.clear(),
              icon: const Icon(Icons.close_rounded, size: 18),
            ),
        ],
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final bg = selected ? _findJobsPurpleDeep : const Color(0xFFF9FAFB);
    final fg = selected ? Colors.white : const Color(0xFF374151);
    final borderColor = selected ? _findJobsPurpleDeep : const Color(0xFFE8ECF1);
    return Material(
      elevation: selected ? 3 : 0,
      shadowColor: selected
          ? _findJobsPurpleDeep.withValues(alpha: 0.35)
          : Colors.transparent,
      color: bg,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(999),
        side: BorderSide(color: borderColor, width: selected ? 1.5 : 1),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(999),
        splashColor: Colors.white.withValues(alpha: selected ? 0.22 : 0.12),
        highlightColor: Colors.white.withValues(alpha: selected ? 0.12 : 0.06),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 11),
          child: Text(
            label,
            style: GoogleFonts.inter(
              fontSize: 12.5,
              fontWeight: FontWeight.w700,
              color: fg,
            ),
          ),
        ),
      ),
    );
  }
}

class _JobCard extends StatelessWidget {
  const _JobCard({
    required this.gig,
    required this.businessName,
    required this.employerVerified,
    required this.applied,
    required this.saved,
    required this.distanceUsesGps,
    required this.distanceKm,
    required this.onBookmark,
    required this.onTap,
  });

  final Gig gig;
  final String businessName;
  final bool employerVerified;
  final bool applied;
  final bool saved;
  final bool distanceUsesGps;
  final double distanceKm;
  final VoidCallback onBookmark;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final minutes = gig.endAt.difference(gig.startAt).inMinutes;
    final hoursDec = math.max(0.25, minutes / 60.0);
    final hoursLabel = hoursDec == hoursDec.roundToDouble()
        ? '${hoursDec.round()} hrs'
        : '${hoursDec.toStringAsFixed(1)} hrs';
    final start = gig.startAt.toLocal();
    final dayLabel = _dayLabel(start);
    final time = _clock(start);
    final pay = _payLine(gig);
    final urgent =
        gig.isUrgent || _descriptionMarksUrgent(gig.description);
    final todayOnly = _isTodayOnlyShift(gig);
    final slots =
        gig.workersNeeded ?? _workersNeededFromDescription(gig.description);

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: Ink(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: AgapColors.borderSubtle.withValues(alpha: 0.85),
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.06),
                blurRadius: 18,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _LeadingIcon(category: gig.category),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                gig.title,
                                style: GoogleFonts.inter(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w800,
                                  color: const Color(0xFF111827),
                                  height: 1.2,
                                ),
                              ),
                              const SizedBox(height: 6),
                              Text(
                                businessName,
                                style: GoogleFonts.inter(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                  color: AgapColors.textMuted,
                                ),
                              ),
                              if (employerVerified) ...[
                                const SizedBox(height: 6),
                                Row(
                                  children: [
                                    Icon(
                                      Icons.verified_rounded,
                                      size: 15,
                                      color: const Color(0xFF059669),
                                    ),
                                    const SizedBox(width: 4),
                                    Text(
                                      'Verified employer',
                                      style: GoogleFonts.inter(
                                        fontSize: 11.5,
                                        fontWeight: FontWeight.w700,
                                        color: const Color(0xFF047857),
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ],
                          ),
                        ),
                        const SizedBox(width: 10),
                        Padding(
                          padding: const EdgeInsets.only(right: 28),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              Text(
                                pay.$1,
                                style: GoogleFonts.inter(
                                  fontSize: 17,
                                  fontWeight: FontWeight.w900,
                                  color: _findJobsPurple,
                                  height: 1.1,
                                ),
                              ),
                              Text(
                                pay.$2,
                                style: GoogleFonts.inter(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                  color: AgapColors.textMuted,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 14,
                      runSpacing: 8,
                      children: [
                        _Meta(
                          icon: Icons.place_outlined,
                          text:
                              '${distanceKm.toStringAsFixed(1)} km · ${distanceUsesGps ? 'GPS' : 'approx'}',
                        ),
                        _Meta(icon: Icons.schedule_rounded, text: hoursLabel),
                        _Meta(
                          icon: Icons.event_available_rounded,
                          text: '$dayLabel $time',
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        if (gig.isBoostedActive)
                          const _Pill(
                            text: 'Boosted',
                            bg: Color(0xFFEDE9FE),
                            fg: Color(0xFF5B21B6),
                            icon: Icons.rocket_launch_rounded,
                          ),
                        if (urgent)
                          const _Pill(
                            text: 'Urgent',
                            bg: Color(0xFFFFE4E6),
                            fg: Color(0xFFB91C1C),
                            icon: Icons.local_fire_department_rounded,
                          ),
                        if (todayOnly && !urgent)
                          const _Pill(
                            text: 'Today only',
                            bg: Color(0xFFFFEDD5),
                            fg: Color(0xFF9A3412),
                            icon: Icons.wb_sunny_outlined,
                          ),
                        if (slots != null && slots > 0)
                          _Pill(
                            text: '$slots ${slots == 1 ? 'slot' : 'slots'} left',
                            bg: const Color(0xFFF3F4F6),
                            fg: const Color(0xFF374151),
                            icon: Icons.people_alt_rounded,
                          ),
                        if (applied)
                          const _Pill(
                            text: 'Applied',
                            bg: Color(0xFFDCFCE7),
                            fg: Color(0xFF166534),
                            icon: Icons.check_circle_rounded,
                          ),
                      ],
                    ),
                  ],
                ),
              ),
              Positioned(
                top: 4,
                right: 4,
                child: IconButton(
                  visualDensity: VisualDensity.compact,
                  tooltip: saved ? 'Remove bookmark' : 'Save job',
                  onPressed: onBookmark,
                  icon: Icon(
                    saved
                        ? Icons.bookmark_rounded
                        : Icons.bookmark_add_outlined,
                    color: saved
                        ? _findJobsPurpleDeep
                        : AgapColors.textMuted,
                    size: 22,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _LeadingIcon extends StatelessWidget {
  const _LeadingIcon({required this.category});
  final String category;

  @override
  Widget build(BuildContext context) {
    final l = category.toLowerCase();
    final icon = l.contains('warehouse')
        ? Icons.inventory_2_rounded
        : l.contains('food')
        ? Icons.restaurant_rounded
        : l.contains('retail')
        ? Icons.storefront_rounded
        : l.contains('event')
        ? Icons.celebration_rounded
        : Icons.work_rounded;
    final tint = l.contains('warehouse')
        ? const Color(0xFFEDE9FE)
        : l.contains('food')
        ? const Color(0xFFFFE4E6)
        : l.contains('retail')
        ? const Color(0xFFFFF7ED)
        : const Color(0xFFE0F2FE);
    return Container(
      width: 50,
      height: 50,
      decoration: BoxDecoration(
        color: tint,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Icon(icon, color: const Color(0xFF334155), size: 24),
    );
  }
}

class _Meta extends StatelessWidget {
  const _Meta({required this.icon, required this.text});
  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 16, color: AgapColors.textMuted),
        const SizedBox(width: 6),
        Text(
          text,
          style: GoogleFonts.inter(
            fontSize: 12.5,
            fontWeight: FontWeight.w600,
            color: AgapColors.textMuted,
          ),
        ),
      ],
    );
  }
}

class _Pill extends StatelessWidget {
  const _Pill({
    required this.text,
    required this.bg,
    required this.fg,
    required this.icon,
  });
  final String text;
  final Color bg;
  final Color fg;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: fg),
          const SizedBox(width: 6),
          Text(
            text,
            style: GoogleFonts.inter(
              fontSize: 11.5,
              fontWeight: FontWeight.w700,
              color: fg,
            ),
          ),
        ],
      ),
    );
  }
}

class _ErrorCard extends StatelessWidget {
  const _ErrorCard({required this.message, required this.onRetry});
  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.red.shade50,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.red.shade100),
      ),
      child: Row(
        children: [
          Icon(Icons.error_outline_rounded, color: Colors.red.shade700),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              message,
              style: GoogleFonts.inter(
                fontSize: 12.5,
                color: Colors.red.shade800,
              ),
            ),
          ),
          TextButton(
            onPressed: onRetry,
            child: Text(
              'Retry',
              style: GoogleFonts.inter(fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ),
    );
  }
}

int? _workersNeededFromDescription(String description) {
  final m = RegExp(
    r'Workers needed:\s*(\d+)',
    caseSensitive: false,
  ).firstMatch(description);
  if (m == null) return null;
  return int.tryParse(m.group(1)!);
}

bool _descriptionMarksUrgent(String description) {
  final l = description.toLowerCase();
  return l.contains('marked as urgent') || l.contains('urgent:');
}

bool _isTodayOnlyShift(Gig g) {
  final s = g.startAt.toLocal();
  final e = g.endAt.toLocal();
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  final sd = DateTime(s.year, s.month, s.day);
  final ed = DateTime(e.year, e.month, e.day);
  return sd == today && ed == today;
}

(String, String) _payLine(Gig g) {
  final total = g.pay.amount / 100.0;
  final minutes = g.endAt.difference(g.startAt).inMinutes;
  final hours = math.max(0.25, minutes / 60.0);
  final eventish = g.category.toLowerCase().contains('event');
  if (eventish) {
    return ('₱${total.round()}', '/event');
  }
  if (hours <= 10) {
    return ('₱${(total / hours).round()}', '/hr');
  }
  return ('₱${total.round()}', '/day');
}

String _clock(DateTime d) {
  final h = d.hour;
  final am = h >= 12 ? 'PM' : 'AM';
  final hr = h % 12 == 0 ? 12 : h % 12;
  final m = d.minute.toString().padLeft(2, '0');
  return '$hr:$m $am';
}

String _dayLabel(DateTime d) {
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  final day = DateTime(d.year, d.month, d.day);
  if (day == today) return 'Today';
  if (day == today.add(const Duration(days: 1))) return 'Tomorrow';
  return '${d.month}/${d.day}';
}

