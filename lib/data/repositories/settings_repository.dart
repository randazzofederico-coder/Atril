import 'package:shared_preferences/shared_preferences.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import 'package:flutter/material.dart'; // For ThemeMode

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
}
