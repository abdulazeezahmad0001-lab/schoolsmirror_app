import 'dart:async';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../api/api_client.dart';
import '../services/biometric_service.dart';
import '../services/app_flags.dart';
import 'sm_ui.dart';
import 'push_notification_service.dart';

/// Login: glass card over the slideshow, "welcome back" mode for returning users,
/// fingerprint opt-in after the first password login, logo preloader while signing in.
class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> with SingleTickerProviderStateMixin {
  final _loginCtrl = TextEditingController();
  final _passCtrl = TextEditingController();
  final _passFocus = FocusNode();

  bool _loading = false;
  bool _bioLoading = false;
  bool _bioAvailable = false;
  bool _bioEnrolled = false;
  bool _obscure = true;
  bool _useOther = false; // "Not you?"
  bool _hasSession = false; // a saved session exists on this phone (offline use)
  bool _networkDown = false;
  String? _error;
  String? _bioStatus;
  LastLogin _last = const LastLogin('', '', '');

  late final AnimationController _enterCtrl;
  late final Animation<double> _fade;
  late final Animation<Offset> _slide;

  bool get _returning => _last.exists && !_useOther;

  @override
  void initState() {
    super.initState();
    _enterCtrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 700));
    _fade = CurvedAnimation(parent: _enterCtrl, curve: Curves.easeOutCubic);
    _slide = Tween<Offset>(begin: const Offset(0, .08), end: Offset.zero).animate(CurvedAnimation(parent: _enterCtrl, curve: Curves.easeOutCubic));
    _enterCtrl.forward();
    _boot();
  }

  Future<void> _boot() async {
    final last = await AppFlags.lastLogin();
    var hasTok = false;
    try {
      await ApiClient.loadToken();
      hasTok = (ApiClient.token ?? '').isNotEmpty;
    } catch (_) {}
    if (!mounted) return;
    setState(() {
      _last = last;
      _hasSession = hasTok;
      if (last.exists) _loginCtrl.text = last.id;
    });
    await _initBiometric();
  }

  Future<void> _initBiometric() async {
    try {
      final available = await BiometricService.isAvailable();
      final enrolled = available && await BiometricService.isEnrolled();
      if (!mounted) return;
      setState(() {
        _bioAvailable = available;
        _bioEnrolled = enrolled;
        if (enrolled) _bioStatus = 'Fingerprint is ready';
      });
      if (enrolled && _returning) {
        await Future.delayed(const Duration(milliseconds: 800));
        if (mounted && !_loading) _biometricLogin();
      }
    } catch (_) {
      // biometrics are optional (web / unsupported phones)
    }
  }

  // ───────────────────────────── password login ─────────────────────────────
  Future<void> _passwordLogin() async {
    final login = _returning ? _last.id : _loginCtrl.text.trim();
    final pass = _passCtrl.text;
    if (login.isEmpty || pass.isEmpty) {
      setState(() => _error = _returning ? 'Please enter your password' : 'Please enter your email/ID and password');
      return;
    }
    FocusScope.of(context).unfocus();
    setState(() {
      _loading = true;
      _error = null;
      _networkDown = false;
    });
    var navigated = false;
    try {
      final result = await ApiClient.login(login: login, password: pass, deviceId: 'flutter_device');
      if (!mounted) return;
      if (result['success'] == true) {
        navigated = await _afterLogin(result, login, pass, viaBio: false);
      } else {
        setState(() => _error = result['message']?.toString() ?? 'Login failed');
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _networkDown = true;
          _error = 'No connection. Check your internet and try again.';
        });
      }
    } finally {
      if (mounted && !navigated) setState(() => _loading = false);
    }
  }

  /// remember the user, offer fingerprint, start push, open the right home. Returns true when it navigated.
  Future<bool> _afterLogin(Map<String, dynamic> result, String login, String pass, {required bool viaBio}) async {
    final data = result['data'] is Map ? Map<String, dynamic>.from(result['data']) : <String, dynamic>{};
    final role = '${data['role'] ?? ''}';
    final name = '${data['fullname'] ?? data['name'] ?? data['username'] ?? ''}'.trim();
    await AppFlags.saveLastLogin(id: login, name: name.isNotEmpty ? name : (_last.id == login ? _last.name : ''), role: role);

    // new to fingerprint: ask once the password has been proven right
    if (!viaBio && _bioAvailable && !_bioEnrolled && mounted) {
      final yes = await smConfirm(context, 'Use fingerprint next time?',
          'Sign in faster with your fingerprint or face. Your login details are kept encrypted on this phone only.',
          yes: 'Enable', no: 'Not now', icon: Icons.fingerprint_rounded);
      if (yes == true) {
        try {
          await BiometricService.enable(login, pass);
          _bioEnrolled = true;
        } catch (_) {
          if (mounted) smToast(context, 'Could not turn on fingerprint on this phone.', kind: SmKind.warn);
        }
      }
    }
    _startPush();
    if (!mounted) return false;
    _routeByRole(role.isNotEmpty ? role : _last.role);
    return true;
  }

  /// every role registers its phone for push notifications right after login
  Future<void> _startPush() async {
    try {
      await ApiClient.loadToken();
      final t = ApiClient.token;
      if (t != null && t.isNotEmpty) PushNotificationService.instance.start(authToken: t);
    } catch (_) {}
  }

  // ───────────────────────────── fingerprint login ─────────────────────────────
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
        _bioStatus = 'Not recognised. Enter your password instead.';
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
    var navigated = false;
    try {
      final result = await ApiClient.login(login: creds.login, password: creds.password, deviceId: 'flutter_device', isBiometric: true);
      if (!mounted) return;
      if (result['success'] == true) {
        navigated = await _afterLogin(result, creds.login, creds.password, viaBio: true);
      } else {
        await BiometricService.disable();
        setState(() {
          _bioEnrolled = false;
          _bioStatus = null;
          _error = 'Fingerprint login expired. Please sign in with your password.';
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _networkDown = true;
          _bioStatus = 'No connection. Use offline mode or try again.';
        });
      }
    } finally {
      if (mounted && !navigated) setState(() => _bioLoading = false);
    }
  }

  void _routeByRole(String role) {
    // students -> student portal; portaladmin, subadmin and teacher share the admin home
    final r = role.toLowerCase().trim();
    if (r == 'student') {
      Navigator.of(context).pushReplacementNamed('/student');
    } else {
      Navigator.of(context).pushReplacementNamed('/admin');
    }
  }

  /// no internet but this phone still has a saved session: open the app and work offline
  void _continueOffline() {
    _routeByRole(_last.role);
  }

  Future<void> _notYou() async {
    await AppFlags.forgetLastLogin();
    if (!mounted) return;
    setState(() {
      _last = const LastLogin('', '', '');
      _useOther = false;
      _loginCtrl.clear();
      _passCtrl.clear();
      _error = null;
    });
  }

  @override
  void dispose() {
    _enterCtrl.dispose();
    _loginCtrl.dispose();
    _passCtrl.dispose();
    _passFocus.dispose();
    super.dispose();
  }

  // ───────────────────────────── UI ─────────────────────────────
  @override
  Widget build(BuildContext context) {
    SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(statusBarColor: Colors.transparent, statusBarIconBrightness: Brightness.light));
    return Scaffold(
      backgroundColor: SM.bg1,
      body: Stack(fit: StackFit.expand, children: [
        // slideshow background (unchanged)
        const _AnimatedLoginBackground(),
        Container(color: SM.a(SM.bg0, .52)),
        Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [SM.a(SM.bg0, .15), SM.a(SM.bg0, .55)]),
          ),
        ),
        SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(18),
              child: FadeTransition(
                opacity: _fade,
                child: SlideTransition(position: _slide, child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 410), child: _glassCard())),
              ),
            ),
          ),
        ),
        SmBusyOverlay(show: _loading || _bioLoading, label: _bioLoading ? 'Verifying…' : 'Signing you in…'),
      ]),
    );
  }

  Widget _glassCard() {
    return ClipRRect(
      borderRadius: BorderRadius.circular(32),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 26, sigmaY: 26),
        child: Container(
          padding: const EdgeInsets.fromLTRB(24, 28, 24, 22),
          decoration: BoxDecoration(
            gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [SM.a(Colors.white, .20), SM.a(Colors.white, .09)]),
            borderRadius: BorderRadius.circular(32),
            border: Border.all(color: SM.a(Colors.white, .32), width: 1.2),
            boxShadow: [BoxShadow(color: SM.a(Colors.black, .35), blurRadius: 44, offset: const Offset(0, 22))],
          ),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            _brand(),
            const SizedBox(height: 18),
            _returning ? _returningHeader() : _newHeader(),
            const SizedBox(height: 20),
            if (_error != null) ...[_errorBox(_error!), const SizedBox(height: 14)],
            if (_returning) _idChip() else ...[_label('Email or Student ID'), const SizedBox(height: 7), _idField(), const SizedBox(height: 14)],
            if (_returning) const SizedBox(height: 14),
            _label('Password'),
            const SizedBox(height: 7),
            _passField(),
            const SizedBox(height: 20),
            SmButton(label: _returning ? 'Continue' : 'Login', icon: Icons.arrow_forward_rounded, gradient: SM.hot, glow: SM.orange, height: 56, loading: _loading, onTap: _passwordLogin),
            if (_bioEnrolled) ...[const SizedBox(height: 18), _fingerprint()],
            if (_returning) ...[
              const SizedBox(height: 14),
              Center(child: TextButton(onPressed: _notYou, child: const Text('Not you? Use another account', style: TextStyle(color: SM.muted, fontWeight: FontWeight.w600)))),
            ],
            if (_hasSession && (_networkDown || _returning)) ...[
              const SizedBox(height: 2),
              Center(
                child: TextButton.icon(
                  onPressed: _continueOffline,
                  icon: Icon(Icons.wifi_off_rounded, size: 17, color: _networkDown ? SM.amber : SM.faint),
                  label: Text('Open offline', style: TextStyle(color: _networkDown ? SM.amber : SM.faint, fontWeight: FontWeight.w700)),
                ),
              ),
            ],
          ]),
        ),
      ),
    );
  }

  Widget _brand() => Center(
        child: Container(
          width: 84,
          height: 84,
          padding: const EdgeInsets.all(3.5),
          decoration: BoxDecoration(shape: BoxShape.circle, gradient: const SweepGradient(colors: [Color(0xFFF7941D), Color(0xFFFF4D8D), Color(0xFF6C8CE0), Color(0xFF22D3EE), Color(0xFFF7941D)]),
              boxShadow: [BoxShadow(color: SM.a(SM.orange, .35), blurRadius: 26)]),
          child: Container(
            padding: const EdgeInsets.all(9),
            decoration: const BoxDecoration(color: Colors.white, shape: BoxShape.circle),
            child: ClipOval(child: Image.asset('assets/images/logo.png', fit: BoxFit.contain, errorBuilder: (_, __, ___) => const Icon(Icons.school_rounded, color: SM.blue, size: 36))),
          ),
        ),
      );

  Widget _newHeader() => const Column(children: [
        Text('Welcome to SchoolsMirror', textAlign: TextAlign.center, style: TextStyle(color: Colors.white, fontSize: 23, fontWeight: FontWeight.w800, letterSpacing: -.4)),
        SizedBox(height: 6),
        Text('Sign in with your email or student ID', textAlign: TextAlign.center, style: TextStyle(color: Color(0xFFDDE6F7), fontSize: 14)),
      ]);

  Widget _returningHeader() => Column(children: [
        const Text('Welcome back 👋', textAlign: TextAlign.center, style: TextStyle(color: Colors.white, fontSize: 23, fontWeight: FontWeight.w800, letterSpacing: -.4)),
        if (_last.name.isNotEmpty) ...[
          const SizedBox(height: 4),
          Text(_last.name, textAlign: TextAlign.center, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w700)),
        ],
        const SizedBox(height: 6),
        const Text('Just enter your password to continue', textAlign: TextAlign.center, style: TextStyle(color: Color(0xFFDDE6F7), fontSize: 14)),
      ]);

  Widget _idChip() => Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(color: SM.a(Colors.white, .14), borderRadius: BorderRadius.circular(18), border: Border.all(color: SM.a(Colors.white, .28))),
        child: Row(children: [
          Container(width: 36, height: 36, decoration: BoxDecoration(gradient: SM.brand, borderRadius: BorderRadius.circular(12)), child: const Icon(Icons.badge_rounded, color: Colors.white, size: 19)),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('Your ID number', style: TextStyle(color: Color(0xFFDDE6F7), fontSize: 11.5)),
              Text(_last.id, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w800, letterSpacing: .4)),
            ]),
          ),
          const Icon(Icons.verified_rounded, color: SM.green, size: 22),
        ]),
      );

  Widget _label(String t) => Text(t, style: const TextStyle(color: Color(0xFFE8EEFB), fontSize: 12.5, fontWeight: FontWeight.w700, letterSpacing: .4));

  InputDecoration _dec(String hint, IconData icon, {Widget? suffix}) =>
      smInput(hint, icon: icon, suffix: suffix, accent: SM.orange).copyWith(fillColor: SM.a(Colors.white, .15));

  Widget _idField() => TextField(
        controller: _loginCtrl,
        keyboardType: TextInputType.emailAddress,
        textInputAction: TextInputAction.next,
        style: const TextStyle(color: Colors.white, fontSize: 15.5, fontWeight: FontWeight.w600),
        cursorColor: SM.orange,
        decoration: _dec('Enter email or student ID', Icons.person_outline_rounded),
        onSubmitted: (_) => _passFocus.requestFocus(),
      );

  Widget _passField() => TextField(
        controller: _passCtrl,
        focusNode: _passFocus,
        obscureText: _obscure,
        textInputAction: TextInputAction.done,
        style: const TextStyle(color: Colors.white, fontSize: 15.5, fontWeight: FontWeight.w600),
        cursorColor: SM.orange,
        decoration: _dec('Enter your password', Icons.lock_outline_rounded,
            suffix: IconButton(icon: Icon(_obscure ? Icons.visibility_off_outlined : Icons.visibility_outlined, color: SM.muted, size: 21), onPressed: () => setState(() => _obscure = !_obscure))),
        onSubmitted: (_) => _passwordLogin(),
      );

  Widget _errorBox(String msg) => Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(color: SM.a(SM.rose, .16), borderRadius: BorderRadius.circular(14), border: Border.all(color: SM.a(SM.rose, .55))),
        child: Row(children: [
          const Icon(Icons.error_outline_rounded, color: SM.rose, size: 20),
          const SizedBox(width: 10),
          Expanded(child: Text(msg, style: const TextStyle(color: Colors.white, fontSize: 13.5, fontWeight: FontWeight.w600))),
        ]),
      );

  Widget _fingerprint() => Column(children: [
        Row(children: [
          Expanded(child: Container(height: 1, color: SM.a(Colors.white, .22))),
          const Padding(padding: EdgeInsets.symmetric(horizontal: 12), child: Text('or', style: TextStyle(color: Color(0xFFDDE6F7), fontSize: 12.5))),
          Expanded(child: Container(height: 1, color: SM.a(Colors.white, .22))),
        ]),
        const SizedBox(height: 14),
        SmPress(
          onTap: _bioLoading ? null : _biometricLogin,
          child: Container(
            width: 70,
            height: 70,
            decoration: BoxDecoration(shape: BoxShape.circle, gradient: SM.brand, boxShadow: [BoxShadow(color: SM.a(SM.blueLight, .5), blurRadius: 24)], border: Border.all(color: SM.a(Colors.white, .35), width: 1.4)),
            child: const Icon(Icons.fingerprint_rounded, color: Colors.white, size: 38),
          ),
        ),
        const SizedBox(height: 8),
        Text(_bioStatus ?? 'Use fingerprint', textAlign: TextAlign.center, style: const TextStyle(color: Color(0xFFE8EEFB), fontSize: 12.5, fontWeight: FontWeight.w600)),
      ]);
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