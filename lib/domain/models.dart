import 'enums.dart';

class GeoPoint {
  const GeoPoint({required this.lat, required this.lng});
  final double lat;
  final double lng;
}

class Money {
  const Money({required this.amount, this.currency = 'PHP'});
  final int amount; // minor units (e.g., centavos)
  final String currency;
}

class AppUser {
  const AppUser({
    required this.id,
    required this.role,
    required this.email,
    required this.accountStatus,
    required this.createdAt,
  });

  final String id;
  final UserRole role;
  final String email;
  final AccountStatus accountStatus;
  final DateTime createdAt;
}

class WorkerProfile {
  const WorkerProfile({
    required this.userId,
    required this.fullName,
    required this.birthdate,
    required this.address,
    required this.emergencyContactName,
    required this.emergencyContactPhone,
    required this.skills,
    required this.bio,
    required this.verificationStatus,
    required this.ratingAvg,
    required this.completedShifts,
  });

  final String userId;
  final String fullName;
  final DateTime birthdate;
  final String address;
  final String emergencyContactName;
  final String emergencyContactPhone;
  final List<String> skills;
  final String bio;
  final VerificationStatus verificationStatus;
  final double ratingAvg;
  final int completedShifts;
}

class BusinessProfile {
  const BusinessProfile({
    required this.userId,
    required this.businessName,
    required this.businessType,
    required this.location,
    required this.verificationStatus,
    required this.ratingAvg,
    required this.completedHires,
  });

  final String userId;
  final String businessName;
  final BusinessType businessType;
  final GeoPoint location;
  final VerificationStatus verificationStatus;
  final double ratingAvg;
  final int completedHires;
}

class Gig {
  const Gig({
    required this.id,
    required this.businessId,
    required this.title,
    required this.description,
    required this.location,
    required this.addressLabel,
    required this.startAt,
    required this.endAt,
    required this.pay,
    required this.category,
    required this.status,
    required this.createdAt,
    this.workersNeeded,
    this.isUrgent = false,
  });

  final String id;
  final String businessId;
  final String title;
  final String description;
  final GeoPoint location;
  final String addressLabel;
  final DateTime startAt;
  final DateTime endAt;
  final Money pay;
  final String category;
  final GigStatus status;
  final DateTime createdAt;
  /// Openings for this gig when set (Supabase `workers_needed`).
  final int? workersNeeded;
  final bool isUrgent;
}

class GigApplication {
  const GigApplication({
    required this.id,
    required this.gigId,
    required this.workerId,
    required this.status,
    required this.createdAt,
  });

  final String id;
  final String gigId;
  final String workerId;
  final ApplicationStatus status;
  final DateTime createdAt;
}

class ShiftSession {
  const ShiftSession({
    required this.id,
    required this.gigId,
    required this.workerId,
    required this.businessId,
    required this.checkInAt,
    required this.checkOutAt,
  });

  final String id;
  final String gigId;
  final String workerId;
  final String businessId;
  final DateTime? checkInAt;
  final DateTime? checkOutAt;
}

class AttendanceRecord {
  const AttendanceRecord({
    required this.id,
    required this.gigId,
    required this.workerId,
    required this.type,
    required this.scannedAt,
  });

  final String id;
  final String gigId;
  final String workerId;
  final AttendanceScanType type;
  final DateTime scannedAt;
}

class Escrow {
  const Escrow({
    required this.id,
    required this.gigId,
    required this.amount,
    required this.status,
    required this.updatedAt,
  });

  final String id;
  final String gigId;
  final Money amount;
  final EscrowStatus status;
  final DateTime updatedAt;
}

class Wallet {
  const Wallet({
    required this.userId,
    required this.available,
    required this.pending,
    required this.updatedAt,
  });

  final String userId;
  final Money available;
  final Money pending;
  final DateTime updatedAt;
}

class LedgerTransaction {
  const LedgerTransaction({
    required this.id,
    required this.userId,
    required this.type,
    required this.amount,
    required this.createdAt,
    this.gigId,
  });

  final String id;
  final String userId;
  final TransactionType type;
  final Money amount;
  final DateTime createdAt;
  final String? gigId;
}

class Payout {
  const Payout({
    required this.id,
    required this.userId,
    required this.amount,
    required this.status,
    required this.createdAt,
  });

  final String id;
  final String userId;
  final Money amount;
  final PayoutStatus status;
  final DateTime createdAt;
}

class Rating {
  const Rating({
    required this.id,
    required this.gigId,
    required this.raterUserId,
    required this.ratedUserId,
    required this.stars,
    required this.createdAt,
    this.feedback,
  });

  final String id;
  final String gigId;
  final String raterUserId;
  final String ratedUserId;
  final int stars; // 1-5
  final DateTime createdAt;
  final String? feedback;
}

class AppNotification {
  const AppNotification({
    required this.id,
    required this.userId,
    required this.title,
    required this.body,
    required this.createdAt,
    required this.readAt,
    this.data,
  });

  final String id;
  final String userId;
  final String title;
  final String body;
  final DateTime createdAt;
  final DateTime? readAt;
  final Map<String, String>? data;
}

