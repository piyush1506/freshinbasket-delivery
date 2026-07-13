import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/auth_provider.dart';
import '../services/api_service.dart';
import '../theme/app_theme.dart';

enum AuthStep { phone, otp, register }

class AuthScreen extends StatefulWidget {
  const AuthScreen({super.key});

  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> {
  AuthStep _step = AuthStep.phone;
  final _phoneController = TextEditingController();
  final _usernameController = TextEditingController();
  final _emailController = TextEditingController();
  final _otpController = TextEditingController();
  final _formKey = GlobalKey<FormState>();
  String? _reqId;

  @override
  void dispose() {
    _phoneController.dispose();
    _usernameController.dispose();
    _emailController.dispose();
    _otpController.dispose();
    super.dispose();
  }

  void _showSettingsDialog() {
    final controller = TextEditingController(text: ApiService.baseUrl);
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Server Settings'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('Configure API Backend Base URL:'),
            const SizedBox(height: 12),
            TextField(
              controller: controller,
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                labelText: 'Base URL',
                hintText: 'http://192.168.x.x:8000',
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () async {
              await ApiService.setBaseUrl(controller.text);
              if (context.mounted) Navigator.pop(context);
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }

  void _handleSendOtp() async {
    if (!_formKey.currentState!.validate()) return;

    final auth = Provider.of<AuthProvider>(context, listen: false);
    final reqId = await auth.sendOtp(_phoneController.text.trim());
    if (!mounted) return;

    if (reqId != null) {
      setState(() {
        _step = AuthStep.otp;
        _reqId = reqId;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('OTP sent successfully.'),
          backgroundColor: AppTheme.primaryColor,
        ),
      );
    } else {
      _showError(auth.error ?? 'Failed to send OTP');
    }
  }

  void _handleVerifyOtp() async {
    if (!_formKey.currentState!.validate()) return;
    if (_reqId == null) {
      _showError('Request session expired. Please request a new OTP.');
      return;
    }

    final auth = Provider.of<AuthProvider>(context, listen: false);
    final data = await auth.verifyOtp(
      _phoneController.text.trim(),
      _otpController.text.trim(),
      _reqId!,
    );

    if (!mounted) return;

    if (data != null) {
      final role = data['user']['role'];
      final username = data['user']['username'];

      if (role == 'DELIVERY' && username != null && username.isNotEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Login successful! Welcome back.'),
            backgroundColor: AppTheme.primaryColor,
          ),
        );
        Navigator.pushReplacementNamed(context, '/');
      } else {
        // Need to fill registration details (either role is customer or username is empty)
        setState(() {
          _step = AuthStep.register;
          if (username != null && username.isNotEmpty) {
            _usernameController.text = username;
          }
          final email = data['user']['email'];
          if (email != null && email.isNotEmpty) {
            _emailController.text = email;
          }
        });
      }
    } else {
      _showError(auth.error ?? 'Invalid OTP code');
    }
  }

  void _handleRegister() async {
    if (!_formKey.currentState!.validate()) return;

    final auth = Provider.of<AuthProvider>(context, listen: false);
    final success = await auth.register(
      _usernameController.text.trim(),
      _phoneController.text.trim(),
      _emailController.text.trim(),
    );

    if (!mounted) return;

    if (success) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Registration successful! Welcome to the delivery network.'),
          backgroundColor: AppTheme.primaryColor,
        ),
      );
      Navigator.pushReplacementNamed(context, '/');
    } else {
      _showError(auth.error ?? 'Registration failed');
    }
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: AppTheme.errorColor,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final auth = Provider.of<AuthProvider>(context);

    String buttonText;
    VoidCallback? buttonAction;

    switch (_step) {
      case AuthStep.phone:
        buttonText = 'Send OTP';
        buttonAction = auth.loading ? null : _handleSendOtp;
        break;
      case AuthStep.otp:
        buttonText = 'Verify & Sign In';
        buttonAction = auth.loading ? null : _handleVerifyOtp;
        break;
      case AuthStep.register:
        buttonText = 'Complete Registration';
        buttonAction = auth.loading ? null : _handleRegister;
        break;
    }

    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.settings_outlined, color: AppTheme.textSecondaryColor),
            onPressed: _showSettingsDialog,
            tooltip: 'Server Settings',
          ),
        ],
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: 20),
                const Icon(
                  Icons.local_shipping_outlined,
                  size: 56,
                  color: AppTheme.primaryColor,
                ),
                const SizedBox(height: 24),
                Text(
                  _step == AuthStep.register ? 'Register Agent' : 'Welcome Back',
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        fontSize: 32,
                        fontWeight: FontWeight.w800,
                        color: AppTheme.primaryColor,
                      ),
                ),
                const SizedBox(height: 8),
                Text(
                  _step == AuthStep.phone
                      ? 'Sign in or register to manage deliveries and track routes.'
                      : (_step == AuthStep.otp
                          ? 'Enter the 6-digit OTP code sent to your phone.'
                          : 'Please enter your details to complete registration as a delivery partner.'),
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
                const SizedBox(height: 40),

                // Phone Number Field (Common for all steps, read-only when step is otp or register)
                TextFormField(
                  controller: _phoneController,
                  enabled: _step == AuthStep.phone,
                  keyboardType: TextInputType.phone,
                  decoration: InputDecoration(
                    labelText: 'Phone Number',
                    prefixIcon: const Icon(Icons.phone_outlined),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: const BorderSide(color: AppTheme.primaryColor, width: 2),
                    ),
                  ),
                  validator: (value) {
                    if (value == null || value.isEmpty) {
                      return 'Please enter phone number';
                    }
                    if (value.length < 10) {
                      return 'Enter a valid phone number';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 20),

                if (_step == AuthStep.otp) ...[
                  // OTP Code Field
                  TextFormField(
                    controller: _otpController,
                    keyboardType: TextInputType.number,
                    maxLength: 6,
                    decoration: InputDecoration(
                      labelText: 'OTP Code',
                      prefixIcon: const Icon(Icons.lock_open_outlined),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: const BorderSide(color: AppTheme.primaryColor, width: 2),
                      ),
                    ),
                    validator: (value) {
                      if (value == null || value.isEmpty) {
                        return 'Please enter OTP code';
                      }
                      if (value.length < 6) {
                        return 'OTP must be 6 digits';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 20),
                ],

                if (_step == AuthStep.register) ...[
                  // Username Field
                  TextFormField(
                    controller: _usernameController,
                    decoration: InputDecoration(
                      labelText: 'Full Name',
                      prefixIcon: const Icon(Icons.person_outlined),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: const BorderSide(color: AppTheme.primaryColor, width: 2),
                      ),
                    ),
                    validator: (value) {
                      if (value == null || value.trim().isEmpty) {
                        return 'Please enter your name';
                      }
                      if (value.trim().length < 3) {
                        return 'Name must be at least 3 characters';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 20),

                  // Email Field
                  TextFormField(
                    controller: _emailController,
                    keyboardType: TextInputType.emailAddress,
                    decoration: InputDecoration(
                      labelText: 'Email Address (Optional)',
                      prefixIcon: const Icon(Icons.email_outlined),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: const BorderSide(color: AppTheme.primaryColor, width: 2),
                      ),
                    ),
                    validator: (value) {
                      if (value != null && value.isNotEmpty) {
                        final emailRegex = RegExp(r'^[^@]+@[^@]+\.[^@]+');
                        if (!emailRegex.hasMatch(value)) {
                          return 'Enter a valid email address';
                        }
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 20),
                ],

                // Submit Button
                SizedBox(
                  width: double.infinity,
                  height: 56,
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppTheme.primaryColor,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      elevation: 0,
                    ),
                    onPressed: buttonAction,
                    child: auth.loading
                        ? const CircularProgressIndicator(valueColor: AlwaysStoppedAnimation(Colors.white))
                        : Text(
                            buttonText,
                            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                          ),
                  ),
                ),

                const SizedBox(height: 24),

                // Option to go back / change phone number
                if (_step != AuthStep.phone)
                  Center(
                    child: TextButton(
                      onPressed: () {
                        setState(() {
                          _step = AuthStep.phone;
                          _otpController.clear();
                          _usernameController.clear();
                          _emailController.clear();
                          _formKey.currentState?.reset();
                        });
                      },
                      child: const Text(
                        'Change Phone Number',
                        style: TextStyle(
                          color: AppTheme.primaryColor,
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
    );
  }
}
