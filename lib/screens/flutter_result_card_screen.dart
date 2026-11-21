// flutter_result_card_screen.dart
// Mirrors displayResult.php: the student's result card (school header, student, subjects, totals,
// position, grading key, attendance, traits, remarks + signatures, next-term date) in the class
// template colours, the career-suggestion panel, and the bottom action bar:
//   🎬 Reveal (animated reveal)  ·  PDF  ·  Print
// API: https://schoolsmirror.com/flutter_class_results.php   (needs flutter_result_common.dart)

import 'package:flutter/material.dart';
import 'package:printing/printing.dart';
import 'flutter_result_common.dart';
import 'flutter_result_reveal_screen.dart';

class FlutterResultCardScreen extends StatefulWidget {
  final String? token;
  final String idnumber;
  final int sessionId;
  final int termId;
  final int classId;
  final String studentName;
  const FlutterResultCardScreen({
    super.key,
    this.token,
    required this.idnumber,
    required this.sessionId,
    required this.termId,
    required this.classId,
    this.studentName = '',
  });

  @override
  State<FlutterResultCardScreen> createState() => _FlutterResultCardScreenState();
}

class _FlutterResultCardScreenState extends State<FlutterResultCardScreen> {
  String? _token;
  Map<String, dynamic>? _card;
  bool _loading = true;
  String? _error;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      _token = await resultToken(widget.token);
      if (_token == null) throw Exception('Session expired. Please log in again.');
      final r = await ResultApi.call(_token!, 'student_card', {
        'idnumber': widget.idnumber,
        'session_id': '${widget.sessionId}',
        'term_id': '${widget.termId}',
        'class_id': '${widget.classId}',
      });
      if (r['success'] != true) throw Exception(r['message'] ?? 'Failed to load result');
      if (!mounted) return;
      setState(() {
        _card = rMap(r['data']);
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = rFriendly(e);
        _loading = false;
      });
    }
  }

  String get _fileName => 'Result_${(widget.studentName.isEmpty ? widget.idnumber : widget.studentName).replaceAll(RegExp(r'[^a-zA-Z0-9]'), '_')}.pdf';

  Future<void> _pdf({required bool print}) async {
    if (_card == null || _busy) return;
    setState(() => _busy = true);
    try {
      final bytes = await ReportCardPdf.build([_card!]);
      if (print) {
        await Printing.layoutPdf(onLayout: (_) async => bytes, name: _fileName);
      } else {
        await Printing.sharePdf(bytes: bytes, filename: _fileName);
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('PDF failed: ${rFriendly(e)}'), backgroundColor: Colors.red));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _reveal() {
    if (_card == null) return;
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => FlutterResultRevealScreen(card: _card!)));
  }

  @override
  Widget build(BuildContext context) {
    final colors = rMap(rMap(_card?['template'])['colors']);
    final primary = hexColor(colors['primary_color']);
    return Theme(
      data: resultLightTheme(),
      child: Scaffold(
        backgroundColor: const Color(0xFFF0F4FF),
        appBar: AppBar(
          backgroundColor: Colors.white,
          surfaceTintColor: Colors.transparent,
          foregroundColor: kRText,
          elevation: 0,
          title: Text(widget.studentName.isEmpty ? 'Result' : 'Result – ${widget.studentName}', style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 17)),
          actions: [IconButton(tooltip: 'Refresh', icon: const Icon(Icons.refresh), onPressed: _load)],
        ),
        bottomNavigationBar: _card == null ? null : _actionBar(),
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
                        ElevatedButton.icon(onPressed: _load, icon: const Icon(Icons.refresh), label: const Text('Retry')),
                      ]),
                    ),
                  )
                : SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(12, 14, 12, 24),
                    child: Center(
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 900),
                        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                          if (rMaps(_card!['subjects']).isEmpty)
                            Container(
                              margin: const EdgeInsets.only(bottom: 12),
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(color: const Color(0xFFFFF3CD), borderRadius: BorderRadius.circular(10)),
                              child: const Text('No finalized results for this student yet, so the card below is empty.', style: TextStyle(color: Color(0xFF856404))),
                            ),
                          ReportCardView(card: _card!),
                          const SizedBox(height: 16),
                          _career(primary),
                        ]),
                      ),
                    ),
                  ),
      ),
    );
  }

  Widget _career(Color primary) {
    final c = rMap(_card!['career']);
    final good = rMaps(_card!['good_subjects']);
    final weak = rMaps(_card!['weak_subjects']);
    if ('${c['tier'] ?? ''}'.isEmpty) return const SizedBox.shrink();
    Widget chips(String title, List<Map<String, dynamic>> l, Color color) => l.isEmpty
        ? const SizedBox.shrink()
        : Padding(
            padding: const EdgeInsets.only(top: 10),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(title, style: TextStyle(fontWeight: FontWeight.w800, color: color, fontSize: 12.5)),
              const SizedBox(height: 4),
              Wrap(spacing: 6, runSpacing: 6, children: [
                for (final g in l)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(color: color.withOpacity(0.12), borderRadius: BorderRadius.circular(20)),
                    child: Text('${g['name']} · ${rNum(g['score'])}', style: TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.w700)),
                  ),
              ]),
            ]),
          );
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(gradient: const LinearGradient(colors: [Color(0xFF1E1B4B), Color(0xFF312E81)]), borderRadius: BorderRadius.circular(18)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Row(children: [Icon(Icons.explore, color: Color(0xFFFBBF24)), SizedBox(width: 8), Text('Career Insight', style: TextStyle(color: Colors.white, fontSize: 17, fontWeight: FontWeight.w800))]),
        const SizedBox(height: 10),
        Text('${c['tier']}', style: const TextStyle(color: Color(0xFFFBBF24), fontWeight: FontWeight.w800, fontSize: 15)),
        const SizedBox(height: 6),
        Text('${c['posLine'] ?? ''}${c['advice'] ?? ''}', style: const TextStyle(color: Color(0xFFC4B5FD), height: 1.5, fontSize: 13.5)),
        chips('🔥 Strong subjects', good, const Color(0xFF34D399)),
        chips('⚠️ Needs improvement', weak, const Color(0xFFFF8A80)),
      ]),
    );
  }

  Widget _actionBar() => Container(
        padding: EdgeInsets.fromLTRB(12, 10, 12, 10 + MediaQuery.of(context).padding.bottom),
        decoration: BoxDecoration(color: const Color(0xFF0A051E).withOpacity(0.97), border: Border(top: BorderSide(color: const Color(0xFF667EEA).withOpacity(0.25)))),
        child: Wrap(alignment: WrapAlignment.center, spacing: 8, runSpacing: 8, children: [
          _abt('Reveal', Icons.movie_filter, const [Color(0xFF6D28D9), Color(0xFF4C1D95)], _reveal),
          _abt(_busy ? 'Working…' : 'PDF', Icons.picture_as_pdf, const [Color(0xFF2563EB), Color(0xFF1E40AF)], _busy ? null : () => _pdf(print: false)),
          _abt('Print', Icons.print, const [Color(0xFF059669), Color(0xFF047857)], _busy ? null : () => _pdf(print: true)),
        ]),
      );

  Widget _abt(String label, IconData icon, List<Color> colors, VoidCallback? onTap) => Opacity(
        opacity: onTap == null ? 0.6 : 1,
        child: Container(
          decoration: BoxDecoration(gradient: LinearGradient(colors: colors), borderRadius: BorderRadius.circular(50), boxShadow: [BoxShadow(color: colors.first.withOpacity(0.45), blurRadius: 12, offset: const Offset(0, 4))]),
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              borderRadius: BorderRadius.circular(50),
              onTap: onTap,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 11),
                child: Row(mainAxisSize: MainAxisSize.min, children: [Icon(icon, color: Colors.white, size: 17), const SizedBox(width: 6), Text(label, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 13))]),
              ),
            ),
          ),
        ),
      );
}
