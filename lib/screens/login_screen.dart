import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:flutter/foundation.dart' show kIsWeb, defaultTargetPlatform, TargetPlatform;

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> with SingleTickerProviderStateMixin {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();

  bool _isRegisterMode = false;
  bool _showPasswordFields = false;
  bool _isLoading = false;
  String? _errorMessage;
  String? _successMessage;

  late AnimationController _fadeController;
  late Animation<double> _fadeAnimation;

  // Atril color palette — elegant indigo/slate
  static const Color _accentColor = Color(0xFF5B6CF0);
  static const Color _bgDark = Color(0xFF121218);
  static const Color _surfaceDark = Color(0xFF1E1E2A);
  static const Color _borderColor = Color(0xFF2A2A3A);
  static const Color _textPrimary = Color(0xFFE8E6F0);
  static const Color _textSecondary = Color(0xFF8A87A0);

  /// Google Sign-In is only supported on Android, iOS, and Web.
  bool get _supportsGoogleSignIn {
    if (kIsWeb) return true;
    final platform = defaultTargetPlatform;
    return platform == TargetPlatform.android || platform == TargetPlatform.iOS;
  }

  @override
  void initState() {
    super.initState();
    _fadeController = AnimationController(
      duration: const Duration(milliseconds: 600),
      vsync: this,
    );
    _fadeAnimation = CurvedAnimation(
      parent: _fadeController,
      curve: Curves.easeOut,
    );
    _fadeController.forward();
  }

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    _fadeController.dispose();
    super.dispose();
  }

  void _showError(String msg) {
    setState(() {
      _errorMessage = msg;
      _successMessage = null;
    });
  }

  void _showSuccess(String msg) {
    setState(() {
      _successMessage = msg;
      _errorMessage = null;
    });
  }

  void _clearMessages() {
    setState(() {
      _errorMessage = null;
      _successMessage = null;
    });
  }

  static const String _noInternetMsg =
      'No hay conexión a internet.\n'
      'Para iniciar sesión por primera vez necesitás estar conectado. '
      'Una vez logueado, podrás usar Atril sin conexión.';

  bool _isNetworkError(Object error) {
    final msg = error.toString().toLowerCase();
    return msg.contains('socketexception') ||
        msg.contains('network') ||
        msg.contains('failed host lookup') ||
        msg.contains('connection refused') ||
        msg.contains('no address associated') ||
        msg.contains('unreachable') ||
        msg.contains('errno = 7') ||
        msg.contains('clientexception');
  }

  Future<void> _signInWithGoogle() async {
    _clearMessages();
    setState(() => _isLoading = true);

    try {
      if (kIsWeb) {
        final provider = GoogleAuthProvider();
        await FirebaseAuth.instance.signInWithPopup(provider);
      } else {
        final googleUser = await GoogleSignIn().signIn();
        if (googleUser == null) {
          setState(() => _isLoading = false);
          return;
        }
        final googleAuth = await googleUser.authentication;
        final credential = GoogleAuthProvider.credential(
          accessToken: googleAuth.accessToken,
          idToken: googleAuth.idToken,
        );
        await FirebaseAuth.instance.signInWithCredential(credential);
      }
    } on FirebaseAuthException catch (e) {
      if (_isNetworkError(e)) {
        _showError(_noInternetMsg);
      } else {
        _showError("Error al conectar con Google: ${e.message}");
      }
    } catch (e) {
      if (_isNetworkError(e)) {
        _showError(_noInternetMsg);
      } else {
        _showError("Error al conectar con Google: $e");
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _submitForm() async {
    if (!_formKey.currentState!.validate()) return;
    _clearMessages();

    final email = _emailController.text.trim();
    final password = _passwordController.text.trim();

    setState(() => _isLoading = true);

    if (_isRegisterMode) {
      final confirmPassword = _confirmPasswordController.text.trim();
      if (password != confirmPassword) {
        _showError("Las contraseñas no coinciden.");
        setState(() => _isLoading = false);
        return;
      }
      if (password.length < 6) {
        _showError("La contraseña debe tener al menos 6 caracteres.");
        setState(() => _isLoading = false);
        return;
      }

      try {
        final userCredential = await FirebaseAuth.instance
            .createUserWithEmailAndPassword(email: email, password: password);
        await userCredential.user?.sendEmailVerification();
        _showSuccess(
          "Cuenta creada exitosamente. Revisá tu casilla de correo (incluyendo spam) para verificar tu email.",
        );
        _formKey.currentState?.reset();
        Future.delayed(const Duration(seconds: 3), () {
          if (mounted) {
            setState(() {
              _isRegisterMode = false;
            });
          }
        });
      } on FirebaseAuthException catch (e) {
        if (_isNetworkError(e)) {
          _showError(_noInternetMsg);
        } else if (e.code == 'email-already-in-use') {
          _showError("Ese email ya está registrado.");
        } else {
          _showError("Error: ${e.message}");
        }
      } catch (e) {
        if (_isNetworkError(e)) {
          _showError(_noInternetMsg);
        } else {
          _showError("Error al registrar: $e");
        }
      }
    } else {
      try {
        await FirebaseAuth.instance.signInWithEmailAndPassword(
          email: email,
          password: password,
        );
      } on FirebaseAuthException catch (e) {
        if (_isNetworkError(e)) {
          _showError(_noInternetMsg);
        } else if (e.code == 'invalid-credential' || e.code == 'wrong-password' || e.code == 'user-not-found') {
          _showError("Credenciales incorrectas.");
        } else {
          _showError("Error al iniciar sesión: ${e.message}");
        }
      } catch (e) {
        if (_isNetworkError(e)) {
          _showError(_noInternetMsg);
        } else {
          _showError("Error al iniciar sesión: $e");
        }
      }
    }

    if (mounted) setState(() => _isLoading = false);
  }

  Future<void> _forgotPassword() async {
    final email = _emailController.text.trim();
    if (email.isEmpty) {
      _showError("Ingresá tu email primero para recuperar la contraseña.");
      return;
    }

    try {
      await FirebaseAuth.instance.sendPasswordResetEmail(email: email);
      _showSuccess("Email de recuperación enviado. Revisá tu bandeja de entrada y spam.");
    } on FirebaseAuthException catch (e) {
      _showError("Error al enviar el email: ${e.message}");
    }
  }

  void _toggleMode() {
    _clearMessages();
    setState(() {
      _isRegisterMode = !_isRegisterMode;
      _showPasswordFields = true;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bgDark,
      body: FadeTransition(
        opacity: _fadeAnimation,
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Container(
                padding: const EdgeInsets.all(32),
                decoration: BoxDecoration(
                  color: _surfaceDark,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: _borderColor),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.5),
                      blurRadius: 40,
                      offset: const Offset(0, 16),
                    ),
                  ],
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Header
                    Text(
                      _isRegisterMode ? "Registrate" : "Bienvenido",
                      style: const TextStyle(
                        fontSize: 28,
                        fontWeight: FontWeight.bold,
                        color: _textPrimary,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      _isRegisterMode
                          ? "Creá una cuenta para acceder a Atril."
                          : "Iniciá sesión para usar Atril.",
                      style: TextStyle(
                        fontSize: 14,
                        color: _textSecondary.withOpacity(0.7),
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 28),

                    // Google button (only on supported platforms)
                    if (_supportsGoogleSignIn) ...[
                      SizedBox(
                        width: double.infinity,
                        height: 50,
                        child: ElevatedButton.icon(
                          onPressed: _isLoading ? null : _signInWithGoogle,
                          icon: Image.network(
                            'https://www.gstatic.com/firebasejs/ui/2.0.0/images/auth/google.svg',
                            width: 20,
                            height: 20,
                            errorBuilder: (_, __, ___) => const Icon(Icons.g_mobiledata, size: 24),
                          ),
                          label: const Text(
                            "Continuar con Google",
                            style: TextStyle(
                              fontWeight: FontWeight.w600,
                              fontSize: 15,
                            ),
                          ),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.white,
                            foregroundColor: const Color(0xFF09090B),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                            elevation: 0,
                          ),
                        ),
                      ),
                      const SizedBox(height: 24),

                      // Separator
                      Row(
                        children: [
                          Expanded(child: Divider(color: _borderColor)),
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 12),
                            child: Text(
                              _isRegisterMode
                                  ? "O usá tu email"
                                  : "¿Tenés otro mail?",
                              style: TextStyle(
                                fontSize: 12,
                                color: _textSecondary.withOpacity(0.5),
                              ),
                            ),
                          ),
                          Expanded(child: Divider(color: _borderColor)),
                        ],
                      ),
                      const SizedBox(height: 24),
                    ],

                    // Form
                    Form(
                      key: _formKey,
                      child: Column(
                        children: [
                          _buildField(
                            controller: _emailController,
                            label: "EMAIL",
                            hint: "tu@email.com",
                            keyboardType: TextInputType.emailAddress,
                            onTap: () {
                              if (!_showPasswordFields) {
                                setState(() => _showPasswordFields = true);
                              }
                            },
                          ),
                          
                          AnimatedSize(
                            duration: const Duration(milliseconds: 300),
                            curve: Curves.easeOutCubic,
                            child: _showPasswordFields
                                ? Column(
                                    children: [
                                      const SizedBox(height: 16),
                                      _buildField(
                                        controller: _passwordController,
                                        label: "CONTRASEÑA",
                                        hint: "••••••••",
                                        isPassword: true,
                                      ),
                                      if (_isRegisterMode) ...[
                                        const SizedBox(height: 16),
                                        _buildField(
                                          controller: _confirmPasswordController,
                                          label: "CONFIRMAR CONTRASEÑA",
                                          hint: "••••••••",
                                          isPassword: true,
                                        ),
                                      ],
                                      const SizedBox(height: 20),
                                      SizedBox(
                                        width: double.infinity,
                                        height: 50,
                                        child: ElevatedButton(
                                          onPressed: _isLoading ? null : _submitForm,
                                          style: ElevatedButton.styleFrom(
                                            backgroundColor: _accentColor,
                                            foregroundColor: Colors.white,
                                            shape: RoundedRectangleBorder(
                                              borderRadius: BorderRadius.circular(12),
                                            ),
                                            elevation: 0,
                                          ),
                                          child: _isLoading
                                              ? const SizedBox(
                                                  width: 22,
                                                  height: 22,
                                                  child: CircularProgressIndicator(
                                                    strokeWidth: 2.5,
                                                    color: Colors.white,
                                                  ),
                                                )
                                              : Text(
                                                  _isRegisterMode ? "Crear Cuenta" : "Entrar",
                                                  style: const TextStyle(
                                                    fontWeight: FontWeight.w600,
                                                    fontSize: 15,
                                                  ),
                                                ),
                                        ),
                                      ),
                                      if (!_isRegisterMode) ...[
                                        const SizedBox(height: 12),
                                        TextButton(
                                          onPressed: _isLoading ? null : _forgotPassword,
                                          child: Text(
                                            "¿Olvidaste tu contraseña?",
                                            style: TextStyle(
                                              fontSize: 13,
                                              color: _textSecondary.withOpacity(0.6),
                                            ),
                                          ),
                                        ),
                                      ],
                                    ],
                                  )
                                : const SizedBox.shrink(),
                          ),
                        ],
                      ),
                    ),

                    // Messages
                    if (_errorMessage != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 16),
                        child: Text(
                          _errorMessage!,
                          style: const TextStyle(color: Color(0xFFEF4444), fontSize: 13),
                          textAlign: TextAlign.center,
                        ),
                      ),
                    if (_successMessage != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 16),
                        child: Text(
                          _successMessage!,
                          style: const TextStyle(color: Color(0xFF4CAF50), fontSize: 13),
                          textAlign: TextAlign.center,
                        ),
                      ),

                    const SizedBox(height: 24),
                    Divider(color: _borderColor),
                    const SizedBox(height: 16),

                    // Toggle mode
                    Wrap(
                      alignment: WrapAlignment.center,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        Text(
                          _isRegisterMode ? "¿Ya tenés cuenta?" : "¿No tenés usuario?",
                          style: TextStyle(
                            fontSize: 14,
                            color: _textSecondary.withOpacity(0.7),
                          ),
                        ),
                        TextButton(
                          onPressed: _toggleMode,
                          child: Text(
                            _isRegisterMode ? "Iniciar Sesión" : "Crear una cuenta",
                            style: const TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                              color: _accentColor,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildField({
    required TextEditingController controller,
    required String label,
    required String hint,
    bool isPassword = false,
    TextInputType? keyboardType,
    VoidCallback? onTap,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w500,
            letterSpacing: 1.2,
            color: _textSecondary.withOpacity(0.6),
          ),
        ),
        const SizedBox(height: 6),
        TextFormField(
          controller: controller,
          obscureText: isPassword,
          keyboardType: keyboardType,
          onTap: onTap,
          style: const TextStyle(color: _textPrimary, fontSize: 15),
          decoration: InputDecoration(
            hintText: hint,
            hintStyle: TextStyle(color: _textSecondary.withOpacity(0.3)),
            filled: true,
            fillColor: _bgDark,
            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: _borderColor),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: _borderColor),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: _accentColor),
            ),
          ),
          validator: (value) {
            if (value == null || value.isEmpty) return 'Campo requerido';
            return null;
          },
        ),
      ],
    );
  }
}
