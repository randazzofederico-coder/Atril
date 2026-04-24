/// Cached permission state from the last successful Firestore verification.
/// Used to allow offline access when the device has no internet connection.
class PermissionCache {
  final bool hasAccess;
  final bool hasProfile;
  final String rol;
  final bool trialActive;
  final int trialDaysLeft;
  final bool trialExpired;
  final bool trialUsed;
  final DateTime lastVerified;

  const PermissionCache({
    required this.hasAccess,
    required this.hasProfile,
    required this.rol,
    required this.trialActive,
    required this.trialDaysLeft,
    required this.trialExpired,
    required this.trialUsed,
    required this.lastVerified,
  });

  /// How many days since the last online verification.
  int get daysSinceVerification =>
      DateTime.now().difference(lastVerified).inDays;

  /// Days remaining before a re-verification is required (max 30).
  int get daysUntilExpiry => (30 - daysSinceVerification).clamp(0, 30);

  /// Whether the cache has expired (older than 30 days).
  bool get isExpired => daysSinceVerification >= 30;

  /// Whether we should show a warning banner (≤5 days left).
  bool get showWarningBanner => daysUntilExpiry <= 5 && daysUntilExpiry > 0;
}
