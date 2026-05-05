import '../../domain/models.dart';

/// AgapShift operates only in **Davao del Sur**. All marketplace gigs must fall
/// inside this rough boundary; defaults and fallbacks use Digos City area.
abstract final class DavaoDelSurScope {
  /// Default map / search anchor (Digos City — matches business onboarding map).
  static const GeoPoint defaultCenter =
      GeoPoint(lat: 6.7461, lng: 125.3553);

  static const String regionLabel = 'Davao del Sur';

  /// Shown when GPS is unavailable (search still uses [defaultCenter]).
  static const String fallbackLocationLabel = 'Digos area, Davao del Sur';

  /// User has location permission but is outside the province.
  static const String outsideRegionListLabel =
      'Davao del Sur · outside service area';

  /// Rough WGS84 bounds for Davao del Sur province (inclusive margin).
  static bool contains(GeoPoint p) {
    return p.lat >= 5.88 &&
        p.lat <= 7.12 &&
        p.lng >= 124.92 &&
        p.lng <= 125.78;
  }
}
