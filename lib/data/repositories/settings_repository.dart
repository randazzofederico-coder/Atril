import 'package:shared_preferences/shared_preferences.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import 'package:flutter/material.dart'; // For ThemeMode
import '../../models/permission_cache.dart';

class SettingsRepository {
  static final SettingsRepository _instance = SettingsRepository._internal();
  static SettingsRepository get instance => _instance;

  SettingsRepository._internal();

  late SharedPreferences _prefs;

  // Notifiers for UI to listen to
  final ValueNotifier<ThemeMode> themeMode = ValueNotifier(ThemeMode.system);
  final ValueNotifier<double> uiScale = ValueNotifier(1.0);
  final ValueNotifier<bool> keepScreenOn = ValueNotifier(false);
  final ValueNotifier<bool> invertPdfColors = ValueNotifier(false);

  // Keys
  static const String _keyThemeMode = 'theme_mode';
  static const String _keyUiScale = 'ui_scale';
  static const String _keyKeepScreenOn = 'keep_screen_on';
  static const String _keyInvertPdfColors = 'invert_pdf_colors';

  // Permission cache keys
  static const String _keyPermHasAccess = 'perm_has_access';
  static const String _keyPermHasProfile = 'perm_has_profile';
  static const String _keyPermRol = 'perm_rol';
  static const String _keyPermTrialActive = 'perm_trial_active';
  static const String _keyPermTrialDaysLeft = 'perm_trial_days_left';
  static const String _keyPermTrialExpired = 'perm_trial_expired';
  static const String _keyPermTrialUsed = 'perm_trial_used';
  static const String _keyPermLastVerified = 'perm_last_verified';

  Future<void> init() async {
    _prefs = await SharedPreferences.getInstance();
    
    _loadThemeMode();
    _loadUiScale();
    _loadKeepScreenOn();
    _loadInvertPdfColors();
  }

  // --- Theme Mode ---
  void _loadThemeMode() {
    final val = _prefs.getString(_keyThemeMode);
    if (val == 'light') {
      themeMode.value = ThemeMode.light;
    } else if (val == 'dark') {
      themeMode.value = ThemeMode.dark;
    } else {
      themeMode.value = ThemeMode.system;
    }
  }

  Future<void> setThemeMode(ThemeMode mode) async {
    themeMode.value = mode;
    String val;
    switch (mode) {
      case ThemeMode.light:
        val = 'light';
        break;
      case ThemeMode.dark:
        val = 'dark';
        break;
      case ThemeMode.system:
        val = 'system';
        break;
    }
    await _prefs.setString(_keyThemeMode, val);
  }

  // --- UI Scale ---
  void _loadUiScale() {
    final val = _prefs.getDouble(_keyUiScale);
    uiScale.value = val ?? 1.0;
  }

  Future<void> setUiScale(double scale) async {
    // Clamp to reasonable values
    final clamped = scale.clamp(0.8, 2.0);
    uiScale.value = clamped;
    await _prefs.setDouble(_keyUiScale, clamped);
  }

  // --- Keep Screen On ---
  void _loadKeepScreenOn() {
    final val = _prefs.getBool(_keyKeepScreenOn) ?? false;
    keepScreenOn.value = val;
    _applyWakelock(val);
  }

  Future<void> setKeepScreenOn(bool enable) async {
    keepScreenOn.value = enable;
    await _prefs.setBool(_keyKeepScreenOn, enable);
    _applyWakelock(enable);
  }

  void _applyWakelock(bool enable) {
    if (enable) {
      WakelockPlus.enable();
    } else {
      WakelockPlus.disable();
    }
  }

  // --- Invert PDF Colors ---
  void _loadInvertPdfColors() {
    final val = _prefs.getBool(_keyInvertPdfColors) ?? false;
    invertPdfColors.value = val;
  }

  Future<void> setInvertPdfColors(bool enable) async {
    invertPdfColors.value = enable;
    await _prefs.setBool(_keyInvertPdfColors, enable);
  }

  // --- Annotation Tool Preferences ---
  static const String _keyAnnotationColor = 'annotation_color_';
  static const String _keyAnnotationWidth = 'annotation_width_';

  /// Load the last-used color for a tool. Returns null if not set.
  int? getAnnotationColor(String toolName) {
    return _prefs.getInt('$_keyAnnotationColor$toolName');
  }

  /// Load the last-used width for a tool. Returns null if not set.
  double? getAnnotationWidth(String toolName) {
    return _prefs.getDouble('$_keyAnnotationWidth$toolName');
  }

  /// Save the last-used color for a tool.
  Future<void> setAnnotationColor(String toolName, int colorValue) async {
    await _prefs.setInt('$_keyAnnotationColor$toolName', colorValue);
  }

  /// Save the last-used width for a tool.
  Future<void> setAnnotationWidth(String toolName, double width) async {
    await _prefs.setDouble('$_keyAnnotationWidth$toolName', width);
  }

  // =========================================================================
  // PERMISSION CACHE — Offline Access
  // =========================================================================

  /// Save the result of a successful Firestore permission check.
  Future<void> savePermissionCache({
    required bool hasAccess,
    required bool hasProfile,
    required String rol,
    required bool trialActive,
    required int trialDaysLeft,
    required bool trialExpired,
    required bool trialUsed,
  }) async {
    await _prefs.setBool(_keyPermHasAccess, hasAccess);
    await _prefs.setBool(_keyPermHasProfile, hasProfile);
    await _prefs.setString(_keyPermRol, rol);
    await _prefs.setBool(_keyPermTrialActive, trialActive);
    await _prefs.setInt(_keyPermTrialDaysLeft, trialDaysLeft);
    await _prefs.setBool(_keyPermTrialExpired, trialExpired);
    await _prefs.setBool(_keyPermTrialUsed, trialUsed);
    await _prefs.setString(
      _keyPermLastVerified,
      DateTime.now().toIso8601String(),
    );
  }

  /// Load the cached permission state. Returns null if no cache exists.
  PermissionCache? loadPermissionCache() {
    final lastVerifiedStr = _prefs.getString(_keyPermLastVerified);
    if (lastVerifiedStr == null) return null;

    return PermissionCache(
      hasAccess: _prefs.getBool(_keyPermHasAccess) ?? false,
      hasProfile: _prefs.getBool(_keyPermHasProfile) ?? false,
      rol: _prefs.getString(_keyPermRol) ?? 'pendiente',
      trialActive: _prefs.getBool(_keyPermTrialActive) ?? false,
      trialDaysLeft: _prefs.getInt(_keyPermTrialDaysLeft) ?? 0,
      trialExpired: _prefs.getBool(_keyPermTrialExpired) ?? false,
      trialUsed: _prefs.getBool(_keyPermTrialUsed) ?? false,
      lastVerified: DateTime.parse(lastVerifiedStr),
    );
  }

  /// Clear the permission cache (used on logout).
  Future<void> clearPermissionCache() async {
    await _prefs.remove(_keyPermHasAccess);
    await _prefs.remove(_keyPermHasProfile);
    await _prefs.remove(_keyPermRol);
    await _prefs.remove(_keyPermTrialActive);
    await _prefs.remove(_keyPermTrialDaysLeft);
    await _prefs.remove(_keyPermTrialExpired);
    await _prefs.remove(_keyPermTrialUsed);
    await _prefs.remove(_keyPermLastVerified);
  }
}
