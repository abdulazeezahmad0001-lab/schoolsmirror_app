// flutter_result_reveal_screen.dart
// Native version of resultPreloader.php ("Result Reveal"): dark starfield, school header, intro with the
// student's photo, then the info cards revealed one by one (name, school, class, session, term, average,
// position, subjects, total, performance, remarks, weak / strong subjects) with the history strip,
// Prev / Next, progress bar, and the final reveal (average counter, grade label, position, career
// suggestion, confetti, "View Full Result").
// Background music and the video recording of the web page are not included (browser-only features).
// Needs flutter_result_common.dart

import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'flutter_result_common.dart';

class _RevealCard {
  final String icon, label, value;
  final Color color;
  const _RevealCard(this.icon, this.label, this.value, this.color);
}

class FlutterResultRevealScreen extends StatefulWidget {
  final Map<String, dynamic> card; // data of `student_card`
  const FlutterResultRevealScreen({super.key, required this.card});

  @override
  State<FlutterResultRevealScreen> createState() => _FlutterResultRevealScreenState();
}

class _FlutterResultRevealScreenState extends State<FlutterResultRevealScreen> with TickerProviderStateMixin {
  late final AnimationController _bg = AnimationController(vsync: this, duration: const Duration(seconds: 24))..repeat();
  late final AnimationController _conf = AnimationController(vsync: this, duration: const Duration(milliseconds: 3600));
  late final AnimationController _count = AnimationController(vsync: this, duration: const Duration(milliseconds: 1800));
  final _rand = math.Random(7);
  late final List<_Star> _stars = List.generate(70, (_) => _Star(_rand.nextDouble(), _rand.nextDouble(), 0.6 + _rand.nextDouble() * 1.6, _rand.nextDouble() * 6.28));
  late final List<_Bit> _bits = List.generate(90, (_) => _Bit(_rand.nextDouble(), _rand.nextDouble() * 0.5, 0.4 + _rand.nextDouble() * 0.9, _rand.nextDouble() * 6.28, _confColors[_rand.nextInt(_confColors.length)]));

  static const _confColors = [Color(0xFFA78BFA), Color(0xFFF472B6), Color(0xFF34D399), Color(0xFFFBBF24), Color(0xFF60A5FA), Color(0xFFF97316)];

  int _phase = 0; // 0 intro, 1 cards, 2 final
  int _idx = 0;
  Timer? _auto;
  late final List<_RevealCard> _cards;

  Map<String, dynamic> get _school => rMap(widget.card['school']);
  Map<String, dynamic> get _student => rMap(widget.card['student']);
  Map<String, dynamic> get _sum => rMap(widget.card['summary']);

  double get _avgPct => rDouble(_sum['average_percentage']);
  Color get _gc => _avgPct >= 70 ? const Color(0xFF00E676) : (_avgPct >= 50 ? const Color(0xFFFFD600) : const Color(0xFFFF1744));

  @override
  void initState() {
    super.initState();
    final pos = '${_sum['position'] ?? ''}'.trim();
    final weak = rMaps(widget.card['weak_subjects']);
    final good = rMaps(widget.card['good_subjects']);
    final tc = '${widget.card['teacher_comment'] ?? ''}';
    final pc = '${widget.card['proprietor_comment'] ?? ''}';
    String cut(String s) => s.length > 55 ? '${s.substring(0, 55)}…' : s;
    _cards = [
      _RevealCard('👤', 'Full Name', '${_student['fullname'] ?? ''}', const Color(0xFF00E5FF)),
      _RevealCard('🏫', 'School', '${_school['name'] ?? ''}', const Color(0xFFB388FF)),
      _RevealCard('📚', 'Class', '${_student['class_name'] ?? ''}', const Color(0xFF69F0AE)),
      _RevealCard('📅', 'Session', '${widget.card['session_name'] ?? ''}', const Color(0xFFFFD740)),
      _RevealCard('📋', 'Term', '${widget.card['term_name'] ?? ''}', const Color(0xFFFF6E40)),
      _RevealCard('📊', 'Average Score', '${rNum(_avgPct)}%', _gc),
      _RevealCard('🏅', 'Class Position', pos.isEmpty ? '—' : pos, const Color(0xFFFFD600)),
      _RevealCard('📖', 'Subjects', '${rInt(_sum['subject_count'])} subjects', const Color(0xFF40C4FF)),
      _RevealCard('🔢', 'Total Score', '${rNum(_sum['total_score'])} pts', const Color(0xFFEA80FC)),
      _RevealCard('🌟', 'Performance', '${perfEmoji(_avgPct)} ${perfLabel(_avgPct)}', _gc),
      if (tc.isNotEmpty) _RevealCard('💬', "Teacher's Remark", cut(tc), const Color(0xFF80CBC4)),
      if (pc.isNotEmpty) _RevealCard('🎓', "Principal's Remark", cut(pc), const Color(0xFFFFCC02)),
      if (weak.isNotEmpty) _RevealCard('⚠️', 'Needs Improvement', '${weak.length} subject${weak.length > 1 ? 's' : ''} below 50%', const Color(0xFFFF5252)),
      if (good.isNotEmpty) _RevealCard('🔥', 'Strong Subjects', '${good.length} subject${good.length > 1 ? 's' : ''} above 70%', const Color(0xFF76FF03)),
    ];
    // intro -> first card after a short pause
    _auto = Timer(const Duration(milliseconds: 2600), _startCards);
  }

  @override
  void dispose() {
    _auto?.cancel();
    _bg.dispose();
    _conf.dispose();
    _count.dispose();
    super.dispose();
  }

  void _startCards() {
    if (!mounted) return;
    setState(() {
      _phase = 1;
      _idx = 0;
    });
    _schedule();
  }

  void _schedule() {
    _auto?.cancel();
    _auto = Timer(const Duration(milliseconds: 2500), () => _go(1));
  }

  void _go(int dir) {
    if (!mounted) return;
    final n = _idx + dir;
    if (n < 0) return;
    if (n >= _cards.length) {
      _showFinal();
      return;
    }
    setState(() {
      _phase = 1;
      _idx = n;
    });
    _schedule();
  }

  void _showFinal() {
    _auto?.cancel();
    setState(() => _phase = 2);
    _conf.forward(from: 0);
    _count.forward(from: 0);
  }

  void _replay() {
    _conf.reset();
    _count.reset();
    setState(() {
      _phase = 0;
      _idx = 0;
    });
    _auto?.cancel();
    _auto = Timer(const Duration(milliseconds: 1800), _startCards);
  }

  // ───────────────────────────── BUILD ─────────────────────────────
  @override
  Widget build(BuildContext context) {
    return Theme(
      data: ThemeData.dark(),
      child: Scaffold(
        backgroundColor: const Color(0xFF03070F),
        body: Stack(children: [
          Positioned.fill(child: AnimatedBuilder(animation: _bg, builder: (_, __) => CustomPaint(painter: _StarPainter(_stars, _bg.value)))),
          SafeArea(
            child: Column(children: [
              _header(),
              Expanded(child: AnimatedSwitcher(duration: const Duration(milliseconds: 500), child: _stage())),
              _bottom(),
            ]),
          ),
          if (_phase == 2) Positioned.fill(child: IgnorePointer(child: AnimatedBuilder(animation: _conf, builder: (_, __) => CustomPaint(painter: _ConfettiPainter(_bits, _conf.value))))),
          Positioned(top: 4, left: 4, child: SafeArea(child: IconButton(icon: const Icon(Icons.close, color: Colors.white54), onPressed: () => Navigator.of(context).maybePop()))),
        ]),
      ),
    );
  }

  Widget _header() => Padding(
        padding: const EdgeInsets.fromLTRB(48, 8, 48, 6),
        child: Column(children: [
          Text('RESULT REVEAL', style: TextStyle(fontSize: 10.5, color: Colors.white.withOpacity(0.35), fontWeight: FontWeight.w700, letterSpacing: 3)),
          const SizedBox(height: 2),
          Text('${_school['name'] ?? ''}'.toUpperCase(),
              textAlign: TextAlign.center,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 21, color: Colors.white, fontWeight: FontWeight.w900, letterSpacing: 0.6, shadows: [Shadow(color: Color(0x804FACFE), blurRadius: 24)])),
          const SizedBox(height: 3),
          Text('${widget.card['term_name'] ?? ''} • ${widget.card['session_name'] ?? ''}', style: TextStyle(fontSize: 10.5, color: Colors.white.withOpacity(0.35), letterSpacing: 1.4)),
        ]),
      );

  Widget _stage() {
    if (_phase == 0) return KeyedSubtree(key: const ValueKey('intro'), child: _intro());
    if (_phase == 2) return KeyedSubtree(key: const ValueKey('final'), child: _final());
    return KeyedSubtree(key: const ValueKey('cards'), child: _cardsStage());
  }

  // ---------------------------- intro ----------------------------
  Widget _intro() {
    final photo = '${_student['photo_url'] ?? ''}';
    final first = '${_student['fullname'] ?? ''}'.split(' ').first;
    return Center(
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        AnimatedBuilder(
          animation: _bg,
          builder: (_, __) => Container(
            width: 150,
            height: 150,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              boxShadow: [BoxShadow(color: Color.lerp(const Color(0xFF8B5CF6), const Color(0xFFEC4899), (math.sin(_bg.value * 62.8) + 1) / 2)!.withOpacity(0.55), blurRadius: 40, spreadRadius: 4)],
              border: Border.all(color: Colors.white24, width: 3),
            ),
            child: ClipOval(
              child: photo.isEmpty
                  ? Container(color: const Color(0xFF1E1B4B), child: Center(child: Text(rInitials('${_student['fullname']}'), style: const TextStyle(fontSize: 48, fontWeight: FontWeight.w900, color: Colors.white))))
                  : Image.network(photo, fit: BoxFit.cover, errorBuilder: (_, __, ___) => Container(color: const Color(0xFF1E1B4B), child: const Icon(Icons.person, size: 70, color: Colors.white54))),
            ),
          ),
        ),
        const SizedBox(height: 22),
        Text('Hello, $first! 👋', style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w900, color: Colors.white)),
        const SizedBox(height: 6),
        Text('Your result is ready…', style: TextStyle(fontSize: 15, color: Colors.white.withOpacity(0.6))),
        const SizedBox(height: 22),
        const SizedBox(width: 120, child: LinearProgressIndicator(minHeight: 3, color: Color(0xFF8B5CF6), backgroundColor: Colors.white12)),
      ]),
    );
  }

  // ---------------------------- cards ----------------------------
  Widget _cardsStage() {
    final c = _cards[_idx];
    return Column(children: [
      // history strip
      SizedBox(
        height: 74,
        child: ListView.separated(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          scrollDirection: Axis.horizontal,
          itemCount: _idx,
          separatorBuilder: (_, __) => const SizedBox(width: 8),
          itemBuilder: (_, i) => GestureDetector(
            onTap: () {
              setState(() => _idx = i);
              _schedule();
            },
            child: Container(
              width: 110,
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(color: Colors.white.withOpacity(0.06), borderRadius: BorderRadius.circular(12), border: Border.all(color: _cards[i].color.withOpacity(0.35))),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisAlignment: MainAxisAlignment.center, children: [
                Text('${_cards[i].icon} ${_cards[i].label}', maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 9.5, color: Colors.white54, fontWeight: FontWeight.w600)),
                const SizedBox(height: 2),
                Text(_cards[i].value, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12, color: _cards[i].color, fontWeight: FontWeight.w800)),
              ]),
            ),
          ),
        ),
      ),
      Expanded(
        child: Center(
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 520),
            transitionBuilder: (child, anim) => FadeTransition(
              opacity: anim,
              child: SlideTransition(position: Tween<Offset>(begin: const Offset(0, 0.18), end: Offset.zero).animate(CurvedAnimation(parent: anim, curve: Curves.easeOutBack)), child: ScaleTransition(scale: Tween<double>(begin: 0.85, end: 1).animate(anim), child: child)),
            ),
            child: Container(
              key: ValueKey(_idx),
              width: math.min(MediaQuery.of(context).size.width - 40, 420),
              padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 34),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(26),
                gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [c.color.withOpacity(0.18), Colors.white.withOpacity(0.04)]),
                border: Border.all(color: c.color.withOpacity(0.55), width: 1.6),
                boxShadow: [BoxShadow(color: c.color.withOpacity(0.3), blurRadius: 40, spreadRadius: 1)],
              ),
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                Text(c.icon, style: const TextStyle(fontSize: 54)),
                const SizedBox(height: 12),
                Text(c.label.toUpperCase(), style: TextStyle(fontSize: 12.5, letterSpacing: 3, color: Colors.white.withOpacity(0.55), fontWeight: FontWeight.w700)),
                const SizedBox(height: 10),
                Text(c.value, textAlign: TextAlign.center, style: TextStyle(fontSize: c.value.length > 22 ? 20 : 30, fontWeight: FontWeight.w900, color: c.color, height: 1.2)),
              ]),
            ),
          ),
        ),
      ),
    ]);
  }

  // ---------------------------- final ----------------------------
  Widget _final() {
    final pos = '${_sum['position'] ?? ''}'.trim();
    final career = rMap(widget.card['career']);
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(22, 10, 22, 20),
      child: Column(children: [
        Text(perfEmoji(_avgPct), style: const TextStyle(fontSize: 62)),
        const SizedBox(height: 6),
        AnimatedBuilder(
          animation: _count,
          builder: (_, __) => Text('${(_avgPct * Curves.easeOut.transform(_count.value)).toStringAsFixed(1)}%', style: TextStyle(fontSize: 56, fontWeight: FontWeight.w900, color: _gc, shadows: [Shadow(color: _gc.withOpacity(0.6), blurRadius: 30)])),
        ),
        Text(perfLabel(_avgPct).toUpperCase(), style: TextStyle(fontSize: 15, letterSpacing: 4, color: _gc, fontWeight: FontWeight.w800)),
        const SizedBox(height: 18),
        Wrap(spacing: 10, runSpacing: 10, alignment: WrapAlignment.center, children: [
          _pill('🏅 Position', pos.isEmpty ? '—' : pos),
          _pill('📖 Subjects', '${rInt(_sum['subject_count'])}'),
          _pill('🔢 Total', rNum(_sum['total_score'])),
        ]),
        if ('${career['tier'] ?? ''}'.isNotEmpty) ...[
          const SizedBox(height: 20),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(color: Colors.white.withOpacity(0.06), borderRadius: BorderRadius.circular(18), border: Border.all(color: const Color(0xFF8B5CF6).withOpacity(0.4))),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('${career['tier']}', style: const TextStyle(color: Color(0xFFFBBF24), fontWeight: FontWeight.w800, fontSize: 15)),
              const SizedBox(height: 6),
              Text('${career['posLine'] ?? ''}${career['advice'] ?? ''}', style: const TextStyle(color: Color(0xFFC4B5FD), height: 1.5, fontSize: 13)),
            ]),
          ),
        ],
        const SizedBox(height: 24),
        Container(
          decoration: BoxDecoration(gradient: const LinearGradient(colors: [Color(0xFF8B5CF6), Color(0xFFEC4899)]), borderRadius: BorderRadius.circular(40), boxShadow: [BoxShadow(color: const Color(0xFF8B5CF6).withOpacity(0.5), blurRadius: 20, offset: const Offset(0, 8))]),
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              borderRadius: BorderRadius.circular(40),
              onTap: () => Navigator.of(context).maybePop(),
              child: const Padding(
                padding: EdgeInsets.symmetric(horizontal: 30, vertical: 15),
                child: Row(mainAxisSize: MainAxisSize.min, children: [Icon(Icons.description, color: Colors.white), SizedBox(width: 10), Text('View Full Result', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 16))]),
              ),
            ),
          ),
        ),
        TextButton.icon(onPressed: _replay, icon: const Icon(Icons.replay, size: 16), label: const Text('Replay reveal')),
      ]),
    );
  }

  Widget _pill(String k, String v) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: BoxDecoration(color: Colors.white.withOpacity(0.07), borderRadius: BorderRadius.circular(14)),
        child: Column(children: [
          Text(k, style: const TextStyle(fontSize: 11, color: Colors.white54)),
          const SizedBox(height: 2),
          Text(v, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900, color: Colors.white)),
        ]),
      );

  // ---------------------------- bottom nav ----------------------------
  Widget _bottom() {
    final total = _cards.length;
    final shown = _phase == 2 ? total : (_phase == 0 ? 0 : _idx + 1);
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 6, 16, 12),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: LinearProgressIndicator(value: total == 0 ? 0 : shown / total, minHeight: 5, backgroundColor: Colors.white12, color: const Color(0xFF4FACFE)),
        ),
        const SizedBox(height: 4),
        Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          Text(_phase == 2 ? 'COMPLETE' : (_phase == 0 ? 'LOADING' : 'REVEALING'), style: const TextStyle(fontSize: 10, color: Colors.white38, letterSpacing: 2)),
          Text('$shown / $total', style: const TextStyle(fontSize: 10, color: Colors.white38)),
        ]),
        if (_phase == 1)
          Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            IconButton(onPressed: _idx > 0 ? () => _go(-1) : null, icon: const Icon(Icons.chevron_left, size: 30), color: Colors.white),
            const SizedBox(width: 24),
            IconButton(onPressed: () => _go(1), icon: const Icon(Icons.chevron_right, size: 30), color: Colors.white),
          ]),
      ]),
    );
  }
}

// ───────────────────────────── painters ─────────────────────────────
class _Star {
  final double x, y, r, phase;
  const _Star(this.x, this.y, this.r, this.phase);
}

class _StarPainter extends CustomPainter {
  final List<_Star> stars;
  final double t;
  _StarPainter(this.stars, this.t);
  @override
  void paint(Canvas c, Size s) {
    final bg = Paint()..shader = const LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Color(0xFF03070F), Color(0xFF0B1330), Color(0xFF160B33)]).createShader(Offset.zero & s);
    c.drawRect(Offset.zero & s, bg);
    for (final st in stars) {
      final tw = 0.35 + 0.65 * (math.sin(t * 62.8 + st.phase) + 1) / 2;
      final drift = (st.y + t * 0.5 * st.r * 0.2) % 1.0;
      c.drawCircle(Offset(st.x * s.width, drift * s.height), st.r, Paint()..color = Colors.white.withOpacity(0.15 + tw * 0.6));
    }
  }

  @override
  bool shouldRepaint(covariant _StarPainter old) => old.t != t;
}

class _Bit {
  final double x, delay, speed, phase;
  final Color color;
  const _Bit(this.x, this.delay, this.speed, this.phase, this.color);
}

class _ConfettiPainter extends CustomPainter {
  final List<_Bit> bits;
  final double t;
  _ConfettiPainter(this.bits, this.t);
  @override
  void paint(Canvas c, Size s) {
    for (final b in bits) {
      final p = ((t - b.delay) / (1 - b.delay)).clamp(0.0, 1.0) * b.speed;
      if (p <= 0) continue;
      final x = b.x * s.width + math.sin(p * 9 + b.phase) * 26;
      final y = -20 + p * (s.height + 40);
      c.save();
      c.translate(x, y);
      c.rotate(p * 12 + b.phase);
      c.drawRect(const Rect.fromLTWH(-4, -2.5, 8, 5), Paint()..color = b.color.withOpacity((1 - p * 0.6).clamp(0.0, 1.0)));
      c.restore();
    }
  }

  @override
  bool shouldRepaint(covariant _ConfettiPainter old) => old.t != t;
}
