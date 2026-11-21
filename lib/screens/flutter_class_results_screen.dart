// flutter_class_results_screen.dart
// Mirrors view_class_results.php:
//   • subscription gate (Term ₦ / Session ₦ plans, Flutterwave checkout, auto-verify when you come back)
//   • "Result Access Active" banner + "Subscription Expiring Soon" renew bar
//   • Class → Session → Term filters (session unlocks after class, term after session) + Fetch Students
//   • header card (class, session, term, View All Results) and the student list: avatar, name, ID,
//     admission no, class, status badge (Finalized / Draft / No Result + subject count)
//   • Preview · Download (PDF) · Send to Parent (WhatsApp)   – auto refresh every 30 s
// Video download / "send video" of the web page records a browser canvas and cannot run in Flutter;
// "Download" gives the PDF and "Send to Parent" shares the PDF + opens the parent's WhatsApp chat.
// API: https://schoolsmirror.com/flutter_class_results.php   (needs flutter_result_common.dart)

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:printing/printing.dart';
import 'package:url_launcher/url_launcher.dart';
import 'flutter_result_common.dart';
import 'flutter_result_card_screen.dart';
import 'flutter_all_results_screen.dart';

class FlutterClassResultsScreen extends StatefulWidget {
  final String? token;
  const FlutterClassResultsScreen({super.key, this.token});

  @override
  State<FlutterClassResultsScreen> createState() => _FlutterClassResultsScreenState();
}

class _FlutterClassResultsScreenState extends State<FlutterClassResultsScreen> with WidgetsBindingObserver {
  String? _token;
  bool _loading = true;
  String? _error;

  Map<String, dynamic> _access = {};
  bool get _hasAccess => _access['has_access'] == true;

  List<Map<String, dynamic>> _classes = [], _sessions = [], _terms = [];
  int? _classId, _sessionId, _termId;

  List<Map<String, dynamic>> _students = [];
  Map<String, dynamic> _meta = {};
  bool _loadingStudents = false;
  bool _fetched = false;
  Timer? _auto;

  String? _pendingRef; // a Flutterwave checkout is open
  bool _verifying = false;
  int? _busyStudent;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _init();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _auto?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // back from the Flutterwave page -> verify automatically
    if (state == AppLifecycleState.resumed && _pendingRef != null && !_verifying) _verifyPayment(silent: true);
  }

  void _toast(String m, {Color color = kRGreen}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(m), backgroundColor: color, behavior: SnackBarBehavior.floating));
  }

  // ───────────────────────────── data ─────────────────────────────
  Future<void> _init() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      _token = await resultToken(widget.token);
      if (_token == null) throw Exception('Session expired. Please log in again.');
      final r = await ResultApi.call(_token!, 'access');
      if (r['success'] != true) throw Exception(r['message'] ?? 'Failed to load');
      _access = rMap(r['data']);
      if (_hasAccess) await _loadFilters();
      if (!mounted) return;
      setState(() => _loading = false);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = rFriendly(e);
        _loading = false;
      });
    }
  }

  Future<void> _loadFilters() async {
    final r = await ResultApi.call(_token!, 'load_filters');
    if (r['success'] != true) throw Exception(r['message'] ?? 'Failed to load filters');
    final d = rMap(r['data']);
    if (!mounted) return;
    setState(() {
      _classes = rMaps(d['classes']);
      _sessions = rMaps(d['sessions']);
      _terms = rMaps(d['terms']);
    });
  }

  bool get _filtersReady => _classId != null && _sessionId != null && _termId != null;

  Future<void> _fetchStudents({bool silent = false}) async {
    if (!_filtersReady) return;
    if (!silent) {
      setState(() {
        _loadingStudents = true;
        _fetched = false;
      });
    }
    try {
      final r = await ResultApi.call(_token!, 'students', {'session_id': '$_sessionId', 'term_id': '$_termId', 'class_id': '$_classId'});
      if (r['success'] != true) throw Exception(r['message'] ?? 'Failed to load students');
      final d = rMap(r['data']);
      final list = rMaps(d['students']);
      if (!mounted) return;
      final changed = silent && list.length != _students.length;
      setState(() {
        _students = list;
        _meta = d;
        _loadingStudents = false;
        _fetched = true;
      });
      if (changed) _toast('Student list updated', color: kRPrimary);
      _startAuto();
    } catch (e) {
      if (!mounted) return;
      setState(() => _loadingStudents = false);
      if (!silent) _toast(rFriendly(e), color: Colors.red);
    }
  }

  void _startAuto() {
    _auto?.cancel();
    _auto = Timer.periodic(const Duration(seconds: 30), (_) {
      if (mounted && _fetched && _filtersReady && !_loadingStudents) _fetchStudents(silent: true);
    });
  }

  void _onFilterChanged() {
    _auto?.cancel();
    setState(() {
      _students = [];
      _fetched = false;
    });
    if (_filtersReady) _fetchStudents();
  }

  // ───────────────────────────── payment ─────────────────────────────
  Future<void> _startPayment(String plan) async {
    try {
      final r = await ResultApi.call(_token!, 'init_payment', {'plan_type': plan});
      if (r['success'] != true) throw Exception(r['message'] ?? 'Failed to initialize payment');
      final d = rMap(r['data']);
      setState(() => _pendingRef = '${d['reference']}');
      final ok = await launchUrl(Uri.parse('${d['payment_url']}'), mode: LaunchMode.externalApplication);
      if (!ok) _toast('Could not open the payment page.', color: Colors.red);
    } catch (e) {
      _toast(rFriendly(e), color: Colors.red);
    }
  }

  Future<void> _verifyPayment({bool silent = false}) async {
    if (_pendingRef == null) return;
    setState(() => _verifying = true);
    try {
      final r = await ResultApi.call(_token!, 'check_payment', {'reference': _pendingRef!});
      if (!mounted) return;
      if (r['success'] == true) {
        _access = rMap(r['data']);
        _pendingRef = null;
        await _loadFilters();
        setState(() {});
        _toast('Payment successful! You now have access to Class Results.');
      } else if (!silent) {
        _toast('${r['message']}', color: kRAmber);
      }
    } catch (e) {
      if (!silent) _toast(rFriendly(e), color: Colors.red);
    } finally {
      if (mounted) setState(() => _verifying = false);
    }
  }

  void _showPlans() {
    final plans = rMaps(_access['plans']);
    String? selected;
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Theme(
        data: resultLightTheme(),
        child: StatefulBuilder(builder: (ctx, setS) {
          final plan = plans.firstWhere((p) => p['type'] == selected, orElse: () => <String, dynamic>{});
          return DraggableScrollableSheet(
            expand: false,
            initialChildSize: 0.88,
            maxChildSize: 0.95,
            builder: (ctx, scroll) => Container(
              decoration: const BoxDecoration(color: Colors.white, borderRadius: BorderRadius.vertical(top: Radius.circular(22))),
              child: ListView(controller: scroll, padding: const EdgeInsets.fromLTRB(18, 10, 18, 28), children: [
                Center(child: Container(width: 44, height: 4, decoration: BoxDecoration(color: kRBorder, borderRadius: BorderRadius.circular(2)))),
                const SizedBox(height: 14),
                const Row(children: [
                  Icon(Icons.workspace_premium, color: kRPrimary),
                  SizedBox(width: 8),
                  Expanded(child: Text('Class Results – Subscription Plans', style: TextStyle(fontSize: 19, fontWeight: FontWeight.w800, color: kRPrimary))),
                ]),
                const SizedBox(height: 4),
                const Text('Choose a plan to unlock full access to Class Results Management.', style: TextStyle(color: Color(0xFF666666))),
                const SizedBox(height: 14),
                for (final p in plans)
                  GestureDetector(
                    onTap: () => setS(() => selected = '${p['type']}'),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 180),
                      margin: const EdgeInsets.only(bottom: 14),
                      padding: const EdgeInsets.all(18),
                      decoration: BoxDecoration(
                        color: selected == p['type'] ? const Color(0xFFF0F9FF) : Colors.white,
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: selected == p['type'] ? kRPrimary : const Color(0xFFDDDDDD), width: 2),
                        boxShadow: selected == p['type'] ? [BoxShadow(color: kRPrimary.withOpacity(0.2), blurRadius: 14, offset: const Offset(0, 6))] : null,
                      ),
                      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                        Text('${p['name']}', textAlign: TextAlign.center, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
                        const SizedBox(height: 6),
                        Text('₦${_money(p['price'])}', textAlign: TextAlign.center, style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w900, color: kRPrimary)),
                        Text('${p['duration']}', textAlign: TextAlign.center, style: const TextStyle(color: Color(0xFF666666), fontSize: 13)),
                        const SizedBox(height: 10),
                        for (final f in (p['features'] as List? ?? []))
                          Padding(
                            padding: const EdgeInsets.only(bottom: 6),
                            child: Row(children: [
                              const Icon(Icons.check_circle, size: 17, color: kRGreen),
                              const SizedBox(width: 8),
                              Expanded(child: Text('$f', style: const TextStyle(fontSize: 14))),
                            ]),
                          ),
                      ]),
                    ),
                  ),
                if (selected != null) ...[
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(color: const Color(0xFFF8F9FA), borderRadius: BorderRadius.circular(14)),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                      const Row(children: [Icon(Icons.credit_card, size: 18), SizedBox(width: 8), Text('Secure Online Payment', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16))]),
                      const SizedBox(height: 12),
                      Container(
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(color: const Color(0xFFF0F9FF), borderRadius: BorderRadius.circular(10), border: Border.all(color: kRPrimary, width: 2)),
                        child: const Column(children: [
                          Icon(Icons.credit_card, size: 30, color: kRPrimary),
                          Text('Flutterwave', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
                          Text('Card, Bank Transfer, USSD, Mobile Money & more', textAlign: TextAlign.center, style: TextStyle(color: Color(0xFF666666), fontSize: 12.5)),
                          SizedBox(height: 4),
                          Row(mainAxisAlignment: MainAxisAlignment.center, children: [Icon(Icons.lock, size: 12, color: Color(0xFF27AE60)), SizedBox(width: 4), Text('Secure & Encrypted', style: TextStyle(color: Color(0xFF27AE60), fontSize: 11.5))]),
                        ]),
                      ),
                      const SizedBox(height: 12),
                      Container(
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(10), border: Border.all(color: const Color(0xFFE0E0E0))),
                        child: Column(children: [
                          _sumRow('Plan Selected:', '${plan['name'] ?? '—'}'),
                          _sumRow('Amount to Pay:', '₦${_money(plan['price'])}', valueColor: const Color(0xFFD32F2F), bold: true),
                          _sumRow('Payment Reference:', 'Created at checkout', last: true),
                        ]),
                      ),
                      const SizedBox(height: 12),
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(color: const Color(0xFFFFF8E1), borderRadius: BorderRadius.circular(8), border: Border.all(color: const Color(0xFFF5A623), width: 1.5)),
                        child: const Text('Secure Payment via Flutterwave\nYou will be taken to Flutterwave\'s secure checkout where you can pay by:\n• Credit / Debit Cards (Visa, Mastercard, Verve)\n• Bank Transfers\n• USSD\n• Mobile Money / QR', style: TextStyle(fontSize: 13, height: 1.45)),
                      ),
                      const SizedBox(height: 14),
                      Container(
                        decoration: BoxDecoration(gradient: const LinearGradient(colors: [kRPrimary, kRSecondary]), borderRadius: BorderRadius.circular(10)),
                        child: Material(
                          color: Colors.transparent,
                          child: InkWell(
                            borderRadius: BorderRadius.circular(10),
                            onTap: () {
                              Navigator.pop(ctx);
                              _startPayment(selected!);
                            },
                            child: const Padding(
                              padding: EdgeInsets.symmetric(vertical: 15),
                              child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                                Icon(Icons.credit_card, color: Colors.white, size: 20),
                                SizedBox(width: 10),
                                Text('PROCEED TO SECURE PAYMENT', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 15)),
                              ]),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 14),
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(color: const Color(0xFFE8F5E9), borderRadius: BorderRadius.circular(8), border: Border.all(color: const Color(0xFF4CAF50), width: 1.5)),
                        child: Column(children: [
                          const Text('Need help? Contact support:', style: TextStyle(color: Color(0xFF2E7D32), fontSize: 13)),
                          Text('✉ ${_access['contact_email'] ?? ''}', style: const TextStyle(color: Color(0xFF2E7D32), fontSize: 13)),
                          Text('☎ ${_access['contact_phone'] ?? ''}', style: const TextStyle(color: Color(0xFF2E7D32), fontSize: 13)),
                        ]),
                      ),
                      const SizedBox(height: 12),
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(color: const Color(0xFFFFF3CD), borderRadius: BorderRadius.circular(8)),
                        child: const Text('What Happens Next?\n1. Tap "Proceed to Secure Payment"\n2. Complete payment on Flutterwave\'s secure page\n3. Come back here – it is verified automatically\n4. Access Class Results immediately!', style: TextStyle(color: Color(0xFF856404), fontSize: 13, height: 1.5)),
                      ),
                    ]),
                  ),
                ],
              ]),
            ),
          );
        }),
      ),
    );
  }

  String _money(dynamic v) {
    final n = rDouble(v).round().toString();
    return n.replaceAllMapped(RegExp(r'\B(?=(\d{3})+(?!\d))'), (m) => ',');
  }

  Widget _sumRow(String k, String v, {Color? valueColor, bool bold = false, bool last = false}) => Container(
        padding: const EdgeInsets.only(bottom: 10),
        margin: EdgeInsets.only(bottom: last ? 0 : 10),
        decoration: last ? null : const BoxDecoration(border: Border(bottom: BorderSide(color: Color(0xFFEEEEEE)))),
        child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          Text(k, style: const TextStyle(fontWeight: FontWeight.w600, color: Color(0xFF555555))),
          Flexible(child: Text(v, textAlign: TextAlign.right, style: TextStyle(fontWeight: bold ? FontWeight.w800 : FontWeight.w500, color: valueColor ?? const Color(0xFF333333)))),
        ]),
      );

  // ───────────────────────────── student actions ─────────────────────────────
  void _preview(Map<String, dynamic> s) {
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => FlutterResultCardScreen(
        token: _token,
        idnumber: '${s['idnumber']}',
        sessionId: _sessionId!,
        termId: _termId!,
        classId: _classId!,
        studentName: '${s['fullname']}',
      ),
    ));
  }

  Future<Map<String, dynamic>?> _loadCard(Map<String, dynamic> s) async {
    final r = await ResultApi.call(_token!, 'student_card', {'idnumber': '${s['idnumber']}', 'session_id': '$_sessionId', 'term_id': '$_termId', 'class_id': '$_classId'});
    if (r['success'] != true) {
      _toast('${r['message']}', color: Colors.red);
      return null;
    }
    return rMap(r['data']);
  }

  Future<void> _download(Map<String, dynamic> s) async {
    setState(() => _busyStudent = rInt(s['user_id']));
    try {
      final card = await _loadCard(s);
      if (card == null) return;
      final bytes = await ReportCardPdf.build([card]);
      await Printing.sharePdf(bytes: bytes, filename: 'Result_${'${s['fullname']}'.replaceAll(RegExp(r'[^a-zA-Z0-9]'), '_')}.pdf');
    } catch (e) {
      _toast('Could not create the PDF: ${rFriendly(e)}', color: Colors.red);
    } finally {
      if (mounted) setState(() => _busyStudent = null);
    }
  }

  Future<void> _sendToParent(Map<String, dynamic> s) async {
    final wa = waNumber(s['parent_phone']);
    if (wa == null) {
      _toast('This student has no guardian/parent phone number on file.', color: kRAmber);
      return;
    }
    final name = '${s['fullname']}';
    final go = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Theme(
        data: resultLightTheme(),
        child: Container(
          decoration: const BoxDecoration(color: Colors.white, borderRadius: BorderRadius.vertical(top: Radius.circular(22))),
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Center(child: Container(width: 44, height: 4, decoration: BoxDecoration(color: kRBorder, borderRadius: BorderRadius.circular(2)))),
            const SizedBox(height: 14),
            Text('Send $name\'s result to the parent', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
            const SizedBox(height: 4),
            Text('Parent: ${s['parent_name'] ?? ''} • ${s['parent_phone']}', style: const TextStyle(color: kRMuted, fontSize: 13)),
            const SizedBox(height: 16),
            _waBtn('Share result PDF', 'Pick WhatsApp (or any app) and the parent’s chat', Icons.picture_as_pdf, () => Navigator.pop(ctx, 'pdf')),
            const SizedBox(height: 10),
            _waBtn('Open WhatsApp chat', 'Starts a chat with the parent with a ready message', Icons.chat, () => Navigator.pop(ctx, 'chat')),
          ]),
        ),
      ),
    );
    if (go == null) return;
    if (go == 'pdf') {
      await _download(s);
    } else {
      final msg = Uri.encodeComponent('Hello, here is $name\'s result for ${_meta['term_name'] ?? ''} ${_meta['session_name'] ?? ''}. Please check the attached result card.');
      final ok = await launchUrl(Uri.parse('https://wa.me/$wa?text=$msg'), mode: LaunchMode.externalApplication);
      if (!ok) _toast('Could not open WhatsApp.', color: Colors.red);
    }
  }

  Widget _waBtn(String t, String sub, IconData icon, VoidCallback onTap) => InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(gradient: const LinearGradient(colors: [Color(0xFF25D366), Color(0xFF128C7E)]), borderRadius: BorderRadius.circular(14)),
          child: Row(children: [
            Icon(icon, color: Colors.white),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(t, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 15)),
                Text(sub, style: TextStyle(color: Colors.white.withOpacity(0.9), fontSize: 12)),
              ]),
            ),
          ]),
        ),
      );

  void _viewAll() {
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => FlutterAllResultsScreen(
        token: _token,
        sessionId: _sessionId!,
        termId: _termId!,
        classId: _classId!,
        sessionName: '${_meta['session_name'] ?? ''}',
        termName: '${_meta['term_name'] ?? ''}',
        className: '${_meta['class_name'] ?? ''}',
      ),
    ));
  }

  // ───────────────────────────── BUILD ─────────────────────────────
  @override
  Widget build(BuildContext context) {
    return Theme(
      data: resultLightTheme(),
      child: Scaffold(
        backgroundColor: kRBg,
        appBar: AppBar(
          backgroundColor: Colors.white,
          surfaceTintColor: Colors.transparent,
          foregroundColor: kRText,
          elevation: 0,
          title: const Text('Class Results', style: TextStyle(fontWeight: FontWeight.w800)),
          actions: [IconButton(tooltip: 'Refresh', icon: const Icon(Icons.refresh), onPressed: _init)],
        ),
        body: _loading
            ? const Center(child: CircularProgressIndicator(color: kRPrimary))
            : _error != null
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Column(mainAxisSize: MainAxisSize.min, children: [
                        const Icon(Icons.error_outline, color: Colors.red, size: 44),
                        const SizedBox(height: 10),
                        Text(_error!, textAlign: TextAlign.center, style: const TextStyle(color: Colors.red)),
                        const SizedBox(height: 14),
                        ElevatedButton.icon(onPressed: _init, icon: const Icon(Icons.refresh), label: const Text('Retry')),
                      ]),
                    ),
                  )
                : RefreshIndicator(
                    onRefresh: _init,
                    child: ListView(
                      physics: const AlwaysScrollableScrollPhysics(),
                      padding: const EdgeInsets.fromLTRB(14, 14, 14, 40),
                      children: [
                        Row(children: const [
                          Icon(Icons.school, color: kRPrimary),
                          SizedBox(width: 8),
                          Expanded(child: Text('Class Results Management', style: TextStyle(fontSize: 21, fontWeight: FontWeight.w800))),
                        ]),
                        const SizedBox(height: 14),
                        if (_pendingRef != null) _pendingBanner(),
                        if (!_hasAccess) ..._gate() else ..._main(),
                      ],
                    ),
                  ),
      ),
    );
  }

  Widget _pendingBanner() => Container(
        margin: const EdgeInsets.only(bottom: 14),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(color: const Color(0xFFFFF3CD), borderRadius: BorderRadius.circular(12), border: Border.all(color: const Color(0xFFFFE08A))),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Row(children: [Icon(Icons.hourglass_top, color: Color(0xFF856404), size: 20), SizedBox(width: 8), Expanded(child: Text('Waiting for your payment…', style: TextStyle(fontWeight: FontWeight.w800, color: Color(0xFF856404))))]),
          const SizedBox(height: 4),
          const Text('Finished paying? It is checked automatically when you come back to the app, or tap the button.', style: TextStyle(color: Color(0xFF856404), fontSize: 13)),
          const SizedBox(height: 10),
          Row(children: [
            ElevatedButton.icon(
              onPressed: _verifying ? null : () => _verifyPayment(),
              style: ElevatedButton.styleFrom(backgroundColor: kRPrimary, foregroundColor: Colors.white),
              icon: _verifying ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)) : const Icon(Icons.verified, size: 18),
              label: const Text('I have paid – verify'),
            ),
            const SizedBox(width: 8),
            TextButton(onPressed: () => setState(() => _pendingRef = null), child: const Text('Dismiss')),
          ]),
        ]),
      );

  List<Widget> _gate() => [
        Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(gradient: kRPurpleGradient, borderRadius: BorderRadius.circular(14)),
          child: Row(children: [
            const Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [Icon(Icons.lock, color: Colors.white), SizedBox(width: 8), Text('Access Required', style: TextStyle(color: Colors.white, fontSize: 19, fontWeight: FontWeight.w800))]),
                SizedBox(height: 6),
                Text('Subscribe to a plan to unlock Class Results Management.', style: TextStyle(color: Colors.white70)),
              ]),
            ),
          ]),
        ),
        const SizedBox(height: 16),
        Container(
          padding: const EdgeInsets.symmetric(vertical: 36, horizontal: 20),
          decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14), boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.07), blurRadius: 12, offset: const Offset(0, 2))]),
          child: Column(children: [
            const Icon(Icons.lock, size: 62, color: kRPayment),
            const SizedBox(height: 14),
            const Text('Class Results is a Premium Feature', textAlign: TextAlign.center, style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
            const SizedBox(height: 6),
            const Text('Subscribe to view, preview and download student result sheets.', textAlign: TextAlign.center, style: TextStyle(color: kRMuted)),
            const SizedBox(height: 18),
            Container(
              decoration: BoxDecoration(gradient: const LinearGradient(colors: [Color(0xFF9C27B0), Color(0xFF7B1FA2)]), borderRadius: BorderRadius.circular(10), boxShadow: [BoxShadow(color: kRPayment.withOpacity(0.35), blurRadius: 14, offset: const Offset(0, 5))]),
              child: Material(
                color: Colors.transparent,
                child: InkWell(
                  borderRadius: BorderRadius.circular(10),
                  onTap: _showPlans,
                  child: const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 26, vertical: 14),
                    child: Row(mainAxisSize: MainAxisSize.min, children: [Icon(Icons.workspace_premium, color: Colors.white), SizedBox(width: 8), Text('See Available Plans', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 16))]),
                  ),
                ),
              ),
            ),
          ]),
        ),
      ];

  List<Widget> _main() {
    final sub = rMap(_access['subscription']);
    return [
      Container(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(gradient: kRPurpleGradient, borderRadius: BorderRadius.circular(14)),
        child: Row(children: [
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Row(children: [Icon(Icons.shield, color: Colors.white), SizedBox(width: 8), Text('Result Access Active', style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w800))]),
              const SizedBox(height: 6),
              Text(sub.isEmpty ? 'Free access (payment gate is off)' : '${'${sub['plan_type']}'.isEmpty ? '' : '${sub['plan_type']}'[0].toUpperCase() + '${sub['plan_type']}'.substring(1)} Plan — valid until ${sub['expiry_fmt']}', style: const TextStyle(color: Colors.white, fontSize: 13.5)),
            ]),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(color: Colors.white.withOpacity(0.2), borderRadius: BorderRadius.circular(20)),
            child: const Row(mainAxisSize: MainAxisSize.min, children: [Icon(Icons.lock_open, size: 14, color: Colors.white), SizedBox(width: 5), Text('Active', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700))]),
          ),
        ]),
      ),
      if (sub['expiring_soon'] == true)
        Container(
          margin: const EdgeInsets.only(top: 12),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(color: const Color(0xFFFFF8E1), borderRadius: BorderRadius.circular(10), border: Border.all(color: kRAmber, width: 1.5)),
          child: Row(children: [
            const Icon(Icons.warning_amber_rounded, color: kRAmber),
            const SizedBox(width: 8),
            Expanded(child: Text('Subscription Expiring Soon! Expires on ${sub['expiry_fmt']}.', style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13))),
            ElevatedButton(onPressed: _showPlans, style: ElevatedButton.styleFrom(backgroundColor: kRAmber, foregroundColor: Colors.black), child: const Text('Renew Now')),
          ]),
        ),
      const SizedBox(height: 16),
      _filters(),
      const SizedBox(height: 18),
      if (_loadingStudents) const Padding(padding: EdgeInsets.all(40), child: Center(child: CircularProgressIndicator(color: kRPrimary))),
      if (_fetched && !_loadingStudents) ..._studentsSection(),
    ];
  }

  InputDecoration _dec() => InputDecoration(
        isDense: true,
        filled: true,
        fillColor: Colors.white,
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 13),
        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: Color(0xFFCED4DA))),
        disabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: Color(0xFFE9ECEF))),
        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: kRPrimary, width: 2)),
      );

  Widget _drop(String label, String hint, int? value, List<Map<String, dynamic>> items, String idKey, String nameKey, ValueChanged<int?>? onChanged) {
    final has = items.any((m) => rInt(m[idKey]) == value);
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Padding(padding: const EdgeInsets.only(bottom: 6), child: Text(label, style: const TextStyle(fontWeight: FontWeight.w700))),
      DropdownButtonFormField<int>(
        value: has ? value : null,
        isExpanded: true,
        decoration: _dec(),
        style: kRFieldStyle,
        dropdownColor: Colors.white,
        menuMaxHeight: 320,
        hint: Text(hint, style: const TextStyle(color: Color(0xFF9CA3AF), fontSize: 14)),
        items: [for (final m in items) DropdownMenuItem(value: rInt(m[idKey]), child: Text('${m[nameKey]}', overflow: TextOverflow.ellipsis))],
        onChanged: onChanged,
      ),
    ]);
  }

  Widget _filters() => Container(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12), boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.07), blurRadius: 10, offset: const Offset(0, 2))]),
        child: LayoutBuilder(builder: (context, c) {
          final cols = c.maxWidth >= 760 ? 4 : (c.maxWidth >= 480 ? 2 : 1);
          final w = (c.maxWidth - 14 * (cols - 1)) / cols;
          return Wrap(spacing: 14, runSpacing: 14, crossAxisAlignment: WrapCrossAlignment.end, children: [
            SizedBox(
              width: w,
              child: _drop('Class', 'Select Class', _classId, _classes, 'class_id', 'class_name', (v) {
                _classId = v;
                _sessionId = null;
                _termId = null;
                _onFilterChanged();
              }),
            ),
            SizedBox(
              width: w,
              child: _drop('Academic Session', 'Select Session', _sessionId, _sessions, 'id', 'session_name', _classId == null
                  ? null
                  : (v) {
                      _sessionId = v;
                      _termId = null;
                      _onFilterChanged();
                    }),
            ),
            SizedBox(
              width: w,
              child: _drop('Term', 'Select Term', _termId, _terms, 'id', 'term_name', _sessionId == null
                  ? null
                  : (v) {
                      _termId = v;
                      _onFilterChanged();
                    }),
            ),
            SizedBox(
              width: w,
              height: 46,
              child: ElevatedButton.icon(
                onPressed: _filtersReady && !_loadingStudents ? _fetchStudents : null,
                style: ElevatedButton.styleFrom(backgroundColor: kRPrimary, foregroundColor: Colors.white, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8))),
                icon: const Icon(Icons.search, size: 18),
                label: const Text('Fetch Students', style: TextStyle(fontWeight: FontWeight.w700)),
              ),
            ),
          ]);
        }),
      );

  List<Widget> _studentsSection() {
    Widget chip(IconData i, String t) => Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
          decoration: BoxDecoration(color: const Color(0xFFF8F9FA), borderRadius: BorderRadius.circular(6)),
          child: Row(mainAxisSize: MainAxisSize.min, children: [Icon(i, size: 13, color: kRText), const SizedBox(width: 5), Text(t, style: const TextStyle(fontSize: 12.5, color: kRText))]),
        );
    return [
      Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(gradient: kRPurpleGradient, borderRadius: BorderRadius.circular(10)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [const Icon(Icons.groups, color: Colors.white), const SizedBox(width: 8), Expanded(child: Text('${_meta['class_name'] ?? ''}', style: const TextStyle(color: Colors.white, fontSize: 19, fontWeight: FontWeight.w800)))]),
          const SizedBox(height: 10),
          Wrap(spacing: 8, runSpacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
            chip(Icons.calendar_today, '${_meta['session_name'] ?? ''}'),
            chip(Icons.event, '${_meta['term_name'] ?? ''}'),
            if (_students.isNotEmpty)
              ElevatedButton.icon(
                onPressed: _viewAll,
                style: ElevatedButton.styleFrom(backgroundColor: Colors.white, foregroundColor: kRText, visualDensity: VisualDensity.compact),
                icon: const Icon(Icons.visibility, size: 16),
                label: const Text('View All Results'),
              ),
          ]),
        ]),
      ),
      const SizedBox(height: 12),
      if (_students.isEmpty)
        Container(
          padding: const EdgeInsets.symmetric(vertical: 40),
          alignment: Alignment.center,
          child: const Column(children: [Icon(Icons.groups, size: 48, color: kRMuted), SizedBox(height: 10), Text('No Students Found', style: TextStyle(fontSize: 19, fontWeight: FontWeight.w800)), Text('No students found for the selected criteria.', style: TextStyle(color: kRMuted))]),
        )
      else
        for (var i = 0; i < _students.length; i++) _studentCard(_students[i], i),
    ];
  }

  Widget _studentCard(Map<String, dynamic> s, int i) {
    final status = '${s['result_status'] ?? 'none'}';
    final finalized = status == 'finalized';
    final hasPhone = '${s['parent_phone'] ?? ''}'.trim().isNotEmpty;
    final busy = _busyStudent == rInt(s['user_id']);

    Widget btn(String label, IconData icon, List<Color> colors, VoidCallback? onTap) => Opacity(
          opacity: onTap == null ? 0.5 : 1,
          child: Container(
            decoration: BoxDecoration(gradient: LinearGradient(colors: colors), borderRadius: BorderRadius.circular(6)),
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                borderRadius: BorderRadius.circular(6),
                onTap: onTap,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    if (busy && label == 'Download')
                      const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                    else
                      Icon(icon, size: 15, color: Colors.white),
                    const SizedBox(width: 6),
                    Text(label, style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w600)),
                  ]),
                ),
              ),
            ),
          ),
        );

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12), boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.06), blurRadius: 8, offset: const Offset(0, 2))]),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          SizedBox(width: 26, child: Text('${i + 1}', style: const TextStyle(fontWeight: FontWeight.w800))),
          RAvatar(name: '${s['fullname']}', url: '${s['image_url'] ?? ''}'),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('${s['fullname']}', style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
              Text('${s['idnumber'] ?? 'N/A'}  •  Adm: ${'${s['admission_number'] ?? ''}'.isEmpty ? 'N/A' : s['admission_number']}', style: const TextStyle(color: kRMuted, fontSize: 12.5)),
            ]),
          ),
        ]),
        const SizedBox(height: 10),
        Wrap(spacing: 8, runSpacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
          Container(padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4), decoration: BoxDecoration(color: kRMuted, borderRadius: BorderRadius.circular(6)), child: Text('${s['class_name'] ?? ''}', style: const TextStyle(color: Colors.white, fontSize: 12))),
          RStatusBadge(status, count: rInt(s['subject_count'])),
        ]),
        const SizedBox(height: 12),
        Wrap(spacing: 8, runSpacing: 8, children: [
          btn('Preview', Icons.visibility, const [Color(0xFF2196F3), Color(0xFF0D47A1)], () => _preview(s)),
          btn('Download', Icons.download, const [Color(0xFF4CAF50), Color(0xFF2E7D32)], finalized && !busy ? () => _download(s) : null),
          Tooltip(
            message: !hasPhone ? 'No parent phone number on file' : (!finalized ? 'Result not finalized yet' : 'Send the result to the parent via WhatsApp'),
            child: btn('Send to Parent', Icons.chat, const [Color(0xFF25D366), Color(0xFF128C7E)], (finalized && hasPhone) ? () => _sendToParent(s) : null),
          ),
        ]),
      ]),
    );
  }
}
