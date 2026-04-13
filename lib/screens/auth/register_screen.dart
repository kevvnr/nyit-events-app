import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../../config/app_config.dart';
import '../../providers/auth_provider.dart';
import '../../router/app_router.dart';
import '../../services/auth_service.dart';

class RegisterScreen extends ConsumerStatefulWidget {
  const RegisterScreen({super.key});

  @override
  ConsumerState<RegisterScreen> createState() =>
      _RegisterScreenState();
}

class _RegisterScreenState extends ConsumerState<RegisterScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _emailController = TextEditingController();
  final _studentIdController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();
  bool _obscurePassword = true;
  bool _obscureConfirm = true;
  bool _isLoading = false;
  String _selectedRole = AppConfig.roleStudent;

  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    _studentIdController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  String _friendlyError(dynamic e) {
    if (e is FirebaseAuthException) {
      switch (e.code) {
        case 'email-already-in-use':
          return 'An account with this email already exists.';
        case 'weak-password':
          return 'Password must be at least 6 characters.';
        case 'invalid-email-domain':
          return e.message ?? 'Only @nyit.edu emails are allowed.';
        default:
          return e.message ?? 'An error occurred. Please try again.';
      }
    }
    return 'An error occurred. Please try again.';
  }

  Future<void> _register() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _isLoading = true);
    try {
      // Check ID uniqueness before creating account
      final idTaken = await AuthService()
          .isStudentIdTaken(_studentIdController.text);
      if (idTaken) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: const Text(
                  'This ID number is already in use. Please use your actual student/employee ID.'),
              backgroundColor: Colors.red.shade700,
            ),
          );
        }
        setState(() => _isLoading = false);
        return;
      }

      await ref.read(authNotifierProvider.notifier).register(
            name: _nameController.text,
            email: _emailController.text,
            password: _passwordController.text,
            studentId: _studentIdController.text,
            role: _selectedRole,
          );

      if (!mounted) return;

      if (_selectedRole == AppConfig.roleTeacher) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Account created! A Super Admin will approve your teacher account shortly.',
            ),
            duration: Duration(seconds: 4),
          ),
        );
        context.go(AppRoutes.welcome);
      } else {
        context.go(AppRoutes.home);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(_friendlyError(e)),
            backgroundColor: Colors.red.shade700,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Widget _buildField({
    required String label,
    required TextEditingController controller,
    required String? Function(String?) validator,
    TextInputType keyboardType = TextInputType.text,
    bool obscure = false,
    bool showToggle = false,
    VoidCallback? onToggle,
    String? hint,
    bool autocorrect = true,
    List<TextInputFormatter>? inputFormatters,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w600,
            color: Color(0xFF1a3a6b),
          ),
        ),
        const SizedBox(height: 6),
        TextFormField(
          controller: controller,
          keyboardType: keyboardType,
          obscureText: obscure,
          autocorrect: autocorrect,
          inputFormatters: inputFormatters,
          style: const TextStyle(
              fontSize: 15, color: Color(0xFF1a3a6b)),
          decoration: InputDecoration(
            hintText: hint,
            hintStyle: TextStyle(
                color: Colors.grey.shade400, fontSize: 14),
            contentPadding: const EdgeInsets.symmetric(
                horizontal: 14, vertical: 14),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(6),
              borderSide:
                  BorderSide(color: Colors.grey.shade400),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(6),
              borderSide:
                  BorderSide(color: Colors.grey.shade400),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(6),
              borderSide: const BorderSide(
                  color: Color(0xFF1565C0), width: 2),
            ),
            errorBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(6),
              borderSide:
                  const BorderSide(color: Colors.red, width: 1),
            ),
            filled: true,
            fillColor: Colors.white,
            suffixIcon: showToggle
                ? IconButton(
                    icon: Icon(
                      obscure
                          ? Icons.visibility_outlined
                          : Icons.visibility_off_outlined,
                      color: Colors.grey.shade500,
                      size: 20,
                    ),
                    onPressed: onToggle,
                  )
                : null,
          ),
          validator: validator,
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: Column(
        children: [
          // Top navy header
          Container(
            width: double.infinity,
            color: const Color(0xFF1a3a6b),
            child: SafeArea(
              bottom: false,
              child: Padding(
                padding:
                    const EdgeInsets.fromLTRB(16, 8, 16, 24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const SizedBox(height: 16),
                    const Text(
                      'NEW YORK INSTITUTE\nOF TECHNOLOGY',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 20,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 0.5,
                        height: 1.3,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Create your NYIT Events account',
                      style: TextStyle(
                        color: Colors.white.withOpacity(0.7),
                        fontSize: 13,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),

          // Form
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const SizedBox(height: 8),
                    const Text(
                      'Create Account',
                      style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFF1a3a6b),
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'Use your @nyit.edu email address',
                      style: TextStyle(
                        color: Colors.grey.shade500,
                        fontSize: 13,
                      ),
                    ),
                    const SizedBox(height: 24),

                    // Role selector
                    const Text(
                      'Account Type',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFF1a3a6b),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Container(
                      decoration: BoxDecoration(
                        border: Border.all(
                            color: Colors.grey.shade400),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Column(
                        children: [
                          _RoleTile(
                            title: 'Student',
                            subtitle:
                                'Browse and RSVP for events',
                            icon: Icons.person_rounded,
                            selected: _selectedRole ==
                                AppConfig.roleStudent,
                            onTap: () => setState(() =>
                                _selectedRole =
                                    AppConfig.roleStudent),
                          ),
                          Divider(
                              height: 0,
                              color: Colors.grey.shade300),
                          _RoleTile(
                            title: 'Faculty / Staff',
                            subtitle:
                                'Create and manage events (requires approval)',
                            icon: Icons.school_rounded,
                            selected: _selectedRole ==
                                AppConfig.roleTeacher,
                            onTap: () => setState(() =>
                                _selectedRole =
                                    AppConfig.roleTeacher),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 20),

                    _buildField(
                      label: 'Full Name',
                      controller: _nameController,
                      hint: 'John Smith',
                      validator: (val) {
                        if (val == null || val.trim().isEmpty) {
                          return 'Full name is required';
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 16),

                    _buildField(
                      label: 'NYIT Email',
                      controller: _emailController,
                      hint: 'you@nyit.edu',
                      keyboardType: TextInputType.emailAddress,
                      autocorrect: false,
                      validator: (val) {
                        if (val == null || val.isEmpty) {
                          return 'Email is required';
                        }
                        if (!AppConfig.isValidNyitEmail(val)) {
                          return 'Must be a @nyit.edu email address';
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 16),

                    _buildField(
                      label: 'Student / Employee ID',
                      controller: _studentIdController,
                      hint: 'e.g. 1234567',
                      keyboardType: TextInputType.number,
                      inputFormatters: [
                        FilteringTextInputFormatter.digitsOnly,
                        LengthLimitingTextInputFormatter(7),
                      ],
                      validator: (val) {
                        if (val == null || val.trim().isEmpty) {
                          return 'ID is required';
                        }
                        if (val.trim().length > 7) {
                          return 'ID must be 7 digits or fewer';
                        }
                        if (!RegExp(r'^\d+$').hasMatch(val.trim())) {
                          return 'ID must contain numbers only';
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 16),

                    _buildField(
                      label: 'Password',
                      controller: _passwordController,
                      obscure: _obscurePassword,
                      showToggle: true,
                      onToggle: () => setState(() =>
                          _obscurePassword = !_obscurePassword),
                      validator: (val) {
                        if (val == null || val.isEmpty) {
                          return 'Password is required';
                        }
                        if (val.length < 6) {
                          return 'Password must be at least 6 characters';
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 16),

                    _buildField(
                      label: 'Confirm Password',
                      controller: _confirmPasswordController,
                      obscure: _obscureConfirm,
                      showToggle: true,
                      onToggle: () => setState(() =>
                          _obscureConfirm = !_obscureConfirm),
                      validator: (val) {
                        if (val == null || val.isEmpty) {
                          return 'Please confirm your password';
                        }
                        if (val != _passwordController.text) {
                          return 'Passwords do not match';
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 28),

                    // Create account button
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: _isLoading ? null : _register,
                        style: ElevatedButton.styleFrom(
                          backgroundColor:
                              const Color(0xFF1565C0),
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(
                              vertical: 16),
                          shape: RoundedRectangleBorder(
                            borderRadius:
                                BorderRadius.circular(6),
                          ),
                          elevation: 0,
                          textStyle: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        child: _isLoading
                            ? const SizedBox(
                                height: 20,
                                width: 20,
                                child: CircularProgressIndicator(
                                  color: Colors.white,
                                  strokeWidth: 2,
                                ),
                              )
                            : const Text('Create account'),
                      ),
                    ),
                    const SizedBox(height: 16),

                    Center(
                      child: Row(
                        mainAxisAlignment:
                            MainAxisAlignment.center,
                        children: [
                          Text(
                            'Already have an account? ',
                            style: TextStyle(
                              color: Colors.grey.shade600,
                              fontSize: 14,
                            ),
                          ),
                          TextButton(
                            onPressed: () =>
                                context.push(AppRoutes.login),
                            child: const Text(
                              'Sign in',
                              style: TextStyle(
                                color: Color(0xFF1565C0),
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 24),
                  ],
                ),
              ),
            ),
          ),

          // Footer
          Container(
            color: Colors.grey.shade100,
            padding: const EdgeInsets.symmetric(
                horizontal: 24, vertical: 12),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Powered by NYIT',
                  style: TextStyle(
                    color: Colors.grey.shade500,
                    fontSize: 12,
                  ),
                ),
                Text(
                  'Privacy Policy',
                  style: TextStyle(
                    color: Colors.grey.shade500,
                    fontSize: 12,
                    decoration: TextDecoration.underline,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _RoleTile extends StatelessWidget {
  final String title;
  final String subtitle;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;

  const _RoleTile({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(
            horizontal: 16, vertical: 12),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: selected
                    ? const Color(0xFF1565C0).withOpacity(0.1)
                    : Colors.grey.withOpacity(0.08),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(
                icon,
                color: selected
                    ? const Color(0xFF1565C0)
                    : Colors.grey,
                size: 20,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 14,
                      color: selected
                          ? const Color(0xFF1565C0)
                          : const Color(0xFF1a3a6b),
                    ),
                  ),
                  Text(
                    subtitle,
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.grey.shade500,
                    ),
                  ),
                ],
              ),
            ),
            Radio<bool>(
              value: true,
              groupValue: selected,
              onChanged: (_) => onTap(),
              activeColor: const Color(0xFF1565C0),
            ),
          ],
        ),
      ),
    );
  }
}