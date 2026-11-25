// lib/screens/student_profile_screen.dart — "Me" tab: profile + settings for students
//   photo, details, edit contact info, notifications on/off + test, fingerprint login, change password,
//   clear saved data, logout.

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../api/api_client.dart';
import '../services/app_flags.dart';
import '../services/auth_helper.dart';
import '../services/biometric_service.dart';
import 'push_notification_service.dart';
import 'sm_ui.dart';
import 'student_api.dart';

const String _appVersion = '1.0.0';

class StudentProfileTab extends StatefulWidget {
  final String token;
  const StudentProfileTab({super.key, required this.token});

  @override
  State<StudentProfileTab> createState() => _StudentProfileTabState();
}

class _StudentProfileTabState extends State<StudentProfileTab> {
  bool _loading = true, _offline = false, _uploading = false;
  String? _error;
  Map<String, dynamic> _p = {};

  bool _pushOn = true, _bioAvail = false, _bioOn = false;
  final _picker = ImagePicker();

  @override
  void initState() {
    super.initState();
    _load();
    _loadSettings();
  }

  Future<void> _load() async {
    final r = await StudentApi.call(widget.token, 'profile');
    if (!mounted) return;
    if (r['success'] == true) {
      final d = stMap(r['data']);
      await StudentCache.put('profile', d);
      setState(() {
        _p = d;
        _offline = false;
        _error = null;
        _loading = false;
      });
    } else if (StudentApi.isNet(r)) {
      final c = await StudentCache.get('profile');
      setState(() {
        if (c is Map) _p = Map<String, dynamic>.from(c);
        _offline = true;
        _error = c is Map ? null : 'No internet connection and nothing saved yet.';
        _loading = false;
      });
    } else {
      setState(() {
        _error = stStr(r['message']);
        _loading = false;
      });
    }
  }

  Future<void> _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    var avail = false, on = false;
    try {
      avail = await BiometricService.isAvailable();
      on = avail && await BiometricService.isEnrolled();
    } catch (_) {}
    if (mounted) {
      setState(() {
        _pushOn = prefs.getBool('push_enabled') ?? true;
        _bioAvail = avail;
        _bioOn = on;
      });
    }
  }

  // ───────────────────────────── photo ─────────────────────────────
  Future<void> _changePhoto() async {
    final src = await smSheet<ImageSource>(
      context,
      (ctx) => SmSheetFrame(
        title: 'Profile photo',
        subtitle: 'Choose where to get your photo',
        icon: Icons.photo_camera_rounded,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            SmButton(label: 'Take a photo', icon: Icons.photo_camera_rounded, onTap: () => Navigator.pop(ctx, ImageSource.camera)),
            const SizedBox(height: 10),
            SmButton(label: 'Choose from gallery', icon: Icons.photo_library_rounded, outline: true, onTap: () => Navigator.pop(ctx, ImageSource.gallery)),
          ]),
        ),
      ),
    );
    if (src == null) return;
    try {
      final x = await _picker.pickImage(source: src, imageQuality: 85, maxWidth: 1000, maxHeight: 1000);
      if (x == null) return;
      setState(() => _uploading = true);
      final n = x.name.toLowerCase();
      final mime = n.endsWith('.png') ? 'image/png' : (n.endsWith('.webp') ? 'image/webp' : 'image/jpeg');
      final r = await StudentApi.upload(widget.token, 'upload_photo', files: [StFile('photo', x.path, x.name.isEmpty ? 'photo.jpg' : x.name, mime)]);
      if (!mounted) return;
      setState(() => _uploading = false);
      if (r['success'] == true) {
        setState(() => _p['image_url'] = stStr(stMap(r['data'])['image_url']));
        await StudentCache.put('profile', _p);
        smToast(context, 'Photo updated.');
      } else {
        smToast(context, StudentApi.isNet(r) ? 'No internet connection.' : stStr(r['message']), kind: SmKind.error);
      }
    } catch (_) {
      if (mounted) {
        setState(() => _uploading = false);
        smToast(context, 'Could not use that photo.', kind: SmKind.error);
      }
    }
  }

  // ───────────────────────────── edit contact ─────────────────────────────
  Future<void> _editContact() async {
    final editable = (_p['editable'] is List ? _p['editable'] as List : []).map((e) => '$e').toList();
    final extra = stMap(_p['extra']);
    final ctrls = {for (final f in editable) f: TextEditingController(text: stStr(extra[f]))};
    final labels = {'phone': 'Phone number', 'email': 'Email address', 'address': 'Home address'};
    final icons = {'phone': Icons.phone_rounded, 'email': Icons.email_rounded, 'address': Icons.home_rounded};
    final ok = await smSheet<bool>(
      context,
      (ctx) => AnimatedPadding(
        duration: const Duration(milliseconds: 120),
        padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
        child: SmSheetFrameFit(
          title: 'Contact details',
          icon: Icons.edit_rounded,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 20),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              for (final f in editable) ...[
                TextField(
                  controller: ctrls[f],
                  keyboardType: f == 'phone' ? TextInputType.phone : (f == 'email' ? TextInputType.emailAddress : TextInputType.streetAddress),
                  style: const TextStyle(color: SM.text, fontWeight: FontWeight.w600),
                  cursorColor: SM.orange,
                  decoration: smInput(labels[f] ?? f, icon: icons[f], accent: SM.orange),
                ),
                const SizedBox(height: 12),
              ],
              const SizedBox(height: 4),
              SmButton(label: 'Save changes', icon: Icons.check_rounded, gradient: SM.hot, glow: SM.orange, onTap: () => Navigator.pop(ctx, true)),
            ]),
          ),
        ),
      ),
    );
    if (ok != true) return;
    final r = await StudentApi.call(widget.token, 'update_profile', form: {for (final e in ctrls.entries) e.key: e.value.text.trim()});
    for (final c in ctrls.values) {
      c.dispose();
    }
    if (!mounted) return;
    if (r['success'] == true) {
      smToast(context, 'Profile updated.');
      _load();
    } else {
      smToast(context, StudentApi.isNet(r) ? 'No internet connection.' : stStr(r['message']), kind: SmKind.error);
    }
  }

  // ───────────────────────────── settings actions ─────────────────────────────
  Future<void> _togglePush(bool v) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('push_enabled', v);
    setState(() => _pushOn = v);
    if (v) {
      await PushNotificationService.instance.start(authToken: widget.token);
      if (mounted) smToast(context, 'Notifications are on for this phone.');
    } else {
      await PushNotificationService.instance.unregister();
      if (mounted) smToast(context, 'Notifications are off for this phone.', kind: SmKind.warn);
    }
  }

  Future<void> _testPush() async {
    final msg = await PushNotificationService.instance.sendTest(widget.token);
    if (mounted) smToast(context, msg, kind: msg.toLowerCase().contains('sent') ? SmKind.success : SmKind.warn);
  }

  /// asks for the password in a dark sheet; returns null when cancelled
  Future<String?> _askPassword(String title, String text) async {
    final c = TextEditingController();
    var hide = true;
    final res = await smSheet<String>(
      context,
      (ctx) => StatefulBuilder(
        builder: (ctx, setS) => AnimatedPadding(
          duration: const Duration(milliseconds: 120),
          padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
          child: SmSheetFrameFit(
            title: title,
            icon: Icons.lock_rounded,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 20),
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                Text(text, style: const TextStyle(color: SM.muted, fontSize: 13.5, height: 1.4)),
                const SizedBox(height: 14),
                TextField(
                  controller: c,
                  obscureText: hide,
                  autofocus: true,
                  style: const TextStyle(color: SM.text, fontWeight: FontWeight.w600),
                  cursorColor: SM.orange,
                  decoration: smInput('Your password', icon: Icons.lock_outline_rounded, accent: SM.orange, suffix: IconButton(icon: Icon(hide ? Icons.visibility_off_outlined : Icons.visibility_outlined, color: SM.muted), onPressed: () => setS(() => hide = !hide))),
                ),
                const SizedBox(height: 16),
                SmButton(label: 'Continue', icon: Icons.check_rounded, onTap: () => Navigator.pop(ctx, c.text)),
              ]),
            ),
          ),
        ),
      ),
    );
    c.dispose();
    return (res == null || res.isEmpty) ? null : res;
  }

  Future<void> _toggleBio(bool v) async {
    if (!v) {
      await BiometricService.disable();
      setState(() => _bioOn = false);
      if (mounted) smToast(context, 'Fingerprint login is off.', kind: SmKind.warn);
      return;
    }
    final pass = await _askPassword('Turn on fingerprint', 'Enter your password once to confirm it is you. Next time you can sign in with your fingerprint.');
    if (pass == null) return;
    final last = await AppFlags.lastLogin();
    try {
      final r = await ApiClient.login(login: last.id, password: pass, deviceId: 'flutter_device');
      if (r['success'] != true) {
        if (mounted) smToast(context, 'That password is not correct.', kind: SmKind.error);
        return;
      }
      await BiometricService.enable(last.id, pass);
      if (mounted) {
        setState(() => _bioOn = true);
        smToast(context, 'Fingerprint login is on.');
      }
    } catch (_) {
      if (mounted) smToast(context, 'Could not turn on fingerprint. Check your internet.', kind: SmKind.error);
    }
  }

  Future<void> _changePassword() async {
    final cur = TextEditingController(), nw = TextEditingController(), rep = TextEditingController();
    String? err;
    var busy = false;
    var hide = true;
    await smSheet<void>(
      context,
      (ctx) => StatefulBuilder(
        builder: (ctx, setS) => AnimatedPadding(
          duration: const Duration(milliseconds: 120),
          padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
          child: SmSheetFrameFit(
            title: 'Change password',
            icon: Icons.key_rounded,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 20),
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                if (err != null)
                  Container(
                    margin: const EdgeInsets.only(bottom: 12),
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(color: SM.a(SM.rose, .13), borderRadius: BorderRadius.circular(14), border: Border.all(color: SM.a(SM.rose, .5))),
                    child: Row(children: [const Icon(Icons.error_outline_rounded, color: SM.rose, size: 19), const SizedBox(width: 8), Expanded(child: Text(err!, style: const TextStyle(color: SM.text, fontSize: 13)))]),
                  ),
                for (final f in [
                  [cur, 'Current password'],
                  [nw, 'New password (min. 6 characters)'],
                  [rep, 'Repeat new password'],
                ]) ...[
                  TextField(
                    controller: f[0] as TextEditingController,
                    obscureText: hide,
                    style: const TextStyle(color: SM.text, fontWeight: FontWeight.w600),
                    cursorColor: SM.orange,
                    decoration: smInput(f[1] as String, icon: Icons.lock_outline_rounded, accent: SM.orange, suffix: IconButton(icon: Icon(hide ? Icons.visibility_off_outlined : Icons.visibility_outlined, color: SM.muted), onPressed: () => setS(() => hide = !hide))),
                  ),
                  const SizedBox(height: 12),
                ],
                const SizedBox(height: 4),
                SmButton(
                  label: 'Update password',
                  icon: Icons.check_rounded,
                  gradient: SM.hot,
                  glow: SM.orange,
                  loading: busy,
                  onTap: () async {
                    if (cur.text.isEmpty || nw.text.isEmpty) return setS(() => err = 'Please fill in all the boxes.');
                    if (nw.text.length < 6) return setS(() => err = 'The new password must be at least 6 characters.');
                    if (nw.text != rep.text) return setS(() => err = 'The two new passwords do not match.');
                    setS(() {
                      busy = true;
                      err = null;
                    });
                    final r = await StudentApi.call(widget.token, 'change_password', form: {'current_password': cur.text, 'new_password': nw.text});
                    if (r['success'] == true) {
                      // a saved fingerprint login would still hold the OLD password
                      if (_bioOn) {
                        try {
                          await BiometricService.disable();
                        } catch (_) {}
                      }
                      if (ctx.mounted) Navigator.pop(ctx);
                      if (mounted) {
                        setState(() => _bioOn = false);
                        smToast(context, _bioAvail ? 'Password changed. Turn fingerprint login on again in Settings.' : 'Password changed successfully.');
                      }
                    } else {
                      setS(() {
                        busy = false;
                        err = StudentApi.isNet(r) ? 'No internet connection.' : stStr(r['message']);
                      });
                    }
                  },
                ),
              ]),
            ),
          ),
        ),
      ),
    );
    cur.dispose();
    nw.dispose();
    rep.dispose();
  }

  Future<void> _clearData() async {
    final ok = await smConfirm(context, 'Clear saved data?', 'Removes the copies of your assignments and profile kept on this phone, and any unsaved typed answers. Your account is not affected.', yes: 'Clear', destructive: true, icon: Icons.delete_sweep_rounded);
    if (ok != true) return;
    final n = await StudentCache.clearAll();
    if (mounted) smToast(context, n > 0 ? 'Saved data cleared.' : 'Nothing to clear.', kind: SmKind.info);
  }

  // ───────────────────────────── BUILD ─────────────────────────────
  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: SmLogoLoader(size: 100));
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: SmGlass(radius: 26, padding: const EdgeInsets.all(22), child: Column(mainAxisSize: MainAxisSize.min, children: [
            const Icon(Icons.cloud_off_rounded, size: 46, color: SM.amber),
            const SizedBox(height: 10),
            Text(_error!, textAlign: TextAlign.center, style: const TextStyle(color: SM.text)),
            const SizedBox(height: 16),
            SmButton(label: 'Try again', onTap: () { setState(() => _loading = true); _load(); }),
          ])),
        ),
      );
    }
    final extra = stMap(_p['extra']);
    final editable = (_p['editable'] is List ? _p['editable'] as List : []);
    final labels = {'admission_number': 'Admission number', 'phone': 'Phone', 'email': 'Email', 'address': 'Address', 'dob': 'Date of birth', 'date_of_birth': 'Date of birth'};
    return RefreshIndicator(
      color: SM.orange,
      backgroundColor: SM.sheet,
      onRefresh: _load,
      child: ListView(padding: const EdgeInsets.fromLTRB(16, 10, 16, 130), children: [
        const SmTopBar(title: 'My profile', subtitle: 'Details and settings'),
        if (_offline)
          Container(
            margin: const EdgeInsets.only(bottom: 12),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(color: SM.a(SM.amber, .13), borderRadius: BorderRadius.circular(16), border: Border.all(color: SM.a(SM.amber, .45))),
            child: const Row(children: [Icon(Icons.wifi_off_rounded, color: SM.amber, size: 20), SizedBox(width: 10), Expanded(child: Text('Offline — showing saved details.', style: TextStyle(color: SM.text, fontSize: 13)))]),
          ),
        // identity card
        SmGlass(
          radius: 30,
          padding: const EdgeInsets.all(20),
          gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [SM.a(SM.blueLight, .28), SM.a(SM.violet, .12)]),
          border: SM.a(SM.blueLight, .4),
          child: Column(children: [
            SmPress(
              onTap: _uploading ? null : _changePhoto,
              child: Stack(clipBehavior: Clip.none, children: [
                SmAvatar(url: stStr(_p['image_url']), name: stStr(_p['fullname']), size: 96),
                Positioned(
                  right: 0,
                  bottom: 0,
                  child: Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(gradient: SM.hot, shape: BoxShape.circle, border: Border.all(color: SM.bg1, width: 3)),
                    child: _uploading ? const Padding(padding: EdgeInsets.all(9), child: CircularProgressIndicator(strokeWidth: 2.4, color: Colors.white)) : const Icon(Icons.photo_camera_rounded, size: 17, color: Colors.white),
                  ),
                ),
              ]),
            ),
            const SizedBox(height: 14),
            Text(stStr(_p['fullname']), textAlign: TextAlign.center, style: const TextStyle(color: SM.text, fontSize: 21, fontWeight: FontWeight.w800, letterSpacing: -.4, height: 1.2)),
            const SizedBox(height: 4),
            Text('ID ${stStr(_p['idnumber'])}', style: const TextStyle(color: SM.muted, fontWeight: FontWeight.w700)),
            const SizedBox(height: 12),
            Wrap(alignment: WrapAlignment.center, spacing: 8, runSpacing: 8, children: [
              SmPill(stStr(_p['class_name']).isEmpty ? 'No class' : stStr(_p['class_name']), color: SM.violet, icon: Icons.class_rounded),
              if (stStr(_p['department_name']).isNotEmpty) SmPill(stStr(_p['department_name']), color: SM.cyan, icon: Icons.apartment_rounded),
              if (stStr(_p['gender']).isNotEmpty) SmPill(stStr(_p['gender']), color: SM.orange, icon: Icons.person_rounded),
            ]),
          ]),
        ),
        // details
        const SmSectionTitle('Details'),
        SmGlass(
          radius: 26,
          padding: const EdgeInsets.fromLTRB(18, 8, 18, 14),
          child: Column(children: [
            _row(Icons.badge_rounded, 'ID number', stStr(_p['idnumber'])),
            _row(Icons.class_rounded, 'Class', stStr(_p['class_name'])),
            _row(Icons.apartment_rounded, 'Department', stStr(_p['department_name']).isEmpty ? '—' : stStr(_p['department_name'])),
            _row(Icons.person_rounded, 'Gender', stStr(_p['gender']).isEmpty ? '—' : stStr(_p['gender'])),
            for (final e in extra.entries) _row(Icons.info_outline_rounded, labels[e.key] ?? e.key, stStr(e.value)),
            if (editable.isNotEmpty) ...[const SizedBox(height: 10), SmButton(label: 'Edit contact details', icon: Icons.edit_rounded, outline: true, height: 46, onTap: _editContact)],
          ]),
        ),
        // settings
        const SmSectionTitle('Settings'),
        SmGlass(
          radius: 26,
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Column(children: [
            _switch(Icons.notifications_active_rounded, SM.orange, 'Push notifications', 'New assignments and published results', _pushOn, _togglePush),
            if (_pushOn) _tap(Icons.send_rounded, SM.cyan, 'Send a test notification', 'Check that this phone receives alerts', _testPush),
            if (_bioAvail) _switch(Icons.fingerprint_rounded, SM.green, 'Fingerprint login', _bioOn ? 'On — sign in with your fingerprint' : 'Sign in without typing your password', _bioOn, _toggleBio),
            _tap(Icons.key_rounded, SM.violet, 'Change password', 'Use a strong password you do not share', _changePassword),
            _tap(Icons.delete_sweep_rounded, SM.amber, 'Clear saved data', 'Free space used by offline copies', _clearData),
          ]),
        ),
        const SizedBox(height: 14),
        SmGlass(
          radius: 22,
          padding: const EdgeInsets.all(16),
          child: Row(children: [
            Container(width: 40, height: 40, padding: const EdgeInsets.all(6), decoration: const BoxDecoration(color: Colors.white, shape: BoxShape.circle), child: ClipOval(child: Image.asset('assets/images/logo.png', fit: BoxFit.contain, errorBuilder: (_, __, ___) => const Icon(Icons.school_rounded, color: SM.blue)))),
            const SizedBox(width: 12),
            const Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text('SchoolsMirror', style: TextStyle(color: SM.text, fontWeight: FontWeight.w800)), Text('Version $_appVersion', style: TextStyle(color: SM.muted, fontSize: 12.5))])),
          ]),
        ),
        const SizedBox(height: 16),
        SmButton(label: 'Log out', icon: Icons.logout_rounded, gradient: SM.rose2, glow: SM.rose, onTap: _confirmLogout),
      ]),
    );
  }

  Future<void> _confirmLogout() async {
    final ok = await smConfirm(context, 'Log out?', 'You will need your password (or fingerprint) to sign in again.', yes: 'Log out', destructive: true, icon: Icons.logout_rounded);
    if (ok == true && mounted) await logoutUser(context);
  }

  Widget _row(IconData i, String label, String value) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 10),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Icon(i, size: 19, color: SM.orange),
          const SizedBox(width: 12),
          SizedBox(width: 96, child: Text(label, style: const TextStyle(color: SM.muted, fontSize: 13, fontWeight: FontWeight.w600))),
          Expanded(child: Text(value.isEmpty ? '—' : value, style: const TextStyle(color: SM.text, fontSize: 14, fontWeight: FontWeight.w700, height: 1.3))),
        ]),
      );

  Widget _switch(IconData i, Color c, String title, String sub, bool v, ValueChanged<bool> onChanged) => Padding(
        padding: const EdgeInsets.fromLTRB(14, 8, 8, 8),
        child: Row(children: [
          Container(width: 42, height: 42, decoration: BoxDecoration(color: SM.a(c, .16), borderRadius: BorderRadius.circular(14), border: Border.all(color: SM.a(c, .45))), child: Icon(i, color: c, size: 21)),
          const SizedBox(width: 12),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(title, style: const TextStyle(color: SM.text, fontWeight: FontWeight.w800, fontSize: 14.5)), Text(sub, style: const TextStyle(color: SM.muted, fontSize: 12.5, height: 1.3))])),
          Switch(value: v, onChanged: onChanged, activeColor: c),
        ]),
      );

  Widget _tap(IconData i, Color c, String title, String sub, VoidCallback onTap) => SmPress(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
          child: Row(children: [
            Container(width: 42, height: 42, decoration: BoxDecoration(color: SM.a(c, .16), borderRadius: BorderRadius.circular(14), border: Border.all(color: SM.a(c, .45))), child: Icon(i, color: c, size: 21)),
            const SizedBox(width: 12),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(title, style: const TextStyle(color: SM.text, fontWeight: FontWeight.w800, fontSize: 14.5)), Text(sub, style: const TextStyle(color: SM.muted, fontSize: 12.5, height: 1.3))])),
            const Icon(Icons.chevron_right_rounded, color: SM.faint),
          ]),
        ),
      );
}
