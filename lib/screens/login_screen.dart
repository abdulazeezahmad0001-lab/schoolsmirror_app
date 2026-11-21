import 'dart:async';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../api/api_client.dart';
import '../services/biometric_service.dart';

/// Login screen styled to match auth_login.php (glass / dark SchoolsMirror design).
class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen>
    with SingleTickerProviderStateMixin {
  final _loginCtrl = TextEditingController();
  final _passCtrl = TextEditingController();

  bool _loading = false;
  bool _bioLoading = false;
  bool _bioAvailable = false;
  bool _bioEnrolled = false;
  bool _enableBioToggle = false;
  bool _obscurePassword = true;
  String? _error;
  String? _bioStatus;

  late final AnimationController _enterCtrl;
  late final Animation<double> _fade;
  late final Animation<Offset> _slide;

  // Brand colours matching auth_login.php
  static const _primary = Color(0xFF3A57A5);
  static const _primaryDark = Color(0xFF2A4480);
  static const _primaryLight = Color(0xFF5A7AC7);
  static const _bgDark = Color(0xFF0A1929);
  static const _danger = Color(0xFFFF6B6B);
  static const _success = Color(0xFF51CF66);

  @override
  void initState() {
    super.initState();
    _enterCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );
    _fade = CurvedAnimation(parent: _enterCtrl, curve: Curves.easeOutCubic);
    _slide = Tween<Offset>(
      begin: const Offset(0, 0.08),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _enterCtrl, curve: Curves.easeOutCubic));
    _enterCtrl.forward();
    _initBiometric();
  }

  Future<void> _initBiometric() async {
    try {
      final available = await BiometricService.isAvailable();
      final enrolled = available && await BiometricService.isEnrolled();
      if (!mounted) return;
      setState(() {
        _bioAvailable = available;
        _bioEnrolled = enrolled;
        _enableBioToggle = enrolled;
        if (enrolled) _bioStatus = 'Fingerprint is set up';
      });
      if (enrolled) {
        await Future.delayed(const Duration(milliseconds: 900));
        if (mounted) _biometricLogin();
      }
    } catch (_) {
      // Biometric optional on web / unsupported devices
    }
  }

  Future<void> _passwordLogin() async {
    final login = _loginCtrl.text.trim();
    final pass = _passCtrl.text;
    if (login.isEmpty || pass.isEmpty) {
      setState(() => _error = 'Please enter your email/ID and password');
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final result = await ApiClient.login(
        login: login,
        password: pass,
        deviceId: 'flutter_device',
      );
      if (!mounted) return;
      if (result['success'] == true) {
        if (_enableBioToggle && !_bioEnrolled && _bioAvailable) {
          try {
            await BiometricService.enable(login, pass);
          } catch (_) {}
        }
        _routeByRole(result['data']?['role']?.toString() ?? '');
      } else {
        setState(() => _error = result['message']?.toString() ?? 'Login failed');
      }
    } catch (e) {
      setState(() => _error = 'Network error: $e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _biometricLogin() async {
    if (!_bioEnrolled) return;
    setState(() {
      _bioLoading = true;
      _bioStatus = 'Verifying fingerprint…';
      _error = null;
    });
    final ok = await BiometricService.authenticate();
    if (!ok) {
      if (!mounted) return;
      setState(() {
        _bioLoading = false;
        _bioStatus = 'Fingerprint not recognised. Use password below.';
      });
      return;
    }
    final creds = await BiometricService.retrieveCredentials();
    if (creds == null) {
      if (!mounted) return;
      setState(() {
        _bioLoading = false;
        _bioEnrolled = false;
        _bioStatus = null;
      });
      return;
    }
    try {
      final result = await ApiClient.login(
        login: creds.login,
        password: creds.password,
        deviceId: 'flutter_device',
        isBiometric: true,
      );
      if (!mounted) return;
      if (result['success'] == true) {
        _routeByRole(result['data']?['role']?.toString() ?? '');
      } else {
        await BiometricService.disable();
        setState(() {
          _bioLoading = false;
          _bioEnrolled = false;
          _enableBioToggle = false;
          _bioStatus = null;
          _error = 'Fingerprint login failed. Please sign in with password.';
        });
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _bioLoading = false;
        _bioStatus = 'Network error. Use password below.';
      });
    }
  }

  void _routeByRole(String role) {
    final r = role.toLowerCase();
    if (r == 'student' || r == 'teacher') {
      Navigator.of(context).pushReplacementNamed('/student');
    } else {
      Navigator.of(context).pushReplacementNamed('/admin');
    }
  }

  @override
  void dispose() {
    _enterCtrl.dispose();
    _loginCtrl.dispose();
    _passCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.light,
    ));

    return Scaffold(
      body: Stack(
        fit: StackFit.expand,
        children: [
          // Auto-changing Background
          const _AnimatedLoginBackground(),
          
          // Dark overlay + radial glows (matches PHP)
          Container(
            decoration: const BoxDecoration(
              gradient: RadialGradient(
                center: Alignment(-0.6, 0),
                radius: 1.1,
                colors: [
                  Color(0x263A57A5),
                  Colors.transparent,
                ],
              ),
            ),
          ),
          Container(
            decoration: const BoxDecoration(
              gradient: RadialGradient(
                center: Alignment(0.7, 0.2),
                radius: 1.0,
                colors: [
                  Color(0x1A5A7AC7),
                  Colors.transparent,
                ],
              ),
            ),
          ),
          // Heavy dark overlay to make text readable over images
          Container(color: _bgDark.withOpacity(0.82)),
          
          SafeArea(
            child: Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(16),
                child: FadeTransition(
                  opacity: _fade,
                  child: SlideTransition(
                    position: _slide,
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 380),
                      child: _glassCard(),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _glassCard() {
    return ClipRRect(
      borderRadius: BorderRadius.circular(20),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
        child: Container(
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.07),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: Colors.white.withOpacity(0.12)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.4),
                blurRadius: 40,
                offset: const Offset(0, 20),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _header(),
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (_bioEnrolled) ...[
                      _fingerprintSection(),
                      const SizedBox(height: 12),
                      _orDivider(),
                      const SizedBox(height: 16),
                    ],
                    if (_error != null) ...[
                      _errorBox(_error!),
                      const SizedBox(height: 14),
                    ],
                    _label('Email or Student ID'),
                    const SizedBox(height: 6),
                    _field(
                      controller: _loginCtrl,
                      hint: 'Enter email or student ID',
                      icon: Icons.person_outline,
                      keyboard: TextInputType.emailAddress,
                    ),
                    const SizedBox(height: 14),
                    _label('Password'),
                    const SizedBox(height: 6),
                    _field(
                      controller: _passCtrl,
                      hint: 'Enter your password',
                      icon: Icons.lock_outline,
                      obscure: _obscurePassword,
                      suffix: IconButton(
                        icon: Icon(
                          _obscurePassword
                              ? Icons.visibility_off_outlined
                              : Icons.visibility_outlined,
                          color: Colors.white.withOpacity(0.4),
                          size: 20,
                        ),
                        onPressed: () =>
                            setState(() => _obscurePassword = !_obscurePassword),
                      ),
                    ),
                    if (_bioAvailable && !_bioEnrolled) ...[
                      const SizedBox(height: 8),
                      SwitchListTile.adaptive(
                        contentPadding: EdgeInsets.zero,
                        value: _enableBioToggle,
                        onChanged: (v) => setState(() => _enableBioToggle = v),
                        activeColor: _primary,
                        secondary: Icon(Icons.fingerprint,
                            color: Colors.white.withOpacity(0.55)),
                        title: Text(
                          'Enable fingerprint login',
                          style: TextStyle(
                            color: Colors.white.withOpacity(0.7),
                            fontSize: 13,
                          ),
                        ),
                      ),
                    ],
                    const SizedBox(height: 18),
                    SizedBox(
                      height: 52,
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(12),
                          gradient: const LinearGradient(
                            colors: [_primary, _primaryDark],
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: _primary.withOpacity(0.35),
                              blurRadius: 16,
                              offset: const Offset(0, 8),
                            ),
                          ],
                        ),
                        child: Material(
                          color: Colors.transparent,
                          child: InkWell(
                            borderRadius: BorderRadius.circular(12),
                            onTap: _loading ? null : _passwordLogin,
                            child: Center(
                              child: _loading
                                  ? const SizedBox(
                                      width: 22,
                                      height: 22,
                                      child: CircularProgressIndicator(
                                        color: Colors.white,
                                        strokeWidth: 2.5,
                                      ),
                                    )
                                  : const Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Icon(Icons.login,
                                            color: Colors.white, size: 18),
                                        SizedBox(width: 8),
                                        Text(
                                          'Sign In',
                                          style: TextStyle(
                                            color: Colors.white,
                                            fontSize: 16,
                                            fontWeight: FontWeight.w700,
                                          ),
                                        ),
                                      ],
                                    ),
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    TextButton(
                      onPressed: () {
                        // Hook forgot-password route when ready
                      },
                      child: Text(
                        'Forgot Password?',
                        style: TextStyle(
                          color: Colors.white.withOpacity(0.55),
                          fontSize: 12,
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Divider(color: Colors.white.withOpacity(0.08)),
                    const SizedBox(height: 8),
                    Text(
                      'SchoolsMirror · Secure Login Portal',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: Colors.white.withOpacity(0.35),
                        fontSize: 11,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _header() {
    return Container(
      padding: const EdgeInsets.fromLTRB(24, 28, 24, 16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            _primary.withOpacity(0.15),
            Colors.transparent,
          ],
        ),
      ),
      child: Column(
        children: [
          Container(
            width: 64,
            height: 64,
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.95),
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: _primary.withOpacity(0.3),
                  blurRadius: 20,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            child: ClipOval(
              child: Image.asset(
                'assets/images/logo.png',
                fit: BoxFit.contain,
                errorBuilder: (_, __, ___) => const Icon(
                  Icons.school,
                  size: 32,
                  color: _primary,
                ),
              ),
            ),
          ),
          const SizedBox(height: 12),
          const Text(
            'SchoolsMirror',
            style: TextStyle(
              color: Colors.white,
              fontSize: 22,
              fontWeight: FontWeight.w800,
              letterSpacing: -0.5,
            ),
          ),
          Text(
            'Secure Login Portal',
            style: TextStyle(
              color: Colors.white.withOpacity(0.7),
              fontSize: 12,
            ),
          ),
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
            decoration: BoxDecoration(
              color: _primary.withOpacity(0.2),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: _primary.withOpacity(0.3)),
            ),
            child: const Text(
              'ADMIN · TEACHER · STUDENT',
              style: TextStyle(
                color: Colors.white70,
                fontSize: 10,
                fontWeight: FontWeight.w600,
                letterSpacing: 0.6,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _fingerprintSection() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.03),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withOpacity(0.06)),
      ),
      child: Column(
        children: [
          GestureDetector(
            onTap: _bioLoading ? null : _biometricLogin,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 250),
              width: 72,
              height: 72,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.white.withOpacity(0.06),
                border: Border.all(
                  color: _bioLoading
                      ? _primaryLight.withOpacity(0.5)
                      : Colors.white.withOpacity(0.12),
                  width: 2,
                ),
              ),
              child: _bioLoading
                  ? const Padding(
                      padding: EdgeInsets.all(20),
                      child: CircularProgressIndicator(
                        color: Colors.white,
                        strokeWidth: 2.5,
                      ),
                    )
                  : const Icon(Icons.fingerprint, size: 36, color: Colors.white),
            ),
          ),
          const SizedBox(height: 10),
          const Text(
            'Sign in with fingerprint',
            style: TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w600,
              fontSize: 13,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            _bioStatus ?? 'Tap the icon above',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: (_bioStatus ?? '').contains('not')
                  ? _danger
                  : Colors.white.withOpacity(0.55),
              fontSize: 11,
            ),
          ),
        ],
      ),
    );
  }

  Widget _orDivider() {
    return Row(
      children: [
        Expanded(child: Divider(color: Colors.white.withOpacity(0.08))),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Text(
            'OR PASSWORD',
            style: TextStyle(
              color: Colors.white.withOpacity(0.35),
              fontSize: 10,
              letterSpacing: 1.2,
            ),
          ),
        ),
        Expanded(child: Divider(color: Colors.white.withOpacity(0.08))),
      ],
    );
  }

  Widget _errorBox(String msg) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: _danger.withOpacity(0.12),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: _danger.withOpacity(0.25)),
      ),
      child: Row(
        children: [
          const Icon(Icons.error_outline, color: _danger, size: 18),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              msg,
              style: const TextStyle(color: Color(0xFFFFB3B3), fontSize: 12),
            ),
          ),
        ],
      ),
    );
  }

  Widget _label(String text) {
    return Text(
      text,
      style: TextStyle(
        color: Colors.white.withOpacity(0.7),
        fontWeight: FontWeight.w600,
        fontSize: 12,
      ),
    );
  }

  Widget _field({
    required TextEditingController controller,
    required String hint,
    required IconData icon,
    bool obscure = false,
    Widget? suffix,
    TextInputType? keyboard,
  }) {
    return TextField(
      controller: controller,
      obscureText: obscure,
      keyboardType: keyboard,
      style: const TextStyle(color: Colors.white, fontSize: 14),
      cursorColor: _primaryLight,
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: TextStyle(color: Colors.white.withOpacity(0.35), fontSize: 13),
        prefixIcon: Icon(icon, color: Colors.white.withOpacity(0.4), size: 20),
        suffixIcon: suffix,
        filled: true,
        fillColor: Colors.white.withOpacity(0.05),
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: Colors.white.withOpacity(0.08), width: 1.5),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: _primaryLight, width: 1.5),
        ),
      ),
    );
  }
}

/// Auto-changing background with 2 images.
class _AnimatedLoginBackground extends StatefulWidget {
  const _AnimatedLoginBackground();

  @override
  State<_AnimatedLoginBackground> createState() =>
      _AnimatedLoginBackgroundState();
}

class _AnimatedLoginBackgroundState extends State<_AnimatedLoginBackground> {
  final PageController _pageController = PageController();
  int _currentPage = 0;
  Timer? _timer;

  // The two images from your folder
  final List<String> _images = [
    'assets/images/login_bg.jpg',
    'assets/images/image.jpg',
  ];

  @override
  void initState() {
    super.initState();
    _startSlideshow();
  }

  void _startSlideshow() {
    _timer = Timer.periodic(const Duration(seconds: 6), (Timer timer) {
      if (_currentPage < _images.length - 1) {
        _currentPage++;
      } else {
        _currentPage = 0;
      }

      if (_pageController.hasClients) {
        _pageController.animateToPage(
          _currentPage,
          duration: const Duration(milliseconds: 1500),
          curve: Curves.easeInOut,
        );
      }
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    _pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return PageView.builder(
      controller: _pageController,
      physics: const NeverScrollableScrollPhysics(), // Prevents swiping manually
      itemCount: _images.length,
      itemBuilder: (context, index) {
        return AnimatedScale(
          scale: 1.05, // Slight zoom prevents blank edges during slide
          duration: const Duration(seconds: 6),
          child: Image.asset(
            _images[index],
            fit: BoxFit.cover,
            errorBuilder: (_, __, ___) => Container(
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    Color(0xFF0A1929),
                    Color(0xFF132F4C),
                    Color(0xFF0A1929),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}