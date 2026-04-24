import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:url_launcher/url_launcher.dart';
import 'login_screen.dart';
import 'onboarding_screen.dart';
import 'home_shell.dart';
import '../data/repositories/settings_repository.dart';
import '../models/permission_cache.dart';

class AuthGate extends StatelessWidget {
  const AuthGate({super.key});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<User?>(
      stream: FirebaseAuth.instance.authStateChanges(),
      builder: (context, snapshot) {
        // No user (or still loading) → Login
        if (!snapshot.hasData || snapshot.data == null) {
          return const LoginScreen();
        }

        // User logged in → check Firestore permissions
        return _PermissionChecker(user: snapshot.data!);
      },
    );
  }
}

class _PermissionChecker extends StatefulWidget {
  final User user;
  const _PermissionChecker({required this.user});

  @override
  State<_PermissionChecker> createState() => _PermissionCheckerState();
}

class _PermissionCheckerState extends State<_PermissionChecker> {
  bool _isLoading = true;
  bool _hasProfile = false;
  bool _hasAccess = false;
  String _rolStatus = '';
  bool _trialActive = false;
  int _trialDaysLeft = 0;
  bool _trialExpired = false;
  bool _trialUsed = false;

  // Offline state
  bool _isOffline = false;
  int _daysUntilExpiry = 30;
  bool _needsInternet = false; // true = no cache at all, or cache expired
  String _needsInternetReason = '';

  // Atril color palette
  static const Color _accentColor = Color(0xFF5B6CF0);
  static const Color _bgDark = Color(0xFF121218);
  static const Color _surfaceDark = Color(0xFF1E1E2A);
  static const Color _borderColor = Color(0xFF2A2A3A);
  static const Color _textPrimary = Color(0xFFE8E6F0);
  static const Color _textSecondary = Color(0xFF8A87A0);

  @override
  void initState() {
    super.initState();
    _checkPermissions();
  }

  Future<void> _checkPermissions() async {
    try {
      // --- ATTEMPT ONLINE CHECK ---
      final docSnap = await FirebaseFirestore.instance
          .collection('usuarios')
          .doc(widget.user.uid)
          .get(const GetOptions(source: Source.server));

      if (!docSnap.exists) {
        // No profile → needs onboarding
        // Also cache this state so offline shows "needs onboarding"
        await SettingsRepository.instance.savePermissionCache(
          hasAccess: false,
          hasProfile: false,
          rol: 'pendiente',
          trialActive: false,
          trialDaysLeft: 0,
          trialExpired: false,
          trialUsed: false,
        );
        setState(() {
          _isLoading = false;
          _hasProfile = false;
          _isOffline = false;
        });
        return;
      }

      final data = docSnap.data()!;
      final suscripciones = data['suscripciones_apps'] as Map<String, dynamic>?;
      final hasAtril = suscripciones?['atril'] == true;
      final rol = data['rol'] as String? ?? 'pendiente';

      // Check trial period
      bool trialActive = false;
      int trialDaysLeft = 0;
      bool trialExpired = false;
      bool trialUsed = false;

      final trialInicio = data['trial_atril_inicio'];
      if (trialInicio != null) {
        trialUsed = true;
        final DateTime trialStart = (trialInicio as Timestamp).toDate();
        final DateTime trialEnd = trialStart.add(const Duration(days: 30));
        final DateTime now = DateTime.now();

        if (now.isBefore(trialEnd)) {
          trialActive = true;
          trialDaysLeft = trialEnd.difference(now).inDays;
        } else {
          trialExpired = true;
        }
      }

      final hasAccess = hasAtril || rol == 'admin' || trialActive;

      // --- CACHE THE RESULT ---
      await SettingsRepository.instance.savePermissionCache(
        hasAccess: hasAccess,
        hasProfile: true,
        rol: rol,
        trialActive: trialActive,
        trialDaysLeft: trialDaysLeft,
        trialExpired: trialExpired,
        trialUsed: trialUsed,
      );

      setState(() {
        _isLoading = false;
        _hasProfile = true;
        _hasAccess = hasAccess;
        _rolStatus = rol;
        _trialActive = trialActive;
        _trialDaysLeft = trialDaysLeft;
        _trialExpired = trialExpired;
        _trialUsed = trialUsed;
        _isOffline = false;
        _daysUntilExpiry = 30; // Just verified
      });
    } catch (e) {
      // --- OFFLINE FALLBACK ---
      debugPrint("Firestore check failed (offline?): $e");
      _handleOfflineFallback();
    }
  }

  void _handleOfflineFallback() {
    final cache = SettingsRepository.instance.loadPermissionCache();

    if (cache == null) {
      // Never verified online → must connect
      setState(() {
        _isLoading = false;
        _needsInternet = true;
        _needsInternetReason =
            'Necesitás conectarte a internet al menos una vez para verificar tu acceso.';
      });
      return;
    }

    if (cache.isExpired) {
      // Cache too old → must reconnect
      setState(() {
        _isLoading = false;
        _needsInternet = true;
        _needsInternetReason =
            'Han pasado más de 30 días desde tu última verificación. '
            'Conectate a internet para revalidar tu acceso.';
      });
      return;
    }

    if (!cache.hasProfile) {
      // Profile was never created
      setState(() {
        _isLoading = false;
        _needsInternet = true;
        _needsInternetReason =
            'Tu perfil no fue creado todavía. '
            'Conectate a internet para completar el registro.';
      });
      return;
    }

    if (!cache.hasAccess) {
      // No access in last check
      setState(() {
        _isLoading = false;
        _needsInternet = true;
        _needsInternetReason =
            'Tu acceso no estaba habilitado en la última verificación. '
            'Conectate a internet para verificar si cambió tu estado.';
      });
      return;
    }

    // Cache valid + has access → enter offline mode
    setState(() {
      _isLoading = false;
      _hasProfile = true;
      _hasAccess = true;
      _rolStatus = cache.rol;
      _trialActive = cache.trialActive;
      _trialDaysLeft = cache.trialDaysLeft;
      _trialExpired = cache.trialExpired;
      _trialUsed = cache.trialUsed;
      _isOffline = true;
      _daysUntilExpiry = cache.daysUntilExpiry;
    });
  }

  Future<void> _signOut() async {
    await SettingsRepository.instance.clearPermissionCache();
    await FirebaseAuth.instance.signOut();
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(
        backgroundColor: Color(0xFF121218),
        body: Center(
          child: ClipRRect(
            borderRadius: BorderRadius.all(Radius.circular(20)),
            child: Image(
              image: AssetImage('Atril_cropped.png'),
              width: 120,
              height: 120,
            ),
          ),
        ),
      );
    }

    // Needs internet (no cache, expired cache, or no access in cache)
    if (_needsInternet) {
      return _NeedsInternetScreen(
        reason: _needsInternetReason,
        onRetry: () {
          setState(() {
            _isLoading = true;
            _needsInternet = false;
          });
          _checkPermissions();
        },
        onSignOut: _signOut,
      );
    }

    // No profile → Onboarding
    if (!_hasProfile) {
      return const OnboardingScreen();
    }

    // Has profile but no access → pending screen
    if (!_hasAccess) {
      return _PendingAccessScreen(
        rol: _rolStatus,
        trialExpired: _trialExpired,
        trialUsed: _trialUsed,
        onSignOut: _signOut,
        onRetry: () {
          setState(() => _isLoading = true);
          _checkPermissions();
        },
        onTrialActivated: () {
          setState(() => _isLoading = true);
          _checkPermissions();
        },
      );
    }

    // Access granted → App!
    // Show offline warning banner if ≤5 days remain
    if (_isOffline && _daysUntilExpiry <= 5) {
      return _OfflineWarningWrapper(
        daysLeft: _daysUntilExpiry,
        child: const HomeShell(),
      );
    }
    if (_trialActive) {
      return _TrialBannerWrapper(
        daysLeft: _trialDaysLeft,
        child: const HomeShell(),
      );
    }
    return const HomeShell();
  }
}

// ---------------------------------------------------------------------------
// Offline warning banner — shows when ≤5 days until revalidation required
// ---------------------------------------------------------------------------
class _OfflineWarningWrapper extends StatelessWidget {
  final int daysLeft;
  final Widget child;

  const _OfflineWarningWrapper({required this.daysLeft, required this.child});

  @override
  Widget build(BuildContext context) {
    final dayText = daysLeft == 1 ? 'día' : 'días';
    final message = daysLeft == 0
        ? 'Conectate a internet hoy para revalidar tu acceso'
        : 'Conectate a internet para revalidar tu acceso · $daysLeft $dayText restantes';

    return Column(
      children: [
        Material(
          color: const Color(0xFF1E1E2A),
          child: SafeArea(
            bottom: false,
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  colors: [Color(0xFF4A3800), Color(0xFFF59E0B)],
                ),
              ),
              child: Row(
                children: [
                  const Icon(Icons.wifi_off_rounded, color: Colors.white70, size: 18),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      message,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        Expanded(child: child),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Trial banner wrapper — shows remaining trial days at the top
// ---------------------------------------------------------------------------
class _TrialBannerWrapper extends StatelessWidget {
  final int daysLeft;
  final Widget child;

  const _TrialBannerWrapper({required this.daysLeft, required this.child});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Material(
          color: const Color(0xFF1E1E2A),
          child: SafeArea(
            bottom: false,
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  colors: [Color(0xFF2A2A3A), Color(0xFF5B6CF0)],
                ),
              ),
              child: Row(
                children: [
                  const Icon(Icons.access_time_rounded, color: Colors.white70, size: 18),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      "Período de prueba · $daysLeft ${daysLeft == 1 ? 'día' : 'días'} restantes",
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                  GestureDetector(
                    onTap: () => _openSubscription(),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.15),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Text(
                        "Suscribirse",
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        Expanded(child: child),
      ],
    );
  }

  Future<void> _openSubscription() async {
    final uri = Uri.parse('https://federicorandazzo.com.ar/apps/');
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }
}

// ---------------------------------------------------------------------------
// Needs Internet Screen — shown when no cache or expired cache
// ---------------------------------------------------------------------------
class _NeedsInternetScreen extends StatelessWidget {
  final String reason;
  final VoidCallback onRetry;
  final VoidCallback onSignOut;

  const _NeedsInternetScreen({
    required this.reason,
    required this.onRetry,
    required this.onSignOut,
  });

  // Atril color palette
  static const Color _accentColor = Color(0xFF5B6CF0);
  static const Color _bgDark = Color(0xFF121218);
  static const Color _surfaceDark = Color(0xFF1E1E2A);
  static const Color _borderColor = Color(0xFF2A2A3A);
  static const Color _textPrimary = Color(0xFFE8E6F0);
  static const Color _textSecondary = Color(0xFF8A87A0);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bgDark,
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 440),
            child: Container(
              padding: const EdgeInsets.all(28),
              decoration: BoxDecoration(
                color: _surfaceDark,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: _borderColor),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.4),
                    blurRadius: 30,
                    offset: const Offset(0, 12),
                  ),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Icon
                  TweenAnimationBuilder<double>(
                    tween: Tween(begin: 0.0, end: 1.0),
                    duration: const Duration(milliseconds: 800),
                    curve: Curves.elasticOut,
                    builder: (context, value, child) {
                      return Transform.scale(scale: value, child: child);
                    },
                    child: Container(
                      width: 72,
                      height: 72,
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: [
                            const Color(0xFFF59E0B).withOpacity(0.15),
                            const Color(0xFFEF4444).withOpacity(0.15),
                          ],
                        ),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.wifi_off_rounded,
                        color: Color(0xFFF59E0B),
                        size: 34,
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),

                  const Text(
                    "Conexión necesaria",
                    style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                      color: _textPrimary,
                    ),
                  ),
                  const SizedBox(height: 16),

                  Text(
                    reason,
                    style: TextStyle(
                      fontSize: 14,
                      color: _textSecondary.withOpacity(0.7),
                      height: 1.6,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 28),

                  // Retry button
                  SizedBox(
                    width: double.infinity,
                    height: 48,
                    child: ElevatedButton.icon(
                      onPressed: onRetry,
                      icon: const Icon(Icons.refresh_rounded, size: 20),
                      label: const Text(
                        "Reintentar",
                        style: TextStyle(
                          fontWeight: FontWeight.w600,
                          fontSize: 15,
                        ),
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: _accentColor,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        elevation: 0,
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),

                  // Sign out
                  SizedBox(
                    width: double.infinity,
                    height: 44,
                    child: TextButton(
                      onPressed: onSignOut,
                      style: TextButton.styleFrom(
                        foregroundColor: _textSecondary.withOpacity(0.5),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: const Text(
                        "Cerrar sesión",
                        style: TextStyle(fontWeight: FontWeight.w500, fontSize: 14),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Pending access screen — trial, subscription & admin notice
// ---------------------------------------------------------------------------
class _PendingAccessScreen extends StatefulWidget {
  final String rol;
  final bool trialExpired;
  final bool trialUsed;
  final VoidCallback onSignOut;
  final VoidCallback onRetry;
  final VoidCallback onTrialActivated;

  const _PendingAccessScreen({
    required this.rol,
    required this.trialExpired,
    required this.trialUsed,
    required this.onSignOut,
    required this.onRetry,
    required this.onTrialActivated,
  });

  @override
  State<_PendingAccessScreen> createState() => _PendingAccessScreenState();
}

class _PendingAccessScreenState extends State<_PendingAccessScreen>
    with SingleTickerProviderStateMixin {
  bool _isActivatingTrial = false;
  late AnimationController _fadeController;
  late Animation<double> _fadeAnim;

  // Atril color palette
  static const Color _accentColor = Color(0xFF5B6CF0);
  static const Color _bgDark = Color(0xFF121218);
  static const Color _surfaceDark = Color(0xFF1E1E2A);
  static const Color _borderColor = Color(0xFF2A2A3A);
  static const Color _textPrimary = Color(0xFFE8E6F0);
  static const Color _textSecondary = Color(0xFF8A87A0);

  @override
  void initState() {
    super.initState();
    _fadeController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );
    _fadeAnim = CurvedAnimation(parent: _fadeController, curve: Curves.easeOut);
    _fadeController.forward();
  }

  @override
  void dispose() {
    _fadeController.dispose();
    super.dispose();
  }

  Future<void> _activateTrial() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    setState(() => _isActivatingTrial = true);

    try {
      await FirebaseFirestore.instance
          .collection('usuarios')
          .doc(user.uid)
          .update({
        'trial_atril_inicio': FieldValue.serverTimestamp(),
      });

      // Send admin notification about trial activation
      await FirebaseFirestore.instance.collection('consultas_web').add({
        'nombre': user.displayName ?? 'Usuario',
        'email': user.email,
        'motivo': 'Trial Activado - Atril',
        'mensaje':
            '${user.displayName ?? "Un usuario"} (${user.email}) activó el período de prueba de 30 días para Atril.',
        'tipo': 'trial_activado',
        'fecha': FieldValue.serverTimestamp(),
        'leido': false,
        'eliminado': false,
      });

      if (mounted) {
        widget.onTrialActivated();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text("Error al activar prueba: $e"),
            backgroundColor: Colors.redAccent,
          ),
        );
        setState(() => _isActivatingTrial = false);
      }
    }
  }

  Future<void> _openSubscription() async {
    final uri = Uri.parse('https://federicorandazzo.com.ar/apps/');
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bgDark,
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: FadeTransition(
            opacity: _fadeAnim,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 440),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _buildMainCard(),
                  const SizedBox(height: 16),
                  _buildTrialCard(),
                  const SizedBox(height: 16),
                  _buildSubscriptionCard(),
                  const SizedBox(height: 24),
                  _buildBottomActions(),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildMainCard() {
    return Container(
      padding: const EdgeInsets.all(28),
      decoration: BoxDecoration(
        color: _surfaceDark,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: _borderColor),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.4),
            blurRadius: 30,
            offset: const Offset(0, 12),
          ),
        ],
      ),
      child: Column(
        children: [
          // Animated icon
          TweenAnimationBuilder<double>(
            tween: Tween(begin: 0.0, end: 1.0),
            duration: const Duration(milliseconds: 800),
            curve: Curves.elasticOut,
            builder: (context, value, child) {
              return Transform.scale(scale: value, child: child);
            },
            child: Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    _accentColor.withOpacity(0.15),
                    const Color(0xFF8B5CF6).withOpacity(0.15),
                  ],
                ),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.mail_outline_rounded,
                color: _accentColor,
                size: 34,
              ),
            ),
          ),
          const SizedBox(height: 20),

          const Text(
            "Solicitud Enviada",
            style: TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.bold,
              color: _textPrimary,
            ),
          ),
          const SizedBox(height: 12),

          // Info badge
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            decoration: BoxDecoration(
              color: const Color(0xFF4CAF50).withOpacity(0.1),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: const Color(0xFF4CAF50).withOpacity(0.2),
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.check_circle_outline,
                  color: const Color(0xFF4CAF50).withOpacity(0.8),
                  size: 16,
                ),
                const SizedBox(width: 8),
                Text(
                  "El administrador fue notificado",
                  style: TextStyle(
                    color: const Color(0xFF4CAF50).withOpacity(0.9),
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          Text(
            "Tu solicitud de acceso a Atril está siendo revisada. "
            "Mientras tanto, podés iniciar un período de prueba gratuito "
            "o suscribirte directamente.",
            style: TextStyle(
              fontSize: 14,
              color: _textSecondary.withOpacity(0.7),
              height: 1.6,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  Widget _buildTrialCard() {
    final bool canTrial = !widget.trialUsed;

    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: _surfaceDark,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: canTrial
              ? _accentColor.withOpacity(0.3)
              : _borderColor,
        ),
        boxShadow: [
          if (canTrial)
            BoxShadow(
              color: _accentColor.withOpacity(0.08),
              blurRadius: 24,
              offset: const Offset(0, 8),
            ),
        ],
      ),
      child: Column(
        children: [
          Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: canTrial
                      ? _accentColor.withOpacity(0.12)
                      : Colors.white.withOpacity(0.05),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  canTrial
                      ? Icons.rocket_launch_rounded
                      : Icons.timer_off_outlined,
                  color: canTrial
                      ? _accentColor
                      : _textSecondary,
                  size: 22,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      canTrial
                          ? "Prueba Gratuita"
                          : widget.trialExpired
                              ? "Prueba Finalizada"
                              : "Prueba no disponible",
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: _textPrimary,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      canTrial
                          ? "30 días de acceso completo, sin compromiso"
                          : "Tu período de prueba de 30 días ha expirado",
                      style: TextStyle(
                        fontSize: 12,
                        color: _textSecondary.withOpacity(0.6),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),

          SizedBox(
            width: double.infinity,
            height: 48,
            child: ElevatedButton(
              onPressed: canTrial && !_isActivatingTrial
                  ? _activateTrial
                  : null,
              style: ElevatedButton.styleFrom(
                backgroundColor: _accentColor,
                foregroundColor: Colors.white,
                disabledBackgroundColor: Colors.white.withOpacity(0.06),
                disabledForegroundColor: _textSecondary,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                elevation: 0,
              ),
              child: _isActivatingTrial
                  ? const SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(
                        strokeWidth: 2.5,
                        color: Colors.white,
                      ),
                    )
                  : Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          canTrial ? Icons.play_arrow_rounded : Icons.block,
                          size: 20,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          canTrial
                              ? "Comenzar prueba gratuita"
                              : "Prueba utilizada",
                          style: const TextStyle(
                            fontWeight: FontWeight.w600,
                            fontSize: 15,
                          ),
                        ),
                      ],
                    ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSubscriptionCard() {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: _surfaceDark,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: _borderColor),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: const Color(0xFFF59E0B).withOpacity(0.12),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(
                  Icons.lock_open_rounded,
                  color: Color(0xFFF59E0B),
                  size: 22,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      "Suscripción",
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: _textPrimary,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      "Acceso completo y permanente a Atril",
                      style: TextStyle(
                        fontSize: 12,
                        color: _textSecondary.withOpacity(0.6),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),

          SizedBox(
            width: double.infinity,
            height: 48,
            child: OutlinedButton(
              onPressed: _openSubscription,
              style: OutlinedButton.styleFrom(
                side: const BorderSide(
                  color: Color(0xFFF59E0B),
                  width: 1.5,
                ),
                foregroundColor: const Color(0xFFF59E0B),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child: const Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.open_in_new_rounded, size: 18),
                  SizedBox(width: 8),
                  Text(
                    "Ver opciones de suscripción",
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 15,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBottomActions() {
    return Column(
      children: [
        SizedBox(
          width: double.infinity,
          height: 44,
          child: TextButton.icon(
            onPressed: widget.onRetry,
            icon: const Icon(Icons.refresh_rounded, size: 18),
            label: const Text(
              "Verificar acceso de nuevo",
              style: TextStyle(fontWeight: FontWeight.w500, fontSize: 14),
            ),
            style: TextButton.styleFrom(
              foregroundColor: _textSecondary,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          ),
        ),
        const SizedBox(height: 4),
        SizedBox(
          width: double.infinity,
          height: 44,
          child: TextButton(
            onPressed: widget.onSignOut,
            style: TextButton.styleFrom(
              foregroundColor: _textSecondary.withOpacity(0.5),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            child: const Text(
              "Cerrar sesión",
              style: TextStyle(fontWeight: FontWeight.w500, fontSize: 14),
            ),
          ),
        ),
      ],
    );
  }
}
