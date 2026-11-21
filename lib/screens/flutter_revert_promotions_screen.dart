// flutter_revert_promotions_screen.dart
// Mirrors revert_promotions.php 1:1: class selector, "Promotion History in: <class>" list with
// Original / Current class, Transferred|Promoted badge, last promotion date, Has Results,
// "Revert All in This Class" card, select-all, info + warning panels, "Revert Selected Students".
// Fix vs the web page: a permanent promotion is reverted to the class stored in promotion_history
// (the web page tried to "revert" to the class the student is already in). Students whose original
// class cannot be found are marked and skipped instead of being reported as reverted.
// API: https://schoolsmirror.com/flutter_promotion.php   (needs flutter_promotion_common.dart)

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'flutter_promotion_common.dart';
import 'flutter_promote_students_screen.dart';

class FlutterRevertPromotionsScreen extends StatefulWidget {
  final String? token;
  const FlutterRevertPromotionsScreen({super.key, this.token});

  @override
  State<FlutterRevertPromotionsScreen> createState() => _FlutterRevertPromotionsScreenState();
}

class _FlutterRevertPromotionsScreenState extends State<FlutterRevertPromotionsScreen> {
  String? _token;
  List<Map<String, dynamic>> _classes = [];
  int? _classId;
  List<Map<String, dynamic>> _students = [];
  final Set<int> _selected = {};

  bool _loading = true;
  bool _loadingStudents = false;
  bool _saving = false;
  String? _loadError;

  String? _msg;
  bool _msgError = false;
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
      await _loadClasses();
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

  Future<void> _loadClasses() async {
    final r = await PromoApi.call(_token!, 'load_data');
    if (r['success'] != true) throw Exception(r['message'] ?? 'Failed to load');
    if (!mounted) return;
    setState(() => _classes = pMaps((r['data'] as Map?)?['classes']));
  }

  Future<void> _loadStudents() async {
    if (_classId == null) return;
    setState(() {
      _loadingStudents = true;
      _students = [];
      _selected.clear();
    });
    try {
      final r = await PromoApi.call(_token!, 'load_revert', {'class_id': '$_classId'});
      if (r['success'] != true) throw Exception(r['message'] ?? 'Failed to load');
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
      });
    }
  }

  String _className(int? id) {
    for (final c in _classes) {
      if (pInt(c['class_id']) == id) return '${c['class_name']}';
    }
    return '';
  }

  // ───────────────────────────── revert ─────────────────────────────
  Future<bool> _confirm(String title, String text) async {
    final r = await showDialog<bool>(
      context: context,
      builder: (ctx) => Theme(
        data: promoLightTheme(),
        child: AlertDialog(
          backgroundColor: Colors.white,
          surfaceTintColor: Colors.transparent,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: Column(children: [
            const Icon(Icons.undo, size: 48, color: kRed600),
            const SizedBox(height: 8),
            Text(title, textAlign: TextAlign.center, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 19)),
          ]),
          content: Text(text, textAlign: TextAlign.center),
          actionsAlignment: MainAxisAlignment.center,
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: kRed600, foregroundColor: Colors.white),
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Yes, Revert'),
            ),
          ],
        ),
      ),
    );
    return r == true;
  }

  Future<void> _revert({required bool all}) async {
    if (!all && _selected.isEmpty) {
      setState(() {
        _msg = 'Please select at least one student to revert.';
        _msgError = true;
      });
      _scrollTop();
      return;
    }
    final ok = await _confirm(
      all ? 'Revert ALL in this class?' : 'Revert selected students?',
      all
          ? 'Are you sure you want to revert ALL promotions/transfers in this class? This action cannot be undone.'
          : 'Are you sure you want to revert the selected students? This action cannot be undone.',
    );
    if (!ok) return;

    setState(() {
      _saving = true;
      _msg = null;
    });
    try {
      final Map<String, String> fields;
      if (all) {
        fields = {'class_id': '$_classId'};
      } else {
        final ids = _selected.toList();
        fields = {for (var i = 0; i < ids.length; i++) 'student_ids[$i]': '${ids[i]}'};
      }
      final r = await PromoApi.call(_token!, all ? 'revert_all' : 'revert', fields, false);
      if (!mounted) return;
      setState(() {
        _msg = '${r['message']}';
        _msgError = r['success'] != true;
      });
      if (r['success'] == true) HapticFeedback.mediumImpact();
      _scrollTop();
      await _loadClasses();
      await _loadStudents();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _msg = promoFriendly(e);
        _msgError = true;
      });
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _scrollTop() {
    if (_scroll.hasClients) _scroll.animateTo(0, duration: const Duration(milliseconds: 350), curve: Curves.easeOut);
  }

  void _goPromote() => Navigator.of(context).pushReplacement(MaterialPageRoute(builder: (_) => FlutterPromoteStudentsScreen(token: widget.token)));

  // ───────────────────────────── BUILD ─────────────────────────────
  @override
  Widget build(BuildContext context) {
    return Theme(
      data: promoLightTheme(),
      child: Scaffold(
        backgroundColor: kIndigo50,
        appBar: AppBar(
          elevation: 0,
          foregroundColor: Colors.white,
          surfaceTintColor: Colors.transparent,
          flexibleSpace: Container(decoration: const BoxDecoration(gradient: LinearGradient(colors: [kRed600, kOrange600]))),
          title: const Text('Revert Promotions', style: TextStyle(fontWeight: FontWeight.w800)),
          actions: [IconButton(tooltip: 'Refresh', icon: const Icon(Icons.refresh), onPressed: _init)],
        ),
        body: Container(
          decoration: const BoxDecoration(gradient: kPageGradient),
          child: _loading
              ? const Center(child: CircularProgressIndicator(color: kRed600))
              : _loadError != null
                  ? Center(
                      child: Padding(
                        padding: const EdgeInsets.all(24),
                        child: Column(mainAxisSize: MainAxisSize.min, children: [
                          const Icon(Icons.error_outline, color: kRed600, size: 44),
                          const SizedBox(height: 10),
                          Text(_loadError!, textAlign: TextAlign.center, style: const TextStyle(color: kRed600)),
                          const SizedBox(height: 14),
                          ElevatedButton.icon(
                            style: ElevatedButton.styleFrom(backgroundColor: kRed600, foregroundColor: Colors.white),
                            onPressed: _init,
                            icon: const Icon(Icons.refresh),
                            label: const Text('Retry'),
                          ),
                        ]),
                      ),
                    )
                  : SingleChildScrollView(
                      controller: _scroll,
                      padding: const EdgeInsets.fromLTRB(14, 16, 14, 40),
                      child: Center(
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 1100),
                          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                            Center(
                              child: PromoPillButton(icon: Icons.swap_horiz, label: 'Back to Promotion', color: const Color(0xFF28A745), onTap: _goPromote),
                            ),
                            const SizedBox(height: 18),
                            PromoCard(
                              headerGradient: const LinearGradient(colors: [kRed600, kOrange600]),
                              title: 'Revert Student Promotions',
                              subtitle: 'Undo incorrect promotions or transfers',
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

  Widget _content() {
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      if (_msg != null) PromoBanner(_msg!, error: _msgError, onClose: () => setState(() => _msg = null)),
      const Text('Select Class to View Promotions', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: kGray700)),
      const SizedBox(height: 10),
      DropdownButtonFormField<int>(
        value: _classes.any((c) => pInt(c['class_id']) == _classId) ? _classId : null,
        isExpanded: true,
        decoration: promoSelectDecoration(kRed300, focus: kRed600),
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
          });
          _loadStudents();
        },
      ),
      const SizedBox(height: 24),
      if (_classId != null)
        if (_loadingStudents)
          const Padding(padding: EdgeInsets.all(30), child: Center(child: CircularProgressIndicator(color: kRed600)))
        else if (_students.isEmpty)
          _emptyInfo()
        else ...[
          Text.rich(TextSpan(style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: kGray800), children: [
            const TextSpan(text: 'Promotion History in: '),
            TextSpan(text: _className(_classId), style: const TextStyle(color: kRed600)),
            TextSpan(text: '  (${_students.length} promoted/transferred student(s))', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.normal, color: kGray600)),
          ])),
          const SizedBox(height: 16),
          _bulkCard(),
          const SizedBox(height: 18),
          _studentsList(),
          const SizedBox(height: 24),
          _revertPanel(),
        ],
    ]);
  }

  Widget _emptyInfo() => Container(
        padding: const EdgeInsets.all(28),
        decoration: BoxDecoration(color: const Color(0xFFEFF6FF), borderRadius: BorderRadius.circular(18), border: Border.all(color: const Color(0xFFBFDBFE), width: 2)),
        child: Column(children: [
          const Icon(Icons.info, size: 56, color: Color(0xFF60A5FA)),
          const SizedBox(height: 14),
          const Text('No Promotions Found', textAlign: TextAlign.center, style: TextStyle(fontSize: 24, fontWeight: FontWeight.w800, color: Color(0xFF1E40AF))),
          const SizedBox(height: 8),
          const Text('There are no promoted or transferred students in this class.', textAlign: TextAlign.center, style: TextStyle(fontSize: 15, color: Color(0xFF1D4ED8))),
          const SizedBox(height: 18),
          PromoPillButton(
            icon: Icons.swap_horiz,
            label: 'Go to Promotion Page',
            gradient: const LinearGradient(colors: [Color(0xFF2563EB), kIndigo600]),
            onTap: _goPromote,
          ),
        ]),
      );

  Widget _bulkCard() => Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(color: kYellow50, borderRadius: BorderRadius.circular(18), border: Border.all(color: kYellow300, width: 2)),
        child: LayoutBuilder(builder: (context, c) {
          final info = Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('Revert All in This Class', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: kYellow800)),
            const SizedBox(height: 4),
            const Text('This will revert ALL promoted/transferred students in this class back to their original classes.', style: TextStyle(color: kYellow700, fontSize: 13.5)),
          ]);
          final btn = _bigButton('Revert All', Icons.undo, _saving ? null : () => _revert(all: true), small: true);
          return c.maxWidth > 560
              ? Row(children: [Expanded(child: info), const SizedBox(width: 16), btn])
              : Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [info, const SizedBox(height: 12), btn]);
        }),
      );

  Widget _bigButton(String label, IconData icon, VoidCallback? onTap, {bool small = false, bool busy = false}) => Opacity(
        opacity: onTap == null ? 0.6 : 1,
        child: Container(
          decoration: BoxDecoration(
            gradient: const LinearGradient(colors: [kRed600, kOrange600]),
            borderRadius: BorderRadius.circular(40),
            boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.25), blurRadius: small ? 10 : 18, offset: Offset(0, small ? 4 : 8))],
          ),
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              borderRadius: BorderRadius.circular(40),
              onTap: onTap,
              child: Padding(
                padding: EdgeInsets.symmetric(horizontal: small ? 26 : 20, vertical: small ? 12 : 18),
                child: Row(mainAxisSize: MainAxisSize.min, mainAxisAlignment: MainAxisAlignment.center, children: [
                  if (busy)
                    const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.white))
                  else
                    Icon(icon, color: Colors.white, size: small ? 18 : 22),
                  const SizedBox(width: 10),
                  Flexible(child: Text(label, style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: small ? 15 : 17))),
                ]),
              ),
            ),
          ),
        ),
      );

  // ---------------------------- list ----------------------------
  Widget _studentsList() {
    final revertable = _students.where((s) => s['can_revert'] == true).map((s) => pInt(s['user_id'])).toList();
    final allSel = revertable.isNotEmpty && revertable.every(_selected.contains);
    return Container(
      decoration: BoxDecoration(borderRadius: BorderRadius.circular(18), border: Border.all(color: kGray200, width: 3)),
      clipBehavior: Clip.antiAlias,
      child: Column(children: [
        Container(
          padding: const EdgeInsets.fromLTRB(6, 6, 14, 6),
          decoration: const BoxDecoration(gradient: LinearGradient(colors: [kRed600, kOrange600])),
          child: Row(children: [
            Checkbox(
              value: allSel,
              activeColor: Colors.white,
              checkColor: kRed600,
              side: const BorderSide(color: Colors.white, width: 2),
              onChanged: revertable.isEmpty
                  ? null
                  : (v) => setState(() {
                        if (v == true) {
                          _selected.addAll(revertable);
                        } else {
                          _selected.clear();
                        }
                      }),
            ),
            const Text('Select All', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800)),
            const Spacer(),
            Text('${_selected.length} selected', style: const TextStyle(color: Colors.white70, fontSize: 12.5, fontWeight: FontWeight.w600)),
          ]),
        ),
        for (var i = 0; i < _students.length; i++) _row(_students[i], i),
      ]),
    );
  }

  Widget _statusBadge(String status) {
    if (status == 'transferred') return const PromoPill('Transferred', bg: Color(0xFFFEF3C7), fg: Color(0xFF92400E), icon: Icons.swap_horiz);
    if (status == 'promoted') return const PromoPill('Promoted', bg: Color(0xFFDCFCE7), fg: Color(0xFF166534), icon: Icons.school);
    return const PromoPill('Unknown', bg: kGray100, fg: kGray800);
  }

  Widget _row(Map<String, dynamic> s, int i) {
    final id = pInt(s['user_id']);
    final can = s['can_revert'] == true;
    final sel = _selected.contains(id);
    final hasResults = pInt(s['has_results']) > 0;
    final adm = '${s['admission_number'] ?? ''}';
    return InkWell(
      onTap: can
          ? () => setState(() {
                if (sel) {
                  _selected.remove(id);
                } else {
                  _selected.add(id);
                }
              })
          : null,
      child: Container(
        padding: const EdgeInsets.fromLTRB(4, 8, 12, 12),
        decoration: BoxDecoration(
          color: sel ? kRed100.withOpacity(0.5) : (i.isOdd ? const Color(0xFFFAFAFC) : Colors.white),
          border: const Border(bottom: BorderSide(color: kGray200)),
        ),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Checkbox(
            value: sel,
            activeColor: kRed600,
            onChanged: can
                ? (v) => setState(() {
                      if (v == true) {
                        _selected.add(id);
                      } else {
                        _selected.remove(id);
                      }
                    })
                : null,
          ),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('${s['fullname']}', style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
                Text('Adm No: ${adm.isEmpty ? '—' : adm}', style: const TextStyle(fontSize: 12.5, color: kGray600)),
                const SizedBox(height: 8),
                Wrap(spacing: 8, runSpacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
                  _labelled('Original Class', PromoPill('${s['original_class_name'] ?? '—'}', bg: kGreen100, fg: kGreen800)),
                  _labelled('Current Class', PromoPill('${s['current_class_name'] ?? '—'}', bg: kBlue100, fg: kBlue800)),
                  _labelled('Status', _statusBadge('${s['promotion_status']}')),
                ]),
                const SizedBox(height: 8),
                Wrap(spacing: 14, runSpacing: 4, crossAxisAlignment: WrapCrossAlignment.center, children: [
                  Text('Last: ${s['last_promotion_fmt'] ?? '—'}', style: const TextStyle(fontSize: 12, color: kGray600)),
                  Row(mainAxisSize: MainAxisSize.min, children: [
                    Icon(hasResults ? Icons.check_circle : Icons.cancel, size: 15, color: hasResults ? kGreen600 : const Color(0xFF9CA3AF)),
                    const SizedBox(width: 4),
                    Text(hasResults ? 'Has Results: Yes' : 'Has Results: No',
                        style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: hasResults ? kGreen600 : const Color(0xFF9CA3AF))),
                  ]),
                ]),
                if (!can)
                  Container(
                    margin: const EdgeInsets.only(top: 8),
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(color: const Color(0xFFFFF7ED), borderRadius: BorderRadius.circular(8)),
                    child: const Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Icon(Icons.info_outline, size: 15, color: kOrange600),
                      SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          'Original class unknown (promoted before history tracking) – cannot be reverted automatically.',
                          style: TextStyle(fontSize: 11.5, color: Color(0xFF9A3412)),
                        ),
                      ),
                    ]),
                  ),
              ]),
            ),
          ),
        ]),
      ),
    );
  }

  Widget _labelled(String label, Widget child) => Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(label, style: const TextStyle(fontSize: 9.5, color: kGray600)),
        const SizedBox(height: 2),
        child,
      ]);

  // ---------------------------- info panels + button ----------------------------
  Widget _revertPanel() {
    Widget li(IconData icon, Color color, Widget text) => Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Padding(padding: const EdgeInsets.only(top: 2), child: Icon(icon, size: 16, color: color)),
            const SizedBox(width: 8),
            Expanded(child: text),
          ]),
        );
    Text bold(String b, String rest) => Text.rich(TextSpan(style: const TextStyle(color: kGray700, height: 1.35), children: [
          TextSpan(text: '$b ', style: const TextStyle(fontWeight: FontWeight.bold)),
          TextSpan(text: rest),
        ]));

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: const LinearGradient(colors: [kRed100, kOrange100]),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: kRed300, width: 3),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        const Text('Revert Selected Students', textAlign: TextAlign.center, style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: kRed700)),
        const SizedBox(height: 16),
        Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(18), boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.1), blurRadius: 12, offset: const Offset(0, 5))]),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Row(children: [
              Icon(Icons.info, color: kRed700, size: 20),
              SizedBox(width: 8),
              Expanded(child: Text('What Happens When Reverting:', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800, color: kRed700))),
            ]),
            const SizedBox(height: 12),
            li(Icons.check, kGreen500, bold('Temporary Transfers:', 'Student returns to original class, results unchanged')),
            li(Icons.check, kGreen500, bold('Permanent Promotions:', 'Student and all results moved back to original class')),
            li(Icons.warning_amber_rounded, const Color(0xFFEAB308), bold('Note:', 'This action cannot be undone automatically')),
          ]),
        ),
        const SizedBox(height: 14),
        Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(color: kYellow50, borderRadius: BorderRadius.circular(18), border: Border.all(color: kYellow300, width: 2)),
          child: const Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Icon(Icons.warning_amber_rounded, color: kYellow800, size: 20),
              SizedBox(width: 8),
              Expanded(child: Text('Important Warning', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800, color: kYellow800))),
            ]),
            SizedBox(height: 8),
            Text(
              'Reverting will move students back to their original classes. If the original class no longer exists or has been deleted, contact your administrator.',
              style: TextStyle(color: kYellow700, height: 1.4),
            ),
          ]),
        ),
        const SizedBox(height: 22),
        _bigButton(_saving ? 'Processing...' : 'Revert Selected Students', Icons.undo, _saving ? null : () => _revert(all: false), busy: _saving),
      ]),
    );
  }
}
