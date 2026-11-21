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
// import 'flutter_class_management_screen.dart';

// ════════════════════════════════════════════════════════════════════════════
//  THEME
// ════════════════════════════════════════════════════════════════════════════
const _kPrimary = Color(0xFF4361ee);
const _kViolet = Color(0xFF7c3aed);
const _kDark = Color(0xFF0f172a);
const _kBg = Color(0xFFf0f4ff);
const _kMuted = Color(0xFF64748b);
const _kBorder = Color(0xFFe2e8f0);
const _kGreen = Color(0xFF10b981);
const _kAmber = Color(0xFFf59e0b);
const _kRose = Color(0xFFf43f5e);
const _kCyan = Color(0xFF06b6d4);

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
    NavLeaf('Published Result', Icons.visibility, '/admin/published-results',
        roles: _adminRoles),
    NavLeaf('Result Audio', Icons.graphic_eq, '/admin/result-audio',
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

  bool _loading = true;
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
    _load();
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    if (_data == null) setState(() => _loading = true);
    setState(() => _error = null);
    try {
      // Force load the token into memory FIRST
      await ApiClient.loadToken();
      
      final token = ApiClient.token; // Get it from memory
      
      if (token == null || token.isEmpty) {
        throw Exception('No token found. Please log out and log back in.');
      }

      // Cache + persist so child screens (Add Student) always have it
      _sessionToken = token;
      try {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('auth_token', token);
        await prefs.setString('token', token);
      } catch (_) {}

      print("SENDING TOKEN TO PHP: $token"); // Look at this in Chrome DevTools!

      final url = Uri.parse('https://schoolsmirror.com/fetch_data.php?token=$token');
      final res = await http.get(url).timeout(const Duration(seconds: 15));
      final Map<String, dynamic> json = jsonDecode(res.body);
      if (!mounted) return;

      if (json['success'] == true && json['data'] != null) {
        setState(() {
          _data = Map<String, dynamic>.from(json['data']);
          _seed++;
        });
      } else {
        _fail(json['message'] ?? 'Failed to load dashboard');
      }
    } catch (e) {
      if (mounted) _fail('Network error: $e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _fail(String msg) {
    setState(() => _error = msg);
    if (_data != null) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
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

  String get _roleLabel => _role == _rAdmin
      ? 'Admin Panel'
      : (_role == _rSub ? 'Subadmin' : 'Teacher');

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
  //  BUILD
  // ════════════════════════════════════════════════════════════════════════
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      key: _scaffoldKey,
      backgroundColor: _kBg,
      drawer: _buildDrawer(),
      appBar: _buildAppBar(),
      body: Column(
        children: [
          if (_maint != null && _maint!['show_banner'] == true) _buildMaintenanceBanner(),
          Expanded(
            child: (_loading && _data == null)
                ? const Center(child: CircularProgressIndicator())
                : RefreshIndicator(
                    onRefresh: _load,
                    child: (_error != null && _data == null) ? _errorView() : _body(),
                  ),
          ),
        ],
      ),
    );
  }

  PreferredSizeWidget _buildAppBar() {
    final unread = _num(_stats['unread_messages']).toInt();
    final school = '${_user['schoolname'] ?? 'Admin'}';

    return AppBar(
      backgroundColor: Colors.white,
      elevation: 1,
      iconTheme: const IconThemeData(color: _kDark),
      // Explicit hamburger so the drawer always opens (nested navigators often hide the default)
      leading: IconButton(
        icon: const Icon(Icons.menu, color: _kDark),
        tooltip: 'Menu',
        onPressed: _openDrawer,
      ),
      title: const Text('Dashboard', style: TextStyle(color: _kDark, fontWeight: FontWeight.bold)),
      actions: [
        Container(
          margin: const EdgeInsets.only(right: 12),
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(color: _kGreen.withOpacity(0.1), borderRadius: BorderRadius.circular(12)),
          child: const Row(
            children: [
              Icon(Icons.circle, color: _kGreen, size: 8),
              SizedBox(width: 4),
              Text('Live', style: TextStyle(color: _kGreen, fontSize: 10, fontWeight: FontWeight.bold)),
            ],
          ),
        ),
        Stack(
          alignment: Alignment.center,
          children: [
            IconButton(
              icon: const Icon(Icons.notifications_outlined, color: _kDark),
              onPressed: _openMessages,
            ),
            if (unread > 0)
              Positioned(
                right: 6, top: 6,
                child: Container(
                  padding: const EdgeInsets.all(4),
                  decoration: const BoxDecoration(color: _kRose, shape: BoxShape.circle),
                  child: Text('$unread', style: const TextStyle(color: Colors.white, fontSize: 8, fontWeight: FontWeight.bold)),
                ),
              ),
          ],
        ),
        PopupMenuButton<String>(
          offset: const Offset(0, 50),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          itemBuilder: (context) => [
            const PopupMenuItem(value: 'profile', child: Row(children: [Icon(Icons.person, size: 18), SizedBox(width: 8), Text('Profile')])),
            const PopupMenuItem(value: 'logout', child: Row(children: [Icon(Icons.logout, color: Colors.red, size: 18), SizedBox(width: 8), Text('Logout', style: TextStyle(color: Colors.red))])),
          ],
          onSelected: (val) async {
            if (val == 'logout') {
              await ApiClient.logout();
              if (mounted) Navigator.of(context).pushReplacementNamed('/');
            } else {
              await _open(NavLeaf('Profile', Icons.person, '/admin/profile'));
            }
          },
          child: Padding(
            padding: const EdgeInsets.only(right: 16, left: 8),
            child: Row(
              children: [
                CircleAvatar(
                  radius: 18,
                  backgroundColor: _kPrimary.withOpacity(0.1),
                  child: const Icon(Icons.person, color: _kPrimary, size: 20),
                ),
                const SizedBox(width: 8),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(school, style: const TextStyle(color: _kDark, fontSize: 12, fontWeight: FontWeight.bold)),
                    Text(_roleLabel, style: const TextStyle(color: _kMuted, fontSize: 10)),
                  ],
                ),
                const Icon(Icons.arrow_drop_down, color: _kMuted, size: 16),
              ],
            ),
          ),
        ),
      ],
    );
  }

  // ── Maintenance Banner ──
  Widget _buildMaintenanceBanner() {
    final m = _maint!;
    final level = m['level'] ?? 'info';
    final days = (m['days_remaining'] ?? 0) as int;
    final amount = (m['amount'] ?? 0).toDouble();
    final renewal = (m['renewal_days'] ?? 0) as int;
    
    final color = level == 'danger'
        ? const Color(0xFF7f1d1d)
        : level == 'warning'
            ? const Color(0xFF92400e)
            : _kDark;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      color: color,
      child: Row(
        children: [
          Icon(days > 0 ? Icons.schedule : Icons.warning_amber_rounded, color: Colors.amber, size: 24),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  days > 0 ? 'Portal Maintenance Due in $days days' : 'PORTAL OVERDUE - Payment Required',
                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13),
                ),
                const SizedBox(height: 2),
                Text(
                  'Pay ₦${amount.toStringAsFixed(2)} to renew for $renewal days.',
                  style: const TextStyle(color: Colors.white70, fontSize: 11),
                ),
              ],
            ),
          ),
          TextButton(
            onPressed: () {},
            style: TextButton.styleFrom(backgroundColor: _kPrimary, foregroundColor: Colors.white),
            child: const Text('Pay Now', style: TextStyle(fontSize: 11)),
          ),
        ],
      ),
    );
  }

  Widget _errorView() {
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      children: [
        const SizedBox(height: 140),
        Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.error_outline, size: 48, color: Colors.red.shade400),
                const SizedBox(height: 12),
                Text(_error ?? '', textAlign: TextAlign.center),
                const SizedBox(height: 16),
                ElevatedButton(onPressed: _load, child: const Text('Retry')),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _body() {
    return LayoutBuilder(builder: (context, c) {
      final wide = c.maxWidth >= 800;
      final contentW = math.min(c.maxWidth, 1200.0) - 32;
      return SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(16),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 1200),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildPageHeader(),
                const SizedBox(height: 16),
                _buildWelcomeBanner(),
                const SizedBox(height: 16),
                _buildStatCards(wide),
                const SizedBox(height: 22),
                _buildQuickActions(),
                if (!_isTeacher) ...[
                  _buildCharts(wide),
                  const SizedBox(height: 22),
                ],
                _buildModules(contentW, wide),
                const SizedBox(height: 22),
                _buildRecentStudents(),
                const SizedBox(height: 24),
              ],
            ),
          ),
        ),
      );
    });
  }

  Widget _buildPageHeader() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Dashboard', style: TextStyle(fontSize: 24, fontWeight: FontWeight.w800, color: _kDark)),
              Text('${_data?['date'] ?? ''}', style: const TextStyle(color: _kMuted, fontSize: 13)),
            ],
          ),
        ),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: _kBorder),
          ),
          child: const Text('Home > Dashboard', style: TextStyle(color: _kMuted, fontSize: 12)),
        ),
      ],
    );
  }

  Widget _buildWelcomeBanner() {
    final school = '${_user['schoolname'] ?? 'Admin'}';
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: const LinearGradient(colors: [_kPrimary, _kViolet], begin: Alignment.topLeft, end: Alignment.bottomRight),
        borderRadius: BorderRadius.circular(18),
        boxShadow: [BoxShadow(color: _kPrimary.withOpacity(0.25), blurRadius: 18, offset: const Offset(0, 8))],
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Welcome back, $school! 👋', style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
                const SizedBox(height: 4),
                const Text("Here's what's happening with your school today.", style: TextStyle(color: Colors.white70, fontSize: 12)),
                const SizedBox(height: 10),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(color: Colors.white.withOpacity(0.18), borderRadius: BorderRadius.circular(20)),
                  child: Text(_roleLabel, style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w600)),
                ),
              ],
            ),
          ),
          Icon(Icons.school, size: 48, color: Colors.white.withOpacity(0.3)),
        ],
      ),
    );
  }

  Widget _buildStatCards(bool wide) {
    final cards = <Widget>[
      _statCard('Total Students', '${_num(_stats['total_students']).toInt()}', 'Registered students', Icons.people, Colors.blue),
      _statCard('Staff Members', '${_num(_stats['total_staff']).toInt()}', 'Teaching & admin', Icons.co_present, _kGreen),
    ];
    if (!_isTeacher) {
      cards.add(_statCard('Finalized Results', '${_num(_stats['finalized_results']).toInt()}', 'Completed assessments', Icons.file_copy, _kAmber));
      cards.add(_statCard('Total Revenue', '₦${_money(_num(_stats['total_revenue']))}', 'Student payments', Icons.monetization_on, _kRose));
    }
    return GridView.count(
      crossAxisCount: wide ? cards.length : 2,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      mainAxisSpacing: 12,
      crossAxisSpacing: 12,
      childAspectRatio: wide ? 2.2 : 1.35,
      children: cards,
    );
  }

  Widget _statCard(String title, String value, String sub, IconData icon, Color color) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16), border: Border.all(color: _kBorder)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(child: Text(title.toUpperCase(), maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: _kMuted))),
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(color: color.withOpacity(0.12), borderRadius: BorderRadius.circular(8)),
                child: Icon(icon, color: color, size: 16),
              ),
            ],
          ),
          FittedBox(fit: BoxFit.scaleDown, alignment: Alignment.centerLeft, child: Text(value, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: _kDark))),
          Row(
            children: [
              Container(width: 18, height: 4, decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(4))),
              const SizedBox(width: 6),
              Expanded(child: Text(sub, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 11, color: _kMuted))),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildQuickActions() {
    const wanted = ['Manage Users', 'Result Upload', 'Student Fees', 'Add Notice', 'Add Exam', 'Homework'];
    final items = <MapEntry<NavGroup, NavLeaf>>[];
    for (final title in wanted) {
      for (final g in _visibleGroups) {
        final hit = g.leavesFor(_role).where((l) => l.title == title);
        if (hit.isNotEmpty) { items.add(MapEntry(g, hit.first)); break; }
      }
    }
    if (items.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionTitle('Quick Actions'),
        const SizedBox(height: 10),
        SizedBox(
          height: 92,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: items.length,
            separatorBuilder: (_, __) => const SizedBox(width: 10),
            itemBuilder: (_, i) {
              final g = items[i].key;
              final l = items[i].value;
              return InkWell(
                borderRadius: BorderRadius.circular(16),
                onTap: () => _open(l),
                child: Container(
                  width: 92,
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16), border: Border.all(color: _kBorder)),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(color: g.color.withOpacity(0.12), borderRadius: BorderRadius.circular(10)),
                        child: Icon(l.icon, color: g.color, size: 20),
                      ),
                      const SizedBox(height: 6),
                      Text(l.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: _kDark)),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
        const SizedBox(height: 22),
      ],
    );
  }

  Widget _sectionTitle(String text, {Widget? trailing}) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(text, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: _kDark)),
        if (trailing != null) trailing,
      ],
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

  Widget _chartCard({required String title, required String subtitle, required Widget toggle, required Widget child}) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(18), border: Border.all(color: _kBorder)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: _kDark)),
                    const SizedBox(height: 2),
                    Text(subtitle, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 11, color: _kMuted)),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              toggle,
            ],
          ),
          const SizedBox(height: 16),
          child,
        ],
      ),
    );
  }

  // ════════════════════════════════════════════════════════════════════════
  //  ALL MODULES
  // ════════════════════════════════════════════════════════════════════════
  Widget _buildModules(double width, bool wide) {
    final q = (_query ?? '').trim().toLowerCase();
    final cardW = wide ? (width - 12) / 2 - 0.5 : width;
    final cards = <Widget>[];
    var linkCount = 0;

    for (final g in _visibleGroups) {
      var leaves = g.leavesFor(_role);
      if (q.isNotEmpty) {
        leaves = leaves.where((l) => 
          '${l.title}'.toLowerCase().contains(q) || 
          '${g.title}'.toLowerCase().contains(q)
        ).toList();
      }
      if (leaves.isEmpty) continue;
      linkCount += leaves.length;
      cards.add(SizedBox(width: cardW, child: _moduleCard(g, leaves)));
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionTitle('All Modules', trailing: Text('$linkCount links', style: const TextStyle(fontSize: 12, color: _kMuted))),
        const SizedBox(height: 10),
        TextField(
          controller: _search,
          onChanged: (v) => setState(() => _query = v),
          decoration: InputDecoration(
            hintText: 'Search pages…',
            hintStyle: const TextStyle(fontSize: 13, color: _kMuted),
            prefixIcon: const Icon(Icons.search, size: 20, color: _kMuted),
            suffixIcon: _query.isEmpty ? null : IconButton(
              icon: const Icon(Icons.close, size: 18),
              onPressed: () { _search.clear(); setState(() => _query = ''); },
            ),
            filled: true,
            fillColor: Colors.white,
            contentPadding: const EdgeInsets.symmetric(vertical: 0),
            enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: _kBorder)),
            focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: _kPrimary)),
          ),
        ),
        const SizedBox(height: 12),
        if (cards.isEmpty)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(28),
            decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16), border: Border.all(color: _kBorder)),
            child: const Center(child: Text('No pages match your search', style: TextStyle(color: _kMuted))),
          )
        else
          Wrap(spacing: 12, runSpacing: 12, children: cards),
      ],
    );
  }

  Widget _moduleCard(NavGroup g, List<NavLeaf> leaves) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16), border: Border.all(color: _kBorder)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(color: g.color.withOpacity(0.12), borderRadius: BorderRadius.circular(10)),
                child: Icon(g.icon, color: g.color, size: 18),
              ),
              const SizedBox(width: 10),
              Expanded(child: Text(g.title, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: _kDark))),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(color: g.color.withOpacity(0.1), borderRadius: BorderRadius.circular(10)),
                child: Text('${leaves.length}', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: g.color)),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Wrap(spacing: 8, runSpacing: 8, children: leaves.map((l) => _linkChip(g, l)).toList()),
        ],
      ),
    );
  }

  Widget _linkChip(NavGroup g, NavLeaf l) {
    return Material(
      color: g.color.withOpacity(0.07),
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: () => _open(l),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(l.icon, size: 15, color: g.color),
              const SizedBox(width: 6),
              Flexible(child: Text(l.title, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: _kDark))),
              if (l.isNew) ...[
                const SizedBox(width: 6),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                  decoration: BoxDecoration(color: _kGreen, borderRadius: BorderRadius.circular(4)),
                  child: const Text('NEW', style: TextStyle(color: Colors.white, fontSize: 8, fontWeight: FontWeight.bold)),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  // ════════════════════════════════════════════════════════════════════════
  //  RECENT STUDENTS
  // ════════════════════════════════════════════════════════════════════════
  Widget _buildRecentStudents() {
    return Container(
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16), border: Border.all(color: _kBorder)),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Row(
                  children: [
                    Icon(Icons.school, color: _kPrimary, size: 20),
                    SizedBox(width: 8),
                    Text('Recent Students', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: _kDark)),
                  ],
                ),
                TextButton(
                  onPressed: () { final leaf = _findLeaf('Manage Users'); if (leaf != null) _open(leaf); },
                  child: const Text('View All'),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          if (_students.isEmpty)
            Padding(
              padding: const EdgeInsets.all(32),
              child: Column(
                children: [
                  Icon(Icons.person_off_outlined, size: 48, color: Colors.grey.shade300),
                  const SizedBox(height: 12),
                  const Text('No students added yet', style: TextStyle(color: _kMuted)),
                ],
              ),
            )
          else
            Column(
              children: _students.map<Widget>((s) {
                final m = Map<String, dynamic>.from(s);
                final img = '${m['image_url'] ?? ''}';
                return ListTile(
                  leading: CircleAvatar(
                    backgroundColor: _kPrimary.withOpacity(0.1),
                    backgroundImage: img.isNotEmpty ? NetworkImage(img) : null,
                    onBackgroundImageError: img.isNotEmpty ? (exception, stackTrace) {} : null,
                    child: img.isEmpty 
                        ? const Icon(Icons.person, color: _kPrimary) 
                        : null,
                  ),
                  title: Text('${m['fullname'] ?? ''}', style: const TextStyle(fontWeight: FontWeight.w600, color: _kDark)),
                  subtitle: Text('${m['department'] ?? '-'} • ${m['class_name'] ?? '-'}', style: const TextStyle(fontSize: 12, color: _kMuted)),
                  trailing: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(color: Colors.green.withOpacity(0.1), borderRadius: BorderRadius.circular(8)),
                    child: const Text('Active', style: TextStyle(fontSize: 10, color: Colors.green)),
                  ),
                );
              }).toList(),
            ),
        ],
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
          showModalBottomSheet(
            context: context,
            isScrollControlled: true,
            backgroundColor: Colors.transparent,
            builder: (_) => _MessagesSheet(messages: messages, onRefresh: _load),
          );
        }
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error loading messages: $e')));
    }
  }

  // ════════════════════════════════════════════════════════════════════════
  //  DRAWER
  // ════════════════════════════════════════════════════════════════════════
  Widget _buildDrawer() {
    final groups = _visibleGroups;
    return Drawer(
      backgroundColor: Colors.white, 
      child: Column(
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.only(top: 50, bottom: 20, left: 20),
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                  colors: [_kPrimary, Color(0xFF3a0ca3)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const CircleAvatar(
                    radius: 30,
                    backgroundColor: Colors.white24,
                    child: Icon(Icons.school, color: Colors.white, size: 30)),
                const SizedBox(height: 12),
                Text('${_user['schoolname'] ?? 'Admin Panel'}',
                    style: const TextStyle(
                        color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
                Text(_roleLabel,
                    style: const TextStyle(color: Colors.white70, fontSize: 12)),
              ],
            ),
          ),
          Expanded(
            child: Theme(
              data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
              child: ListView(
                padding: EdgeInsets.zero,
                children: [
                  ListTile(
                    leading: const Icon(Icons.dashboard, color: _kPrimary),
                    title: const Text('Dashboard', style: TextStyle(fontSize: 14, color: _kDark, fontWeight: FontWeight.w500)),
                    selected: true,
                    selectedTileColor: _kPrimary.withOpacity(0.08),
                    onTap: () => Navigator.of(context).pop(),
                  ),
                  const Padding(
                    padding: EdgeInsets.only(left: 16, top: 16, bottom: 8),
                    child: Text('NAVIGATION',
                        style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                            color: _kMuted,
                            letterSpacing: 1.2)),
                  ),
                  for (final g in groups) _drawerGroup(g),
                ],
              ),
            ),
          ),
          const Divider(height: 1),
          ListTile(
            leading: const Icon(Icons.logout, color: Colors.red),
            title: const Text('Logout', style: TextStyle(color: Colors.red)),
            onTap: () async {
              await ApiClient.logout();
              if (mounted) Navigator.of(context).pushReplacementNamed('/');
            },
          ),
          const SizedBox(height: 20),
        ],
      ),
    );
  }

  Widget _drawerGroup(NavGroup g) {
    final leaves = g.leavesFor(_role);
    if (g.flat && leaves.length == 1) {
      final l = leaves.first;
      return ListTile(
        leading: Icon(g.icon, size: 20, color: g.color),
        title: Row(
          children: [
            Text(l.title, style: const TextStyle(fontSize: 14, color: _kDark)),
            if (l.isNew) ...[
              const SizedBox(width: 6),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                decoration: BoxDecoration(
                    color: _kGreen, borderRadius: BorderRadius.circular(4)),
                child: const Text('NEW',
                    style: TextStyle(
                        color: Colors.white, fontSize: 8, fontWeight: FontWeight.bold)),
              ),
            ],
          ],
        ),
        onTap: () => _open(l),
      );
    }
    return ExpansionTile(
      leading: Icon(g.icon, size: 20, color: g.color),
      title: Text(g.title, style: const TextStyle(fontSize: 14, color: _kDark)),
      iconColor: g.color,
      collapsedIconColor: _kMuted,
      childrenPadding: EdgeInsets.zero,
      children: [
        for (final l in leaves)
          ListTile(
            dense: true,
            contentPadding: const EdgeInsets.only(left: 46, right: 16),
            leading: Icon(l.icon, size: 16, color: _kMuted),
            title: Row(
              children: [
                Flexible(
                  child: Text(l.title,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 13, color: _kMuted)),
                ),
                if (l.isNew) ...[
                  const SizedBox(width: 6),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                    decoration: BoxDecoration(
                        color: _kGreen, borderRadius: BorderRadius.circular(4)),
                    child: const Text('NEW',
                        style: TextStyle(
                            color: Colors.white,
                            fontSize: 8,
                            fontWeight: FontWeight.bold)),
                  ),
                ],
              ],
            ),
            onTap: () => _open(l),
          ),
      ],
    );
  }
}

// ════════════════════════════════════════════════════════════════════════════
//  MESSAGES SHEET WIDGET
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

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.7,
      maxChildSize: 0.95,
      minChildSize: 0.4,
      expand: false,
      builder: (_, controller) => Container(
        decoration: const BoxDecoration(color: Colors.white, borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
        child: Column(
          children: [
            const SizedBox(height: 10),
            Container(width: 40, height: 4, decoration: BoxDecoration(color: Colors.grey.shade300, borderRadius: BorderRadius.circular(2))),
            const SizedBox(height: 12),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text('Messages & Notifications', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                  TextButton(
                    onPressed: () async {
                      try {
                        await ApiClient.loadToken();
                        final token = ApiClient.token;
                        await http.post(Uri.parse('https://schoolsmirror.com/fetch_data.php'), body: {'token': token, 'action': 'mark_read'});
                        setState(() => _items = _items.map((m) => {...m, 'unread': false}).toList());
                        widget.onRefresh();
                      } catch (_) {}
                    },
                    child: const Text('Mark all read'),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: _items.isEmpty
                  ? const Center(child: Text('No messages', style: TextStyle(color: Colors.grey)))
                  : ListView.builder(
                      controller: controller,
                      itemCount: _items.length,
                      itemBuilder: (_, i) {
                        final m = _items[i];
                        final unread = m['unread'] == true;
                        return Container(
                          margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: unread ? const Color(0xFFeff6ff) : Colors.grey.shade50,
                            borderRadius: BorderRadius.circular(12),
                            border: Border(left: BorderSide(color: unread ? _kCyan : _kPrimary, width: 3)),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  Text(m['sender'] ?? '', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                                  Text(m['time_ago'] ?? '', style: const TextStyle(fontSize: 11, color: Colors.grey)),
                                ],
                              ),
                              const SizedBox(height: 6),
                              Text(m['message'] ?? '', style: const TextStyle(fontSize: 13, color: Color(0xFF475569))),
                              const SizedBox(height: 6),
                              Align(
                                alignment: Alignment.centerRight,
                                child: TextButton.icon(
                                  onPressed: () async {
                                    try {
                                      await ApiClient.loadToken();
                                      final token = ApiClient.token;
                                      await http.post(Uri.parse('https://schoolsmirror.com/fetch_data.php'), body: {'token': token, 'action': 'delete_message', 'message_id': m['id'].toString()});
                                      setState(() => _items.removeWhere((x) => x['id'] == m['id']));
                                      widget.onRefresh();
                                    } catch (_) {}
                                  },
                                  icon: const Icon(Icons.delete_outline, size: 14, color: Colors.red),
                                  label: const Text('Delete', style: TextStyle(fontSize: 11, color: Colors.red)),
                                ),
                              ),
                            ],
                          ),
                        );
                      },
                    ),
            ),
          ],
        ),
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
      decoration: BoxDecoration(color: const Color(0xFFf1f5f9), borderRadius: BorderRadius.circular(10)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: List.generate(options.length, (i) {
          final sel = i == index;
          return GestureDetector(
            onTap: () => onChanged(i),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: sel ? Colors.white : Colors.transparent,
                borderRadius: BorderRadius.circular(8),
                boxShadow: sel ? [BoxShadow(color: Colors.black.withOpacity(0.08), blurRadius: 4)] : null,
              ),
              child: Text(options[i], style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: sel ? _kPrimary : _kMuted)),
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

    canvas.drawArc(rect, 0, math.pi * 2, false, Paint()..color = const Color(0xFFf1f5f9)..style = PaintingStyle.stroke..strokeWidth = stroke);

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