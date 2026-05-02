/// Reads business display fields from [profiles.identity_snapshot] JSON
/// (shape from business onboarding final submit — see `BusinessOnboardingScreen`).
class BusinessIdentityDisplay {
  const BusinessIdentityDisplay({
    required this.displayName,
    required this.tagline,
    this.addressLine,
    this.phone,
  });

  /// Trade name / partnership name / corporate name — never the owner's personal name alone.
  final String displayName;
  final String tagline;
  final String? addressLine;
  final String? phone;
}

BusinessIdentityDisplay? businessIdentityFromProfileIdentitySnapshot(
  dynamic identitySnapshot,
) {
  if (identitySnapshot == null) return null;
  if (identitySnapshot is! Map) return null;
  final flow = identitySnapshot['flow'];
  if (flow != 'business') return null;
  final data = identitySnapshot['data'];
  if (data is! Map) return null;
  return _fromPayloadData(Map<String, dynamic>.from(data));
}

BusinessIdentityDisplay? _fromPayloadData(Map<String, dynamic> data) {
  final kind = data['business_kind'] as String?;
  final details = data['details'];
  if (details is! Map) return null;
  final d = Map<String, dynamic>.from(details);

  final displayName = _businessNameForKind(kind, d);
  if (displayName == null || displayName.isEmpty) return null;

  final kindLabel = _kindLabel(kind);
  final locShort = _shortLocationFromData(data);
  final tagline = locShort != null && locShort.isNotEmpty
      ? '$kindLabel · $locShort'
      : kindLabel;

  final loc = data['location'];
  String? addressLine;
  String? phone;
  if (loc is Map) {
    final m = Map<String, dynamic>.from(loc);
    final a = m['address'] as String?;
    addressLine = a?.trim();
    if (addressLine == null || addressLine.isEmpty) {
      final parts = <String>[
        if (_str(m['street_detail']) != null) _str(m['street_detail'])!,
        if (_str(m['barangay']) != null) _str(m['barangay'])!,
        if (_str(m['municipality']) != null) _str(m['municipality'])!,
        if (_str(m['province']) != null) _str(m['province'])!,
      ];
      addressLine = parts.isEmpty ? null : parts.join(', ');
    }
    phone = _str(m['phone']);
  }

  return BusinessIdentityDisplay(
    displayName: displayName,
    tagline: tagline,
    addressLine: addressLine,
    phone: phone,
  );
}

String? _str(dynamic v) {
  if (v == null) return null;
  final s = v.toString().trim();
  return s.isEmpty ? null : s;
}

String? _businessNameForKind(String? kind, Map<String, dynamic> details) {
  switch (kind) {
    case 'soleProprietorship':
      final block = details['sole_proprietorship'];
      if (block is Map) {
        final t = _str(Map<String, dynamic>.from(block)['trade_name']);
        if (t != null) return t;
      }
      return null;
    case 'partnership':
      final block = details['partnership'];
      if (block is Map) {
        final t = _str(Map<String, dynamic>.from(block)['partnership_name']);
        if (t != null) return t;
      }
      return null;
    case 'corporation':
      final block = details['corporation'];
      if (block is Map) {
        final t = _str(Map<String, dynamic>.from(block)['corporate_name']);
        if (t != null) return t;
      }
      return null;
    default:
      return null;
  }
}

String _kindLabel(String? kind) {
  return switch (kind) {
    'soleProprietorship' => 'Sole proprietorship',
    'partnership' => 'Partnership',
    'corporation' => 'Corporation',
    _ => 'Business',
  };
}

String? _shortLocationFromData(Map<String, dynamic> data) {
  final loc = data['location'];
  if (loc is! Map) return null;
  final m = Map<String, dynamic>.from(loc);
  final muni = _str(m['municipality']);
  final prov = _str(m['province']);
  if (muni != null && prov != null) return '$muni, $prov';
  if (muni != null) return muni;
  return _str(m['address']);
}
