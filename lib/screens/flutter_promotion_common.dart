// flutter_promotion_common.dart
// Shared by flutter_promote_students_screen.dart, flutter_revert_promotions_screen.dart and
// flutter_promotion_history_screen.dart  (put all four files in the same folder).
//
// API: https://schoolsmirror.com/flutter_promotion.php

import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../api/api_client.dart';

// ---- Tailwind palette used by the web pages ----
const Color kIndigo50 = Color(0xFFEEF2FF);
const Color kPurple50 = Color(0xFFFAF5FF);
const Color kPink50 = Color(0xFFFDF2F8);
const Color kIndigo300 = Color(0xFFA5B4FC);
const Color kIndigo600 = Color(0xFF4F46E5);
const Color kPurple100 = Color(0xFFF3E8FF);
const Color kPurple300 = Color(0xFFD8B4FE);
const Color kPurple600 = Color(0xFF9333EA);
const Color kPurple700 = Color(0xFF7E22CE);
const Color kPink100 = Color(0xFFFCE7F3);
const Color kPink600 = Color(0xFFDB2777);
const Color kRed100 = Color(0xFFFEE2E2);
const Color kRed300 = Color(0xFFFCA5A5);
const Color kRed600 = Color(0xFFDC2626);
const Color kRed700 = Color(0xFFB91C1C);
const Color kOrange100 = Color(0xFFFFEDD5);
const Color kOrange600 = Color(0xFFEA580C);
const Color kGreen100 = Color(0xFFDCFCE7);
const Color kGreen500 = Color(0xFF22C55E);
const Color kGreen600 = Color(0xFF16A34A);
const Color kGreen700 = Color(0xFF15803D);
const Color kGreen800 = Color(0xFF166534);
const Color kBlue100 = Color(0xFFDBEAFE);
const Color kBlue800 = Color(0xFF1E40AF);
const Color kYellow50 = Color(0xFFFEFCE8);
const Color kYellow300 = Color(0xFFFDE047);
const Color kYellow700 = Color(0xFFA16207);
const Color kYellow800 = Color(0xFF854D0E);
const Color kGray100 = Color(0xFFF3F4F6);
const Color kGray200 = Color(0xFFE5E7EB);
const Color kGray600 = Color(0xFF4B5563);
const Color kGray700 = Color(0xFF374151);
const Color kGray800 = Color(0xFF1F2937);

const LinearGradient kPageGradient = LinearGradient(
  begin: Alignment.topLeft,
  end: Alignment.bottomRight,
  colors: [kIndigo50, kPurple50, kPink50],
);
const TextStyle kFieldStyle = TextStyle(fontSize: 15, color: kGray800);

/// The app theme can be dark; the promotion pages always use a light theme so text stays readable.
ThemeData promoLightTheme() {
  final base = ThemeData.light();
  return base.copyWith(
    scaffoldBackgroundColor: kIndigo50,
    canvasColor: Colors.white,
    cardColor: Colors.white,
    colorScheme: base.colorScheme.copyWith(primary: kIndigo600, surface: Colors.white, onSurface: kGray800),
    textTheme: base.textTheme.apply(bodyColor: kGray800, displayColor: kGray800),
  );
}

// ───────────────────────────── helpers ─────────────────────────────
int pInt(dynamic v) => int.tryParse('${v ?? ''}') ?? 0;

List<Map<String, dynamic>> pMaps(dynamic v) =>
    (v is List ? v : []).map((e) => Map<String, dynamic>.from(e as Map)).toList();

String promoFriendly(Object e) {
  final s = e.toString();
  if (e is TimeoutException) return 'Request timed out. Please try again.';
  if (e is http.ClientException || s.contains('Failed to fetch') || s.contains('SocketException')) {
    return 'Cannot reach the server. Check your internet connection.';
  }
  return s.replaceFirst('Exception: ', '');
}

Future<String?> promoToken(String? given) async {
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

// Your host redirects "*.php" to the extensionless address and a redirect turns POST into GET
// (form data lost -> "Missing token"). The extensionless URL is tried first; the app switches to
// the other form automatically if one of them fails.
const List<String> _apiUrls = [
  'https://schoolsmirror.com/flutter_promotion',
  'https://schoolsmirror.com/flutter_promotion.php',
];
int _apiIdx = 0;

class PromoApi {
  static bool _retry(Map<String, dynamic> d) {
    final m = '${d['message'] ?? ''}';
    return d['success'] != true &&
        (m == 'Unexpected server response' ||
            m.startsWith('The server received this request as') ||
            m.startsWith('Missing token'));
  }

  static Map<String, dynamic> _decode(String body) {
    try {
      final i = body.indexOf('{');
      final d = jsonDecode(i > 0 ? body.substring(i) : body);
      if (d is Map<String, dynamic>) return d;
    } catch (_) {}
    return {'success': false, 'message': 'Unexpected server response'};
  }

  /// POST. token + action + small fields are sent in the URL AND the body so they survive a redirect.
  /// Lists use bracket keys, e.g. {'student_ids[0]': '5'}. Pass queryToo:false for big bodies.
  static Future<Map<String, dynamic>> call(
    String token,
    String action, [
    Map<String, String> fields = const {},
    bool queryToo = true,
  ]) async {
    Object? err;
    for (var i = 0; i < _apiUrls.length; i++) {
      try {
        final uri = Uri.parse(_apiUrls[_apiIdx]).replace(queryParameters: {
          'token': token,
          'action': action,
          if (queryToo) ...fields,
        });
        final res = await http
            .post(
              uri,
              headers: {'Content-Type': 'application/x-www-form-urlencoded; charset=utf-8'},
              body: {'token': token, 'action': action, ...fields},
            )
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
    throw Exception(promoFriendly(err ?? 'Request failed'));
  }

  /// GET url for downloads (CSV export).
  static Uri downloadUri(String token, String action, Map<String, String> fields) =>
      Uri.parse(_apiUrls[_apiIdx]).replace(queryParameters: {'token': token, 'action': action, ...fields});
}

// ───────────────────────────── widgets ─────────────────────────────

class PromoPill extends StatelessWidget {
  final String text;
  final Color bg;
  final Color fg;
  final IconData? icon;
  final double size;
  const PromoPill(this.text, {super.key, required this.bg, required this.fg, this.icon, this.size = 12});

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
        decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(20)),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          if (icon != null) ...[Icon(icon, size: size + 1, color: fg), const SizedBox(width: 4)],
          Flexible(child: Text(text, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: size, fontWeight: FontWeight.w700, color: fg))),
        ]),
      );
}

/// Rounded card with a coloured stripe on the left (or top). Flutter cannot paint a non-uniform
/// border together with a border radius, so the stripe is a real child that gets clipped instead.
class AccentCard extends StatelessWidget {
  final Color accent;
  final bool top;
  final double thickness;
  final double radius;
  final Color bg;
  final Color? outline;
  final double outlineWidth;
  final List<BoxShadow>? shadow;
  final EdgeInsets padding;
  final Widget child;
  const AccentCard({
    super.key,
    required this.accent,
    required this.child,
    this.top = false,
    this.thickness = 4,
    this.radius = 12,
    this.bg = Colors.white,
    this.outline,
    this.outlineWidth = 2,
    this.shadow,
    this.padding = const EdgeInsets.all(14),
  });

  @override
  Widget build(BuildContext context) {
    final stripe = top
        ? Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
            Container(height: thickness, color: accent),
            Padding(padding: padding, child: child),
          ])
        : IntrinsicHeight(
            child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Container(width: thickness, color: accent),
              Expanded(child: Padding(padding: padding, child: child)),
            ]),
          );
    return Container(
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(radius),
        boxShadow: shadow,
        border: outline != null ? Border.all(color: outline!, width: outlineWidth) : null,
      ),
      child: ClipRRect(borderRadius: BorderRadius.circular(math.max(0, radius - (outline != null ? outlineWidth : 0))), child: stripe),
    );
  }
}

/// Green success / red error banner (same look as the web alerts).
class PromoBanner extends StatelessWidget {
  final String message;
  final bool error;
  final VoidCallback? onClose;
  final List<String> extraLines;
  const PromoBanner(this.message, {super.key, this.error = false, this.onClose, this.extraLines = const []});

  @override
  Widget build(BuildContext context) {
    final bg = error ? kRed100 : kGreen100;
    final edge = error ? const Color(0xFFEF4444) : kGreen500;
    final fg = error ? const Color(0xFF991B1B) : const Color(0xFF166534);
    return Padding(
      padding: const EdgeInsets.only(bottom: 20),
      child: AccentCard(
        accent: edge,
        bg: bg,
        radius: 8,
        padding: const EdgeInsets.fromLTRB(14, 14, 6, 14),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Icon(error ? Icons.error : Icons.check_circle, size: 26, color: edge),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text.rich(TextSpan(style: TextStyle(color: fg, fontSize: 15, height: 1.35), children: [
                if (error) const TextSpan(text: 'Error: ', style: TextStyle(fontWeight: FontWeight.bold)),
                TextSpan(text: message),
              ])),
              for (final l in extraLines)
                Padding(padding: const EdgeInsets.only(top: 4), child: Text(l, style: TextStyle(color: fg, fontSize: 13, fontWeight: FontWeight.w600))),
            ]),
          ),
          if (onClose != null) IconButton(visualDensity: VisualDensity.compact, onPressed: onClose, icon: Icon(Icons.close, size: 18, color: fg)),
        ]),
      ),
    );
  }
}

/// White rounded-3xl card with a gradient title block (the web `.container > .bg-white` look).
class PromoCard extends StatelessWidget {
  final Gradient headerGradient;
  final String title;
  final String subtitle;
  final Widget child;
  const PromoCard({super.key, required this.headerGradient, required this.title, required this.subtitle, required this.child});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.18), blurRadius: 40, offset: const Offset(0, 18))],
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 28),
          decoration: BoxDecoration(gradient: headerGradient),
          child: Column(children: [
            Text(title, textAlign: TextAlign.center, style: const TextStyle(color: Colors.white, fontSize: 26, fontWeight: FontWeight.w800, height: 1.15)),
            const SizedBox(height: 8),
            Text(subtitle, textAlign: TextAlign.center, style: TextStyle(color: Colors.white.withOpacity(0.9), fontSize: 14)),
          ]),
        ),
        Padding(padding: const EdgeInsets.all(18), child: child),
      ]),
    );
  }
}

InputDecoration promoSelectDecoration(Color border, {Color? focus}) => InputDecoration(
      isDense: true,
      filled: true,
      fillColor: Colors.white,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide(color: border, width: 3)),
      focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide(color: focus ?? border, width: 3)),
    );

/// Pill button used at the top of the pages ("Revert Promotions", "Back to Promotion"…).
class PromoPillButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final Gradient? gradient;
  final Color? color;
  final VoidCallback onTap;
  const PromoPillButton({super.key, required this.icon, required this.label, this.gradient, this.color, required this.onTap});

  @override
  Widget build(BuildContext context) => Container(
        decoration: BoxDecoration(
          gradient: gradient,
          color: color,
          borderRadius: BorderRadius.circular(40),
          boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.18), blurRadius: 12, offset: const Offset(0, 5))],
        ),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(40),
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                Icon(icon, color: Colors.white, size: 16),
                const SizedBox(width: 8),
                Text(label, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 14)),
              ]),
            ),
          ),
        ),
      );
}
