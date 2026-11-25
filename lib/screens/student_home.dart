// lib/screens/student_home.dart — the student portal in the app (replaces your old StudentHome)
//   Home (student-portal.php)  ·  Tasks (assignment.php)  ·  Alerts (push inbox)  ·  Me (profile + settings)
// Students use the same login as staff; login_screen.dart sends role "student" to '/student'.

import 'dart:async';
import 'package:flutter/material.dart';
import 'dart:ui' show ImageFilter;
import 'push_notification_service.dart';
import 'sm_ui.dart';
import 'student_api.dart';
import 'student_assignments_screen.dart';
import 'student_profile_screen.dart';

class StudentHome extends StatefulWidget {
  const StudentHome({super.key});

  @override
  State<StudentHome> createState() => _StudentHomeState();
}

class _StudentHomeState extends State<StudentHome> with WidgetsBindingObserver {
  String? _token;
  bool _booting = true;
  int _tab = 0;
  int _unread = 0;
  Timer? _timer;
  final ValueNotifier<int?> _openAssignment = ValueNotifier<int?>(null);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    PushNotificationService.instance.setOnOpen(_onPushOpen);
    _boot();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _timer?.cancel();
    _openAssignment.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _refreshUnread();
  }

  Future<void> _boot() async {
    await StudentCache.init();
    final t = await StudentApi.token();
    if (!mounted) return;
    if (t == null) {
      Navigator.of(context).pushReplacementNamed('/');
      return;
    }
    setState(() {
      _token = t;
      _booting = false;
    });
    // this phone receives push notifications (new assignments, results, …)
    PushNotificationService.instance.start(authToken: t, onOpen: _onPushOpen);
    _refreshUnread();
    _timer = Timer.periodic(const Duration(seconds: 60), (_) => _refreshUnread());
  }

  Future<void> _refreshUnread() async {
    final t = _token;
    if (t == null) return;
    final n = await PushNotificationService.instance.unreadCount(t);
    if (mounted && n != _unread) setState(() => _unread = n);
  }

  /// the student tapped a notification
  void _onPushOpen(Map<String, dynamic> data) {
    if (!mounted) return;
    final screen = '${data['screen'] ?? ''}';
    if (screen == 'assignments') {
      _openAssignment.value = int.tryParse('${data['assignment_id'] ?? ''}');
      setState(() => _tab = 1);
    } else {
      setState(() => _tab = 2);
    }
    _refreshUnread();
  }

  void _goto(int i) {
    setState(() => _tab = i);
    if (i == 2) Future.delayed(const Duration(seconds: 2), _refreshUnread);
  }

  @override
  Widget build(BuildContext context) {
    if (_booting || _token == null) {
      return const Scaffold(backgroundColor: SM.bg1, body: SmBackground(child: Center(child: SmLogoLoader(label: 'Loading your portal…'))));
    }
    final t = _token!;
    return PopScope(
      canPop: _tab == 0,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) setState(() => _tab = 0);
      },
      child: Scaffold(
        backgroundColor: SM.bg1,
        extendBody: true,
        bottomNavigationBar: _dock(),
        body: SmBackground(
          child: SafeArea(
            bottom: false,
            child: IndexedStack(index: _tab, children: [
              _DashboardTab(token: t, onGoto: _goto, onOpenAssignment: (id) {
                _openAssignment.value = id;
                _goto(1);
              }),
              StudentAssignmentsTab(token: t, openId: _openAssignment),
              _AlertsTab(token: t, onChanged: _refreshUnread, onOpenAssignment: (id) {
                _openAssignment.value = id;
                _goto(1);
              }),
              StudentProfileTab(token: t),
            ]),
          ),
        ),
      ),
    );
  }

  Widget _dock() {
    Widget item(int i, IconData icon, String label, {int badge = 0}) {
      final on = _tab == i;
      return Expanded(
        child: SmPress(
          onTap: () => _goto(i),
          child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
            Stack(clipBehavior: Clip.none, children: [
              AnimatedContainer(
                duration: const Duration(milliseconds: 220),
                padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 6),
                decoration: BoxDecoration(gradient: on ? SM.hot : null, borderRadius: BorderRadius.circular(16)),
                child: Icon(icon, size: 22, color: on ? Colors.white : SM.muted),
              ),
              if (badge > 0)
                Positioned(
                  right: 4,
                  top: -4,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                    decoration: BoxDecoration(color: SM.rose, borderRadius: BorderRadius.circular(10), border: Border.all(color: SM.sheet, width: 2)),
                    child: Text(badge > 9 ? '9+' : '$badge', style: const TextStyle(color: Colors.white, fontSize: 9.5, fontWeight: FontWeight.w800)),
                  ),
                ),
            ]),
            const SizedBox(height: 2),
            Text(label, style: TextStyle(color: on ? SM.text : SM.muted, fontSize: 10.5, fontWeight: FontWeight.w700)),
          ]),
        ),
      );
    }

    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(30),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 22, sigmaY: 22),
            child: Container(
              height: 68,
              padding: const EdgeInsets.symmetric(horizontal: 6),
              decoration: BoxDecoration(color: SM.a(SM.sheet, .84), borderRadius: BorderRadius.circular(30), border: Border.all(color: SM.glassLine), boxShadow: [BoxShadow(color: SM.a(Colors.black, .4), blurRadius: 24, offset: const Offset(0, 10))]),
              child: Row(children: [
                item(0, Icons.home_rounded, 'Home'),
                item(1, Icons.assignment_rounded, 'Tasks'),
                item(2, Icons.notifications_rounded, 'Alerts', badge: _unread),
                item(3, Icons.person_rounded, 'Me'),
              ]),
            ),
          ),
        ),
      ),
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════════
//  HOME  (student-portal.php)
// ═════════════════════════════════════════════════════════════════════════════
class _DashboardTab extends StatefulWidget {
  final String token;
  final void Function(int tab) onGoto;
  final void Function(int assignmentId) onOpenAssignment;
  const _DashboardTab({required this.token, required this.onGoto, required this.onOpenAssignment});

  @override
  State<_DashboardTab> createState() => _DashboardTabState();
}

class _DashboardTabState extends State<_DashboardTab> {
  bool _loading = true, _offline = false;
  String? _error;
  Map<String, dynamic> _d = {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final r = await StudentApi.call(widget.token, 'dashboard');
    if (!mounted) return;
    if (r['success'] == true) {
      final d = stMap(r['data']);
      await StudentCache.put('dashboard', d);
      setState(() {
        _d = d;
        _offline = false;
        _error = null;
        _loading = false;
      });
    } else if (StudentApi.isNet(r)) {
      final c = await StudentCache.get('dashboard');
      setState(() {
        if (c is Map) _d = Map<String, dynamic>.from(c);
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

  String get _greeting {
    final h = DateTime.now().hour;
    return h < 12 ? 'Good morning' : (h < 17 ? 'Good afternoon' : 'Good evening');
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: SmLogoLoader(size: 110, label: 'Loading…'));
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: SmGlass(
            radius: 28,
            padding: const EdgeInsets.all(24),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              const Icon(Icons.cloud_off_rounded, size: 50, color: SM.amber),
              const SizedBox(height: 12),
              Text(_error!, textAlign: TextAlign.center, style: const TextStyle(color: SM.text, height: 1.4)),
              const SizedBox(height: 18),
              SmButton(label: 'Try again', icon: Icons.refresh_rounded, onTap: () {
                setState(() => _loading = true);
                _load();
              }),
            ]),
          ),
        ),
      );
    }
    final u = stMap(_d['user']);
    final st = stMap(_d['stats']);
    final first = stStr(u['fullname']).trim().split(' ').first;
    final latest = stMaps(_d['latest_assignments']);
    final total = stInt(st['assignments']) ?? 0, pending = stInt(st['pending']) ?? 0, exams = stInt(st['upcoming_exams']) ?? 0;
    final maxV = [total, pending, exams, 1].reduce((a, b) => a > b ? a : b);
    final unread = stInt(_d['unread_notifications']) ?? 0;

    return RefreshIndicator(
      color: SM.orange,
      backgroundColor: SM.sheet,
      onRefresh: _load,
      child: ListView(padding: const EdgeInsets.fromLTRB(16, 10, 16, 130), children: [
        // header
        Row(children: [
          SmAvatar(url: stStr(u['image_url']), name: stStr(u['fullname']), size: 46),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(_greeting, style: const TextStyle(color: SM.muted, fontSize: 12.5, fontWeight: FontWeight.w600)),
              Text(first.isEmpty ? 'Student' : first, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: SM.text, fontSize: 20, fontWeight: FontWeight.w800, letterSpacing: -.4)),
            ]),
          ),
          SmIconBtn(icon: Icons.notifications_rounded, badge: unread, onTap: () => widget.onGoto(2)),
        ]),
        const SizedBox(height: 16),
        if (_offline)
          Container(
            margin: const EdgeInsets.only(bottom: 12),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(color: SM.a(SM.amber, .13), borderRadius: BorderRadius.circular(16), border: Border.all(color: SM.a(SM.amber, .45))),
            child: const Row(children: [Icon(Icons.wifi_off_rounded, color: SM.amber, size: 20), SizedBox(width: 10), Expanded(child: Text("You're offline — showing what was saved last time.", style: TextStyle(color: SM.text, fontSize: 13)))]),
          ),
        // hero
        Container(
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(30),
            gradient: const LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [Color(0xFF4767C0), Color(0xFF2A3F86), Color(0xFF1B2A5E)]),
            border: Border.all(color: SM.a(Colors.white, .18)),
            boxShadow: [BoxShadow(color: SM.a(SM.blue, .45), blurRadius: 30, offset: const Offset(0, 14))],
          ),
          child: Stack(children: [
            Positioned(right: -40, top: -50, child: Container(width: 180, height: 180, decoration: BoxDecoration(shape: BoxShape.circle, gradient: RadialGradient(colors: [SM.a(SM.orange, .5), SM.a(SM.orange, 0)])))),
            Padding(
              padding: const EdgeInsets.all(22),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('Welcome back,', style: TextStyle(color: SM.a(Colors.white, .8), fontSize: 14)),
                const SizedBox(height: 2),
                Text('${stStr(u['fullname'])} 👋', style: const TextStyle(color: Colors.white, fontSize: 23, fontWeight: FontWeight.w800, letterSpacing: -.5, height: 1.2)),
                const SizedBox(height: 12),
                Wrap(spacing: 8, runSpacing: 8, children: [
                  SmPill(stStr(u['class_name']), color: Colors.white, icon: Icons.class_rounded),
                  if (stStr(u['department_name']).isNotEmpty) SmPill(stStr(u['department_name']), color: SM.cyan, icon: Icons.apartment_rounded),
                  SmPill('ID ${stStr(u['idnumber'])}', color: SM.amber, icon: Icons.badge_rounded),
                ]),
                if (stStr(u['last_login']).isNotEmpty) Padding(padding: const EdgeInsets.only(top: 12), child: Text('Last login: ${stStr(u['last_login'])}', style: TextStyle(color: SM.a(Colors.white, .7), fontSize: 12))),
              ]),
            ),
          ]),
        ),
        const SizedBox(height: 16),
        // stats
        GridView.count(
          crossAxisCount: 2,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          mainAxisSpacing: 12,
          crossAxisSpacing: 12,
          childAspectRatio: 1.35,
          children: [
            _tile('Assignments', SmCount(total, style: _big), Icons.assignment_rounded, SM.brand, SM.blueLight, () => widget.onGoto(1)),
            _tile('Pending', SmCount(pending, style: _big), Icons.hourglass_top_rounded, SM.hot, SM.orange, () => widget.onGoto(1)),
            _tile('Upcoming exams', SmCount(exams, style: _big), Icons.menu_book_rounded, SM.violet2, SM.violet, null),
            _tile('Latest result', Text(stStr(st['latest_result']).isEmpty ? 'Not available yet' : stStr(st['latest_result']), maxLines: 2, style: const TextStyle(color: SM.text, fontSize: 14.5, fontWeight: FontWeight.w800, height: 1.25)), Icons.insights_rounded, SM.cyan2, SM.cyan, null),
          ],
        ),
        // activity
        const SmSectionTitle('Activity overview', sub: 'Your class'),
        SmGlass(
          radius: 26,
          padding: const EdgeInsets.all(18),
          child: Column(children: [
            _bar('Assignments', total, maxV, Icons.assignment_rounded, SM.blueLight),
            const SizedBox(height: 16),
            _bar('Pending', pending, maxV, Icons.hourglass_top_rounded, SM.orange),
            const SizedBox(height: 16),
            _bar('Exams', exams, maxV, Icons.menu_book_rounded, SM.violet),
          ]),
        ),
        // latest assignments
        SmSectionTitle('Latest assignments', trailing: TextButton(onPressed: () => widget.onGoto(1), child: const Text('View all', style: TextStyle(color: SM.orange, fontWeight: FontWeight.w700)))),
        if (latest.isEmpty)
          const SmGlass(radius: 24, padding: EdgeInsets.all(26), child: Center(child: Column(children: [Icon(Icons.assignment_late_outlined, size: 40, color: SM.faint), SizedBox(height: 8), Text('No assignments yet.', style: TextStyle(color: SM.muted))])))
        else
          for (final a in latest)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: SmGlass(
                radius: 22,
                padding: const EdgeInsets.all(14),
                onTap: () => widget.onOpenAssignment(stInt(a['id']) ?? 0),
                child: Row(children: [
                  Container(width: 44, height: 44, decoration: BoxDecoration(gradient: SM.brand, borderRadius: BorderRadius.circular(15)), child: const Icon(Icons.description_rounded, color: Colors.white, size: 22)),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(stStr(a['title']), style: const TextStyle(color: SM.text, fontWeight: FontWeight.w800, fontSize: 14.5, height: 1.25)),
                      const SizedBox(height: 3),
                      Text('${stStr(a['subject']).isEmpty ? 'General' : stStr(a['subject'])} · Due ${fmtDue(a['deadline'])}', style: const TextStyle(color: SM.muted, fontSize: 12.5)),
                    ]),
                  ),
                  const SizedBox(width: 8),
                  statusPill(stStr(a['status'])),
                ]),
              ),
            ),
      ]),
    );
  }

  TextStyle get _big => const TextStyle(color: SM.text, fontSize: 28, fontWeight: FontWeight.w800, letterSpacing: -.8);

  Widget _tile(String label, Widget value, IconData icon, Gradient g, Color glow, VoidCallback? onTap) => SmGlass(
        radius: 26,
        padding: const EdgeInsets.all(16),
        onTap: onTap,
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          Container(width: 40, height: 40, decoration: BoxDecoration(gradient: g, borderRadius: BorderRadius.circular(14), boxShadow: [BoxShadow(color: SM.a(glow, .45), blurRadius: 12, offset: const Offset(0, 5))]), child: Icon(icon, color: Colors.white, size: 21)),
          value,
          Text(label, style: const TextStyle(color: SM.muted, fontSize: 12.5, fontWeight: FontWeight.w700)),
        ]),
      );

  Widget _bar(String label, int v, int max, IconData icon, Color c) => Row(children: [
        Icon(icon, size: 17, color: c),
        const SizedBox(width: 8),
        SizedBox(width: 96, child: Text(label, style: const TextStyle(color: SM.text, fontSize: 13, fontWeight: FontWeight.w700))),
        Expanded(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: TweenAnimationBuilder<double>(
              key: ValueKey('$label$v'),
              tween: Tween(begin: 0, end: v / max),
              duration: const Duration(milliseconds: 1000),
              curve: Curves.easeOutCubic,
              builder: (_, x, __) => LinearProgressIndicator(value: x, minHeight: 12, backgroundColor: SM.a(Colors.white, .08), color: c),
            ),
          ),
        ),
        SizedBox(width: 34, child: Text('$v', textAlign: TextAlign.right, style: const TextStyle(color: SM.text, fontWeight: FontWeight.w800))),
      ]);
}

// ═════════════════════════════════════════════════════════════════════════════
//  ALERTS  (push inbox)
// ═════════════════════════════════════════════════════════════════════════════
class _AlertsTab extends StatefulWidget {
  final String token;
  final VoidCallback onChanged;
  final void Function(int assignmentId) onOpenAssignment;
  const _AlertsTab({required this.token, required this.onChanged, required this.onOpenAssignment});

  @override
  State<_AlertsTab> createState() => _AlertsTabState();
}

class _AlertsTabState extends State<_AlertsTab> {
  bool _loading = true;
  List<AppNotification> _items = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final list = await PushNotificationService.instance.fetchNotifications(widget.token);
    if (!mounted) return;
    setState(() {
      _items = list;
      _loading = false;
    });
  }

  Future<void> _markAll() async {
    await PushNotificationService.instance.markAllRead(widget.token);
    await _load();
    widget.onChanged();
  }

  IconData _icon(String type) => type == 'assignment_published' ? Icons.assignment_rounded : (type.startsWith('result') ? Icons.insights_rounded : Icons.notifications_rounded);
  Color _color(String type) => type == 'assignment_published' ? SM.blueLight : (type.startsWith('result') ? SM.green : SM.orange);

  String _ago(String s) {
    final d = DateTime.tryParse(s.replaceFirst(' ', 'T'));
    if (d == null) return '';
    final diff = DateTime.now().difference(d);
    if (diff.inMinutes < 1) return 'just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    if (diff.inDays < 7) return '${diff.inDays}d ago';
    return '${d.day}/${d.month}/${d.year}';
  }

  @override
  Widget build(BuildContext context) {
    final unread = _items.where((e) => !e.isRead).length;
    return Column(children: [
      SmTopBar(
        title: 'Alerts',
        subtitle: unread > 0 ? '$unread unread' : 'You are all caught up',
        actions: [if (unread > 0) SmIconBtn(icon: Icons.done_all_rounded, onTap: _markAll)],
      ),
      Expanded(
        child: _loading
            ? const Center(child: SmLogoLoader(size: 100))
            : RefreshIndicator(
                color: SM.orange,
                backgroundColor: SM.sheet,
                onRefresh: _load,
                child: _items.isEmpty
                    ? ListView(children: const [
                        SizedBox(height: 90),
                        Icon(Icons.notifications_none_rounded, size: 60, color: SM.faint),
                        SizedBox(height: 12),
                        Center(child: Text('No notifications yet', style: TextStyle(color: SM.text, fontSize: 17, fontWeight: FontWeight.w800))),
                        SizedBox(height: 6),
                        Padding(padding: EdgeInsets.symmetric(horizontal: 40), child: Text('New assignments and published results will appear here.', textAlign: TextAlign.center, style: TextStyle(color: SM.muted, height: 1.4))),
                      ])
                    : ListView.builder(
                        padding: const EdgeInsets.fromLTRB(16, 6, 16, 130),
                        itemCount: _items.length,
                        itemBuilder: (_, i) {
                          final n = _items[i];
                          final c = _color(n.type);
                          return Padding(
                            padding: const EdgeInsets.only(bottom: 10),
                            child: SmGlass(
                              radius: 22,
                              padding: const EdgeInsets.all(14),
                              color: n.isRead ? null : SM.a(c, .10),
                              border: n.isRead ? null : SM.a(c, .5),
                              onTap: () async {
                                if (n.type == 'assignment_published') {
                                  widget.onOpenAssignment(int.tryParse('${n.data['assignment_id'] ?? ''}') ?? 0);
                                }
                                if (!n.isRead) {
                                  await PushNotificationService.instance.markAllRead(widget.token);
                                  widget.onChanged();
                                }
                              },
                              child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                Container(width: 44, height: 44, decoration: BoxDecoration(color: SM.a(c, .18), borderRadius: BorderRadius.circular(15), border: Border.all(color: SM.a(c, .5))), child: Icon(_icon(n.type), color: c, size: 22)),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                    Row(children: [
                                      Expanded(child: Text(n.title, style: const TextStyle(color: SM.text, fontWeight: FontWeight.w800, fontSize: 14.5))),
                                      if (!n.isRead) Container(width: 9, height: 9, decoration: BoxDecoration(color: c, shape: BoxShape.circle)),
                                    ]),
                                    const SizedBox(height: 3),
                                    Text(n.body, style: const TextStyle(color: SM.muted, fontSize: 13, height: 1.4)),
                                    const SizedBox(height: 6),
                                    Text(_ago(n.createdAt), style: const TextStyle(color: SM.faint, fontSize: 11.5)),
                                  ]),
                                ),
                              ]),
                            ),
                          );
                        },
                      ),
              ),
      ),
    ]);
  }
}
