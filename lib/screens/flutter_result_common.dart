// flutter_result_common.dart
// Shared by flutter_class_results_screen.dart, flutter_result_card_screen.dart,
// flutter_result_reveal_screen.dart and flutter_all_results_screen.dart (keep all five files in one folder).
//
// pubspec.yaml needs:  http, shared_preferences, url_launcher, pdf, printing
//   flutter pub add pdf printing url_launcher
// API: https://schoolsmirror.com/flutter_class_results.php

import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:shared_preferences/shared_preferences.dart';
import '../api/api_client.dart';

// ---- palette of view_class_results.php ----
const Color kRPrimary = Color(0xFF0083B0);
const Color kRSecondary = Color(0xFF00B4DB);
const Color kRPayment = Color(0xFF9C27B0);
const Color kRBg = Color(0xFFF5F7F9);
const Color kRText = Color(0xFF1F2937);
const Color kRMuted = Color(0xFF6C757D);
const Color kRBorder = Color(0xFFE2E8F0);
const Color kRGreen = Color(0xFF28A745);
const Color kRAmber = Color(0xFFFFC107);
const LinearGradient kRPurpleGradient = LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [Color(0xFF667EEA), Color(0xFF764BA2)]);
const TextStyle kRFieldStyle = TextStyle(fontSize: 14, color: kRText);

/// The app theme can be dark; the result pages always use a light theme so text stays readable.
ThemeData resultLightTheme() {
  final base = ThemeData.light();
  return base.copyWith(
    scaffoldBackgroundColor: kRBg,
    canvasColor: Colors.white,
    cardColor: Colors.white,
    colorScheme: base.colorScheme.copyWith(primary: kRPrimary, surface: Colors.white, onSurface: kRText),
    textTheme: base.textTheme.apply(bodyColor: kRText, displayColor: kRText),
  );
}

// ───────────────────────────── helpers ─────────────────────────────
int rInt(dynamic v) => int.tryParse('${v ?? ''}') ?? 0;
double rDouble(dynamic v) => double.tryParse('${v ?? ''}') ?? 0;

/// 45.0 -> "45", 66.667 -> "66.67"
String rNum(dynamic v) {
  final d = rDouble(v);
  if (d == d.roundToDouble()) return d.toInt().toString();
  var s = d.toStringAsFixed(2);
  if (s.endsWith('0')) s = s.substring(0, s.length - 1);
  return s;
}

List<Map<String, dynamic>> rMaps(dynamic v) => (v is List ? v : []).map((e) => Map<String, dynamic>.from(e as Map)).toList();
Map<String, dynamic> rMap(dynamic v) => v is Map ? Map<String, dynamic>.from(v) : <String, dynamic>{};

Color hexColor(dynamic v, [Color fallback = const Color(0xFF3498DB)]) {
  var s = '${v ?? ''}'.trim().replaceFirst('#', '');
  if (s.length == 3) s = s.split('').map((c) => '$c$c').join();
  if (s.length != 6) return fallback;
  final n = int.tryParse(s, radix: 16);
  return n == null ? fallback : Color(0xFF000000 | n);
}

String rFriendly(Object e) {
  final s = e.toString();
  if (e is TimeoutException) return 'Request timed out. Please try again.';
  if (e is http.ClientException || s.contains('Failed to fetch') || s.contains('SocketException')) return 'Cannot reach the server. Check your internet connection.';
  return s.replaceFirst('Exception: ', '');
}

Future<String?> resultToken(String? given) async {
  if (given != null && given.trim().isNotEmpty) return given.trim();
  try {
    await ApiClient.loadToken();
    final t = ApiClient.token;
    if (t != null && t.trim().isNotEmpty) return t.trim();
  } catch (_) {}
  try {
    final p = await SharedPreferences.getInstance();
    final t = p.getString('auth_token') ?? p.getString('token');
    if (t != null && t.trim().isNotEmpty) return t.trim();
  } catch (_) {}
  return null;
}

/// same rules as normalizePhoneForWhatsApp() on the web page
String? waNumber(dynamic raw) {
  if (raw == null) return null;
  var p = '$raw'.trim().replaceAll(RegExp(r'[^0-9+]'), '');
  if (p.isEmpty) return null;
  if (p.startsWith('+')) p = p.substring(1);
  if (p.startsWith('0')) {
    p = '234${p.substring(1)}';
  } else if (!p.startsWith('234') && p.length <= 11) {
    p = '234$p';
  }
  return p;
}

// Your host redirects "*.php" to the extensionless address and a redirect turns POST into GET
// (form data lost -> "Missing token"). The extensionless URL is tried first; the app switches to
// the other form automatically if one of them fails.
const List<String> _apiUrls = [
  'https://schoolsmirror.com/flutter_class_results',
  'https://schoolsmirror.com/flutter_class_results.php',
];
int _apiIdx = 0;

class ResultApi {
  static bool _retry(Map<String, dynamic> d) {
    final m = '${d['message'] ?? ''}';
    return d['success'] != true && (m == 'Unexpected server response' || m.startsWith('The server received this request as') || m.startsWith('Missing token'));
  }

  static Map<String, dynamic> _decode(String body) {
    try {
      final i = body.indexOf('{');
      final d = jsonDecode(i > 0 ? body.substring(i) : body);
      if (d is Map<String, dynamic>) return d;
    } catch (_) {}
    return {'success': false, 'message': 'Unexpected server response'};
  }

  /// POST (token + action + fields are in the URL AND the body so they survive a redirect)
  static Future<Map<String, dynamic>> call(String token, String action, [Map<String, String> fields = const {}]) async {
    Object? err;
    for (var i = 0; i < _apiUrls.length; i++) {
      try {
        final uri = Uri.parse(_apiUrls[_apiIdx]).replace(queryParameters: {'token': token, 'action': action, ...fields});
        final res = await http
            .post(uri, headers: {'Content-Type': 'application/x-www-form-urlencoded; charset=utf-8'}, body: {'token': token, 'action': action, ...fields})
            .timeout(const Duration(seconds: 60));
        final d = _decode(res.body);
        if (_retry(d) && _apiIdx < _apiUrls.length - 1) {
          _apiIdx++;
          continue;
        }
        return d;
      } catch (e) {
        err = e;
        if (_apiIdx < _apiUrls.length - 1) {
          _apiIdx++;
          continue;
        }
      }
    }
    throw Exception(rFriendly(err ?? 'Request failed'));
  }
}

// ───────────────────────────── grade colours ─────────────────────────────
Color scoreColor(num s) => s >= 70 ? const Color(0xFF16A34A) : (s >= 50 ? const Color(0xFFD97706) : const Color(0xFFDC2626));

// ───────────────────────────── REPORT CARD (Flutter view) ─────────────────────────────
/// Builds the result card from the data of `student_card`, using the template colours of the class.
class ReportCardView extends StatelessWidget {
  final Map<String, dynamic> card;
  const ReportCardView({super.key, required this.card});

  @override
  Widget build(BuildContext context) {
    final school = rMap(card['school']);
    final st = rMap(card['student']);
    final sum = rMap(card['summary']);
    final colors = rMap(rMap(card['template'])['colors']);
    final primary = hexColor(colors['primary_color']);
    final secondary = hexColor(colors['secondary_color'], const Color(0xFF2C3E50));
    final accent = hexColor(colors['accent_color'], const Color(0xFFE74C3C));
    final textDark = hexColor(colors['text_dark'], const Color(0xFF2C3E50));
    final border = hexColor(colors['border_color'], const Color(0xFFBDC3C7));
    final subjects = rMaps(card['subjects']);
    final columns = rMaps(card['columns']);
    final scale = rMaps(card['grade_scale']);
    final att = rMap(card['attendance']);
    final aff = rMaps(card['affective']);
    final psy = rMaps(card['psychomotor']);
    final next = rMap(card['next_term']);

    Widget sectionTitle(String t) => Container(
          width: double.infinity,
          margin: const EdgeInsets.only(top: 16, bottom: 8),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
          decoration: BoxDecoration(color: primary, borderRadius: BorderRadius.circular(6)),
          child: Text(t.toUpperCase(), style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w800, letterSpacing: 0.6)),
        );

    Widget info(String k, String v) => SizedBox(
          width: 150,
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(k.toUpperCase(), style: TextStyle(fontSize: 9.5, color: textDark.withOpacity(0.55), fontWeight: FontWeight.w700, letterSpacing: 0.4)),
            const SizedBox(height: 2),
            Text(v.isEmpty ? '—' : v, style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700, color: textDark)),
          ]),
        );

    final pos = '${sum['position'] ?? ''}'.trim();
    final photo = '${st['photo_url'] ?? ''}';
    final logo = '${school['logo_url'] ?? ''}';

    // ---- subject table ----
    const subjW = 150.0, totW = 62.0, grW = 56.0, remW = 120.0, colW = 58.0;
    final tableW = subjW + columns.length * colW + totW + grW + remW;
    Widget cell(String t, double w, {bool head = false, bool bold = false, Color? color, TextAlign align = TextAlign.center}) => Container(
          width: w,
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
          child: Text(t, textAlign: align, style: TextStyle(fontSize: head ? 11 : 12.5, fontWeight: (head || bold) ? FontWeight.w800 : FontWeight.w500, color: head ? Colors.white : (color ?? textDark))),
        );

    final table = SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Container(
        width: tableW,
        decoration: BoxDecoration(border: Border.all(color: border)),
        child: Column(children: [
          Container(
            color: secondary,
            child: Row(children: [
              cell('SUBJECT', subjW, head: true, align: TextAlign.left),
              for (final c in columns) cell('${c['label']}'.toUpperCase(), colW, head: true),
              cell('TOTAL', totW, head: true),
              cell('GRADE', grW, head: true),
              cell('REMARK', remW, head: true),
            ]),
          ),
          for (var i = 0; i < subjects.length; i++)
            Container(
              color: i.isOdd ? primary.withOpacity(0.06) : Colors.white,
              child: Row(children: [
                cell('${subjects[i]['subject']}', subjW, bold: true, align: TextAlign.left),
                for (final c in columns) cell(subjects[i]['scores'] is Map && subjects[i]['scores'][c['key']] != null ? rNum(subjects[i]['scores'][c['key']]) : '—', colW),
                cell(rNum(subjects[i]['total']), totW, bold: true, color: scoreColor(rDouble(subjects[i]['total']))),
                cell('${subjects[i]['grade'] ?? ''}', grW, bold: true, color: scoreColor(rDouble(subjects[i]['total']))),
                cell('${subjects[i]['remark'] ?? ''}', remW),
              ]),
            ),
          if (subjects.isEmpty) const Padding(padding: EdgeInsets.all(18), child: Text('No finalized results yet.')),
        ]),
      ),
    );

    Widget tile(String label, String value, [Color? c]) => Expanded(
          child: Container(
            margin: const EdgeInsets.symmetric(horizontal: 3),
            padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 4),
            decoration: BoxDecoration(color: (c ?? primary).withOpacity(0.1), borderRadius: BorderRadius.circular(8), border: Border.all(color: (c ?? primary).withOpacity(0.35))),
            child: Column(children: [
              Text(value, style: TextStyle(fontSize: 16, fontWeight: FontWeight.w900, color: c ?? primary)),
              const SizedBox(height: 2),
              Text(label, textAlign: TextAlign.center, style: TextStyle(fontSize: 9.5, color: textDark.withOpacity(0.7), fontWeight: FontWeight.w600)),
            ]),
          ),
        );

    Widget traitList(String title, List<Map<String, dynamic>> list) => Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(title, style: TextStyle(fontWeight: FontWeight.w800, color: secondary, fontSize: 12.5)),
            const SizedBox(height: 4),
            if (list.isEmpty) Text('—', style: TextStyle(color: textDark.withOpacity(0.5))),
            for (final t in list)
              Padding(
                padding: const EdgeInsets.only(bottom: 3),
                child: Row(children: [
                  Expanded(child: Text('${t['trait_name']}', style: TextStyle(fontSize: 12, color: textDark))),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                    decoration: BoxDecoration(color: primary.withOpacity(0.12), borderRadius: BorderRadius.circular(10)),
                    child: Text('${t['rating']}', style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w800, color: primary)),
                  ),
                ]),
              ),
          ]),
        );

    Widget sig(String url, String label) => Expanded(
          child: Column(children: [
            SizedBox(
              height: 46,
              child: url.isEmpty ? null : Image.network(url, fit: BoxFit.contain, errorBuilder: (_, __, ___) => const SizedBox.shrink()),
            ),
            Container(height: 1, color: border, margin: const EdgeInsets.symmetric(horizontal: 12)),
            const SizedBox(height: 3),
            Text(label, style: TextStyle(fontSize: 10.5, color: textDark.withOpacity(0.7))),
          ]),
        );

    return Container(
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14), border: Border.all(color: border), boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.08), blurRadius: 18, offset: const Offset(0, 6))]),
      clipBehavior: Clip.antiAlias,
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        // header
        Container(
          padding: const EdgeInsets.fromLTRB(16, 18, 16, 16),
          decoration: BoxDecoration(gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [primary, secondary])),
          child: Column(children: [
            if (logo.isNotEmpty)
              Container(
                width: 64,
                height: 64,
                margin: const EdgeInsets.only(bottom: 8),
                decoration: const BoxDecoration(color: Colors.white, shape: BoxShape.circle),
                padding: const EdgeInsets.all(4),
                child: ClipOval(child: Image.network(logo, fit: BoxFit.cover, errorBuilder: (_, __, ___) => const Icon(Icons.school, color: Colors.grey))),
              ),
            Text('${school['name'] ?? ''}'.toUpperCase(), textAlign: TextAlign.center, style: const TextStyle(color: Colors.white, fontSize: 19, fontWeight: FontWeight.w900, height: 1.2)),
            if ('${school['address'] ?? ''}'.isNotEmpty) Text('${school['address']}${'${school['sub_address'] ?? ''}'.isNotEmpty ? ', ${school['sub_address']}' : ''}', textAlign: TextAlign.center, style: TextStyle(color: Colors.white.withOpacity(0.85), fontSize: 11.5)),
            if ('${school['motto'] ?? ''}'.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 3), child: Text('“${school['motto']}”', textAlign: TextAlign.center, style: TextStyle(color: Colors.white.withOpacity(0.9), fontSize: 11.5, fontStyle: FontStyle.italic))),
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 5),
              decoration: BoxDecoration(color: Colors.white.withOpacity(0.18), borderRadius: BorderRadius.circular(20)),
              child: Text('STUDENT REPORT CARD  •  ${card['term_name'] ?? ''}  •  ${card['session_name'] ?? ''}', textAlign: TextAlign.center, style: const TextStyle(color: Colors.white, fontSize: 11.5, fontWeight: FontWeight.w700, letterSpacing: 0.4)),
            ),
          ]),
        ),
        Padding(
          padding: const EdgeInsets.all(14),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            // student
            Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Container(
                width: 84,
                height: 84,
                decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: primary, width: 3), color: Colors.white),
                padding: const EdgeInsets.all(2),
                child: ClipOval(
                  child: photo.isEmpty
                      ? Container(color: primary.withOpacity(0.15), child: Icon(Icons.person, size: 44, color: primary))
                      : Image.network(photo, fit: BoxFit.cover, errorBuilder: (_, __, ___) => Container(color: primary.withOpacity(0.15), child: Icon(Icons.person, size: 44, color: primary))),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Wrap(spacing: 8, runSpacing: 10, children: [
                  SizedBox(width: 280, child: info('Name', '${st['fullname'] ?? ''}')),
                  info('ID Number', '${st['idnumber'] ?? ''}'),
                  info('Admission No', '${st['admission_number'] ?? ''}'),
                  info('Class', '${st['class_name'] ?? ''}${st['is_transferred'] == true ? ' (transferred)' : ''}'),
                  info('Gender', '${st['gender'] ?? ''}'),
                  info('Department', '${st['department'] ?? ''}' == 'N/A' ? '' : '${st['department']}'),
                ]),
              ),
            ]),
            sectionTitle('Academic Performance'),
            table,
            const SizedBox(height: 12),
            Row(children: [
              tile('SUBJECTS', '${rInt(sum['subject_count'])}'),
              tile('TOTAL SCORE', rNum(sum['total_score'])),
              tile('AVERAGE', rNum(sum['average_score']), scoreColor(rDouble(sum['average_score']))),
              tile('POSITION', pos.isEmpty ? '—' : '$pos / ${rInt(sum['students_in_class'])}', accent),
            ]),
            if (scale.isNotEmpty) ...[
              sectionTitle('Grading Key'),
              Wrap(spacing: 6, runSpacing: 6, children: [
                for (final g in scale)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                    decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(6), border: Border.all(color: border)),
                    child: Text('${g['grade']}  ${rNum(g['min'])}–${rNum(g['max'])}${'${g['remark']}'.isEmpty ? '' : '  ${g['remark']}'}', style: TextStyle(fontSize: 10.5, color: textDark, fontWeight: FontWeight.w600)),
                  ),
              ]),
            ],
            sectionTitle('Attendance'),
            Wrap(spacing: 18, runSpacing: 6, children: [
              Text('Times present: ${rInt(att['no_of_attendance'])}', style: TextStyle(color: textDark, fontWeight: FontWeight.w600, fontSize: 13)),
              Text('Times school opened: ${rInt(att['no_of_time_school_opened'])}', style: TextStyle(color: textDark, fontWeight: FontWeight.w600, fontSize: 13)),
              Text('Attendance: ${rNum(att['attendance_percentage'])}%', style: TextStyle(color: primary, fontWeight: FontWeight.w800, fontSize: 13)),
            ]),
            if (aff.isNotEmpty || psy.isNotEmpty) ...[
              sectionTitle('Behaviour & Skills'),
              Row(crossAxisAlignment: CrossAxisAlignment.start, children: [traitList('Affective Domain', aff), const SizedBox(width: 16), traitList('Psychomotor Domain', psy)]),
            ],
            sectionTitle('Remarks'),
            if ('${card['teacher_comment'] ?? ''}'.isNotEmpty) _remark(textDark, 'Class Teacher', '${card['teacher_comment']}'),
            if ('${card['proprietor_comment'] ?? ''}'.isNotEmpty) _remark(textDark, 'Principal / Proprietor', '${card['proprietor_comment']}'),
            if ('${card['teacher_comment'] ?? ''}'.isEmpty && '${card['proprietor_comment'] ?? ''}'.isEmpty) Text('No remarks yet.', style: TextStyle(color: textDark.withOpacity(0.55))),
            const SizedBox(height: 14),
            Row(children: [sig('${card['teacher_signature_url'] ?? ''}', 'Class Teacher'), const SizedBox(width: 16), sig('${card['principal_signature_url'] ?? ''}', 'Principal')]),
            const SizedBox(height: 14),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(color: primary.withOpacity(0.08), borderRadius: BorderRadius.circular(8)),
              child: Row(children: [
                Icon(Icons.event, size: 18, color: primary),
                const SizedBox(width: 8),
                Expanded(child: Text('${next['description'] ?? 'Next Term Begins'}: ${next['date_fmt'] ?? ''}', style: TextStyle(fontWeight: FontWeight.w700, color: textDark, fontSize: 13))),
              ]),
            ),
          ]),
        ),
      ]),
    );
  }

  Widget _remark(Color textDark, String who, String text) => Container(
        width: double.infinity,
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(color: const Color(0xFFF8FAFC), borderRadius: BorderRadius.circular(8), border: Border.all(color: const Color(0xFFE2E8F0))),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(who, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: textDark.withOpacity(0.6))),
          const SizedBox(height: 3),
          Text(text, style: TextStyle(fontSize: 13, color: textDark, height: 1.35)),
        ]),
      );
}

// ───────────────────────────── PDF ─────────────────────────────
/// A4 portrait, one page (or more if it does not fit) per student. The built-in PDF font only knows
/// Latin-1, so other characters are replaced by "?".
class ReportCardPdf {
  static String _l(dynamic s) => '${s ?? ''}'.runes.map((r) => r < 256 ? String.fromCharCode(r) : '?').join();

  static Future<pw.MemoryImage?> _img(String url) async {
    if (url.isEmpty) return null;
    try {
      final r = await http.get(Uri.parse(url)).timeout(const Duration(seconds: 8));
      if (r.statusCode != 200 || r.bodyBytes.isEmpty) return null;
      return pw.MemoryImage(r.bodyBytes);
    } catch (_) {
      return null;
    }
  }

  static PdfColor _c(Color c) => PdfColor(c.red / 255, c.green / 255, c.blue / 255);
  static PdfColor _score(num s) => s >= 70 ? PdfColor.fromInt(0xFF16A34A) : (s >= 50 ? PdfColor.fromInt(0xFFD97706) : PdfColor.fromInt(0xFFDC2626));

  static Future<Uint8List> build(List<Map<String, dynamic>> cards, {void Function(double)? onProgress}) async {
    final doc = pw.Document();
    for (var i = 0; i < cards.length; i++) {
      await _addCard(doc, cards[i]);
      onProgress?.call((i + 1) / cards.length);
    }
    return doc.save();
  }

  static Future<void> _addCard(pw.Document doc, Map<String, dynamic> card) async {
    final school = rMap(card['school']);
    final st = rMap(card['student']);
    final sum = rMap(card['summary']);
    final colors = rMap(rMap(card['template'])['colors']);
    final primary = _c(hexColor(colors['primary_color']));
    final secondary = _c(hexColor(colors['secondary_color'], const Color(0xFF2C3E50)));
    final textDark = _c(hexColor(colors['text_dark'], const Color(0xFF2C3E50)));
    final subjects = rMaps(card['subjects']);
    final columns = rMaps(card['columns']);
    final scale = rMaps(card['grade_scale']);
    final att = rMap(card['attendance']);
    final aff = rMaps(card['affective']);
    final psy = rMaps(card['psychomotor']);
    final next = rMap(card['next_term']);

    final images = await Future.wait([_img('${school['logo_url']}'), _img('${st['photo_url']}'), _img('${card['teacher_signature_url']}'), _img('${card['principal_signature_url']}')]);
    final logo = images[0], photo = images[1], tSig = images[2], pSig = images[3];

    final fs = subjects.length > 16 ? 8.0 : 9.0;
    pw.Widget cell(String t, {bool head = false, bool bold = false, PdfColor? color, pw.TextAlign align = pw.TextAlign.center}) => pw.Padding(
          padding: const pw.EdgeInsets.symmetric(horizontal: 3, vertical: 3.2),
          child: pw.Text(_l(t), textAlign: align, style: pw.TextStyle(fontSize: head ? fs - 0.5 : fs, color: head ? PdfColors.white : (color ?? textDark), fontWeight: (head || bold) ? pw.FontWeight.bold : pw.FontWeight.normal)),
        );

    final widths = <int, pw.TableColumnWidth>{0: const pw.FlexColumnWidth(3)};
    for (var i = 0; i < columns.length; i++) {
      widths[1 + i] = const pw.FlexColumnWidth(1);
    }
    widths[1 + columns.length] = const pw.FlexColumnWidth(1.1);
    widths[2 + columns.length] = const pw.FlexColumnWidth(1);
    widths[3 + columns.length] = const pw.FlexColumnWidth(2.4);

    final pos = '${sum['position'] ?? ''}'.trim();

    pw.Widget title(String t) => pw.Container(
          width: double.infinity,
          color: primary,
          margin: const pw.EdgeInsets.only(top: 9, bottom: 4),
          padding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 3),
          child: pw.Text(t.toUpperCase(), style: pw.TextStyle(color: PdfColors.white, fontSize: 8.5, fontWeight: pw.FontWeight.bold)),
        );

    pw.Widget traits(String t, List<Map<String, dynamic>> list) => pw.Expanded(
          child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
            pw.Text(t, style: pw.TextStyle(fontSize: 8.5, fontWeight: pw.FontWeight.bold, color: secondary)),
            pw.SizedBox(height: 2),
            for (final x in list)
              pw.Row(mainAxisAlignment: pw.MainAxisAlignment.spaceBetween, children: [
                pw.Text(_l(x['trait_name']), style: pw.TextStyle(fontSize: 8, color: textDark)),
                pw.Text(_l(x['rating']), style: pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold, color: primary)),
              ]),
          ]),
        );

    pw.Widget sig(pw.MemoryImage? img, String label) => pw.Expanded(
          child: pw.Column(children: [
            pw.SizedBox(height: 34, child: img == null ? null : pw.Image(img, fit: pw.BoxFit.contain)),
            pw.Container(height: 0.6, color: PdfColors.grey500, margin: const pw.EdgeInsets.symmetric(horizontal: 14)),
            pw.Text(label, style: const pw.TextStyle(fontSize: 7.5, color: PdfColors.grey700)),
          ]),
        );

    doc.addPage(pw.MultiPage(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.all(22),
      build: (ctx) => [
        pw.Container(
          width: double.infinity,
          color: primary,
          padding: const pw.EdgeInsets.all(10),
          child: pw.Row(children: [
            if (logo != null) pw.Container(width: 44, height: 44, margin: const pw.EdgeInsets.only(right: 10), child: pw.Image(logo, fit: pw.BoxFit.cover)),
            pw.Expanded(
              child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
                pw.Text(_l('${school['name']}').toUpperCase(), style: pw.TextStyle(color: PdfColors.white, fontSize: 15, fontWeight: pw.FontWeight.bold)),
                if ('${school['address'] ?? ''}'.isNotEmpty) pw.Text(_l('${school['address']} ${school['sub_address'] ?? ''}'), style: const pw.TextStyle(color: PdfColors.white, fontSize: 8)),
                if ('${school['motto'] ?? ''}'.isNotEmpty) pw.Text(_l('"${school['motto']}"'), style: pw.TextStyle(color: PdfColors.white, fontSize: 8, fontStyle: pw.FontStyle.italic)),
                pw.SizedBox(height: 3),
                pw.Text(_l('STUDENT REPORT CARD  -  ${card['term_name']}  -  ${card['session_name']}'), style: pw.TextStyle(color: PdfColors.white, fontSize: 9, fontWeight: pw.FontWeight.bold)),
              ]),
            ),
          ]),
        ),
        pw.SizedBox(height: 8),
        pw.Row(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
          if (photo != null) pw.Container(width: 54, height: 54, margin: const pw.EdgeInsets.only(right: 10), decoration: pw.BoxDecoration(border: pw.Border.all(color: primary, width: 1.5)), child: pw.Image(photo, fit: pw.BoxFit.cover)),
          pw.Expanded(
            child: pw.Wrap(spacing: 14, runSpacing: 4, children: [
              for (final e in [
                ['Name', st['fullname']],
                ['ID Number', st['idnumber']],
                ['Admission No', st['admission_number']],
                ['Class', st['class_name']],
                ['Gender', st['gender']],
                ['Position', pos.isEmpty ? '-' : '$pos / ${rInt(sum['students_in_class'])}'],
              ])
                pw.SizedBox(
                  width: 150,
                  child: pw.RichText(text: pw.TextSpan(children: [
                    pw.TextSpan(text: '${e[0]}: ', style: pw.TextStyle(fontSize: 8, color: PdfColors.grey700)),
                    pw.TextSpan(text: _l(e[1]), style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold, color: textDark)),
                  ])),
                ),
            ]),
          ),
        ]),
        title('Academic Performance'),
        pw.Table(
          columnWidths: widths,
          border: pw.TableBorder.all(color: PdfColors.grey400, width: 0.4),
          children: [
            pw.TableRow(decoration: pw.BoxDecoration(color: secondary), children: [
              cell('SUBJECT', head: true, align: pw.TextAlign.left),
              for (final c in columns) cell('${c['label']}'.toUpperCase(), head: true),
              cell('TOTAL', head: true),
              cell('GRADE', head: true),
              cell('REMARK', head: true),
            ]),
            for (var i = 0; i < subjects.length; i++)
              pw.TableRow(decoration: pw.BoxDecoration(color: i.isOdd ? PdfColor.fromInt(0xFFF8FAFC) : PdfColors.white), children: [
                cell('${subjects[i]['subject']}', bold: true, align: pw.TextAlign.left),
                for (final c in columns) cell(subjects[i]['scores'] is Map && subjects[i]['scores'][c['key']] != null ? rNum(subjects[i]['scores'][c['key']]) : '-'),
                cell(rNum(subjects[i]['total']), bold: true, color: _score(rDouble(subjects[i]['total']))),
                cell('${subjects[i]['grade'] ?? ''}', bold: true, color: _score(rDouble(subjects[i]['total']))),
                cell('${subjects[i]['remark'] ?? ''}'),
              ]),
          ],
        ),
        pw.SizedBox(height: 6),
        pw.Row(mainAxisAlignment: pw.MainAxisAlignment.spaceBetween, children: [
          pw.Text('Subjects: ${rInt(sum['subject_count'])}', style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold, color: textDark)),
          pw.Text('Total: ${rNum(sum['total_score'])}', style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold, color: textDark)),
          pw.Text('Average: ${rNum(sum['average_score'])}', style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold, color: _score(rDouble(sum['average_score'])))),
          pw.Text('Position: ${pos.isEmpty ? '-' : pos}', style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold, color: textDark)),
        ]),
        if (scale.isNotEmpty) ...[
          title('Grading Key'),
          pw.Wrap(spacing: 8, runSpacing: 2, children: [
            for (final g in scale) pw.Text(_l('${g['grade']} ${rNum(g['min'])}-${rNum(g['max'])} ${g['remark']}'), style: const pw.TextStyle(fontSize: 7.5, color: PdfColors.grey800)),
          ]),
        ],
        title('Attendance'),
        pw.Text('Present: ${rInt(att['no_of_attendance'])}   School opened: ${rInt(att['no_of_time_school_opened'])}   Attendance: ${rNum(att['attendance_percentage'])}%', style: pw.TextStyle(fontSize: 8.5, color: textDark)),
        if (aff.isNotEmpty || psy.isNotEmpty) ...[
          title('Behaviour & Skills'),
          pw.Row(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [traits('Affective Domain', aff), pw.SizedBox(width: 16), traits('Psychomotor Domain', psy)]),
        ],
        title('Remarks'),
        if ('${card['teacher_comment'] ?? ''}'.isNotEmpty) pw.Text(_l('Class Teacher: ${card['teacher_comment']}'), style: pw.TextStyle(fontSize: 8.5, color: textDark)),
        if ('${card['proprietor_comment'] ?? ''}'.isNotEmpty) pw.Padding(padding: const pw.EdgeInsets.only(top: 3), child: pw.Text(_l('Principal: ${card['proprietor_comment']}'), style: pw.TextStyle(fontSize: 8.5, color: textDark))),
        pw.SizedBox(height: 10),
        pw.Row(children: [sig(tSig, 'Class Teacher'), pw.SizedBox(width: 20), sig(pSig, 'Principal')]),
        pw.SizedBox(height: 8),
        pw.Text(_l('${next['description'] ?? 'Next Term Begins'}: ${next['date_fmt'] ?? ''}'), style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold, color: primary)),
      ],
    ));
  }
}

/// small shared widgets
class RStatusBadge extends StatelessWidget {
  final String status;
  final int count;
  const RStatusBadge(this.status, {super.key, this.count = 0});
  @override
  Widget build(BuildContext context) {
    Color bg, fg;
    String label;
    switch (status) {
      case 'finalized':
        bg = const Color(0xFF28A745);
        fg = Colors.white;
        label = 'Finalized';
        break;
      case 'draft':
        bg = const Color(0xFFFFC107);
        fg = const Color(0xFF212529);
        label = 'Draft';
        break;
      default:
        bg = const Color(0xFF6C757D);
        fg = Colors.white;
        label = 'No Result';
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(20)),
      child: Text('$label${count > 0 ? ' ($count subjects)' : ''}', style: TextStyle(color: fg, fontSize: 12, fontWeight: FontWeight.w700)),
    );
  }
}

String rInitials(String name) {
  final p = name.trim().split(RegExp(r'\s+')).where((e) => e.isNotEmpty).take(2).toList();
  return p.isEmpty ? '?' : p.map((e) => e[0].toUpperCase()).join();
}

class RAvatar extends StatelessWidget {
  final String name;
  final String url;
  final double size;
  const RAvatar({super.key, required this.name, required this.url, this.size = 42});
  @override
  Widget build(BuildContext context) {
    final fallback = Container(color: const Color(0xFF667EEA), alignment: Alignment.center, child: Text(rInitials(name), style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: size * 0.36)));
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: const Color(0xFFDEE2E6), width: 2)),
      child: ClipOval(child: url.isEmpty ? fallback : Image.network(url, fit: BoxFit.cover, errorBuilder: (_, __, ___) => fallback)),
    );
  }
}

/// the 0-100 reveal mood used by the preloader
String perfEmoji(double p) => p >= 70 ? '🏆' : (p >= 60 ? '⭐' : (p >= 50 ? '👍' : (p >= 40 ? '📈' : '📚')));
String perfLabel(double p) => p >= 80 ? 'Excellent' : (p >= 70 ? 'Very Good' : (p >= 60 ? 'Good' : (p >= 50 ? 'Average' : 'Needs Effort')));
double clampD(double v, double lo, double hi) => math.max(lo, math.min(hi, v));
