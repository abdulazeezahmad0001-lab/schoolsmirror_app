// flutter_promotion_history_screen.dart
// Mirrors promotion_history.php 1:1: purple page, blue "📜 Promotion History" header, 4 stat cards
// (Total / Permanent / Temporary / Unique Students), filters (Session, Class, Type) with
// Apply / Clear, Export CSV + Export PDF, and the table (Date & Time, Student, Admission No.,
// From Class, To Class, Session, Type, Admin) + pagination.
//
// pubspec.yaml needs:  http, shared_preferences, url_launcher, pdf, printing
// API: https://schoolsmirror.com/flutter_promotion.php   (needs flutter_promotion_common.dart)

import 'dart:math' as math;
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:url_launcher/url_launcher.dart';
import 'flutter_promotion_common.dart';

// page palette of promotion_history.php
const Color _blue = Color(0xFF3498DB);
const Color _blueDark = Color(0xFF2980B9);
const Color _navy = Color(0xFF2C3E50);
const Color _grey = Color(0xFF95A5A6);
const Color _green = Color(0xFF27AE60);
const Color _panel = Color(0xFFF8F9FA);
const Color _line = Color(0xFFE0E0E0);

class FlutterPromotionHistoryScreen extends StatefulWidget {
  final String? token;
  const FlutterPromotionHistoryScreen({super.key, this.token});

  @override
  State<FlutterPromotionHistoryScreen> createState() => _FlutterPromotionHistoryScreenState();
}

class _FlutterPromotionHistoryScreenState extends State<FlutterPromotionHistoryScreen> {
  String? _token;

  // dropdown values (what the user is choosing) vs the applied filters (what the table shows)
  int _fSession = 0, _fClass = 0;
  String _fType = '';
  int _aSession = 0, _aClass = 0;
  String _aType = '';

  List<Map<String, dynamic>> _sessions = [], _classes = [], _history = [];
  Map<String, dynamic> _stats = {};
  int _page = 1, _totalPages = 1, _total = 0, _from = 0, _to = 0;

  bool _loading = true;
  bool _busyPdf = false;
  bool _busyCsv = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Map<String, String> _filterFields() => {
        if (_aSession > 0) 'session_id': '$_aSession',
        if (_aClass > 0) 'class_id': '$_aClass',
        if (_aType.isNotEmpty) 'promotion_type': _aType,
      };

  Future<void> _load({int page = 1}) async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      _token ??= await promoToken(widget.token);
      if (_token == null) throw Exception('Session expired. Please log in again.');
      final r = await PromoApi.call(_token!, 'history', {..._filterFields(), 'page': '$page'});
      if (r['success'] != true) throw Exception(r['message'] ?? 'Failed to load history');
      final d = (r['data'] as Map?) ?? {};
      if (!mounted) return;
      setState(() {
        _history = pMaps(d['history']);
        _stats = Map<String, dynamic>.from((d['stats'] as Map?) ?? {});
        _sessions = pMaps(d['sessions']);
        _classes = pMaps(d['classes']);
        _page = pInt(d['page']) == 0 ? 1 : pInt(d['page']);
        _totalPages = math.max(1, pInt(d['total_pages']));
        _total = pInt(d['total']);
        _from = pInt(d['from']);
        _to = pInt(d['to']);
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = promoFriendly(e);
        _loading = false;
      });
    }
  }

  void _apply() {
    _aSession = _fSession;
    _aClass = _fClass;
    _aType = _fType;
    _load();
  }

  void _clear() {
    setState(() {
      _fSession = _fClass = _aSession = _aClass = 0;
      _fType = _aType = '';
    });
    _load();
  }

  void _toast(String m, {bool error = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(m), backgroundColor: error ? kRed600 : _green, behavior: SnackBarBehavior.floating));
  }

  // ───────────────────────────── exports ─────────────────────────────
  Future<void> _exportCsv() async {
    if (_busyCsv || _token == null) return;
    setState(() => _busyCsv = true);
    try {
      final ok = await launchUrl(PromoApi.downloadUri(_token!, 'export_history', _filterFields()), mode: LaunchMode.externalApplication);
      if (!ok) _toast('Could not open the download.', error: true);
    } catch (e) {
      _toast('Export failed: ${promoFriendly(e)}', error: true);
    } finally {
      if (mounted) setState(() => _busyCsv = false);
    }
  }

  String _latin(String s) => s.runes.map((r) => r < 256 ? String.fromCharCode(r) : '?').join();

  Future<void> _exportPdf() async {
    if (_busyPdf || _token == null) return;
    setState(() => _busyPdf = true);
    try {
      // fetch every row that matches the filters (not just the current page)
      final r = await PromoApi.call(_token!, 'history', {..._filterFields(), 'all': '1'});
      if (r['success'] != true) throw Exception(r['message'] ?? 'Failed to load history');
      final rows = pMaps((r['data'] as Map?)?['history']);
      if (rows.isEmpty) {
        _toast('No promotion records to export.', error: true);
        return;
      }
      final bytes = await _buildPdf(rows);
      await Printing.sharePdf(bytes: bytes, filename: 'promotion_history_${DateTime.now().millisecondsSinceEpoch}.pdf');
    } catch (e) {
      _toast('PDF failed: ${promoFriendly(e)}', error: true);
    } finally {
      if (mounted) setState(() => _busyPdf = false);
    }
  }

  Future<Uint8List> _buildPdf(List<Map<String, dynamic>> rows) async {
    const mm = PdfPageFormat.mm;
    PdfColor c(int v) => PdfColor.fromInt(v);

    pw.Widget cell(String t, {bool head = false, PdfColor? color, bool bold = false}) => pw.Padding(
          padding: const pw.EdgeInsets.symmetric(horizontal: 4, vertical: 3.5),
          child: pw.Text(_latin(t),
              style: pw.TextStyle(fontSize: head ? 8.5 : 8, color: head ? PdfColors.white : (color ?? c(0xFF1F2937)), fontWeight: (head || bold) ? pw.FontWeight.bold : pw.FontWeight.normal)),
        );

    final filters = <String>[
      if (_aSession > 0) 'Session: ${_nameOf(_sessions, 'id', 'session_name', _aSession)}',
      if (_aClass > 0) 'From class: ${_nameOf(_classes, 'class_id', 'class_name', _aClass)}',
      if (_aType.isNotEmpty) 'Type: ${_aType == 'permanent' ? 'Permanent only' : 'Temporary only'}',
    ];

    final doc = pw.Document();
    doc.addPage(pw.MultiPage(
      pageFormat: PdfPageFormat.a4.landscape,
      margin: pw.EdgeInsets.all(10 * mm),
      header: (ctx) => ctx.pageNumber == 1
          ? pw.Container(
              width: double.infinity,
              color: c(0xFF2C3E50),
              padding: pw.EdgeInsets.all(5 * mm),
              margin: pw.EdgeInsets.only(bottom: 4 * mm),
              child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
                pw.Text('Promotion History', style: pw.TextStyle(fontSize: 17, fontWeight: pw.FontWeight.bold, color: PdfColors.white)),
                pw.SizedBox(height: 1.5 * mm),
                pw.Text(
                  _latin('Total: ${_stats['total'] ?? 0}   Permanent: ${_stats['permanent'] ?? 0}   Temporary: ${_stats['temporary'] ?? 0}   Unique students: ${_stats['unique_students'] ?? 0}'
                      '${filters.isEmpty ? '' : '\n${filters.join('   |   ')}'}'),
                  style: pw.TextStyle(fontSize: 8.5, color: c(0xFFD6E4F0)),
                ),
              ]),
            )
          : pw.SizedBox(height: 3 * mm),
      footer: (ctx) => pw.Align(
        alignment: pw.Alignment.centerRight,
        child: pw.Text('Page ${ctx.pageNumber} of ${ctx.pagesCount}', style: pw.TextStyle(fontSize: 7, color: c(0xFF94A3B8))),
      ),
      build: (ctx) => [
        pw.Table(
          border: pw.TableBorder.all(color: c(0xFFE0E0E0), width: 0.3),
          columnWidths: {
            0: pw.FixedColumnWidth(30 * mm),
            1: const pw.FlexColumnWidth(2.2),
            2: pw.FixedColumnWidth(26 * mm),
            3: const pw.FlexColumnWidth(1.4),
            4: const pw.FlexColumnWidth(1.4),
            5: const pw.FlexColumnWidth(1.3),
            6: pw.FixedColumnWidth(22 * mm),
            7: pw.FixedColumnWidth(20 * mm),
          },
          children: [
            pw.TableRow(
              repeat: true,
              decoration: pw.BoxDecoration(color: c(0xFF2C3E50)),
              children: [for (final h in ['Date & Time', 'Student', 'Admission No.', 'From Class', 'To Class', 'Session', 'Type', 'Admin']) cell(h, head: true)],
            ),
            for (var i = 0; i < rows.length; i++)
              pw.TableRow(
                decoration: pw.BoxDecoration(color: i.isOdd ? c(0xFFF8F9FA) : PdfColors.white),
                children: [
                  cell('${rows[i]['promoted_fmt']}'),
                  cell('${rows[i]['fullname']}'),
                  cell('${rows[i]['admission_number'] ?? 'N/A'}'),
                  cell('${rows[i]['old_class']}'),
                  cell('${rows[i]['new_class']}'),
                  cell('${rows[i]['session_name']}'),
                  cell(rows[i]['is_permanent'] == true ? 'Permanent' : 'Temporary', bold: true, color: rows[i]['is_permanent'] == true ? c(0xFF155724) : c(0xFF856404)),
                  cell('Admin #${rows[i]['portaladmin_id']}'),
                ],
              ),
          ],
        ),
      ],
    ));
    return doc.save();
  }

  String _nameOf(List<Map<String, dynamic>> list, String idKey, String nameKey, int id) {
    for (final m in list) {
      if (pInt(m[idKey]) == id) return '${m[nameKey]}';
    }
    return '';
  }

  // ───────────────────────────── BUILD ─────────────────────────────
  @override
  Widget build(BuildContext context) {
    return Theme(
      data: promoLightTheme(),
      child: Scaffold(
        backgroundColor: const Color(0xFF667EEA),
        appBar: AppBar(
          backgroundColor: Colors.transparent,
          surfaceTintColor: Colors.transparent,
          foregroundColor: Colors.white,
          elevation: 0,
          title: const Text('Promotion History', style: TextStyle(fontWeight: FontWeight.w800)),
          actions: [IconButton(tooltip: 'Refresh', icon: const Icon(Icons.refresh), onPressed: () => _load(page: _page))],
        ),
        extendBodyBehindAppBar: true,
        body: Container(
          decoration: const BoxDecoration(gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [Color(0xFF667EEA), Color(0xFF764BA2)])),
          child: SafeArea(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(14, 64, 14, 40),
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 1400),
                  child: Container(
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(15),
                      boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.2), blurRadius: 30, offset: const Offset(0, 10))],
                    ),
                    clipBehavior: Clip.antiAlias,
                    child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                      _header(),
                      Padding(
                        padding: const EdgeInsets.all(18),
                        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                          Align(
                            alignment: Alignment.centerLeft,
                            child: InkWell(
                              borderRadius: BorderRadius.circular(8),
                              onTap: () => Navigator.of(context).maybePop(),
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
                                decoration: BoxDecoration(color: _navy, borderRadius: BorderRadius.circular(8)),
                                child: const Row(mainAxisSize: MainAxisSize.min, children: [
                                  Icon(Icons.arrow_back, size: 16, color: Colors.white),
                                  SizedBox(width: 8),
                                  Text('Back to Promotion', style: TextStyle(color: Colors.white)),
                                ]),
                              ),
                            ),
                          ),
                          const SizedBox(height: 18),
                          _statsGrid(),
                          const SizedBox(height: 22),
                          _filters(),
                          const SizedBox(height: 22),
                          _tableArea(),
                        ]),
                      ),
                    ]),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _header() => Container(
        padding: const EdgeInsets.fromLTRB(22, 24, 22, 22),
        decoration: const BoxDecoration(
          gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [_blue, _navy]),
          border: Border(bottom: BorderSide(color: _blueDark, width: 4)),
        ),
        child: const Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('📜 Promotion History', style: TextStyle(color: Colors.white, fontSize: 26, fontWeight: FontWeight.w700)),
          SizedBox(height: 8),
          Text('Track all student promotions in your institution', style: TextStyle(color: Colors.white70, fontSize: 14)),
        ]),
      );

  // ---------------------------- stats ----------------------------
  Widget _statsGrid() {
    final cards = [
      ('Total Promotions', pInt(_stats['total'])),
      ('Permanent Promotions', pInt(_stats['permanent'])),
      ('Temporary Promotions', pInt(_stats['temporary'])),
      ('Unique Students', pInt(_stats['unique_students'])),
    ];
    return LayoutBuilder(builder: (context, c) {
      const gap = 16.0;
      final cols = c.maxWidth >= 760 ? 4 : 2;
      final w = (c.maxWidth - gap * (cols - 1)) / cols;
      return Wrap(spacing: gap, runSpacing: gap, children: [
        for (final s in cards)
          SizedBox(
            width: w,
            child: AccentCard(
              accent: _blue,
              top: true,
              thickness: 4,
              radius: 10,
              shadow: [BoxShadow(color: Colors.black.withOpacity(0.1), blurRadius: 15, offset: const Offset(0, 3))],
              padding: const EdgeInsets.fromLTRB(12, 18, 12, 18),
              child: Column(children: [
                Text(s.$1.toUpperCase(), textAlign: TextAlign.center, style: const TextStyle(color: _navy, fontSize: 12.5, fontWeight: FontWeight.w700, letterSpacing: 1)),
                const SizedBox(height: 10),
                Text('${s.$2}', style: const TextStyle(fontSize: 32, fontWeight: FontWeight.bold, color: _blue)),
              ]),
            ),
          ),
      ]);
    });
  }

  // ---------------------------- filters ----------------------------
  InputDecoration _selDec() => InputDecoration(
        isDense: true,
        filled: true,
        fillColor: Colors.white,
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(6), borderSide: const BorderSide(color: Color(0xFFE0E0E0), width: 2)),
        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(6), borderSide: const BorderSide(color: _blue, width: 2)),
      );

  Widget _labelledDrop<T>(String label, T value, List<DropdownMenuItem<T>> items, ValueChanged<T?> onChanged) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(padding: const EdgeInsets.only(bottom: 6), child: Text(label, style: const TextStyle(fontSize: 14, color: Color(0xFF333333)))),
          DropdownButtonFormField<T>(
            value: value,
            isExpanded: true,
            decoration: _selDec(),
            style: const TextStyle(fontSize: 14, color: Color(0xFF1F2937)),
            dropdownColor: Colors.white,
            menuMaxHeight: 320,
            items: items,
            onChanged: onChanged,
          ),
        ],
      );

  Widget _solidBtn(String label, Color color, VoidCallback? onTap, {IconData? icon, bool busy = false}) => Opacity(
        opacity: onTap == null ? 0.6 : 1,
        child: InkWell(
          borderRadius: BorderRadius.circular(6),
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 11),
            decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(6)),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              if (busy)
                const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
              else if (icon != null)
                Icon(icon, size: 16, color: Colors.white),
              if (busy || icon != null) const SizedBox(width: 8),
              Text(label, style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w500)),
            ]),
          ),
        ),
      );

  Widget _filters() {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(color: _panel, borderRadius: BorderRadius.circular(10)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        LayoutBuilder(builder: (context, c) {
          final cols = c.maxWidth >= 720 ? 3 : 1;
          final w = (c.maxWidth - 15 * (cols - 1)) / cols;
          return Wrap(spacing: 15, runSpacing: 15, children: [
            SizedBox(
              width: w,
              child: _labelledDrop<int>('Filter by Session:', _sessions.any((s) => pInt(s['id']) == _fSession) ? _fSession : 0, [
                const DropdownMenuItem(value: 0, child: Text('All Sessions')),
                for (final s in _sessions) DropdownMenuItem(value: pInt(s['id']), child: Text('${s['session_name']}', overflow: TextOverflow.ellipsis)),
              ], (v) => setState(() => _fSession = v ?? 0)),
            ),
            SizedBox(
              width: w,
              child: _labelledDrop<int>('Filter by Class:', _classes.any((s) => pInt(s['class_id']) == _fClass) ? _fClass : 0, [
                const DropdownMenuItem(value: 0, child: Text('All Classes')),
                for (final s in _classes) DropdownMenuItem(value: pInt(s['class_id']), child: Text('${s['class_name']}', overflow: TextOverflow.ellipsis)),
              ], (v) => setState(() => _fClass = v ?? 0)),
            ),
            SizedBox(
              width: w,
              child: _labelledDrop<String>('Promotion Type:', _fType, const [
                DropdownMenuItem(value: '', child: Text('All Types')),
                DropdownMenuItem(value: 'permanent', child: Text('Permanent Only')),
                DropdownMenuItem(value: 'temporary', child: Text('Temporary Only')),
              ], (v) => setState(() => _fType = v ?? '')),
            ),
          ]);
        }),
        const SizedBox(height: 16),
        Wrap(spacing: 10, runSpacing: 10, children: [
          _solidBtn('Apply Filters', _blue, _apply),
          _solidBtn('Clear Filters', _grey, _clear),
        ]),
        const SizedBox(height: 16),
        Wrap(spacing: 10, runSpacing: 10, children: [
          _solidBtn('📥 Export as CSV', _green, _busyCsv ? null : _exportCsv, busy: _busyCsv),
          _solidBtn('📄 Export as PDF', _green, _busyPdf ? null : _exportPdf, busy: _busyPdf),
        ]),
      ]),
    );
  }

  // ---------------------------- table ----------------------------
  Widget _tableArea() {
    if (_loading) {
      return const Padding(padding: EdgeInsets.all(40), child: Center(child: CircularProgressIndicator(color: _blue)));
    }
    if (_error != null) {
      return Container(
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(color: const Color(0xFFFEF2F2), borderRadius: BorderRadius.circular(10)),
        child: Column(children: [
          const Icon(Icons.error_outline, color: kRed600, size: 40),
          const SizedBox(height: 8),
          Text(_error!, textAlign: TextAlign.center, style: const TextStyle(color: kRed600)),
          const SizedBox(height: 12),
          _solidBtn('Retry', _blue, () => _load(page: _page), icon: Icons.refresh),
        ]),
      );
    }
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      _table(),
      if (_totalPages > 1) ...[const SizedBox(height: 18), _pager()],
    ]);
  }

  Widget _th(String t) => Padding(padding: const EdgeInsets.all(14), child: Text(t, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14)));
  Widget _td(Widget w) => Padding(padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12), child: w);

  Widget _table() {
    return Container(
      decoration: BoxDecoration(border: Border.all(color: _line), borderRadius: BorderRadius.circular(8)),
      clipBehavior: Clip.antiAlias,
      child: LayoutBuilder(builder: (context, c) {
        final width = math.max(c.maxWidth, 1000.0);
        final rows = <TableRow>[
          TableRow(
            decoration: const BoxDecoration(color: _navy),
            children: [for (final h in ['Date & Time', 'Student', 'Admission No.', 'From Class', 'To Class', 'Session', 'Type', 'Admin']) _th(h)],
          ),
        ];
        if (_history.isEmpty) {
          return Container(
            padding: const EdgeInsets.symmetric(vertical: 40, horizontal: 16),
            alignment: Alignment.center,
            child: const Text('No promotion records found with the selected filters.', textAlign: TextAlign.center, style: TextStyle(color: Color(0xFF7F8C8D))),
          );
        }
        for (var i = 0; i < _history.length; i++) {
          final h = _history[i];
          final perm = h['is_permanent'] == true;
          rows.add(TableRow(
            decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: _line))),
            children: [
              _td(Text('${h['promoted_fmt']}', style: const TextStyle(fontSize: 14))),
              _td(Text('${h['fullname']}', style: const TextStyle(fontSize: 14))),
              _td(Text('${h['admission_number'] ?? 'N/A'}', style: const TextStyle(fontSize: 14))),
              _td(Text('${h['old_class']}', style: const TextStyle(fontSize: 14))),
              _td(Text('${h['new_class']}', style: const TextStyle(fontSize: 14))),
              _td(Text('${h['session_name']}', style: const TextStyle(fontSize: 14))),
              _td(Align(
                alignment: Alignment.centerLeft,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(color: perm ? const Color(0xFFD4EDDA) : const Color(0xFFFFF3CD), borderRadius: BorderRadius.circular(20)),
                  child: Text(perm ? 'Permanent' : 'Temporary', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: perm ? const Color(0xFF155724) : const Color(0xFF856404))),
                ),
              )),
              _td(Text('Admin #${h['portaladmin_id']}', style: const TextStyle(fontSize: 14))),
            ],
          ));
        }
        return SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: SizedBox(
            width: width,
            child: Table(
              defaultVerticalAlignment: TableCellVerticalAlignment.middle,
              columnWidths: const {
                0: FixedColumnWidth(130),
                1: FlexColumnWidth(2),
                2: FixedColumnWidth(130),
                3: FlexColumnWidth(1.3),
                4: FlexColumnWidth(1.3),
                5: FlexColumnWidth(1.2),
                6: FixedColumnWidth(120),
                7: FixedColumnWidth(100),
              },
              children: rows,
            ),
          ),
        );
      }),
    );
  }

  Widget _pager() {
    final start = math.max(1, _page - 2);
    final end = math.min(_totalPages, _page + 2);
    Widget btn({String? label, IconData? icon, VoidCallback? onTap, bool active = false}) => InkWell(
          borderRadius: BorderRadius.circular(6),
          onTap: onTap,
          child: Container(
            constraints: const BoxConstraints(minWidth: 38, minHeight: 36),
            padding: const EdgeInsets.symmetric(horizontal: 12),
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: active ? _blue : Colors.white,
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: active ? _blue : const Color(0xFFE0E0E0), width: 2),
            ),
            child: label != null
                ? Text(label, style: TextStyle(fontWeight: FontWeight.w600, color: active ? Colors.white : const Color(0xFF4A5568)))
                : Icon(icon, size: 18, color: const Color(0xFF4A5568)),
          ),
        );
    return Wrap(alignment: WrapAlignment.spaceBetween, crossAxisAlignment: WrapCrossAlignment.center, runSpacing: 12, spacing: 12, children: [
      Text('Showing $_from to $_to of $_total entries', style: const TextStyle(fontSize: 13.5, color: Color(0xFF4B5563))),
      Wrap(spacing: 6, runSpacing: 6, children: [
        if (_page > 1) ...[
          btn(icon: Icons.keyboard_double_arrow_left, onTap: () => _load(page: 1)),
          btn(icon: Icons.chevron_left, onTap: () => _load(page: _page - 1)),
        ],
        for (var i = start; i <= end; i++) btn(label: '$i', active: i == _page, onTap: i == _page ? null : () => _load(page: i)),
        if (_page < _totalPages) ...[
          btn(icon: Icons.chevron_right, onTap: () => _load(page: _page + 1)),
          btn(icon: Icons.keyboard_double_arrow_right, onTap: () => _load(page: _totalPages)),
        ],
      ]),
    ]);
  }
}
