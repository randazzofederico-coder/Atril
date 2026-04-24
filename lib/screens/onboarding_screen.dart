import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key});

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _interestController = TextEditingController();
  bool _isSubmitting = false;
  bool _showSuccess = false;

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
    final user = FirebaseAuth.instance.currentUser;
    if (user?.displayName != null && user!.displayName!.isNotEmpty) {
      _nameController.text = user.displayName!;
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _interestController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;

    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    setState(() => _isSubmitting = true);

    try {
      final db = FirebaseFirestore.instance;
      final batch = db.batch();

      // Crear perfil de usuario (shared across all apps)
      final userRef = db.collection('usuarios').doc(user.uid);
      batch.set(userRef, {
        'nombre': _nameController.text.trim().isNotEmpty
            ? _nameController.text.trim()
            : user.displayName ?? "Sin nombre",
        'email': user.email,
        'rol': 'pendiente',
        'es_alumno': false,
        'carpeta_personal_url': '',
        'suscripciones_apps': {
          'afinador': false,
          'metronomo': false,
          'atril': false,
          'elongacion_musical': false,
        },
        'fecha_registro': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      // Crear consulta para admin
      final consultaRef = db.collection('consultas_web').doc();
      batch.set(consultaRef, {
        'nombre': _nameController.text.trim().isNotEmpty
            ? _nameController.text.trim()
            : user.displayName ?? "Usuario Nuevo",
        'email': user.email,
        'motivo': 'Onboarding - Nuevo Registro (Atril App)',
        'mensaje': _interestController.text.trim(),
        'tipo': 'nuevo_registro',
        'fecha': FieldValue.serverTimestamp(),
        'leido': false,
        'eliminado': false,
      });

      await batch.commit();

      // Sincronizar displayName
      final name = _nameController.text.trim();
      if (name.isNotEmpty && name != user.displayName) {
        await user.updateDisplayName(name);
      }

      setState(() {
        _showSuccess = true;
        _isSubmitting = false;
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text("Error: $e"),
            backgroundColor: Colors.redAccent,
          ),
        );
        setState(() => _isSubmitting = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bgDark,
      body: Center(
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
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 400),
                child: _showSuccess ? _buildSuccess() : _buildForm(),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildForm() {
    return Form(
      key: _formKey,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text(
            "¡Ya casi estamos!",
            style: TextStyle(
              fontSize: 28,
              fontWeight: FontWeight.bold,
              color: _textPrimary,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            "Contame brevemente qué te trae por acá (clases, apps, etc.) así puedo habilitarte la cuenta.",
            style: TextStyle(
              fontSize: 14,
              color: _textSecondary.withOpacity(0.7),
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 28),

          // Nombre
          _buildLabel("TU NOMBRE"),
          const SizedBox(height: 6),
          TextFormField(
            controller: _nameController,
            style: const TextStyle(color: _textPrimary),
            decoration: _inputDecoration("¿Cómo te llamás?"),
            validator: (v) => v == null || v.trim().isEmpty ? 'Campo requerido' : null,
          ),
          const SizedBox(height: 20),

          // Interés
          _buildLabel("¿QUÉ ESTÁS BUSCANDO?"),
          const SizedBox(height: 6),
          TextFormField(
            controller: _interestController,
            style: const TextStyle(color: _textPrimary),
            maxLines: 4,
            decoration: _inputDecoration("Ej: Quiero usar el Atril, tomar clases..."),
            validator: (v) => v == null || v.trim().isEmpty ? 'Campo requerido' : null,
          ),
          const SizedBox(height: 24),

          // Submit
          SizedBox(
            width: double.infinity,
            height: 50,
            child: ElevatedButton(
              onPressed: _isSubmitting ? null : _submit,
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.white,
                foregroundColor: const Color(0xFF09090B),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                elevation: 0,
              ),
              child: _isSubmitting
                  ? const SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(
                        strokeWidth: 2.5,
                        color: Color(0xFF09090B),
                      ),
                    )
                  : const Text(
                      "Enviar solicitud",
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 15,
                      ),
                    ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSuccess() {
    return Column(
      key: const ValueKey('success'),
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 64,
          height: 64,
          decoration: BoxDecoration(
            color: const Color(0xFF4CAF50).withOpacity(0.1),
            shape: BoxShape.circle,
          ),
          child: const Icon(Icons.check, color: Color(0xFF4CAF50), size: 32),
        ),
        const SizedBox(height: 20),
        const Text(
          "¡Solicitud enviada!",
          style: TextStyle(
            fontSize: 24,
            fontWeight: FontWeight.bold,
            color: _textPrimary,
          ),
        ),
        const SizedBox(height: 12),
        Text(
          "Te habilitaremos a la brevedad. Recibirás un aviso en cuanto tu cuenta esté activa.",
          style: TextStyle(
            fontSize: 14,
            color: _textSecondary.withOpacity(0.7),
          ),
          textAlign: TextAlign.center,
        ),
      ],
    );
  }

  Widget _buildLabel(String text) {
    return Align(
      alignment: Alignment.centerLeft,
      child: Text(
        text,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w500,
          letterSpacing: 1.2,
          color: _textSecondary.withOpacity(0.6),
        ),
      ),
    );
  }

  InputDecoration _inputDecoration(String hint) {
    return InputDecoration(
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
    );
  }
}
