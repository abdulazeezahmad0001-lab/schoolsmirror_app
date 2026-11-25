import 'dart:convert';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../api/api_client.dart';

// ════════════════════════════════════════════════════════════════════════════
//  SCREEN IMPORTS
// ════════════════════════════════════════════════════════════════════════════
import 'flutter_users_screen.dart'; // Manage Users (add student/teacher/subadmin + list)
import 'flutter_admin_module_screen.dart';
import 'flutter_add_exam_screen.dart';
import 'flutter_result_upload_screen.dart'; // Result Upload (students -> session/term -> scores, works offline)
import 'flutter_assign_subject_screen.dart';
import 'flutter_add_homework_screen.dart';
import 'flutter_cumulative_results_screen.dart';
import 'flutter_promote_students_screen.dart';
import 'flutter_revert_promotions_screen.dart';
import 'flutter_promotion_history_screen.dart';
import 'flutter_result_template_screen.dart'; // Result Template (school details)
import 'flutter_teacher_in_out_screen.dart'; // Teacher In/Out (face + GPS)
import 'flutter_all_attendance_screen.dart'; // Staff Attendance (admin view)
import 'flutter_upload_signature_screen.dart'; // Upload Signature
import 'flutter_position_of_student_screen.dart'; // Class Ranking (student positions)
// import 'flutter_class_management_screen.dart';
import 'dart:ui' show ImageFilter;
import 'sm_ui.dart';
import 'push_notification_service.dart';
import 'flutter_results_overview_screen.dart'; // Result Overview / finalization (+ push)

// ═════════════════════════════════════════════════════════════════════
//  THEME  (dark "Aurora Glass" — see sm_ui.dart)
//  The old names are kept so the chart painters and nav groups keep working.
// ═════════════════════════════════════════════════════════════════════
const _kPrimary = SM.blueLight;
const _kViolet = SM.violet;
const _kDark = SM.text; // main text colour (light on dark)
const _kBg = SM.bg1;
const _kMuted = SM.muted;
const _kBorder = Color(0x1FFFFFFF);
const _kGreen = SM.green;
const _kAmber = SM.amber;
const _kRose = SM.rose;
const _kCyan = SM.cyan;

const _chartPalette = [_kPrimary, _kViolet, _kGreen, _kAmber, _kRose, _kCyan];

// ════════════════════════════════════════════════════════════════════════════
//  ROLES + NAVIGATION REGISTRY
// ════════════════════════════════════════════════════════════════════════════
const _rAdmin = 'portaladmin';
const _rSub = 'subadmin';
const _rTeacher = 'teacher';
const Set<String> _adminRoles = {_rAdmin, _rSub};
const Set<String> _allRoles = {_rAdmin, _rSub, _rTeacher};

const Set<String> _liveRoutes = {
  '/admin/manage-users',
  '/admin/add-class',
};

class NavLeaf {
  final String title;
  final IconData icon;
  final String route;
  final Set<String> roles;
  final bool isNew;
  const NavLeaf(this.title, this.icon, this.route,
      {this.roles = const {}, this.isNew = false});
}

class NavGroup {
  final String title;
  final IconData icon;
  final Color color;
  final Set<String> roles;
  final List<NavLeaf> leaves;
  final bool flat;
  const NavGroup(this.title, this.icon, this.color,
      {required this.leaves, this.roles = _allRoles, this.flat = false});

  List<NavLeaf> leavesFor(String role) => leaves
      .where((l) => l.roles.isEmpty || l.roles.contains(role))
      .toList();

  bool visibleFor(String role) =>
      roles.contains(role) && leavesFor(role).isNotEmpty;
}

const List<NavGroup> _navGroups = [
  NavGroup('User Management', Icons.manage_accounts, _kPrimary,
      roles: _adminRoles,
      leaves: [
        NavLeaf('Manage Users', Icons.manage_accounts, '/admin/manage-users'),
      ]),
  NavGroup('School Management', Icons.apartment, _kViolet,
      roles: _adminRoles,
      leaves: [
        NavLeaf('Add Class', Icons.class_, '/admin/add-class'),
        NavLeaf('Add Department', Icons.apartment, '/admin/add-department'),
        NavLeaf('Add Subject', Icons.menu_book, '/admin/add-subject', isNew: true),
        NavLeaf('Add Session', Icons.event, '/admin/add-session', roles: {_rAdmin}),
        NavLeaf('Add Term', Icons.date_range, '/admin/add-term', roles: {_rAdmin}),
        NavLeaf('Next Term', Icons.skip_next, '/admin/next-term', roles: {_rAdmin}),
        NavLeaf('Add Notice', Icons.campaign, '/admin/add-notice'),
        NavLeaf('Add Homework', Icons.assignment, '/admin/homework'),
        NavLeaf('Add Grade', Icons.grade, '/admin/grading'),
        NavLeaf('Trait Meaning', Icons.psychology, '/admin/psychomotor', isNew: true),
      ]),
  NavGroup('Exam Management', Icons.quiz, _kAmber, leaves: [
    NavLeaf('Add Exam', Icons.add_task, '/admin/add-exam'),
    NavLeaf('Assign Subject', Icons.rule, '/admin/assign-subject',
        roles: _adminRoles),
  ]),
  NavGroup('CBT Management', Icons.computer, _kCyan,
      roles: _adminRoles,
      leaves: [
        NavLeaf('Cumulative Results', Icons.poll, '/admin/cumulative-results'),
      ]),
  NavGroup('Academic Promotion', Icons.upgrade, _kGreen,
      roles: _adminRoles,
      leaves: [
        NavLeaf('Promote Students', Icons.trending_up, '/admin/promote-students'),
        NavLeaf('Revert Promotions', Icons.undo, '/admin/revert-promotions'),
        NavLeaf('Promotion History', Icons.history, '/admin/promotion-history'),
      ]),
  NavGroup('My Class', Icons.assignment_ind, _kPrimary,
      roles: {_rTeacher},
      leaves: [
        NavLeaf('Homework', Icons.assignment, '/admin/homework'),
        NavLeaf('Student Attendance', Icons.how_to_reg, '/admin/student-attendance'),
      ]),
  NavGroup('Syllabus', Icons.menu_book, _kViolet, leaves: [
    NavLeaf('Add Syllabus', Icons.library_add, '/admin/syllabus'),
    NavLeaf('Timetable', Icons.schedule, '/admin/timetable'),
    NavLeaf('Library', Icons.local_library, '/admin/library'),
  ]),
  NavGroup('Teacher Salary', Icons.request_quote, _kGreen,
      roles: {_rTeacher},
      leaves: [
        NavLeaf('Confirm Salary', Icons.check_circle, '/admin/teacher-salary'),
      ]),
  NavGroup('Attendance', Icons.access_time, _kAmber,
      roles: {_rTeacher},
      leaves: [
        NavLeaf('Teacher In/Out', Icons.login, '/admin/teacher-in-out'),
      ]),
  NavGroup('Attendance', Icons.fact_check, _kAmber,
      roles: _adminRoles,
      leaves: [
        NavLeaf('Staff Attendance', Icons.groups, '/admin/staff-attendance'),
      ]),
  NavGroup('Video Tutorial', Icons.ondemand_video, _kRose, leaves: [
    NavLeaf('Add Tutorial', Icons.play_circle, '/admin/tutorials'),
  ]),
  NavGroup('Payment Management', Icons.payments, _kGreen,
      roles: _adminRoles,
      leaves: [
        NavLeaf('Student Fees', Icons.receipt_long, '/admin/student-fees'),
        NavLeaf('Teacher Salary', Icons.account_balance_wallet, '/admin/teacher-payments'),
      ]),
  NavGroup('Result Management', Icons.bar_chart, _kPrimary, leaves: [
    NavLeaf('Select Template', Icons.palette, '/admin/select-template',
        roles: {_rAdmin}),
    NavLeaf('Result Template', Icons.description, '/admin/result-template',
        roles: {_rAdmin}),
    NavLeaf('Result Upload', Icons.upload_file, '/admin/result-upload'),
    NavLeaf('Upload Signature', Icons.edit_note, '/admin/upload-signature',
        roles: _adminRoles),
    NavLeaf('Class Ranking', Icons.emoji_events, '/admin/class-ranking',
        roles: _adminRoles),
    NavLeaf('Result Overview', Icons.fact_check_rounded, '/admin/published-results',
        roles: _adminRoles, isNew: true),
    NavLeaf('Download Result', Icons.download, '/admin/download-results',
        roles: _adminRoles),
    NavLeaf('Student Attendance', Icons.how_to_reg, '/admin/fill-attendance',
        roles: _adminRoles),
    NavLeaf('Generate PIN', Icons.key, '/admin/generate-pin', roles: {_rAdmin}),
    NavLeaf('Color Settings', Icons.color_lens, '/admin/color-settings',
        roles: {_rAdmin}),
  ]),
  NavGroup('Vote Portal', Icons.how_to_vote, _kViolet,
      roles: {_rAdmin},
      flat: true,
      leaves: [
        NavLeaf('Vote Portal', Icons.how_to_vote, '/admin/vote', isNew: true),
      ]),
  NavGroup('Settings', Icons.settings, _kMuted, roles: {_rAdmin}, leaves: [
    NavLeaf('System Settings', Icons.build, '/admin/settings'),
    NavLeaf('Profile', Icons.person, '/admin/profile'),
  ]),
];

// ════════════════════════════════════════════════════════════════════════════
//  HELPERS
// ════════════════════════════════════════════════════════════════════════════
double _num(dynamic v) =>
    v is num ? v.toDouble() : (double.tryParse('${v ?? ''}') ?? 0);

List<dynamic> _list(dynamic v) => v is List ? v : const [];

String _money(double n) => n
    .toStringAsFixed(2)
    .replaceAllMapped(RegExp(r'(\d)(?=(\d{3})+(?!\d))'), (m) => '${m[1]},');

String _compact(double v) {
  if (v >= 1e9) return '${(v / 1e9).toStringAsFixed(1)}B';
  if (v >= 1e6) return '${(v / 1e6).toStringAsFixed(1)}M';
  if (v >= 1e3) return '${(v / 1e3).toStringAsFixed(1)}K';
  return v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toStringAsFixed(1);
}

// ════════════════════════════════════════════════════════════════════════════
//  SCREEN
// ════════════════════════════════════════════════════════════════════════════
class AdminHome extends StatefulWidget {
  const AdminHome({super.key});

  @override
  State<AdminHome> createState() => _AdminHomeState();
}

class _AdminHomeState extends State<AdminHome> {
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();
  final TextEditingController _search = TextEditingController();
  final ScrollController _scroll = ScrollController();

  bool _loading = true;
  bool _offlineData = false;
  String? _error;
  Map<String, dynamic>? _data;
  String? _sessionToken; // cached after successful login/load

  int _payType = 0;
  int _resType = 0;
  int _seed = 0;
  String _query = '';

  @override
  void initState() {
    super.initState();
    PushNotificationService.instance.setOnOpen(_onPushOpen);
    _load();
  }

  @override
  void dispose() {
    _search.dispose();
    _scroll.dispose();
    super.dispose();
  }

  Future<Map<String, dynamic>?> _readCache() async {
    try {
      final p = await SharedPreferences.getInstance();
      final s = p.getString('dash_cache_v1');
      if (s == null) return null;
      final d = jsonDecode(s);
      return d is Map ? Map<String, dynamic>.from(d) : null;
    } catch (_) {
      return null;
    }
  }

  Future<void> _load() async {
    if (_data == null) setState(() => _loading = true);
    setState(() => _error = null);
    try {
      await ApiClient.loadToken();
      final token = ApiClient.token;
      if (token == null || token.isEmpty) {
        throw Exception('No token found. Please log out and log back in.');
      }

      // cache + persist so child screens always have it (also works offline)
      _sessionToken = token;
      try {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('auth_token', token);
        await prefs.setString('token', token);
      } catch (_) {}

      // push notifications: register this phone (safe to call many times)
      PushNotificationService.instance.start(authToken: token, onOpen: _onPushOpen);

      final url = Uri.parse('https://schoolsmirror.com/fetch_data.php?token=$token');
      final res = await http.get(url).timeout(const Duration(seconds: 15));
      final Map<String, dynamic> json = jsonDecode(res.body);
      if (!mounted) return;

      if (json['success'] == true && json['data'] != null) {
        setState(() {
          _data = Map<String, dynamic>.from(json['data']);
          _offlineData = false;
          _seed++;
        });
        try {
          final prefs = await SharedPreferences.getInstance();
          await prefs.setString('dash_cache_v1', jsonEncode(json['data']));
        } catch (_) {}
      } else {
        _fail(json['message'] ?? 'Failed to load dashboard');
      }
    } catch (e) {
      if (mounted) {
        // offline: show the last dashboard that was loaded, so the menu and Result Upload still work
        if (_data == null) {
          final c = await _readCache();
          if (c != null && mounted) {
            setState(() {
              _data = c;
              _offlineData = true;
              _seed++;
            });
          }
        }
        _fail('Network error: $e');
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _fail(String msg) {
    setState(() => _error = msg);
    if (_data != null && mounted) {
      smToast(context, _offlineData ? 'You are offline — showing saved data.' : msg, kind: SmKind.warn);
    }
  }

  // ── Accessors ──
  Map<String, dynamic> get _user => Map<String, dynamic>.from(_data?['user'] ?? {});
  Map<String, dynamic> get _stats => Map<String, dynamic>.from(_data?['stats'] ?? {});
  List<dynamic> get _students => _list(_data?['recent_students']);
  Map<String, dynamic>? get _maint => _data?['maintenance'] is Map ? Map<String, dynamic>.from(_data!['maintenance']) : null;

  String get _role {
    final r = '${_user['role'] ?? ''}'.toLowerCase();
    if (r == _rTeacher) return _rTeacher;
    if (r == _rSub) return _rSub;
    return _rAdmin;
  }

  bool get _isTeacher => _role == _rTeacher;
  List<NavGroup> get _visibleGroups => _navGroups.where((g) => g.visibleFor(_role)).toList();

  String get _roleLabel => _role == _rAdmin ? 'Admin Panel' : (_role == _rSub ? 'Subadmin' : 'Teacher');

  // ── Navigation ──
  Future<void> _open(NavLeaf leaf) async {
    // Close drawer first (if open), then navigate after the frame so context stays valid
    final drawerOpen = _scaffoldKey.currentState?.isDrawerOpen ?? false;
    if (drawerOpen) {
      Navigator.of(context).pop(); // closes drawer only
      await Future.delayed(const Duration(milliseconds: 220));
      if (!mounted) return;
    }

    // Implemented screens — push directly (no named-route auth loop)
    // One page for: add student / teacher / subadmin + users table.
    // The old routes are kept as aliases so any saved link still works.
    if (leaf.route == '/admin/manage-users' ||
        leaf.route == '/admin/add-students' ||
        leaf.route == '/admin/manage-students' ||
        leaf.route == '/admin/manage-staff') {
      String? token = _sessionToken;
      if (token == null || token.isEmpty) {
        try {
          await ApiClient.loadToken();
          token = ApiClient.token;
        } catch (_) {}
      }
      if (token == null || token.isEmpty) {
        try {
          final prefs = await SharedPreferences.getInstance();
          token = prefs.getString('auth_token') ?? prefs.getString('token');
        } catch (_) {}
      }
      if (!mounted) return;
      if (token == null || token.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Session expired. Please log out and log back in.')),
        );
        return;
      }
      await Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => FlutterUsersScreen(
            token: token,
            initialRole: leaf.route == '/admin/manage-staff' ? 'teacher' : 'student',
          ),
        ),
      );
      return;
    }

    // ===== Module routes (classes, dept, session, term, notice, etc.) =====
    Future<void> openModule(FlutterAdminModuleScreen screen) async {
      if (!mounted) return;
      await Navigator.of(context).push(MaterialPageRoute(builder: (_) => screen));
    }

    String? modToken = _sessionToken;
    if (modToken == null || modToken.isEmpty) {
      try {
        await ApiClient.loadToken();
        modToken = ApiClient.token;
      } catch (_) {}
    }
    if (modToken == null || modToken.isEmpty) {
      try {
        final prefs = await SharedPreferences.getInstance();
        modToken = prefs.getString('auth_token') ?? prefs.getString('token');
      } catch (_) {}
    }

    // ===== RESULT OVERVIEW / FINALIZATION (with push notifications) =====
    if (leaf.route == '/admin/published-results' || leaf.route == '/admin/results-overview') {
      if (modToken == null || modToken.isEmpty) {
        smToast(context, 'Session expired. Please log out and log back in.', kind: SmKind.error);
        return;
      }
      await Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => FlutterResultsOverviewScreen(token: modToken!),
      ));
      return;
    }

    if (leaf.route == '/admin/add-class') {
      if (modToken == null || modToken.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Session expired. Please log out and log back in.')));
        return;
      }
      await openModule(FlutterAdminModuleScreen(
        title: 'Class',
        endpoint: 'https://schoolsmirror.com/flutter_classes',
        token: modToken,
        idKey: 'class_id',
        titleKey: 'class_name',
        subtitleKey: 'description',
        icon: Icons.class_,
        fields: const [
          ModuleField(key: 'class_name', label: 'Class name *'),
          ModuleField(key: 'description', label: 'Description *', type: FieldType.multiline, maxLines: 3),
        ],
      ));
      return;
    }
    if (leaf.route == '/admin/add-department') {
      if (modToken == null || modToken.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Session expired. Please log out and log back in.')));
        return;
      }
      await openModule(FlutterAdminModuleScreen(
        title: 'Department',
        endpoint: 'https://schoolsmirror.com/flutter_departments',
        token: modToken,
        idKey: 'id',
        titleKey: 'department_name',
        icon: Icons.apartment,
        fields: const [
          ModuleField(key: 'department_name', label: 'Department name *'),
        ],
      ));
      return;
    }
    if (leaf.route == '/admin/add-session') {
      if (modToken == null || modToken.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Session expired. Please log out and log back in.')));
        return;
      }
      await openModule(FlutterAdminModuleScreen(
        title: 'Session',
        endpoint: 'https://schoolsmirror.com/flutter_sessions',
        token: modToken,
        idKey: 'id',
        titleKey: 'session_name',
        icon: Icons.event,
        fields: const [
          ModuleField(key: 'session_name', label: 'Session name * (e.g. 2024/2025)'),
        ],
      ));
      return;
    }
    if (leaf.route == '/admin/add-term') {
      if (modToken == null || modToken.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Session expired. Please log out and log back in.')));
        return;
      }
      await openModule(FlutterAdminModuleScreen(
        title: 'Term',
        endpoint: 'https://schoolsmirror.com/flutter_terms',
        token: modToken,
        idKey: 'id',
        titleKey: 'term_name',
        icon: Icons.date_range,
        fields: const [
          ModuleField(key: 'term_name', label: 'Term name *'),
        ],
      ));
      return;
    }
    if (leaf.route == '/admin/add-notice') {
      if (modToken == null || modToken.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Session expired. Please log out and log back in.')));
        return;
      }
      await openModule(FlutterAdminModuleScreen(
        title: 'Notice',
        endpoint: 'https://schoolsmirror.com/flutter_notices',
        token: modToken,
        idKey: 'id',
        titleKey: 'header',
        subtitleKey: 'notice',
        icon: Icons.campaign,
        fields: const [
          ModuleField(key: 'class_id', label: 'Class *', type: FieldType.dropdown, optionsFrom: 'classes'),
          ModuleField(key: 'header', label: 'Notice title *'),
          ModuleField(key: 'notice', label: 'Description *', type: FieldType.multiline, maxLines: 4),
        ],
      ));
      return;
    }
    if (leaf.route == '/admin/psychomotor' || leaf.route == '/admin/trait-meaning') {
      if (modToken == null || modToken.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Session expired. Please log out and log back in.')));
        return;
      }
      await openModule(FlutterAdminModuleScreen(
        title: 'Psychomotor Meaning',
        endpoint: 'https://schoolsmirror.com/flutter_psychomotor',
        token: modToken,
        idKey: 'id',
        titleKey: 'meaning_text',
        icon: Icons.psychology,
        fields: const [
          ModuleField(key: 'meaning_text', label: 'Meaning * (min 10 chars)', type: FieldType.multiline, maxLines: 5, minLength: 10),
        ],
      ));
      return;
    }
    if (leaf.route == '/admin/grading') {
      if (modToken == null || modToken.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Session expired. Please log out and log back in.')));
        return;
      }
      await openModule(FlutterAdminModuleScreen(
        title: 'Grade',
        endpoint: 'https://schoolsmirror.com/flutter_grades',
        token: modToken,
        idKey: 'id',
        titleKey: 'grade',
        subtitleKey: 'score_range',
        icon: Icons.grade,
        fields: const [
          ModuleField(key: 'score_range', label: 'Score range * (e.g. 70-100)'),
          ModuleField(key: 'grade', label: 'Grade * (e.g. A)'),
          ModuleField(key: 'grade_point', label: 'Grade point', type: FieldType.number, required: false),
          ModuleField(key: 'meaning', label: 'Meaning *', type: FieldType.multiline, maxLines: 3),
        ],
      ));
      return;
    }
    if (leaf.route == '/admin/next-term') {
      if (modToken == null || modToken.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Session expired. Please log out and log back in.')));
        return;
      }
      await openModule(FlutterAdminModuleScreen(
        title: 'Next Term',
        endpoint: 'https://schoolsmirror.com/flutter_next_term',
        token: modToken,
        idKey: 'id',
        titleKey: 'term_name',
        subtitleKey: 'end_date',
        icon: Icons.skip_next,
        fields: const [
          ModuleField(key: 'session_id', label: 'Session *', type: FieldType.dropdown, optionsFrom: 'sessions'),
          ModuleField(key: 'term_id', label: 'Term *', type: FieldType.dropdown, optionsFrom: 'terms'),
          ModuleField(key: 'end_date', label: 'End date *', type: FieldType.date),
          ModuleField(key: 'description', label: 'Description', type: FieldType.multiline, maxLines: 3, required: false),
        ],
      ));
      return;
    }
    if (leaf.route == '/admin/add-subject') {
      if (modToken == null || modToken.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Session expired. Please log out and log back in.')));
        return;
      }
      await openModule(FlutterAdminModuleScreen(
        title: 'Subject',
        endpoint: 'https://schoolsmirror.com/flutter_subjects',
        token: modToken,
        idKey: 'subject_id',
        titleKey: 'subject_name',
        subtitleKey: 'class_name',
        icon: Icons.menu_book,
        fields: const [
          ModuleField(key: 'class_id', label: 'Class *', type: FieldType.dropdown, optionsFrom: 'classes'),
          ModuleField(key: 'subject_name', label: 'Subject name *'),
          ModuleField(key: 'subject_type', label: 'Type', type: FieldType.dropdown, required: false, options: [
            DropdownOption('Core', 'Core'),
            DropdownOption('Elective', 'Elective'),
            DropdownOption('Optional', 'Optional'),
          ]),
          ModuleField(key: 'department_id', label: 'Department', type: FieldType.dropdown, optionsFrom: 'departments', required: false),
          ModuleField(key: 'status', label: 'Status', type: FieldType.dropdown, required: false, options: [
            DropdownOption('Active', 'Active'),
            DropdownOption('Inactive', 'Inactive'),
          ]),
        ],
      ));
      return;
    }

    // ===== NEW EXAM MANAGEMENT ROUTES =====
    if (leaf.route == '/admin/add-exam') {
      if (modToken == null || modToken.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Session expired. Please log out and log back in.')));
        return;
      }
      await Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => FlutterAddExamScreen(token: modToken),
      ));
      return;
    }

    // ===== RESULT UPLOAD (students -> session/term -> scores + traits, with offline upload) =====
    if (leaf.route == '/admin/result-upload') {
      if (modToken == null || modToken.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Session expired. Please log out and log back in.')));
        return;
      }
      await Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => FlutterResultUploadScreen(token: modToken),
      ));
      return;
    }

    if (leaf.route == '/admin/assign-subject') {
      if (modToken == null || modToken.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Session expired. Please log out and log back in.')));
        return;
      }
      await Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => FlutterAssignSubjectScreen(token: modToken),
      ));
      return;
    }

    if (leaf.route == '/admin/homework') {
      if (modToken == null || modToken.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Session expired. Please log out and log back in.')));
        return;
      }
      await Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => FlutterAddHomeworkScreen(token: modToken),
      ));
      return;
    }

    // ===== NEW CBT & PROMOTION ROUTES =====
    if (leaf.route == '/admin/cumulative-results') {
      if (modToken == null || modToken.isEmpty) return;
      await Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => FlutterCumulativeResultsScreen(token: modToken),
      ));
      return;
    }

    if (leaf.route == '/admin/promote-students') {
      if (modToken == null || modToken.isEmpty) return;
      await Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => FlutterPromoteStudentsScreen(token: modToken),
      ));
      return;
    }

    if (leaf.route == '/admin/revert-promotions') {
      if (modToken == null || modToken.isEmpty) return;
      await Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => FlutterRevertPromotionsScreen(token: modToken),
      ));
      return;
    }

    if (leaf.route == '/admin/promotion-history') {
      if (modToken == null || modToken.isEmpty) return;
      await Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => FlutterPromotionHistoryScreen(token: modToken),
      ));
      return;
    }

    // ===== SCHOOL DETAILS / ATTENDANCE ROUTES =====
    if (leaf.route == '/admin/result-template') {
      if (modToken == null || modToken.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Session expired. Please log out and log back in.')));
        return;
      }
      await Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => FlutterResultTemplateScreen(token: modToken),
      ));
      return;
    }

    if (leaf.route == '/admin/teacher-in-out') {
      if (modToken == null || modToken.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Session expired. Please log out and log back in.')));
        return;
      }
      await Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => FlutterTeacherInOutScreen(token: modToken),
      ));
      return;
    }

    if (leaf.route == '/admin/upload-signature') {
      if (modToken == null || modToken.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Session expired. Please log out and log back in.')));
        return;
      }
      await Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => FlutterUploadSignatureScreen(token: modToken),
      ));
      return;
    }

    if (leaf.route == '/admin/class-ranking') {
      if (modToken == null || modToken.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Session expired. Please log out and log back in.')));
        return;
      }
      await Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => FlutterPositionOfStudentScreen(token: modToken),
      ));
      return;
    }

    if (leaf.route == '/admin/staff-attendance') {
      if (modToken == null || modToken.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Session expired. Please log out and log back in.')));
        return;
      }
      await Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => FlutterAllAttendanceScreen(token: modToken),
      ));
      return;
    }

    // Try named route for every remaining menu item (no "coming soon")
    try {
      await Navigator.of(context).pushNamed(leaf.route);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(
          content: Text('${leaf.title}: screen not registered yet. Add a route for ${leaf.route} in main.dart'),
          duration: const Duration(seconds: 3),
        ));
    }
  }

  void _openDrawer() {
    _scaffoldKey.currentState?.openDrawer();
  }

  NavLeaf? _findLeaf(String title) {
    for (final g in _visibleGroups) {
      for (final l in g.leavesFor(_role)) {
        if (l.title == title) return l;
      }
    }
    return null;
  }

  // ════════════════════════════════════════════════════════════════════════
  //  NEW DESIGN  ("Aurora Glass")
  // ════════════════════════════════════════════════════════════════════════
  String get _greeting {
    final h = DateTime.now().hour;
    return h < 12 ? 'Good morning' : (h < 17 ? 'Good afternoon' : 'Good evening');
  }

  Future<void> _logout() async {
    final ok = await smConfirm(context, 'Log out?', 'You will need your password (or fingerprint) to sign in again.',
        yes: 'Log out', destructive: true, icon: Icons.logout_rounded);
    if (ok != true) return;
    try {
      await PushNotificationService.instance.unregister();
    } catch (_) {}
    await ApiClient.logout();
    if (mounted) Navigator.of(context).pushReplacementNamed('/');
  }

  void _onPushOpen(Map<String, dynamic> data) {
    if (!mounted) return;
    final screen = '${data['screen'] ?? ''}';
    if (screen == 'published-results' || screen == 'results') {
      final l = _findLeaf('Result Overview');
      if (l != null) {
        _open(l);
        return;
      }
    }
    _openMessages();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      key: _scaffoldKey,
      backgroundColor: SM.bg1,
      extendBody: true,
      drawer: _buildDrawer(),
      bottomNavigationBar: _dock(),
      body: SmBackground(
        child: SafeArea(
          bottom: false,
          child: Column(children: [
            _header(),
            if (_maint != null && _maint!['show_banner'] == true) _buildMaintenanceBanner(),
            Expanded(
              child: (_loading && _data == null)
                  ? const Center(child: SmLogoLoader(label: 'Loading your dashboard…'))
                  : RefreshIndicator(
                      color: SM.orange,
                      backgroundColor: SM.sheet,
                      onRefresh: _load,
                      child: (_error != null && _data == null) ? _errorView() : _body(),
                    ),
            ),
          ]),
        ),
      ),
    );
  }

  // ── header ──
  Widget _header() {
    final unread = _num(_stats['unread_messages']).toInt();
    final school = '${_user['schoolname'] ?? 'SchoolsMirror'}';
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 8),
      child: Row(children: [
        SmIconBtn(icon: Icons.menu_rounded, onTap: _openDrawer),
        const SizedBox(width: 12),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(_greeting, style: const TextStyle(color: SM.muted, fontSize: 12.5, fontWeight: FontWeight.w600)),
            Text(school, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: SM.text, fontSize: 19, fontWeight: FontWeight.w800, letterSpacing: -.4)),
          ]),
        ),
        SmIconBtn(icon: Icons.notifications_rounded, badge: unread, onTap: _openMessages),
        const SizedBox(width: 8),
        PopupMenuButton<String>(
          offset: const Offset(0, 54),
          color: SM.sheet,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18), side: BorderSide(color: SM.glassLine)),
          onSelected: (v) {
            if (v == 'logout') {
              _logout();
            } else {
              _open(const NavLeaf('Profile', Icons.person, '/admin/profile'));
            }
          },
          itemBuilder: (_) => [
            PopupMenuItem(value: 'profile', child: Row(children: const [Icon(Icons.person_rounded, size: 19, color: SM.text), SizedBox(width: 10), Text('Profile', style: TextStyle(color: SM.text))])),
            PopupMenuItem(value: 'logout', child: Row(children: const [Icon(Icons.logout_rounded, size: 19, color: SM.rose), SizedBox(width: 10), Text('Logout', style: TextStyle(color: SM.rose))])),
          ],
          child: Container(
            width: 44,
            height: 44,
            alignment: Alignment.center,
            decoration: BoxDecoration(gradient: SM.hot, borderRadius: BorderRadius.circular(16), boxShadow: [BoxShadow(color: SM.a(SM.orange, .35), blurRadius: 14)]),
            child: Text(school.isEmpty ? 'S' : school.substring(0, 1).toUpperCase(), style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 18)),
          ),
        ),
      ]),
    );
  }

  Widget _buildMaintenanceBanner() {
    final m = _maint!;
    final level = m['level'] ?? 'info';
    final days = (m['days_remaining'] ?? 0) as int;
    final amount = (m['amount'] ?? 0).toDouble();
    final renewal = (m['renewal_days'] ?? 0) as int;
    final c = level == 'danger' ? SM.rose : (level == 'warning' ? SM.amber : SM.cyan);
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 2, 16, 8),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: SM.a(c, .14), borderRadius: BorderRadius.circular(20), border: Border.all(color: SM.a(c, .5))),
      child: Row(children: [
        Icon(days > 0 ? Icons.schedule_rounded : Icons.warning_amber_rounded, color: c, size: 26),
        const SizedBox(width: 12),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(days > 0 ? 'Portal maintenance due in $days days' : 'Portal overdue — payment required', style: const TextStyle(color: SM.text, fontWeight: FontWeight.w800, fontSize: 13.5)),
            const SizedBox(height: 2),
            Text('Pay ₦${amount.toStringAsFixed(2)} to renew for $renewal days.', style: const TextStyle(color: SM.muted, fontSize: 12)),
          ]),
        ),
      ]),
    );
  }

  Widget _errorView() {
    return ListView(physics: const AlwaysScrollableScrollPhysics(), padding: const EdgeInsets.all(24), children: [
      const SizedBox(height: 70),
      SmGlass(
        radius: 28,
        padding: const EdgeInsets.all(24),
        child: Column(children: [
          Container(width: 70, height: 70, decoration: BoxDecoration(shape: BoxShape.circle, color: SM.a(SM.amber, .16), border: Border.all(color: SM.a(SM.amber, .5))), child: const Icon(Icons.wifi_off_rounded, color: SM.amber, size: 32)),
          const SizedBox(height: 16),
          const Text('Can’t reach the server', style: TextStyle(color: SM.text, fontSize: 19, fontWeight: FontWeight.w800)),
          const SizedBox(height: 8),
          Text(_error ?? '', textAlign: TextAlign.center, style: const TextStyle(color: SM.muted, fontSize: 13.5)),
          const SizedBox(height: 20),
          SmButton(label: 'Try again', icon: Icons.refresh_rounded, onTap: _load),
          const SizedBox(height: 10),
          SmButton(label: 'Open Result Upload offline', icon: Icons.cloud_off_rounded, outline: true, onTap: () => _open(const NavLeaf('Result Upload', Icons.upload_file, '/admin/result-upload'))),
        ]),
      ),
    ]);
  }

  Widget _body() {
    return LayoutBuilder(builder: (context, c) {
      final wide = c.maxWidth >= 800;
      final contentW = math.min(c.maxWidth, 1100.0) - 32;
      return SingleChildScrollView(
        controller: _scroll,
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 6, 16, 130),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 1100),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              _hero(),
              const SizedBox(height: 16),
              _statsGrid(wide),
              const SizedBox(height: 16),
              _resultsCenter(),
              _quickActions(),
              if (!_isTeacher) ...[
                const SmSectionTitle('Analytics', sub: 'Payments and finalized results'),
                _buildCharts(wide),
              ],
              _buildModules(contentW, wide),
              _buildRecentStudents(),
            ]),
          ),
        ),
      );
    });
  }

  // ── hero ──
  Widget _hero() {
    final school = '${_user['schoolname'] ?? 'Your School'}';
    final who = '${_user['fullname'] ?? _user['name'] ?? ''}'.trim();
    return Container(
      width: double.infinity,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(30),
        gradient: const LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [Color(0xFF4767C0), Color(0xFF2A3F86), Color(0xFF1B2A5E)]),
        border: Border.all(color: SM.a(Colors.white, .18)),
        boxShadow: [BoxShadow(color: SM.a(SM.blue, .45), blurRadius: 34, offset: const Offset(0, 16))],
      ),
      child: Stack(children: [
        Positioned(right: -40, top: -50, child: Container(width: 190, height: 190, decoration: BoxDecoration(shape: BoxShape.circle, gradient: RadialGradient(colors: [SM.a(SM.orange, .55), SM.a(SM.orange, 0)])))),
        Positioned(left: -60, bottom: -80, child: Container(width: 200, height: 200, decoration: BoxDecoration(shape: BoxShape.circle, gradient: RadialGradient(colors: [SM.a(SM.cyan, .30), SM.a(SM.cyan, 0)])))),
        Padding(
          padding: const EdgeInsets.all(22),
          child: Row(children: [
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Wrap(spacing: 8, runSpacing: 6, children: [
                  SmPill(_roleLabel, color: Colors.white, icon: Icons.verified_user_rounded),
                  if (_offlineData) const SmPill('Offline data', color: SM.amber, icon: Icons.cloud_off_rounded) else const SmPill('Live', color: SM.green, icon: Icons.circle),
                ]),
                const SizedBox(height: 14),
                Text(who.isEmpty ? 'Welcome back 👋' : 'Hi, ${who.split(' ').first} 👋', style: const TextStyle(color: Colors.white, fontSize: 26, fontWeight: FontWeight.w800, letterSpacing: -.6)),
                const SizedBox(height: 4),
                Text('${_data?['date'] ?? ''}', style: const TextStyle(color: Color(0xFFD6E0FA), fontSize: 13)),
                const SizedBox(height: 10),
                Text(school, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white, fontSize: 14.5, fontWeight: FontWeight.w700)),
              ]),
            ),
            const SizedBox(width: 12),
            Container(
              width: 74,
              height: 74,
              padding: const EdgeInsets.all(9),
              decoration: BoxDecoration(color: Colors.white, shape: BoxShape.circle, boxShadow: [BoxShadow(color: SM.a(Colors.black, .3), blurRadius: 16, offset: const Offset(0, 8))]),
              child: ClipOval(child: Image.asset('assets/images/logo.png', fit: BoxFit.contain, errorBuilder: (_, __, ___) => const Icon(Icons.school_rounded, color: SM.blue, size: 34))),
            ),
          ]),
        ),
      ]),
    );
  }

  // ── stats bento ──
  Widget _statsGrid(bool wide) {
    final tiles = <Widget>[
      _statTile('Students', SmCount(_num(_stats['total_students']), style: _bigNum), 'Registered', Icons.groups_rounded, SM.brand, SM.blueLight),
      _statTile('Staff', SmCount(_num(_stats['total_staff']), style: _bigNum), 'Teaching & admin', Icons.badge_rounded, SM.mint, SM.green),
    ];
    if (!_isTeacher) {
      tiles.add(_statTile('Finalized', SmCount(_num(_stats['finalized_results']), style: _bigNum), 'Published results', Icons.task_alt_rounded, SM.violet2, SM.violet));
      tiles.add(_statTile('Revenue', FittedBox(fit: BoxFit.scaleDown, alignment: Alignment.centerLeft, child: Text('₦${_compact(_num(_stats['total_revenue']))}', style: _bigNum)), 'Student payments', Icons.payments_rounded, SM.hot, SM.orange));
    }
    return GridView.count(
      crossAxisCount: wide ? tiles.length : 2,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      mainAxisSpacing: 12,
      crossAxisSpacing: 12,
      childAspectRatio: wide ? 1.7 : 1.08,
      children: tiles,
    );
  }

  TextStyle get _bigNum => const TextStyle(color: SM.text, fontSize: 27, fontWeight: FontWeight.w800, letterSpacing: -.8);

  Widget _statTile(String title, Widget value, String sub, IconData icon, Gradient g, Color glow) {
    return SmGlass(
      radius: 26,
      padding: const EdgeInsets.all(16),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
        Container(
          width: 42,
          height: 42,
          decoration: BoxDecoration(gradient: g, borderRadius: BorderRadius.circular(14), boxShadow: [BoxShadow(color: SM.a(glow, .45), blurRadius: 14, offset: const Offset(0, 6))]),
          child: Icon(icon, color: Colors.white, size: 22),
        ),
        value,
        Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(title, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: SM.text, fontSize: 13.5, fontWeight: FontWeight.w700)),
          Text(sub, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: SM.muted, fontSize: 11.5)),
        ]),
      ]),
    );
  }

  // ── results centre (upload + overview) ──
  Widget _resultsCenter() {
    final up = _findLeaf('Result Upload');
    final ov = _findLeaf('Result Overview');
    if (up == null && ov == null) return const SizedBox.shrink();
    return SmGlass(
      radius: 28,
      padding: const EdgeInsets.all(18),
      gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [SM.a(SM.orange, .22), SM.a(const Color(0xFFFF4D8D), .12), SM.a(SM.blue, .18)]),
      border: SM.a(SM.orange, .45),
      glow: SM.orange,
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Container(width: 46, height: 46, decoration: BoxDecoration(gradient: SM.hot, borderRadius: BorderRadius.circular(16)), child: const Icon(Icons.auto_graph_rounded, color: Colors.white, size: 25)),
          const SizedBox(width: 12),
          const Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Results Center', style: TextStyle(color: SM.text, fontSize: 18, fontWeight: FontWeight.w800, letterSpacing: -.3)),
              Text('Upload scores, then publish to students & parents', style: TextStyle(color: SM.muted, fontSize: 12.5)),
            ]),
          ),
        ]),
        const SizedBox(height: 16),
        Row(children: [
          if (up != null) Expanded(child: SmButton(label: 'Upload', icon: Icons.upload_file_rounded, height: 50, onTap: () => _open(up))),
          if (up != null && ov != null) const SizedBox(width: 10),
          if (ov != null) Expanded(child: SmButton(label: 'Overview', icon: Icons.fact_check_rounded, gradient: SM.hot, glow: SM.orange, height: 50, onTap: () => _open(ov))),
        ]),
      ]),
    );
  }

  // ── quick actions ──
  Widget _quickActions() {
    const wanted = ['Manage Users', 'Student Fees', 'Add Notice', 'Add Exam', 'Homework', 'Class Ranking', 'Result Template', 'Add Subject'];
    final items = <MapEntry<NavGroup, NavLeaf>>[];
    for (final title in wanted) {
      for (final g in _visibleGroups) {
        final hit = g.leavesFor(_role).where((l) => l.title == title);
        if (hit.isNotEmpty) {
          items.add(MapEntry(g, hit.first));
          break;
        }
      }
    }
    if (items.isEmpty) return const SizedBox.shrink();
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const SmSectionTitle('Quick actions'),
      SizedBox(
        height: 108,
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          clipBehavior: Clip.none,
          itemCount: items.length,
          separatorBuilder: (_, __) => const SizedBox(width: 12),
          itemBuilder: (_, i) {
            final g = items[i].key;
            final l = items[i].value;
            return SmPress(
              onTap: () => _open(l),
              child: SizedBox(
                width: 82,
                child: Column(children: [
                  Container(
                    width: 64,
                    height: 64,
                    decoration: BoxDecoration(
                      gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [SM.a(g.color, .95), SM.a(g.color, .55)]),
                      borderRadius: BorderRadius.circular(22),
                      boxShadow: [BoxShadow(color: SM.a(g.color, .38), blurRadius: 16, offset: const Offset(0, 8))],
                    ),
                    child: Icon(l.icon, color: Colors.white, size: 28),
                  ),
                  const SizedBox(height: 8),
                  Text(l.title, maxLines: 2, textAlign: TextAlign.center, overflow: TextOverflow.ellipsis, style: const TextStyle(color: SM.text, fontSize: 11.5, fontWeight: FontWeight.w700, height: 1.2)),
                ]),
              ),
            );
          },
        ),
      ),
    ]);
  }

  // ── charts shell ──
  Widget _chartCard({required String title, required String subtitle, required Widget toggle, required Widget child}) {
    return SmGlass(
      radius: 26,
      padding: const EdgeInsets.all(18),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(title, style: const TextStyle(color: SM.text, fontSize: 16, fontWeight: FontWeight.w800)),
              const SizedBox(height: 2),
              Text(subtitle, style: const TextStyle(color: SM.muted, fontSize: 12)),
            ]),
          ),
          const SizedBox(width: 8),
          toggle,
        ]),
        const SizedBox(height: 16),
        child,
      ]),
    );
  }

  // ── all modules ──
  Widget _buildModules(double width, bool wide) {
    final q = _query.trim().toLowerCase();
    final cardW = wide ? (width - 12) / 2 - 0.5 : width;
    final cards = <Widget>[];
    var linkCount = 0;
    for (final g in _visibleGroups) {
      var leaves = g.leavesFor(_role);
      if (q.isNotEmpty) {
        leaves = leaves.where((l) => l.title.toLowerCase().contains(q) || g.title.toLowerCase().contains(q)).toList();
      }
      if (leaves.isEmpty) continue;
      linkCount += leaves.length;
      cards.add(SizedBox(width: cardW, child: _moduleCard(g, leaves)));
    }
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      SmSectionTitle('All modules', trailing: Text('$linkCount links', style: const TextStyle(fontSize: 12, color: SM.muted))),
      TextField(
        controller: _search,
        style: const TextStyle(color: SM.text, fontWeight: FontWeight.w600),
        cursorColor: SM.orange,
        decoration: smInput('Search modules…', icon: Icons.search_rounded, dense: true, accent: SM.orange,
            suffix: _query.isEmpty ? null : IconButton(icon: const Icon(Icons.close_rounded, color: SM.muted, size: 19), onPressed: () { _search.clear(); setState(() => _query = ''); })),
        onChanged: (v) => setState(() => _query = v),
      ),
      const SizedBox(height: 14),
      if (cards.isEmpty)
        const Padding(padding: EdgeInsets.all(30), child: Center(child: Text('No module matches your search', style: TextStyle(color: SM.muted))))
      else
        Wrap(spacing: 12, runSpacing: 12, children: cards),
    ]);
  }

  Widget _moduleCard(NavGroup g, List<NavLeaf> leaves) {
    return SmGlass(
      radius: 24,
      padding: const EdgeInsets.all(14),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(gradient: LinearGradient(colors: [SM.a(g.color, .95), SM.a(g.color, .55)]), borderRadius: BorderRadius.circular(13)),
            child: Icon(g.icon, color: Colors.white, size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(child: Text(g.title, style: const TextStyle(color: SM.text, fontSize: 15, fontWeight: FontWeight.w800))),
          SmPill('${leaves.length}', color: g.color),
        ]),
        const SizedBox(height: 12),
        Wrap(spacing: 8, runSpacing: 8, children: leaves.map((l) => _linkChip(g, l)).toList()),
      ]),
    );
  }

  Widget _linkChip(NavGroup g, NavLeaf l) {
    return SmPress(
      onTap: () => _open(l),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(color: SM.a(Colors.white, .06), borderRadius: BorderRadius.circular(14), border: Border.all(color: SM.glassLine)),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(l.icon, size: 16, color: g.color),
          const SizedBox(width: 7),
          Flexible(child: Text(l.title, style: const TextStyle(color: SM.text, fontSize: 12.5, fontWeight: FontWeight.w600))),
          if (l.isNew) ...[const SizedBox(width: 6), const SmPill('NEW', color: SM.orange, filled: true, fontSize: 9)],
        ]),
      ),
    );
  }

  // ── recent students ──
  Widget _buildRecentStudents() {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      SmSectionTitle('Recent students',
          trailing: TextButton(onPressed: () { final leaf = _findLeaf('Manage Users'); if (leaf != null) _open(leaf); }, child: const Text('View all', style: TextStyle(color: SM.orange, fontWeight: FontWeight.w700)))),
      SmGlass(
        radius: 26,
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: _students.isEmpty
            ? const Padding(
                padding: EdgeInsets.all(28),
                child: Center(child: Column(children: [Icon(Icons.person_off_outlined, size: 44, color: SM.faint), SizedBox(height: 10), Text('No students added yet', style: TextStyle(color: SM.muted))])),
              )
            : Column(
                children: _students.map<Widget>((s) {
                  final m = Map<String, dynamic>.from(s);
                  return Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
                    child: Row(children: [
                      SmAvatar(url: '${m['image_url'] ?? m['image'] ?? ''}', name: '${m['fullname'] ?? ''}', size: 44),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text('${m['fullname'] ?? ''}', style: const TextStyle(color: SM.text, fontWeight: FontWeight.w700, fontSize: 14.5)),
                          Text('${m['department'] ?? '-'} • ${m['class_name'] ?? '-'}', style: const TextStyle(color: SM.muted, fontSize: 12)),
                        ]),
                      ),
                      const SmPill('Active', color: SM.green),
                    ]),
                  );
                }).toList(),
              ),
      ),
    ]);
  }

  // ── floating dock ──
  Widget _dock() {
    final items = <Widget>[];
    Widget btn(IconData icon, String label, VoidCallback onTap, {bool active = false}) => Expanded(
          child: SmPress(
            onTap: onTap,
            child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
              AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                decoration: BoxDecoration(gradient: active ? SM.hot : null, borderRadius: BorderRadius.circular(16)),
                child: Icon(icon, size: 22, color: active ? Colors.white : SM.muted),
              ),
              const SizedBox(height: 2),
              Text(label, style: TextStyle(color: active ? SM.text : SM.muted, fontSize: 10.5, fontWeight: FontWeight.w700)),
            ]),
          ),
        );
    items.add(btn(Icons.home_rounded, 'Home', () {
      if (_scroll.hasClients) _scroll.animateTo(0, duration: const Duration(milliseconds: 450), curve: Curves.easeOutCubic);
    }, active: true));
    final up = _findLeaf('Result Upload');
    final ov = _findLeaf('Result Overview');
    final us = _findLeaf('Manage Users');
    final ex = _findLeaf('Add Exam');
    if (up != null) items.add(btn(Icons.upload_file_rounded, 'Upload', () => _open(up)));
    if (ov != null) items.add(btn(Icons.fact_check_rounded, 'Overview', () => _open(ov)));
    if (us != null) {
      items.add(btn(Icons.groups_rounded, 'Users', () => _open(us)));
    } else if (ex != null && ov == null) {
      items.add(btn(Icons.quiz_rounded, 'Exams', () => _open(ex)));
    }
    items.add(btn(Icons.apps_rounded, 'Menu', _openDrawer));
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
              decoration: BoxDecoration(color: SM.a(SM.sheet, .82), borderRadius: BorderRadius.circular(30), border: Border.all(color: SM.glassLine), boxShadow: [BoxShadow(color: SM.a(Colors.black, .4), blurRadius: 24, offset: const Offset(0, 10))]),
              child: Row(children: items),
            ),
          ),
        ),
      ),
    );
  }

  // ════════════════════════════════════════════════════════════════════════
  //  DRAWER (hamburger) — Result Overview is pinned at the top
  // ════════════════════════════════════════════════════════════════════════
  Widget _buildDrawer() {
    final groups = _visibleGroups;
    final up = _findLeaf('Result Upload');
    final ov = _findLeaf('Result Overview');
    final school = '${_user['schoolname'] ?? 'SchoolsMirror'}';
    return Drawer(
      backgroundColor: SM.bg1,
      width: math.min(MediaQuery.of(context).size.width * .88, 350),
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.horizontal(right: Radius.circular(30))),
      child: SmBackground(
        child: SafeArea(
          child: Column(children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 18, 18, 10),
              child: Row(children: [
                Container(
                  width: 58,
                  height: 58,
                  padding: const EdgeInsets.all(3),
                  decoration: BoxDecoration(shape: BoxShape.circle, gradient: const SweepGradient(colors: [Color(0xFFF7941D), Color(0xFFFF4D8D), Color(0xFF6C8CE0), Color(0xFF22D3EE), Color(0xFFF7941D)])),
                  child: Container(padding: const EdgeInsets.all(7), decoration: const BoxDecoration(color: Colors.white, shape: BoxShape.circle), child: ClipOval(child: Image.asset('assets/images/logo.png', fit: BoxFit.contain, errorBuilder: (_, __, ___) => const Icon(Icons.school_rounded, color: SM.blue)))),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(school, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(color: SM.text, fontSize: 17, fontWeight: FontWeight.w800, letterSpacing: -.3)),
                    const SizedBox(height: 4),
                    SmPill(_roleLabel, color: SM.blueLight),
                  ]),
                ),
              ]),
            ),
            Expanded(
              child: ListView(padding: const EdgeInsets.fromLTRB(14, 6, 14, 10), children: [
                _pin(Icons.dashboard_rounded, 'Dashboard', 'Overview of your school', SM.brand, () => Navigator.of(context).pop()),
                if (ov != null) _pin(Icons.fact_check_rounded, 'Result Overview', 'Finalize & publish results', SM.hot, () => _open(ov), badge: 'PUBLISH'),
                if (up != null) _pin(Icons.upload_file_rounded, 'Result Upload', 'Enter scores, works offline', SM.cyan2, () => _open(up)),
                const Padding(
                  padding: EdgeInsets.fromLTRB(6, 18, 6, 8),
                  child: Text('NAVIGATION', style: TextStyle(color: SM.faint, fontSize: 11, fontWeight: FontWeight.w800, letterSpacing: 1.6)),
                ),
                for (final g in groups) _drawerGroup(g),
              ]),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 4, 14, 14),
              child: SmButton(label: 'Logout', icon: Icons.logout_rounded, gradient: SM.rose2, glow: SM.rose, height: 50, onTap: () {
                Navigator.of(context).pop();
                _logout();
              }),
            ),
          ]),
        ),
      ),
    );
  }

  Widget _pin(IconData icon, String title, String sub, Gradient g, VoidCallback onTap, {String? badge}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: SmPress(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(color: SM.a(Colors.white, .07), borderRadius: BorderRadius.circular(20), border: Border.all(color: SM.glassLine)),
          child: Row(children: [
            Container(width: 44, height: 44, decoration: BoxDecoration(gradient: g, borderRadius: BorderRadius.circular(15)), child: Icon(icon, color: Colors.white, size: 23)),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  Flexible(child: Text(title, style: const TextStyle(color: SM.text, fontSize: 15, fontWeight: FontWeight.w800))),
                  if (badge != null) ...[const SizedBox(width: 8), SmPill(badge, color: SM.orange, filled: true, fontSize: 9)],
                ]),
                Text(sub, style: const TextStyle(color: SM.muted, fontSize: 12)),
              ]),
            ),
            const Icon(Icons.chevron_right_rounded, color: SM.faint),
          ]),
        ),
      ),
    );
  }

  Widget _drawerGroup(NavGroup g) {
    final leaves = g.leavesFor(_role);
    Widget bubble() => Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(gradient: LinearGradient(colors: [SM.a(g.color, .95), SM.a(g.color, .55)]), borderRadius: BorderRadius.circular(12)),
          child: Icon(g.icon, color: Colors.white, size: 19),
        );
    if (g.flat && leaves.length == 1) {
      final l = leaves.first;
      return Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: SmPress(
          onTap: () => _open(l),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(color: SM.glass, borderRadius: BorderRadius.circular(18), border: Border.all(color: SM.glassLine)),
            child: Row(children: [
              bubble(),
              const SizedBox(width: 12),
              Expanded(child: Text(l.title, style: const TextStyle(color: SM.text, fontSize: 14.5, fontWeight: FontWeight.w700))),
              if (l.isNew) const SmPill('NEW', color: SM.orange, filled: true, fontSize: 9),
            ]),
          ),
        ),
      );
    }
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Container(
        decoration: BoxDecoration(color: SM.glass, borderRadius: BorderRadius.circular(18), border: Border.all(color: SM.glassLine)),
        child: Theme(
          data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
          child: ExpansionTile(
            tilePadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
            childrenPadding: const EdgeInsets.fromLTRB(10, 0, 10, 10),
            iconColor: SM.orange,
            collapsedIconColor: SM.muted,
            shape: const RoundedRectangleBorder(),
            collapsedShape: const RoundedRectangleBorder(),
            leading: bubble(),
            title: Text(g.title, style: const TextStyle(color: SM.text, fontSize: 14.5, fontWeight: FontWeight.w700)),
            children: [
              for (final l in leaves)
                SmPress(
                  onTap: () => _open(l),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
                    child: Row(children: [
                      Icon(l.icon, size: 18, color: g.color),
                      const SizedBox(width: 12),
                      Expanded(child: Text(l.title, style: const TextStyle(color: SM.text, fontSize: 13.5, fontWeight: FontWeight.w600))),
                      if (l.isNew) const SmPill('NEW', color: SM.orange, filled: true, fontSize: 9),
                    ]),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  // ════════════════════════════════════════════════════════════════════════
  //  CHARTS
  // ════════════════════════════════════════════════════════════════════════
  Widget _buildCharts(bool wide) {
    final pay = _paymentCard();
    final res = _resultsCard();
    if (wide) {
      return Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(flex: 3, child: pay),
          const SizedBox(width: 16),
          Expanded(flex: 2, child: res),
        ],
      );
    }
    return Column(children: [pay, const SizedBox(height: 16), res]);
  }

  Widget _paymentCard() {
    final chart = _data?['payment_chart'];
    final labels = _list(chart is Map ? chart['labels'] : null).map((e) => '$e').toList();
    final values = _list(chart is Map ? chart['amounts'] : null).map(_num).toList();
    final n = math.min(labels.length, values.length);
    final l = labels.take(n).toList();
    final v = values.take(n).toList();
    final total = v.fold<double>(0, (a, b) => a + b);

    return _chartCard(
      title: 'Payment Analytics',
      subtitle: n == 0 ? 'Last 6 months' : 'Last 6 months · ₦${_money(total)}',
      toggle: _Toggle(options: const ['Bar', 'Line'], index: _payType, onChanged: (i) => setState(() => _payType = i)),
      child: n == 0
          ? _emptyChart('No payment data yet')
          : SizedBox(
              height: 230,
              child: TweenAnimationBuilder<double>(
                key: ValueKey('pay-$_payType-$_seed'),
                tween: Tween(begin: 0, end: 1),
                duration: const Duration(milliseconds: 800),
                curve: Curves.easeOutCubic,
                builder: (_, t, __) => CustomPaint(
                  size: Size.infinite,
                  painter: _CartesianPainter(
                    values: v,
                    labels: l,
                    colors: List.generate(n, (i) => _kPrimary.withOpacity(math.min(1.0, 0.5 + i * 0.1))),
                    isLine: _payType == 1,
                    t: t,
                    fmt: (x) => '₦${_compact(x)}',
                  ),
                ),
              ),
            ),
    );
  }

  Widget _resultsCard() {
    final chart = _data?['results_chart'];
    final labels = _list(chart is Map ? chart['labels'] : null).map((e) => '$e').toList();
    final values = _list(chart is Map ? chart['counts'] : null).map(_num).toList();
    final n = math.min(labels.length, values.length);
    final l = labels.take(n).toList();
    final v = values.take(n).toList();
    final total = v.fold<double>(0, (a, b) => a + b);

    Widget body;
    if (n == 0) {
      body = _emptyChart('No finalized results yet');
    } else if (_resType == 0) {
      body = Column(
        children: [
          SizedBox(
            height: 180,
            child: TweenAnimationBuilder<double>(
              key: ValueKey('res-d-$_seed'),
              tween: Tween(begin: 0, end: 1),
              duration: const Duration(milliseconds: 900),
              curve: Curves.easeOutCubic,
              builder: (_, t, __) => Stack(
                alignment: Alignment.center,
                children: [
                  CustomPaint(size: Size.infinite, painter: _DonutPainter(values: v, t: t)),
                  Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text('${(total * t).round()}', style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w800, color: _kDark)),
                      const Text('Finalized', style: TextStyle(fontSize: 11, color: _kMuted)),
                    ],
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 14),
          Wrap(
            spacing: 14, runSpacing: 8, alignment: WrapAlignment.center,
            children: List.generate(n, (i) {
              final c = _chartPalette[i % _chartPalette.length];
              return Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(width: 10, height: 10, decoration: BoxDecoration(color: c, shape: BoxShape.circle)),
                  const SizedBox(width: 6),
                  Text('${l[i]} (${v[i].toInt()})', style: const TextStyle(fontSize: 11, color: _kMuted)),
                ],
              );
            }),
          ),
        ],
      );
    } else {
      body = SizedBox(
        height: 230,
        child: TweenAnimationBuilder<double>(
          key: ValueKey('res-b-$_seed'),
          tween: Tween(begin: 0, end: 1),
          duration: const Duration(milliseconds: 800),
          curve: Curves.easeOutCubic,
          builder: (_, t, __) => CustomPaint(
            size: Size.infinite,
            painter: _CartesianPainter(
              values: v, labels: l,
              colors: List.generate(n, (i) => _chartPalette[i % _chartPalette.length]),
              isLine: false, t: t, fmt: _compact,
            ),
          ),
        ),
      );
    }

    return _chartCard(
      title: 'Results Overview',
      subtitle: 'Finalized per term',
      toggle: _Toggle(options: const ['Donut', 'Bar'], index: _resType, onChanged: (i) => setState(() => _resType = i)),
      child: body,
    );
  }

  Widget _emptyChart(String msg) {
    return SizedBox(
      height: 160,
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.bar_chart, size: 40, color: Colors.grey.shade300),
            const SizedBox(height: 8),
            Text(msg, style: const TextStyle(color: _kMuted, fontSize: 12)),
          ],
        ),
      ),
    );
  }

  // ════════════════════════════════════════════════════════════════════════
  //  MESSAGES BOTTOM SHEET
  // ════════════════════════════════════════════════════════════════════════
  Future<void> _openMessages() async {
    try {
      await ApiClient.loadToken();
      final token = ApiClient.token;
      
      final url = Uri.parse('https://schoolsmirror.com/fetch_data.php?token=$token&action=messages');
      final res = await http.get(url);
      final json = jsonDecode(res.body);
      
      if (json['success'] == true) {
        final messages = List<Map<String, dynamic>>.from(json['data']['messages'] ?? []);
        
        if (mounted) {
          smSheet(context, (_) => _MessagesSheet(messages: messages, onRefresh: _load));
        }
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error loading messages: $e')));
    }
  }

}

// ════════════════════════════════════════════════════════════════════════════
//  MESSAGES SHEET (dark glass)
// ════════════════════════════════════════════════════════════════════════════
class _MessagesSheet extends StatefulWidget {
  final List<Map<String, dynamic>> messages;
  final VoidCallback onRefresh;
  const _MessagesSheet({required this.messages, required this.onRefresh});

  @override
  State<_MessagesSheet> createState() => _MessagesSheetState();
}

class _MessagesSheetState extends State<_MessagesSheet> {
  late List<Map<String, dynamic>> _items;

  @override
  void initState() {
    super.initState();
    _items = List.of(widget.messages);
  }

  Future<void> _markAll() async {
    try {
      await ApiClient.loadToken();
      final token = ApiClient.token;
      await http.post(Uri.parse('https://schoolsmirror.com/fetch_data.php'), body: {'token': token, 'action': 'mark_read'});
      setState(() => _items = _items.map((m) => {...m, 'unread': false}).toList());
      widget.onRefresh();
    } catch (_) {}
  }

  Future<void> _delete(Map<String, dynamic> m) async {
    try {
      await ApiClient.loadToken();
      final token = ApiClient.token;
      await http.post(Uri.parse('https://schoolsmirror.com/fetch_data.php'), body: {'token': token, 'action': 'delete_message', 'id': '${m['id']}'});
      setState(() => _items.removeWhere((x) => x['id'] == m['id']));
      widget.onRefresh();
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: .75,
      maxChildSize: .95,
      minChildSize: .4,
      expand: false,
      builder: (_, controller) => SmSheetFrame(
        title: 'Messages & Notifications',
        subtitle: '${_items.length} message${_items.length == 1 ? '' : 's'}',
        icon: Icons.notifications_rounded,
        child: Column(children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: Align(alignment: Alignment.centerRight, child: TextButton.icon(onPressed: _markAll, icon: const Icon(Icons.done_all_rounded, size: 18, color: SM.orange), label: const Text('Mark all read', style: TextStyle(color: SM.orange, fontWeight: FontWeight.w700)))),
          ),
          Expanded(
            child: _items.isEmpty
                ? const Center(child: Text('No messages', style: TextStyle(color: SM.muted)))
                : ListView.builder(
                    controller: controller,
                    padding: const EdgeInsets.fromLTRB(14, 0, 14, 24),
                    itemCount: _items.length,
                    itemBuilder: (_, i) {
                      final m = _items[i];
                      final unread = m['unread'] == true;
                      final c = unread ? SM.cyan : SM.blueLight;
                      return Container(
                        margin: const EdgeInsets.only(bottom: 10),
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(color: SM.a(c, unread ? .12 : .05), borderRadius: BorderRadius.circular(18), border: Border(left: BorderSide(color: c, width: 3.5), top: BorderSide(color: SM.glassLine), right: BorderSide(color: SM.glassLine), bottom: BorderSide(color: SM.glassLine))),
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Row(children: [
                            Expanded(child: Text('${m['sender'] ?? ''}', style: const TextStyle(color: SM.text, fontWeight: FontWeight.w800, fontSize: 13.5))),
                            Text('${m['time_ago'] ?? ''}', style: const TextStyle(fontSize: 11.5, color: SM.muted)),
                          ]),
                          const SizedBox(height: 6),
                          Text('${m['message'] ?? ''}', style: const TextStyle(fontSize: 13.5, color: SM.muted, height: 1.4)),
                          Align(alignment: Alignment.centerRight, child: TextButton.icon(onPressed: () => _delete(m), icon: const Icon(Icons.delete_outline_rounded, size: 16, color: SM.rose), label: const Text('Delete', style: TextStyle(fontSize: 12, color: SM.rose)))),
                        ]),
                      );
                    },
                  ),
          ),
        ]),
      ),
    );
  }
}

// ════════════════════════════════════════════════════════════════════════════
//  CHART WIDGETS
// ════════════════════════════════════════════════════════════════════════════
class _Toggle extends StatelessWidget {
  final List<String> options;
  final int index;
  final ValueChanged<int> onChanged;
  const _Toggle({required this.options, required this.index, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(color: SM.a(Colors.white, .07), borderRadius: BorderRadius.circular(13), border: Border.all(color: SM.glassLine)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: List.generate(options.length, (i) {
          final sel = i == index;
          return GestureDetector(
            onTap: () => onChanged(i),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(gradient: sel ? SM.brand : null, borderRadius: BorderRadius.circular(10)),
              child: Text(options[i], style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: sel ? Colors.white : SM.muted)),
            ),
          );
        }),
      ),
    );
  }
}


void _paintText(Canvas canvas, String text, Offset pos, TextStyle style, {double ax = 0.5, double ay = 0.5, double maxWidth = 100}) {
  final tp = TextPainter(text: TextSpan(text: text, style: style), textDirection: TextDirection.ltr, maxLines: 1, ellipsis: '…')..layout(maxWidth: maxWidth);
  tp.paint(canvas, Offset(pos.dx - tp.width * ax, pos.dy - tp.height * ay));
}

class _CartesianPainter extends CustomPainter {
  final List<double> values;
  final List<String> labels;
  final List<Color> colors;
  final bool isLine;
  final double t;
  final String Function(double) fmt;

  _CartesianPainter({required this.values, required this.labels, required this.colors, required this.isLine, required this.t, required this.fmt});

  double _niceMax(double maxV) {
    if (maxV <= 0) return 4;
    final rawStep = maxV / 4;
    final mag = math.pow(10, (math.log(rawStep) / math.ln10).floor()).toDouble();
    final norm = rawStep / mag;
    final double nice = norm <= 1.0 ? 1.0 : norm <= 2.0 ? 2.0 : norm <= 2.5 ? 2.5 : norm <= 5.0 ? 5.0 : 10.0;
    return nice * mag * 4;
  }

  @override
  void paint(Canvas canvas, Size size) {
    const leftPad = 46.0, rightPad = 6.0, topPad = 22.0, bottomPad = 26.0;
    final chartW = size.width - leftPad - rightPad;
    final chartH = size.height - topPad - bottomPad;
    if (chartW <= 0 || chartH <= 0 || values.isEmpty) return;

    final maxV = _niceMax(values.reduce(math.max));
    final base = topPad + chartH;
    const axisStyle = TextStyle(fontSize: 10, color: _kMuted);
    final gridPaint = Paint()..color = _kBorder..strokeWidth = 1;

    for (var i = 0; i <= 4; i++) {
      final y = base - chartH * i / 4;
      canvas.drawLine(Offset(leftPad, y), Offset(size.width - rightPad, y), gridPaint);
      _paintText(canvas, fmt(maxV * i / 4), Offset(leftPad - 6, y), axisStyle, ax: 1, maxWidth: leftPad - 6);
    }

    final n = values.length;
    final slot = chartW / n;
    double xAt(int i) => leftPad + slot * (i + 0.5);
    double yAt(int i) => base - chartH * (values[i] / maxV) * t;

    for (var i = 0; i < n; i++) {
      _paintText(canvas, labels[i], Offset(xAt(i), base + 7), axisStyle, ay: 0, maxWidth: slot);
    }

    final labelOpacity = ((t - 0.6) / 0.4).clamp(0.0, 1.0).toDouble();
    final valueStyle = TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: _kDark.withOpacity(labelOpacity));

    if (isLine) {
      final pts = List.generate(n, (i) => Offset(xAt(i), yAt(i)));
      final path = Path()..moveTo(pts.first.dx, pts.first.dy);
      for (var i = 1; i < n; i++) {
        final mx = (pts[i - 1].dx + pts[i].dx) / 2;
        path.cubicTo(mx, pts[i - 1].dy, mx, pts[i].dy, pts[i].dx, pts[i].dy);
      }
      final fill = Path.from(path)..lineTo(pts.last.dx, base)..lineTo(pts.first.dx, base)..close();
      canvas.drawPath(fill, Paint()..shader = LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [_kPrimary.withOpacity(0.25), _kPrimary.withOpacity(0.0)]).createShader(Rect.fromLTWH(leftPad, topPad, chartW, chartH)));
      canvas.drawPath(path, Paint()..color = _kPrimary..style = PaintingStyle.stroke..strokeWidth = 3..strokeCap = StrokeCap.round);
      for (var i = 0; i < n; i++) {
        canvas.drawCircle(pts[i], 5, Paint()..color = Colors.white);
        canvas.drawCircle(pts[i], 5, Paint()..color = _kPrimary..style = PaintingStyle.stroke..strokeWidth = 2.5);
        _paintText(canvas, fmt(values[i]), Offset(pts[i].dx, pts[i].dy - 10), valueStyle, ay: 1, maxWidth: slot);
      }
    } else {
      final barW = math.min(slot * 0.58, 38.0);
      for (var i = 0; i < n; i++) {
        final h = chartH * (values[i] / maxV) * t;
        if (h > 0.5) {
          final rect = RRect.fromRectAndCorners(Rect.fromLTWH(xAt(i) - barW / 2, base - h, barW, h), topLeft: const Radius.circular(8), topRight: const Radius.circular(8));
          canvas.drawRRect(rect, Paint()..color = colors[i % colors.length]);
        }
        _paintText(canvas, fmt(values[i]), Offset(xAt(i), base - h - 4), valueStyle, ay: 1, maxWidth: slot);
      }
    }
  }

  @override
  bool shouldRepaint(covariant _CartesianPainter old) => old.t != t || old.isLine != isLine || old.values != values;
}

class _DonutPainter extends CustomPainter {
  final List<double> values;
  final double t;
  _DonutPainter({required this.values, required this.t});

  @override
  void paint(Canvas canvas, Size size) {
    const stroke = 24.0;
    final side = math.min(size.width, size.height);
    final rect = Rect.fromCenter(center: Offset(size.width / 2, size.height / 2), width: side - stroke, height: side - stroke);

    canvas.drawArc(rect, 0, math.pi * 2, false, Paint()..color = const Color(0x1AFFFFFF)..style = PaintingStyle.stroke..strokeWidth = stroke);

    final total = values.fold<double>(0, (a, b) => a + b);
    if (total <= 0) return;

    final gap = values.where((v) => v > 0).length > 1 ? 0.05 : 0.0;
    var start = -math.pi / 2;
    for (var i = 0; i < values.length; i++) {
      if (values[i] <= 0) continue;
      final sweep = math.pi * 2 * values[i] / total * t;
      canvas.drawArc(rect, start + gap / 2, math.max(0.0, sweep - gap), false, Paint()..color = _chartPalette[i % _chartPalette.length]..style = PaintingStyle.stroke..strokeWidth = stroke..strokeCap = StrokeCap.butt);
      start += sweep;
    }
  }

  @override
  bool shouldRepaint(covariant _DonutPainter old) => old.t != t || old.values != values;
}
