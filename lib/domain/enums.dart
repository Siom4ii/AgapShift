enum UserRole {
  worker,
  business,
}

enum AccountStatus {
  pendingVerification,
  verified,
  rejected,
  suspended,
}

enum VerificationStatus {
  notSubmitted,
  pending,
  approved,
  rejected,
}

enum BusinessType {
  soleProprietorship,
  partnership,
  corporation,
}

enum GigStatus {
  open,
  filled,
  ongoing,
  completed,
  cancelled,
}

enum ApplicationStatus {
  applied,
  withdrawn,
  rejected,
  hired,
}

enum AttendanceScanType {
  checkIn,
  checkOut,
}

enum EscrowStatus {
  notFunded,
  funded,
  held,
  released,
  refunded,
}

enum PayoutStatus {
  requested,
  processing,
  paid,
  failed,
}

enum TransactionType {
  escrowFunding,
  escrowRelease,
  escrowRefund,
  earningCredit,
  withdrawalDebit,
}

