// flutter_promote_students_screen.dart
// Mirrors promote_students.php 1:1 (class selector, students list with select-all, Temporary vs
// Permanent options, target class + new session, "Promote Selected Students") and adds:
//   • DRAG & DROP: long-press a student (or any selected student to move ALL selected) and drop it on a
//     class chip in the bar at the bottom – a sheet confirms type / session / notification, then it moves.
//   • Notify students (in-app + push) toggle – the server tells the moved students.
// API: https://schoolsmirror.com/flutter_promotion.php   (needs flutter_promotion_common.dart)

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'flutter_promotion_common.dart';
import 'flutter_revert_promotions_screen.dart';
import 'flutter_promotion_history_screen.dart';

class FlutterPromoteStudentsScreen extends StatefulWidget {
  final String? token;
  const FlutterPromoteStudentsScreen({super.key, this.token});

  @override
  State<FlutterPromoteStudentsScreen> createState() => _FlutterPromoteStudentsScreenState();
}

class _FlutterPromoteStudentsScreenState extends State<FlutterPromoteStudentsScreen> {
  String? _token;

  List<Map<String, dynamic>> _classes = [];
  List<Map<String, dynamic>> _sessions = [];
  int _currentSessionId = 0;

  int? _classId;
  List<Map<String, dynamic>> _students = [];
  final Set<int> _selected = {};

  String _type = 'temporary'; // temporary | permanent
  int? _targetId;
  int? _sessionId;
  bool _notify = true;

  bool _loading = true;
  bool _loadingStudents = false;
  bool _saving = false;
  bool _dragging = false;
  String? _loadError;

  String? _msg;
  bool _msgError = false;
  List<String> _msgLines = [];

  final _scroll = ScrollController();

  @override
  void initState() {
    super.initState();
    _init();
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  // ───────────────────────────── data ─────────────────────────────
  Future<void> _init() async {
    setState(() {
      _loading = true;
      _loadError = null;
    });
    try {
      _token = await promoToken(widget.token);
      if (_token == null) throw Exception('Session expired. Please log in again.');
      await _loadData();
      if (!mounted) return;
      setState(() => _loading = false);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loadError = promoFriendly(e);
        _loading = false;
      });
    }
  }

  Future<void> _loadData() async {
    final r = await PromoApi.call(_token!, 'load_data');
    if (r['success'] != true) throw Exception(r['message'] ?? 'Failed to load');
    final d = (r['data'] as Map?) ?? {};
    if (!mounted) return;
    setState(() {
      _classes = pMaps(d['classes']);
      _sessions = pMaps(d['sessions']);
      _currentSessionId = pInt(d['current_session_id']);
      _sessionId ??= _currentSessionId == 0 ? null : _currentSessionId;
    });
  }

  Future<void> _loadStudents() async {
    if (_classId == null) return;
    setState(() {
      _loadingStudents = true;
      _students = [];
      _selected.clear();
    });
    try {
      final r = await PromoApi.call(_token!, 'load_students', {'class_id': '$_classId'});
      if (r['success'] != true) throw Exception(r['message'] ?? 'Failed to load students');
      if (!mounted) return;
      setState(() {
        _students = pMaps((r['data'] as Map?)?['students']);
        _loadingStudents = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loadingStudents = false;
        _msg = promoFriendly(e);
        _msgError = true;
        _msgLines = [];
      });
    }
  }

  String _className(int? id) {
    for (final c in _classes) {
      if (pInt(c['class_id']) == id) return '${c['class_name']}';
    }
    return '';
  }

  String _sessionName(int? id) {
    for (final s in _sessions) {
      if (pInt(s['id']) == id) return '${s['session_name']}';
    }
    return '';
  }

  // ───────────────────────────── promote ─────────────────────────────
  Future<void> _doPromote({
    required List<int> ids,
    required int targetId,
    required int sessionId,
    required String type,
    required bool notify,
  }) async {
    setState(() {
      _saving = true;
      _msg = null;
    });
    try {
      final fields = <String, String>{
        'target_class_id': '$targetId',
        'promotion_session_id': '$sessionId',
        'promotion_type': type,
        'notify': notify ? '1' : '0',
      };
      for (var i = 0; i < ids.length; i++) {
        fields['student_ids[$i]'] = '${ids[i]}';
      }
      final r = await PromoApi.call(_token!, 'promote', fields, false);
      if (!mounted) return;
      if (r['success'] != true) {
        setState(() {
          _msg = '${r['message']}';
          _msgError = true;
          _msgLines = [];
        });
        _scrollTop();
        return;
      }
      final d = (r['data'] as Map?) ?? {};
      final lines = <String>[];
      final n = d['notify'];
      if (n is Map) {
        lines.add('🔔 ${pInt(n['in_app'])} student(s) notified in the app');
        final ps = '${n['push_status']}';
        if (ps == 'ok') {
          lines.add('📲 Push sent: ${pInt(n['push_sent'])}${pInt(n['push_failed']) > 0 ? '  (failed: ${pInt(n['push_failed'])})' : ''}');
        } else if (ps == 'no_devices') {
          lines.add('📲 No registered devices to push to yet');
        } else if (ps == 'not_configured') {
          lines.add('📲 Push is not set up on the server yet (in-app notices were saved)');
        }
      }
      if (d['history_logged'] == false) lines.add('⚠ Could not write the promotion history row');
      setState(() {
        _msg = '${r['message']}';
        _msgError = false;
        _msgLines = lines;
        _selected.clear();
        _targetId = null;
      });
      HapticFeedback.mediumImpact();
      _scrollTop();
      await _loadData(); // refresh student counts
      await _loadStudents();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _msg = promoFriendly(e);
        _msgError = true;
        _msgLines = [];
      });
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _scrollTop() {
    if (_scroll.hasClients) _scroll.animateTo(0, duration: const Duration(milliseconds: 350), curve: Curves.easeOut);
  }

  /// the web form button
  Future<void> _submitForm() async {
    if (_selected.isEmpty) {
      setState(() {
        _msg = 'Please select at least one student.';
        _msgError = true;
        _msgLines = [];
      });
      _scrollTop();
      return;
    }
    if (_targetId == null || _sessionId == null) {
      setState(() {
        _msg = 'Please select target class and session.';
        _msgError = true;
        _msgLines = [];
      });
      _scrollTop();
      return;
    }
    final ok = await _confirm(_selected.length, _className(_targetId), _sessionName(_sessionId), _type);
    if (ok != true) return;
    await _doPromote(ids: _selected.toList(), targetId: _targetId!, sessionId: _sessionId!, type: _type, notify: _notify);
  }

  Future<bool?> _confirm(int n, String cls, String ses, String type) {
    final perm = type == 'permanent';
    return showDialog<bool>(
      context: context,
      builder: (ctx) => Theme(
        data: promoLightTheme(),
        child: AlertDialog(
          backgroundColor: Colors.white,
          surfaceTintColor: Colors.transparent,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: Column(children: [
            Icon(perm ? Icons.warning_amber_rounded : Icons.swap_horiz, size: 52, color: perm ? kRed600 : kGreen600),
            const SizedBox(height: 8),
            Text(perm ? 'Permanent Promotion?' : 'Temporary Transfer?', style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 20)),
          ]),
          content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text.rich(TextSpan(children: [
              TextSpan(text: '$n', style: const TextStyle(fontWeight: FontWeight.bold)),
              const TextSpan(text: ' student(s) will be moved to '),
              TextSpan(text: cls, style: const TextStyle(fontWeight: FontWeight.bold)),
              const TextSpan(text: ' for '),
              TextSpan(text: ses, style: const TextStyle(fontWeight: FontWeight.bold)),
              const TextSpan(text: '.'),
            ])),
            const SizedBox(height: 10),
            Text(
              perm ? 'Full move. Old results move with them. Use only at the end of the academic year.' : 'Old results remain safe and unchanged.',
              style: TextStyle(color: perm ? kRed600 : kGreen700, fontWeight: FontWeight.w600, fontSize: 13),
            ),
          ]),
          actionsAlignment: MainAxisAlignment.center,
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: perm ? kRed600 : kGreen600, foregroundColor: Colors.white),
              onPressed: () => Navigator.pop(ctx, true),
              child: Text(perm ? 'Yes, Promote' : 'Yes, Transfer'),
            ),
          ],
        ),
      ),
    );
  }

  // ───────────────────────────── drag & drop ─────────────────────────────
  List<int> _dragIds(int id) => (_selected.contains(id) && _selected.length > 1) ? _selected.toList() : [id];

  Future<void> _onDrop(Map<String, dynamic> cls, List<int> ids) async {
    if (ids.isEmpty) return;
    final targetId = pInt(cls['class_id']);
    var type = _type;
    var sessionId = _sessionId ?? (_sessions.isNotEmpty ? pInt(_sessions.first['id']) : 0);
    var notify = _notify;

    final go = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Theme(
        data: promoLightTheme(),
        child: StatefulBuilder(builder: (ctx, setS) {
          Widget typeTile(String value, String title, String sub, Color color) {
            final on = type == value;
            return Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: InkWell(
                borderRadius: BorderRadius.circular(14),
                onTap: () => setS(() => type = value),
                child: AccentCard(
                  accent: color,
                  thickness: 6,
                  radius: 14,
                  bg: on ? color.withOpacity(0.08) : Colors.white,
                  outline: on ? color : kGray200,
                  outlineWidth: 1.5,
                  padding: const EdgeInsets.all(12),
                  child: Row(children: [
                    Icon(on ? Icons.radio_button_checked : Icons.radio_button_off, color: color),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(title, style: TextStyle(fontWeight: FontWeight.w800, color: color, fontSize: 15)),
                        Text(sub, style: const TextStyle(fontSize: 12, color: kGray600)),
                      ]),
                    ),
                  ]),
                ),
              ),
            );
          }

          return Container(
            decoration: const BoxDecoration(color: Colors.white, borderRadius: BorderRadius.vertical(top: Radius.circular(26))),
            padding: EdgeInsets.fromLTRB(20, 12, 20, 20 + MediaQuery.of(ctx).viewInsets.bottom),
            child: SingleChildScrollView(
              child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                Center(child: Container(width: 44, height: 4, decoration: BoxDecoration(color: kGray200, borderRadius: BorderRadius.circular(2)))),
                const SizedBox(height: 14),
                Row(children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: const BoxDecoration(shape: BoxShape.circle, gradient: LinearGradient(colors: [kPurple600, kPink600])),
                    child: const Icon(Icons.drive_file_move, color: Colors.white, size: 20),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text.rich(TextSpan(style: const TextStyle(fontSize: 17), children: [
                      const TextSpan(text: 'Move '),
                      TextSpan(text: '${ids.length} student${ids.length == 1 ? '' : 's'}', style: const TextStyle(fontWeight: FontWeight.w800)),
                      const TextSpan(text: ' to '),
                      TextSpan(text: '${cls['class_name']}', style: const TextStyle(fontWeight: FontWeight.w800, color: kPurple700)),
                    ])),
                  ),
                ]),
                const SizedBox(height: 16),
                typeTile('temporary', 'Temporary Transfer (Recommended)', 'Old results remain safe and unchanged.', kGreen600),
                typeTile('permanent', 'Permanent Promotion', 'Full move. Use only at the end of the academic year.', kRed600),
                const SizedBox(height: 4),
                const Text('New Session', style: TextStyle(fontWeight: FontWeight.w700)),
                const SizedBox(height: 6),
                DropdownButtonFormField<int>(
                  value: _sessions.any((s) => pInt(s['id']) == sessionId) ? sessionId : null,
                  isExpanded: true,
                  decoration: promoSelectDecoration(kPurple300),
                  style: kFieldStyle,
                  dropdownColor: Colors.white,
                  hint: const Text('-- Select Session --'),
                  items: [for (final s in _sessions) DropdownMenuItem(value: pInt(s['id']), child: Text('${s['session_name']}'))],
                  onChanged: (v) => setS(() => sessionId = v ?? sessionId),
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  activeColor: kPurple600,
                  title: const Text('Notify students', style: TextStyle(fontWeight: FontWeight.w700)),
                  subtitle: const Text('Send an in-app notice and a push notification', style: TextStyle(fontSize: 12)),
                  value: notify,
                  onChanged: (v) => setS(() => notify = v),
                ),
                const SizedBox(height: 6),
                Row(children: [
                  Expanded(child: OutlinedButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel'))),
                  const SizedBox(width: 12),
                  Expanded(
                    flex: 2,
                    child: Container(
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(colors: [kPurple600, kPink600]),
                        borderRadius: BorderRadius.circular(30),
                      ),
                      child: Material(
                        color: Colors.transparent,
                        child: InkWell(
                          borderRadius: BorderRadius.circular(30),
                          onTap: () => Navigator.pop(ctx, true),
                          child: const Padding(
                            padding: EdgeInsets.symmetric(vertical: 14),
                            child: Center(child: Text('Move Now', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 15))),
                          ),
                        ),
                      ),
                    ),
                  ),
                ]),
              ]),
            ),
          );
        }),
      ),
    );

    if (go == true && sessionId > 0) {
      setState(() {
        _type = type;
        _sessionId = sessionId;
        _notify = notify;
      });
      await _doPromote(ids: ids, targetId: targetId, sessionId: sessionId, type: type, notify: notify);
    }
  }

  // ───────────────────────────── BUILD ─────────────────────────────
  @override
  Widget build(BuildContext context) {
    final hasStudents = _classId != null && _students.isNotEmpty;
    return Theme(
      data: promoLightTheme(),
      child: Scaffold(
        backgroundColor: kIndigo50,
        appBar: AppBar(
          elevation: 0,
          foregroundColor: Colors.white,
          surfaceTintColor: Colors.transparent,
          flexibleSpace: Container(decoration: const BoxDecoration(gradient: LinearGradient(colors: [kIndigo600, kPurple700]))),
          title: const Text('Promote Students', style: TextStyle(fontWeight: FontWeight.w800)),
          actions: [
            IconButton(tooltip: 'Promotion History', icon: const Icon(Icons.history), onPressed: _openHistory),
            IconButton(tooltip: 'Refresh', icon: const Icon(Icons.refresh), onPressed: _init),
          ],
        ),
        bottomNavigationBar: hasStudents ? _dropBar() : null,
        body: Container(
          decoration: const BoxDecoration(gradient: kPageGradient),
          child: _loading
              ? const Center(child: CircularProgressIndicator(color: kIndigo600))
              : _loadError != null
                  ? _errorBox()
                  : SingleChildScrollView(
                      controller: _scroll,
                      padding: const EdgeInsets.fromLTRB(14, 16, 14, 40),
                      child: Center(
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 1100),
                          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                            Wrap(alignment: WrapAlignment.center, spacing: 12, runSpacing: 12, children: [
                              PromoPillButton(
                                icon: Icons.undo,
                                label: 'Revert Promotions',
                                gradient: const LinearGradient(colors: [kRed600, kOrange600]),
                                onTap: _openRevert,
                              ),
                              PromoPillButton(icon: Icons.history, label: 'Promotion History', color: const Color(0xFF2563EB), onTap: _openHistory),
                            ]),
                            const SizedBox(height: 18),
                            PromoCard(
                              headerGradient: const LinearGradient(colors: [kIndigo600, kPurple700]),
                              title: 'Student Promotion System',
                              subtitle: 'Temporary Transfer = Safe Old Results | Permanent = Full Move',
                              child: _content(),
                            ),
                          ]),
                        ),
                      ),
                    ),
        ),
      ),
    );
  }

  void _openRevert() => Navigator.of(context).push(MaterialPageRoute(builder: (_) => FlutterRevertPromotionsScreen(token: widget.token)));
  void _openHistory() => Navigator.of(context).push(MaterialPageRoute(builder: (_) => FlutterPromotionHistoryScreen(token: widget.token)));

  Widget _errorBox() => Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const Icon(Icons.error_outline, color: kRed600, size: 44),
            const SizedBox(height: 10),
            Text(_loadError!, textAlign: TextAlign.center, style: const TextStyle(color: kRed600)),
            const SizedBox(height: 14),
            ElevatedButton.icon(
              style: ElevatedButton.styleFrom(backgroundColor: kIndigo600, foregroundColor: Colors.white),
              onPressed: _init,
              icon: const Icon(Icons.refresh),
              label: const Text('Retry'),
            ),
          ]),
        ),
      );

  Widget _content() {
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      if (_msg != null) PromoBanner(_msg!, error: _msgError, extraLines: _msgLines, onClose: () => setState(() => _msg = null)),
      // class selector
      const Text('Select Current Class', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: kGray700)),
      const SizedBox(height: 10),
      DropdownButtonFormField<int>(
        value: _classes.any((c) => pInt(c['class_id']) == _classId) ? _classId : null,
        isExpanded: true,
        decoration: promoSelectDecoration(kIndigo300, focus: kPurple600),
        style: kFieldStyle,
        dropdownColor: Colors.white,
        menuMaxHeight: 340,
        hint: const Text('-- Choose Class --'),
        items: [
          for (final c in _classes) DropdownMenuItem(value: pInt(c['class_id']), child: Text('${c['class_name']} (${c['active_count']} students)', overflow: TextOverflow.ellipsis)),
        ],
        onChanged: (v) {
          setState(() {
            _classId = v;
            _msg = null;
            _targetId = null;
          });
          _loadStudents();
        },
      ),
      const SizedBox(height: 24),
      if (_classId != null) ...[
        if (_loadingStudents)
          const Padding(padding: EdgeInsets.all(30), child: Center(child: CircularProgressIndicator(color: kPurple600)))
        else if (_students.isEmpty)
          Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(color: kGray100, borderRadius: BorderRadius.circular(16)),
            child: const Column(children: [
              Icon(Icons.group_off, size: 40, color: Color(0xFF9CA3AF)),
              SizedBox(height: 8),
              Text('No students in this class.', style: TextStyle(color: kGray600, fontWeight: FontWeight.w600)),
            ]),
          )
        else ...[
          Text.rich(TextSpan(style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: kGray800), children: [
            const TextSpan(text: 'Students Currently in: '),
            TextSpan(text: _className(_classId), style: const TextStyle(color: kPurple600)),
          ])),
          const SizedBox(height: 6),
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(color: kPurple50, borderRadius: BorderRadius.circular(12), border: Border.all(color: kPurple100)),
            child: const Row(children: [
              Icon(Icons.touch_app, size: 18, color: kPurple600),
              SizedBox(width: 8),
              Expanded(
                child: Text('Tip: long-press a student and drag onto a class in the bar at the bottom. Select several first to move them all.',
                    style: TextStyle(fontSize: 12.5, color: kPurple700)),
              ),
            ]),
          ),
          const SizedBox(height: 14),
          _studentsList(),
          const SizedBox(height: 24),
          _optionsPanel(),
        ],
      ],
    ]);
  }

  // ---------------------------- students ----------------------------
  Widget _studentsList() {
    final allIds = _students.map((s) => pInt(s['user_id'])).toList();
    final allSel = allIds.isNotEmpty && allIds.every(_selected.contains);
    return Container(
      decoration: BoxDecoration(borderRadius: BorderRadius.circular(18), border: Border.all(color: kGray200, width: 3)),
      clipBehavior: Clip.antiAlias,
      child: Column(children: [
        Container(
          padding: const EdgeInsets.fromLTRB(6, 6, 14, 6),
          decoration: const BoxDecoration(gradient: LinearGradient(colors: [kIndigo600, kPurple700])),
          child: Row(children: [
            Checkbox(
              value: allSel,
              activeColor: Colors.white,
              checkColor: kPurple700,
              side: const BorderSide(color: Colors.white, width: 2),
              onChanged: (v) => setState(() {
                if (v == true) {
                  _selected.addAll(allIds);
                } else {
                  _selected.clear();
                }
              }),
            ),
            const Text('Select All', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800)),
            const Spacer(),
            Text('${_selected.length}/${_students.length} selected', style: const TextStyle(color: Colors.white70, fontSize: 12.5, fontWeight: FontWeight.w600)),
          ]),
        ),
        for (var i = 0; i < _students.length; i++) _studentRow(_students[i], i),
      ]),
    );
  }

  Widget _studentRow(Map<String, dynamic> s, int i) {
    final id = pInt(s['user_id']);
    final sel = _selected.contains(id);
    final transferred = s['is_transferred'] == true;
    final ids = _dragIds(id);

    final row = Container(
      padding: const EdgeInsets.fromLTRB(4, 8, 8, 10),
      decoration: BoxDecoration(
        color: sel ? kPurple50 : (i.isOdd ? const Color(0xFFFAFAFC) : Colors.white),
        border: const Border(bottom: BorderSide(color: kGray200)),
      ),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Checkbox(
          value: sel,
          activeColor: kPurple600,
          onChanged: (v) => setState(() {
            if (v == true) {
              _selected.add(id);
            } else {
              _selected.remove(id);
            }
          }),
        ),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('${s['fullname']}', style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
              const SizedBox(height: 2),
              Text('Adm No: ${(s['admission_number'] ?? '').toString().isEmpty ? '—' : s['admission_number']}', style: const TextStyle(fontSize: 12.5, color: kGray600)),
              const SizedBox(height: 8),
              Wrap(spacing: 8, runSpacing: 6, crossAxisAlignment: WrapCrossAlignment.center, children: [
                Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
                  const Text('Result Class (never changes)', style: TextStyle(fontSize: 9.5, color: kGray600)),
                  const SizedBox(height: 2),
                  PromoPill('${s['original_class'] ?? '—'}', bg: kGreen100, fg: kGreen800),
                ]),
                Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
                  const Text('Current Class (live)', style: TextStyle(fontSize: 9.5, color: kGray600)),
                  const SizedBox(height: 2),
                  Row(mainAxisSize: MainAxisSize.min, children: [
                    PromoPill('${s['current_class'] ?? '—'}', bg: kBlue100, fg: kBlue800),
                    if (transferred) const Padding(padding: EdgeInsets.only(left: 6), child: Text('Transferred', style: TextStyle(color: kOrange600, fontSize: 11))),
                  ]),
                ]),
              ]),
              const SizedBox(height: 6),
              Text('Session: ${s['session_name'] ?? '—'}', style: const TextStyle(fontSize: 12, color: kGray600)),
            ]),
          ),
        ),
        const Padding(
          padding: EdgeInsets.only(top: 14, left: 4),
          child: Icon(Icons.drag_indicator, color: Color(0xFF9CA3AF)),
        ),
      ]),
    );

    return LongPressDraggable<List<int>>(
      data: ids,
      delay: const Duration(milliseconds: 220),
      dragAnchorStrategy: pointerDragAnchorStrategy,
      onDragStarted: () {
        HapticFeedback.selectionClick();
        setState(() => _dragging = true);
      },
      onDragEnd: (_) => setState(() => _dragging = false),
      feedback: Material(
        color: Colors.transparent,
        child: FractionalTranslation(
          translation: const Offset(-0.5, -1.4),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            decoration: BoxDecoration(
              gradient: const LinearGradient(colors: [kPurple600, kPink600]),
              borderRadius: BorderRadius.circular(30),
              boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.3), blurRadius: 16, offset: const Offset(0, 8))],
            ),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Icon(ids.length > 1 ? Icons.groups : Icons.person, color: Colors.white, size: 18),
              const SizedBox(width: 8),
              Text(ids.length > 1 ? '${ids.length} students' : '${s['fullname']}',
                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 14)),
            ]),
          ),
        ),
      ),
      childWhenDragging: Opacity(opacity: 0.35, child: row),
      child: row,
    );
  }

  // ---------------------------- promotion options ----------------------------
  Widget _optionCard(String value, String title, String l1, String l2, Color color) {
    final on = _type == value;
    return InkWell(
      borderRadius: BorderRadius.circular(18),
      onTap: () => setState(() => _type = value),
      child: AccentCard(
        accent: color,
        thickness: 8,
        radius: 18,
        outline: on ? color : Colors.transparent,
        outlineWidth: 2,
        padding: const EdgeInsets.all(16),
        shadow: [BoxShadow(color: Colors.black.withOpacity(0.12), blurRadius: 14, offset: const Offset(0, 6))],
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Icon(on ? Icons.radio_button_checked : Icons.radio_button_off, color: color, size: 28),
            const SizedBox(width: 10),
            Expanded(child: Text(title, style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: color))),
          ]),
          const SizedBox(height: 10),
          Text(l1, style: const TextStyle(color: kGray700, height: 1.4)),
          Text(l2, style: TextStyle(color: color, fontWeight: FontWeight.w800, height: 1.4)),
        ]),
      ),
    );
  }

  Widget _optionsPanel() {
    final targets = _classes.where((c) => pInt(c['class_id']) != _classId).toList();
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: const LinearGradient(colors: [kPurple100, kPink100]),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: kPurple300, width: 3),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        const Text('Choose Promotion Type', textAlign: TextAlign.center, style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800)),
        const SizedBox(height: 16),
        _optionCard('temporary', 'Temporary Transfer (Recommended)', 'Moves student to new class immediately.', 'Old results remain safe and unchanged.', kGreen600),
        const SizedBox(height: 14),
        _optionCard('permanent', 'Permanent Promotion', 'Full move to new class.', 'Use only at the end of the academic year.', kRed600),
        const SizedBox(height: 20),
        const Text('Target Class', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
        const SizedBox(height: 8),
        DropdownButtonFormField<int>(
          value: targets.any((c) => pInt(c['class_id']) == _targetId) ? _targetId : null,
          isExpanded: true,
          decoration: promoSelectDecoration(kPurple300, focus: kPurple600),
          style: kFieldStyle,
          dropdownColor: Colors.white,
          menuMaxHeight: 340,
          hint: const Text('-- Select New Class --'),
          items: [for (final c in targets) DropdownMenuItem(value: pInt(c['class_id']), child: Text('${c['class_name']}', overflow: TextOverflow.ellipsis))],
          onChanged: (v) => setState(() => _targetId = v),
        ),
        const SizedBox(height: 16),
        const Text('New Session', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
        const SizedBox(height: 8),
        DropdownButtonFormField<int>(
          value: _sessions.any((s) => pInt(s['id']) == _sessionId) ? _sessionId : null,
          isExpanded: true,
          decoration: promoSelectDecoration(kPurple300, focus: kPurple600),
          style: kFieldStyle,
          dropdownColor: Colors.white,
          menuMaxHeight: 340,
          hint: const Text('-- Select Session --'),
          items: [for (final s in _sessions) DropdownMenuItem(value: pInt(s['id']), child: Text('${s['session_name']}', overflow: TextOverflow.ellipsis))],
          onChanged: (v) => setState(() => _sessionId = v),
        ),
        const SizedBox(height: 8),
        Container(
          margin: const EdgeInsets.only(top: 8),
          decoration: BoxDecoration(color: Colors.white.withOpacity(0.7), borderRadius: BorderRadius.circular(16)),
          child: SwitchListTile(
            activeColor: kPurple600,
            title: const Text('Notify students', style: TextStyle(fontWeight: FontWeight.w800)),
            subtitle: const Text('In-app notice + push notification', style: TextStyle(fontSize: 12)),
            secondary: const Icon(Icons.notifications_active, color: kPurple600),
            value: _notify,
            onChanged: (v) => setState(() => _notify = v),
          ),
        ),
        const SizedBox(height: 22),
        Opacity(
          opacity: _saving ? 0.6 : 1,
          child: Container(
            decoration: BoxDecoration(
              gradient: const LinearGradient(colors: [kPurple600, kPink600]),
              borderRadius: BorderRadius.circular(40),
              boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.25), blurRadius: 18, offset: const Offset(0, 8))],
            ),
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                borderRadius: BorderRadius.circular(40),
                onTap: _saving ? null : _submitForm,
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 18),
                  child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                    if (_saving)
                      const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.white))
                    else
                      const Icon(Icons.trending_up, color: Colors.white),
                    const SizedBox(width: 10),
                    Text(_saving ? 'Processing...' : 'Promote Selected Students',
                        style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 17)),
                  ]),
                ),
              ),
            ),
          ),
        ),
      ]),
    );
  }

  // ---------------------------- drop bar (bottom) ----------------------------
  Widget _dropBar() {
    final targets = _classes.where((c) => pInt(c['class_id']) != _classId).toList();
    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      decoration: BoxDecoration(
        color: _dragging ? kPurple50 : Colors.white,
        border: Border(top: BorderSide(color: _dragging ? kPurple600 : kGray200, width: _dragging ? 3 : 1)),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.12), blurRadius: 16, offset: const Offset(0, -4))],
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 10),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Icon(_dragging ? Icons.south : Icons.drag_indicator, size: 16, color: kPurple600),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  _dragging ? 'Drop on a class to move the student(s)' : 'Drag students here ▸ pick a class',
                  style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 12.5, color: kPurple700),
                ),
              ),
            ]),
            const SizedBox(height: 8),
            SizedBox(
              height: 52,
              child: targets.isEmpty
                  ? const Center(child: Text('No other classes available', style: TextStyle(color: kGray600)))
                  : ListView.separated(
                      scrollDirection: Axis.horizontal,
                      itemCount: targets.length,
                      separatorBuilder: (_, __) => const SizedBox(width: 8),
                      itemBuilder: (_, i) => _dropChip(targets[i]),
                    ),
            ),
          ]),
        ),
      ),
    );
  }

  Widget _dropChip(Map<String, dynamic> c) {
    return DragTarget<List<int>>(
      onWillAcceptWithDetails: (_) => true,
      onAcceptWithDetails: (d) => _onDrop(c, d.data),
      builder: (context, candidate, rejected) {
        final hover = candidate.isNotEmpty;
        return AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.symmetric(horizontal: 16),
          constraints: const BoxConstraints(minWidth: 96),
          decoration: BoxDecoration(
            gradient: hover ? const LinearGradient(colors: [kPurple600, kPink600]) : null,
            color: hover ? null : (_dragging ? Colors.white : kGray100),
            borderRadius: BorderRadius.circular(26),
            border: Border.all(color: hover ? kPurple700 : (_dragging ? kPurple600 : kGray200), width: _dragging ? 2 : 1),
            boxShadow: hover ? [BoxShadow(color: kPurple600.withOpacity(0.4), blurRadius: 12, offset: const Offset(0, 4))] : null,
          ),
          alignment: Alignment.center,
          child: Column(mainAxisSize: MainAxisSize.min, mainAxisAlignment: MainAxisAlignment.center, children: [
            Text('${c['class_name']}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontWeight: FontWeight.w800, fontSize: 13.5, color: hover ? Colors.white : kGray800)),
            Text('${c['active_count']} students', style: TextStyle(fontSize: 10, color: hover ? Colors.white70 : kGray600)),
          ]),
        );
      },
    );
  }
}
