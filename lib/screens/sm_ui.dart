// screens/sm_ui.dart — SchoolsMirror design system ("Aurora Glass")
// Shared by: login, admin home, result upload, result overview.
// Dark navy aurora background, frosted glass cards, gradient buttons, rolling-ring logo loader.

import 'dart:math' as math;
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class SM {
  // surfaces
  static const bg0 = Color(0xFF050D1A);
  static const bg1 = Color(0xFF0A1929);
  static const bg2 = Color(0xFF0F2745);
  static const sheet = Color(0xFF0D2140);
  // brand (logo: blue S + orange)
  static const blue = Color(0xFF3A57A5);
  static const blueLight = Color(0xFF6C8CE0);
  static const orange = Color(0xFFF7941D);
  static const orange2 = Color(0xFFFF6A3D);
  // status
  static const green = Color(0xFF34D399);
  static const amber = Color(0xFFFBBF24);
  static const rose = Color(0xFFFB7185);
  static const cyan = Color(0xFF22D3EE);
  static const violet = Color(0xFFA78BFA);
  // text
  static const text = Color(0xFFF1F5FF);
  static const muted = Color(0xFFA7B6D3);
  static const faint = Color(0xFF70829F);

  static const brand = LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [Color(0xFF7C9BEA), Color(0xFF3A57A5)]);
  static const hot = LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [Color(0xFFFFB347), Color(0xFFFF6A3D)]);
  static const mint = LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [Color(0xFF34D399), Color(0xFF0E9F6E)]);
  static const rose2 = LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [Color(0xFFFB7185), Color(0xFFE11D48)]);
  static const violet2 = LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [Color(0xFFA78BFA), Color(0xFF6D4AE0)]);
  static const cyan2 = LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [Color(0xFF22D3EE), Color(0xFF0E8FB0)]);

  /// colour with opacity without the deprecated withOpacity
  static Color a(Color c, double o) => c.withAlpha((o.clamp(0.0, 1.0) * 255).round());
  static Color get glass => a(Colors.white, .07);
  static Color get glassLine => a(Colors.white, .12);
}

/// Student photo address. Accepts a full URL, "/uploads/x.jpg", "uploads/x.jpg" or just "x.jpg".
String smImgUrl(String? raw) {
  final v = (raw ?? '').trim();
  if (v.isEmpty || v == 'null') return '';
  if (v.startsWith('http://') || v.startsWith('https://')) return v;
  if (v.startsWith('//')) return 'https:$v';
  if (v.startsWith('/')) return 'https://schoolsmirror.com$v';
  if (v.startsWith('uploads/')) return 'https://schoolsmirror.com/$v';
  return 'https://schoolsmirror.com/uploads/${Uri.encodeComponent(v)}';
}

// ───────────────────────────── background ─────────────────────────────
class SmBackground extends StatelessWidget {
  final Widget child;
  const SmBackground({super.key, required this.child});

  Widget _orb(Color c, double size, double o) => IgnorePointer(
        child: Container(
          width: size,
          height: size,
          decoration: BoxDecoration(shape: BoxShape.circle, gradient: RadialGradient(colors: [SM.a(c, o), SM.a(c, 0)])),
        ),
      );

  @override
  Widget build(BuildContext context) {
    return Stack(fit: StackFit.expand, children: [
      const DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [SM.bg2, SM.bg1, SM.bg0]),
        ),
      ),
      Positioned(top: -130, left: -100, child: _orb(SM.blueLight, 380, .30)),
      Positioned(top: 300, right: -150, child: _orb(SM.violet, 320, .16)),
      Positioned(bottom: -160, left: -60, child: _orb(SM.orange, 360, .16)),
      child,
    ]);
  }
}

// ───────────────────────────── press feedback ─────────────────────────────
class SmPress extends StatefulWidget {
  final Widget child;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final double scale;
  const SmPress({super.key, required this.child, this.onTap, this.onLongPress, this.scale = .97});

  @override
  State<SmPress> createState() => _SmPressState();
}

class _SmPressState extends State<SmPress> {
  bool _down = false;
  @override
  Widget build(BuildContext context) {
    final enabled = widget.onTap != null || widget.onLongPress != null;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: enabled ? (_) => setState(() => _down = true) : null,
      onTapCancel: enabled ? () => setState(() => _down = false) : null,
      onTapUp: enabled ? (_) => setState(() => _down = false) : null,
      onTap: widget.onTap == null
          ? null
          : () {
              HapticFeedback.selectionClick();
              widget.onTap!();
            },
      onLongPress: widget.onLongPress,
      child: AnimatedScale(scale: _down ? widget.scale : 1, duration: const Duration(milliseconds: 110), curve: Curves.easeOut, child: widget.child),
    );
  }
}

// ───────────────────────────── glass card ─────────────────────────────
class SmGlass extends StatelessWidget {
  final Widget child;
  final EdgeInsets padding;
  final double radius;
  final Color? color;
  final Gradient? gradient;
  final Color? border;
  final VoidCallback? onTap;
  final Color? glow;
  const SmGlass({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(16),
    this.radius = 22,
    this.color,
    this.gradient,
    this.border,
    this.onTap,
    this.glow,
  });

  @override
  Widget build(BuildContext context) {
    final box = Container(
      padding: padding,
      decoration: BoxDecoration(
        color: gradient == null ? (color ?? SM.glass) : null,
        gradient: gradient,
        borderRadius: BorderRadius.circular(radius),
        border: Border.all(color: border ?? SM.glassLine),
        boxShadow: glow == null ? null : [BoxShadow(color: SM.a(glow!, .28), blurRadius: 26, offset: const Offset(0, 12))],
      ),
      child: child,
    );
    return onTap == null ? box : SmPress(onTap: onTap, child: box);
  }
}

// ───────────────────────────── buttons ─────────────────────────────
class SmButton extends StatelessWidget {
  final String label;
  final IconData? icon;
  final VoidCallback? onTap;
  final Gradient gradient;
  final bool loading;
  final double height;
  final bool outline;
  final Color? glow;
  const SmButton({
    super.key,
    required this.label,
    this.icon,
    this.onTap,
    this.gradient = SM.brand,
    this.loading = false,
    this.height = 52,
    this.outline = false,
    this.glow,
  });

  @override
  Widget build(BuildContext context) {
    final on = onTap != null && !loading;
    final content = Row(mainAxisAlignment: MainAxisAlignment.center, mainAxisSize: MainAxisSize.min, children: [
      if (loading)
        const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2.4, color: Colors.white))
      else ...[
        if (icon != null) ...[Icon(icon, size: 19, color: Colors.white), const SizedBox(width: 8)],
        Flexible(child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 15, letterSpacing: .2))),
      ],
    ]);
    return Opacity(
      opacity: (onTap == null && !loading) ? .45 : 1,
      child: SmPress(
        onTap: on ? onTap : null,
        child: Container(
          height: height,
          padding: const EdgeInsets.symmetric(horizontal: 20),
          decoration: BoxDecoration(
            gradient: outline ? null : gradient,
            color: outline ? SM.a(Colors.white, .06) : null,
            borderRadius: BorderRadius.circular(height / 2.6),
            border: outline ? Border.all(color: SM.glassLine, width: 1.4) : null,
            boxShadow: outline ? null : [BoxShadow(color: SM.a(glow ?? SM.blue, .38), blurRadius: 22, offset: const Offset(0, 10))],
          ),
          child: Center(child: content),
        ),
      ),
    );
  }
}

class SmIconBtn extends StatelessWidget {
  final IconData icon;
  final VoidCallback? onTap;
  final int badge;
  final Color? color;
  final double size;
  const SmIconBtn({super.key, required this.icon, this.onTap, this.badge = 0, this.color, this.size = 44});

  @override
  Widget build(BuildContext context) {
    return SmPress(
      onTap: onTap,
      child: Stack(clipBehavior: Clip.none, children: [
        Container(
          width: size,
          height: size,
          decoration: BoxDecoration(color: SM.glass, borderRadius: BorderRadius.circular(size / 2.8), border: Border.all(color: SM.glassLine)),
          child: Icon(icon, size: 21, color: color ?? SM.text),
        ),
        if (badge > 0)
          Positioned(
            right: -3,
            top: -3,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
              decoration: BoxDecoration(gradient: SM.hot, borderRadius: BorderRadius.circular(10), border: Border.all(color: SM.bg1, width: 2)),
              child: Text(badge > 99 ? '99+' : '$badge', style: const TextStyle(color: Colors.white, fontSize: 9.5, fontWeight: FontWeight.w800)),
            ),
          ),
      ]),
    );
  }
}

// ───────────────────────────── small pieces ─────────────────────────────
class SmPill extends StatelessWidget {
  final String text;
  final Color color;
  final IconData? icon;
  final bool filled;
  final double fontSize;
  const SmPill(this.text, {super.key, this.color = SM.blueLight, this.icon, this.filled = false, this.fontSize = 11.5});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: filled ? color : SM.a(color, .16),
        borderRadius: BorderRadius.circular(99),
        border: filled ? null : Border.all(color: SM.a(color, .35)),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        if (icon != null) ...[Icon(icon, size: 12.5, color: filled ? Colors.white : color), const SizedBox(width: 4)],
        Flexible(child: Text(text, softWrap: true, style: TextStyle(color: filled ? Colors.white : color, fontSize: fontSize, fontWeight: FontWeight.w700))),
      ]),
    );
  }
}

class SmSectionTitle extends StatelessWidget {
  final String title;
  final String? sub;
  final Widget? trailing;
  const SmSectionTitle(this.title, {super.key, this.sub, this.trailing});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 22, 4, 12),
      child: Row(children: [
        Container(width: 4, height: 18, decoration: BoxDecoration(gradient: SM.hot, borderRadius: BorderRadius.circular(4))),
        const SizedBox(width: 10),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(title, style: const TextStyle(color: SM.text, fontSize: 17, fontWeight: FontWeight.w800, letterSpacing: -.2)),
            if (sub != null) Text(sub!, style: const TextStyle(color: SM.muted, fontSize: 12)),
          ]),
        ),
        if (trailing != null) trailing!,
      ]),
    );
  }
}

class SmTopBar extends StatelessWidget {
  final String title;
  final String? subtitle;
  final VoidCallback? onBack;
  final List<Widget> actions;
  const SmTopBar({super.key, required this.title, this.subtitle, this.onBack, this.actions = const []});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 6),
      child: Row(children: [
        if (onBack != null) ...[SmIconBtn(icon: Icons.arrow_back_ios_new_rounded, onTap: onBack), const SizedBox(width: 12)],
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(title, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: SM.text, fontSize: 21, fontWeight: FontWeight.w800, letterSpacing: -.4)),
            if (subtitle != null) Text(subtitle!, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: SM.muted, fontSize: 12.5)),
          ]),
        ),
        for (final a in actions) Padding(padding: const EdgeInsets.only(left: 8), child: a),
      ]),
    );
  }
}

/// selectable chip (session / term / class pickers, comment categories …)
class SmChoice extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback? onTap;
  final IconData? icon;
  final Color color;
  const SmChoice({super.key, required this.label, required this.selected, this.onTap, this.icon, this.color = SM.blueLight});

  @override
  Widget build(BuildContext context) {
    return SmPress(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOut,
        padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 10),
        decoration: BoxDecoration(
          gradient: selected ? LinearGradient(colors: [SM.a(color, .95), SM.a(color, .65)]) : null,
          color: selected ? null : SM.a(Colors.white, .06),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: selected ? SM.a(color, .9) : SM.glassLine),
          boxShadow: selected ? [BoxShadow(color: SM.a(color, .35), blurRadius: 14, offset: const Offset(0, 6))] : null,
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          if (icon != null) ...[Icon(icon, size: 16, color: selected ? Colors.white : SM.muted), const SizedBox(width: 6)],
          Flexible(child: Text(label, style: TextStyle(color: selected ? Colors.white : SM.text, fontWeight: FontWeight.w700, fontSize: 13.5))),
        ]),
      ),
    );
  }
}

InputDecoration smInput(String hint, {IconData? icon, Widget? suffix, String? label, bool dense = false, Color? accent}) {
  final ac = accent ?? SM.blueLight;
  OutlineInputBorder b(Color c, double w) => OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide(color: c, width: w));
  return InputDecoration(
    hintText: hint,
    labelText: label,
    hintStyle: const TextStyle(color: SM.faint, fontSize: 14),
    labelStyle: const TextStyle(color: SM.muted, fontSize: 13),
    floatingLabelStyle: TextStyle(color: ac, fontWeight: FontWeight.w700),
    prefixIcon: icon == null ? null : Icon(icon, size: 20, color: SM.muted),
    suffixIcon: suffix,
    isDense: dense,
    filled: true,
    fillColor: SM.a(Colors.white, .07),
    contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: dense ? 13 : 17),
    border: b(SM.glassLine, 1),
    enabledBorder: b(SM.glassLine, 1),
    focusedBorder: b(ac, 1.7),
    errorBorder: b(SM.rose, 1.2),
    focusedErrorBorder: b(SM.rose, 1.6),
  );
}

// ───────────────────────────── avatar (student photo) ─────────────────────────────
class SmAvatar extends StatelessWidget {
  final String? url;
  final String name;
  final double size;
  final Gradient ring;
  const SmAvatar({super.key, this.url, required this.name, this.size = 48, this.ring = SM.hot});

  @override
  Widget build(BuildContext context) {
    final u = smImgUrl(url);
    final initial = name.trim().isEmpty ? '?' : name.trim().substring(0, 1).toUpperCase();
    final fallback = Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: const BoxDecoration(gradient: SM.brand),
      child: Text(initial, style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: size * .42)),
    );
    return Container(
      width: size + 6,
      height: size + 6,
      padding: const EdgeInsets.all(2.5),
      decoration: BoxDecoration(shape: BoxShape.circle, gradient: ring),
      child: Container(
        padding: const EdgeInsets.all(1.5),
        decoration: const BoxDecoration(shape: BoxShape.circle, color: SM.bg1),
        child: ClipOval(
          child: u.isEmpty
              ? fallback
              : Image.network(
                  u,
                  width: size,
                  height: size,
                  fit: BoxFit.cover,
                  cacheWidth: (size * 3).round(),
                  errorBuilder: (_, __, ___) => fallback,
                  loadingBuilder: (c, child, p) => p == null
                      ? child
                      : Container(width: size, height: size, color: SM.a(Colors.white, .08), alignment: Alignment.center,
                          child: SizedBox(width: size * .3, height: size * .3, child: const CircularProgressIndicator(strokeWidth: 2, color: SM.blueLight))),
                ),
        ),
      ),
    );
  }
}

// ───────────────────────────── logo loader: rolling gradient ring + pop ─────────────────────────────
class SmLogoLoader extends StatefulWidget {
  final double size;
  final String? label;
  const SmLogoLoader({super.key, this.size = 150, this.label});

  @override
  State<SmLogoLoader> createState() => _SmLogoLoaderState();
}

class _SmLogoLoaderState extends State<SmLogoLoader> with TickerProviderStateMixin {
  late final AnimationController _spin = AnimationController(vsync: this, duration: const Duration(milliseconds: 2200))..repeat();
  late final AnimationController _pop = AnimationController(vsync: this, duration: const Duration(milliseconds: 1000))..forward();
  late final AnimationController _breath = AnimationController(vsync: this, duration: const Duration(milliseconds: 1600))..repeat(reverse: true);

  @override
  void dispose() {
    _spin.dispose();
    _pop.dispose();
    _breath.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.size;
    return Column(mainAxisSize: MainAxisSize.min, children: [
      SizedBox(
        width: s,
        height: s,
        child: Stack(alignment: Alignment.center, children: [
          // soft glow
          AnimatedBuilder(
            animation: _breath,
            builder: (_, __) => Container(
              width: s * (.88 + .08 * _breath.value),
              height: s * (.88 + .08 * _breath.value),
              decoration: BoxDecoration(shape: BoxShape.circle, boxShadow: [BoxShadow(color: SM.a(SM.orange, .20 + .12 * _breath.value), blurRadius: 46, spreadRadius: 2)]),
            ),
          ),
          // rolling gradient border
          RotationTransition(turns: _spin, child: CustomPaint(size: Size(s, s), painter: _RingPainter())),
          // logo pops
          ScaleTransition(
            scale: CurvedAnimation(parent: _pop, curve: Curves.elasticOut),
            child: AnimatedBuilder(
              animation: _breath,
              builder: (_, child) => Transform.scale(scale: 1 + .035 * _breath.value, child: child),
              child: Container(
                width: s * .70,
                height: s * .70,
                padding: EdgeInsets.all(s * .06),
                decoration: BoxDecoration(color: Colors.white, shape: BoxShape.circle, boxShadow: [BoxShadow(color: SM.a(Colors.black, .35), blurRadius: 18, offset: const Offset(0, 8))]),
                child: ClipOval(child: Image.asset('assets/images/logo.png', fit: BoxFit.contain, errorBuilder: (_, __, ___) => const Icon(Icons.school_rounded, color: SM.blue, size: 46))),
              ),
            ),
          ),
        ]),
      ),
      if (widget.label != null) ...[
        const SizedBox(height: 18),
        Text(widget.label!, style: const TextStyle(color: SM.muted, fontSize: 14, fontWeight: FontWeight.w600, letterSpacing: .3)),
      ],
    ]);
  }
}

class _RingPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final r = size.width / 2 - 6;
    final rect = Rect.fromCircle(center: c, radius: r);
    const colors = [Color(0xFFF7941D), Color(0xFFFF4D8D), Color(0xFF6C8CE0), Color(0xFF22D3EE), Color(0xFFF7941D)];
    final shader = const SweepGradient(colors: colors).createShader(rect);
    canvas.drawCircle(c, r, Paint()..shader = shader..style = PaintingStyle.stroke..strokeWidth = 9..maskFilter = const MaskFilter.blur(BlurStyle.normal, 9));
    canvas.drawCircle(c, r, Paint()..shader = shader..style = PaintingStyle.stroke..strokeWidth = 5.5..strokeCap = StrokeCap.round);
  }

  @override
  bool shouldRepaint(covariant CustomPainter old) => false;
}

/// Full-screen "please wait" with the logo loader (use inside a Stack)
class SmBusyOverlay extends StatelessWidget {
  final bool show;
  final String? label;
  const SmBusyOverlay({super.key, required this.show, this.label});

  @override
  Widget build(BuildContext context) {
    return Positioned.fill(
      child: IgnorePointer(
        ignoring: !show,
        child: AnimatedOpacity(
          opacity: show ? 1 : 0,
          duration: const Duration(milliseconds: 260),
          child: show
              ? Container(color: SM.a(SM.bg0, .90), child: Center(child: SmLogoLoader(label: label)))
              : const SizedBox.shrink(),
        ),
      ),
    );
  }
}

// ───────────────────────────── toast / dialog / sheet ─────────────────────────────
enum SmKind { success, error, warn, info }

void smToast(BuildContext context, String msg, {SmKind kind = SmKind.success}) {
  if (!context.mounted) return;
  final c = kind == SmKind.success ? SM.green : kind == SmKind.error ? SM.rose : kind == SmKind.warn ? SM.amber : SM.cyan;
  final i = kind == SmKind.success ? Icons.check_circle_rounded : kind == SmKind.error ? Icons.error_rounded : kind == SmKind.warn ? Icons.warning_rounded : Icons.info_rounded;
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(
      behavior: SnackBarBehavior.floating,
      backgroundColor: Colors.transparent,
      elevation: 0,
      margin: const EdgeInsets.fromLTRB(14, 0, 14, 14),
      duration: const Duration(seconds: 4),
      content: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(color: const Color(0xFF14294A), borderRadius: BorderRadius.circular(16), border: Border.all(color: SM.a(c, .6)),
            boxShadow: [BoxShadow(color: SM.a(c, .25), blurRadius: 18)]),
        child: Row(children: [
          Icon(i, color: c, size: 22),
          const SizedBox(width: 10),
          Expanded(child: Text(msg, style: const TextStyle(color: SM.text, fontSize: 13.5, fontWeight: FontWeight.w600))),
        ]),
      ),
    ));
}

Future<bool?> smConfirm(BuildContext context, String title, String text,
    {String yes = 'Yes', String no = 'Cancel', bool destructive = false, IconData icon = Icons.help_outline_rounded, Gradient? gradient}) {
  final g = gradient ?? (destructive ? SM.rose2 : SM.brand);
  final glow = destructive ? SM.rose : SM.blueLight;
  return showDialog<bool>(
    context: context,
    barrierColor: SM.a(Colors.black, .6),
    builder: (ctx) => Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 26),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(28),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
          child: Container(
            padding: const EdgeInsets.fromLTRB(22, 26, 22, 20),
            decoration: BoxDecoration(color: SM.a(SM.sheet, .94), borderRadius: BorderRadius.circular(28), border: Border.all(color: SM.glassLine)),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Container(
                width: 64, height: 64,
                decoration: BoxDecoration(shape: BoxShape.circle, color: SM.a(glow, .16), border: Border.all(color: SM.a(glow, .5)), boxShadow: [BoxShadow(color: SM.a(glow, .3), blurRadius: 22)]),
                child: Icon(icon, color: glow, size: 30),
              ),
              const SizedBox(height: 16),
              Text(title, textAlign: TextAlign.center, style: const TextStyle(color: SM.text, fontSize: 19, fontWeight: FontWeight.w800)),
              const SizedBox(height: 8),
              Text(text, textAlign: TextAlign.center, style: const TextStyle(color: SM.muted, fontSize: 14, height: 1.4)),
              const SizedBox(height: 22),
              Row(children: [
                Expanded(child: SmButton(label: no, outline: true, height: 48, onTap: () => Navigator.pop(ctx, false))),
                const SizedBox(width: 10),
                Expanded(child: SmButton(label: yes, gradient: g, height: 48, glow: glow, onTap: () => Navigator.pop(ctx, true))),
              ]),
            ]),
          ),
        ),
      ),
    ),
  );
}

Future<void> smAlert(BuildContext context, String title, String text, {IconData icon = Icons.info_rounded, Color color = SM.blueLight}) {
  return showDialog<void>(
    context: context,
    barrierColor: SM.a(Colors.black, .6),
    builder: (ctx) => Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 26),
      child: Container(
        padding: const EdgeInsets.fromLTRB(22, 26, 22, 20),
        decoration: BoxDecoration(color: SM.sheet, borderRadius: BorderRadius.circular(28), border: Border.all(color: SM.glassLine)),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Container(
            width: 64, height: 64,
            decoration: BoxDecoration(shape: BoxShape.circle, color: SM.a(color, .16), border: Border.all(color: SM.a(color, .5))),
            child: Icon(icon, color: color, size: 30),
          ),
          const SizedBox(height: 16),
          Text(title, textAlign: TextAlign.center, style: const TextStyle(color: SM.text, fontSize: 19, fontWeight: FontWeight.w800)),
          const SizedBox(height: 8),
          Text(text, textAlign: TextAlign.center, style: const TextStyle(color: SM.muted, fontSize: 14, height: 1.4)),
          const SizedBox(height: 22),
          SmButton(label: 'OK', height: 48, onTap: () => Navigator.pop(ctx)),
        ]),
      ),
    ),
  );
}

/// Dark bottom sheet. [builder] gets the context; use [SmSheetFrame] inside for title + handle.
Future<T?> smSheet<T>(BuildContext context, WidgetBuilder builder) {
  return showModalBottomSheet<T>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: Colors.transparent,
    barrierColor: SM.a(Colors.black, .55),
    builder: builder,
  );
}

class SmSheetFrame extends StatelessWidget {
  final String title;
  final String? subtitle;
  final IconData? icon;
  final Widget child;
  final bool withClose;
  const SmSheetFrame({super.key, required this.title, this.subtitle, this.icon, required this.child, this.withClose = true});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        gradient: const LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Color(0xFF12305A), SM.sheet, SM.bg1]),
        borderRadius: const BorderRadius.vertical(top: Radius.circular(30)),
        border: Border(top: BorderSide(color: SM.glassLine)),
      ),
      child: Column(children: [
        const SizedBox(height: 10),
        Container(width: 46, height: 5, decoration: BoxDecoration(color: SM.a(Colors.white, .25), borderRadius: BorderRadius.circular(5))),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 14, 12, 8),
          child: Row(children: [
            if (icon != null) ...[
              Container(width: 40, height: 40, decoration: BoxDecoration(gradient: SM.brand, borderRadius: BorderRadius.circular(13)), child: Icon(icon, color: Colors.white, size: 21)),
              const SizedBox(width: 12),
            ],
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(title, style: const TextStyle(color: SM.text, fontSize: 18, fontWeight: FontWeight.w800, letterSpacing: -.2)),
                if (subtitle != null) Text(subtitle!, style: const TextStyle(color: SM.muted, fontSize: 12.5)),
              ]),
            ),
            if (withClose) SmIconBtn(icon: Icons.close_rounded, size: 38, onTap: () => Navigator.maybePop(context)),
          ]),
        ),
        Expanded(child: child),
      ]),
    );
  }
}

/// Same look as [SmSheetFrame] but only as tall as its content (small forms: passwords, contact details…)
class SmSheetFrameFit extends StatelessWidget {
  final String title;
  final String? subtitle;
  final IconData? icon;
  final Widget child;
  const SmSheetFrameFit({super.key, required this.title, this.subtitle, this.icon, required this.child});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        gradient: const LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Color(0xFF12305A), SM.sheet, SM.bg1]),
        borderRadius: const BorderRadius.vertical(top: Radius.circular(30)),
        border: Border(top: BorderSide(color: SM.glassLine)),
      ),
      child: SafeArea(
        top: false,
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const SizedBox(height: 10),
          Container(width: 46, height: 5, decoration: BoxDecoration(color: SM.a(Colors.white, .25), borderRadius: BorderRadius.circular(5))),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 14, 12, 8),
            child: Row(children: [
              if (icon != null) ...[
                Container(width: 40, height: 40, decoration: BoxDecoration(gradient: SM.brand, borderRadius: BorderRadius.circular(13)), child: Icon(icon, color: Colors.white, size: 21)),
                const SizedBox(width: 12),
              ],
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(title, style: const TextStyle(color: SM.text, fontSize: 18, fontWeight: FontWeight.w800, letterSpacing: -.2)),
                  if (subtitle != null) Text(subtitle!, style: const TextStyle(color: SM.muted, fontSize: 12.5)),
                ]),
              ),
              SmIconBtn(icon: Icons.close_rounded, size: 38, onTap: () => Navigator.maybePop(context)),
            ]),
          ),
          Flexible(child: SingleChildScrollView(child: child)),
        ]),
      ),
    );
  }
}

/// count-up number
class SmCount extends StatelessWidget {
  final num value;
  final TextStyle style;
  final String prefix;
  final String Function(num)? format;
  const SmCount(this.value, {super.key, required this.style, this.prefix = '', this.format});

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      key: ValueKey(value),
      tween: Tween(begin: 0, end: value.toDouble()),
      duration: const Duration(milliseconds: 1100),
      curve: Curves.easeOutCubic,
      builder: (_, v, __) => Text('$prefix${format != null ? format!(v) : v.round()}', style: style),
    );
  }
}

/// circular progress ring with a centre label (used for subject totals)
class SmRing extends StatelessWidget {
  final double value; // 0..1
  final double size;
  final Color color;
  final Widget? child;
  final double stroke;
  const SmRing({super.key, required this.value, this.size = 56, this.color = SM.blueLight, this.child, this.stroke = 5});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: Stack(alignment: Alignment.center, children: [
        TweenAnimationBuilder<double>(
          tween: Tween(begin: 0, end: value.clamp(0.0, 1.0)),
          duration: const Duration(milliseconds: 600),
          curve: Curves.easeOutCubic,
          builder: (_, v, __) => CustomPaint(size: Size(size, size), painter: _RingValuePainter(v, color, stroke)),
        ),
        if (child != null) child!,
      ]),
    );
  }
}

class _RingValuePainter extends CustomPainter {
  final double v;
  final Color color;
  final double stroke;
  _RingValuePainter(this.v, this.color, this.stroke);

  @override
  void paint(Canvas canvas, Size size) {
    final r = (size.width - stroke) / 2;
    final c = size.center(Offset.zero);
    canvas.drawCircle(c, r, Paint()..color = SM.a(Colors.white, .1)..style = PaintingStyle.stroke..strokeWidth = stroke);
    if (v <= 0) return;
    canvas.drawArc(Rect.fromCircle(center: c, radius: r), -math.pi / 2, math.pi * 2 * v, false,
        Paint()..color = color..style = PaintingStyle.stroke..strokeWidth = stroke..strokeCap = StrokeCap.round);
  }

  @override
  bool shouldRepaint(covariant _RingValuePainter o) => o.v != v || o.color != color;
}
