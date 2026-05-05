/// Display fields from [profiles.identity_snapshot] when [flow] is `worker`
/// (see `WorkerOnboardingScreen` payload).
class WorkerIdentityDisplay {
  const WorkerIdentityDisplay({
    required this.displayName,
    this.tagline,
    this.bio,
    this.skills = const [],
    this.phone,
    this.addressLine,
    this.birthDate,
  });

  final String displayName;
  final String? tagline;
  final String? bio;
  final List<String> skills;
  final String? phone;
  final String? addressLine;
  /// From onboarding `personal.birthdate` when present.
  final DateTime? birthDate;
}

WorkerIdentityDisplay? workerIdentityFromProfileIdentitySnapshot(dynamic raw) {
  if (raw == null || raw is! Map) return null;
  final top = Map<String, dynamic>.from(raw);

  final Map<String, dynamic> m;
  final flow = top['flow']?.toString();
  if (flow == 'worker' && top['data'] is Map) {
    m = Map<String, dynamic>.from(top['data']! as Map);
  } else if (top['personal'] is Map || top['resume'] is Map) {
    // Onboarding payload stored without { flow, data } wrapper (legacy / manual).
    m = top;
  } else {
    return null;
  }

  final personal = m['personal'];
  String? fullName;
  if (personal is Map) {
    fullName = _str(Map<String, dynamic>.from(personal)['full_name']);
  }
  if (fullName == null || fullName.isEmpty) return null;

  String? phone;
  String? addressLine;
  DateTime? birthDate;
  if (personal is Map) {
    final p = Map<String, dynamic>.from(personal);
    phone = _str(p['phone']);
    addressLine = _str(p['address_line']);
    final bdRaw = p['birthdate'];
    if (bdRaw != null) {
      birthDate = DateTime.tryParse(bdRaw.toString());
    }
    final muni = _str(p['municipality']);
    final brgy = _str(p['barangay']);
    if (addressLine == null || addressLine.isEmpty) {
      final parts = <String>[
        if (brgy != null) brgy,
        if (muni != null) muni,
      ];
      addressLine = parts.isEmpty ? null : parts.join(', ');
    }
  }

  String? bio;
  List<String> skills = [];
  final resume = m['resume'];
  if (resume is Map) {
    final r = Map<String, dynamic>.from(resume);
    bio = _str(r['bio']);
    final sk = r['skills'];
    if (sk is List) {
      skills = sk
          .map((e) => e.toString().trim())
          .where((s) => s.isNotEmpty)
          .toList();
    }
  }

  String? tagline;
  if (skills.isNotEmpty) {
    tagline = skills.length <= 3
        ? skills.join(' · ')
        : '${skills.take(3).join(' · ')} · +${skills.length - 3} more';
  }

  return WorkerIdentityDisplay(
    displayName: fullName,
    tagline: tagline,
    bio: bio,
    skills: skills,
    phone: phone,
    addressLine: addressLine,
    birthDate: birthDate,
  );
}

String? _str(dynamic v) {
  if (v == null) return null;
  final s = v.toString().trim();
  return s.isEmpty ? null : s;
}
