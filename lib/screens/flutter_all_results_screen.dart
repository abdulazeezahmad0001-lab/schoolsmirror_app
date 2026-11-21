// flutter_all_results_screen.dart
// Mirrors view_all_results.php: every student of the class with FINALIZED results, each with the header
// (name · ID · admission · "Transferred to" · Position · Average) and the full result card (tap to open),
// "Download All as PDF" with a progress bar, and Print. Students are loaded in batches of 5 while you scroll.
// API: https://schoolsmirror.com/flutter_class_results.php   (needs flutter_result_common.dart)

import 'package:flutter/material.dart';
import 'package:printing/printing.dart';
import 'flutter_result_common.dart';
import 'flutter_result_card_screen.dart';

class FlutterAllResultsScreen extends StatefulWidget {
  final String? token;
  final int sessionId, termId, classId;
  final String sessionName, termName, className;
  const FlutterAllResultsScreen({
    super.key,
    this.token,
    required this.sessionId,
    required this.termId,
    required this.classId,
    this.sessionName = '',
    this.termName = '',
    this.className = '',
  });

  @override
  State<FlutterAllResultsScreen> createState() => _FlutterAllResultsScreenState();
}

class _FlutterAllResultsScreenState extends State<FlutterAllResultsScreen> {
  static const _batch = 5;
  String? _token;
  final _scroll = ScrollController();

  final List<Map<String, dynamic>> _cards = [];
  final Set<int> _open = {};
  int _total = 0;
  bool _loading = true;
  bool _loadingMore = false;
  bool _hasMore = false;
  String? _error;

  // export progress
  double? _progress; // null = idle
  String _progressText = '';

  @override
  void initState() {
    super.initState();
    _scroll.addListener(() {
      if (_hasMore && !_loadingMore && !_loading && _scroll.position.pixels > _scroll.position.maxScrollExtent - 500) _loadMore();
    });
    _first();
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  Future<Map<String, dynamic>> _fetch(int offset) async {
    final r = await ResultApi.call(_token!, 'class_cards', {
      'session_id': '${widget.sessionId}',
      'term_id': '${widget.termId}',
      'class_id': '${widget.classId}',
      'offset': '$offset',
      'limit': '$_batch',
    });
    if (r['success'] != true) throw Exception(r['message'] ?? 'Failed to load results');
    return rMap(r['data']);
  }

  Future<void> _first() async {
    setState(() {
      _loading = true;
      _error = null;
      _cards.clear();
    });
    try {
      _token = await resultToken(widget.token);
      if (_token == null) throw Exception('Session expired. Please log in again.');
      final d = await _fetch(0);
      if (!mounted) return;
      setState(() {
        _cards.addAll(rMaps(d['cards']));
        _total = rInt(d['total']);
        _hasMore = d['has_more'] == true;
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

  Future<void> _loadMore() async {
    if (_loadingMore || !_hasMore) return;
    setState(() => _loadingMore = true);
    try {
      final d = await _fetch(_cards.length);
      if (!mounted) return;
      setState(() {
        _cards.addAll(rMaps(d['cards']));
        _hasMore = d['has_more'] == true;
        _loadingMore = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _loadingMore = false);
      _toast(rFriendly(e), error: true);
    }
  }

  void _toast(String m, {bool error = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(m), backgroundColor: error ? Colors.red : kRGreen, behavior: SnackBarBehavior.floating));
  }

  /// every card of the class (loads what is still missing, with progress)
  Future<List<Map<String, dynamic>>> _allCards() async {
    final all = List<Map<String, dynamic>>.of(_cards);
    var more = _hasMore;
    while (more) {
      setState(() {
        _progress = 0.05 + 0.4 * (all.length / math_max(_total, 1));
        _progressText = 'Loading students… ${all.length}/$_total';
      });
      final d = await _fetch(all.length);
      all.addAll(rMaps(d['cards']));
      more = d['has_more'] == true;
    }
    return all;
  }

  int math_max(int a, int b) => a > b ? a : b;

  Future<void> _export({required bool print}) async {
    if (_progress != null || _cards.isEmpty) return;
    setState(() {
      _progress = 0.02;
      _progressText = 'Preparing…';
    });
    try {
      final all = await _allCards();
      final bytes = await ReportCardPdf.build(all, onProgress: (p) {
        if (mounted) {
          setState(() {
            _progress = 0.45 + 0.55 * p;
            _progressText = 'Building PDF… ${(p * 100).round()}%';
          });
        }
      });
      final name = 'All_Results_${widget.className}_${widget.termName}_${widget.sessionName}.pdf'.replaceAll(RegExp(r'[^a-zA-Z0-9_.-]'), '_');
      if (print) {
        await Printing.layoutPdf(onLayout: (_) async => bytes, name: name);
      } else {
        await Printing.sharePdf(bytes: bytes, filename: name);
      }
      _toast('PDF ready (${all.length} students).');
    } catch (e) {
      _toast('Export failed: ${rFriendly(e)}', error: true);
    } finally {
      if (mounted) setState(() => _progress = null);
    }
  }

  // ───────────────────────────── BUILD ─────────────────────────────
  @override
  Widget build(BuildContext context) {
    return Theme(
      data: resultLightTheme(),
      child: Scaffold(
        backgroundColor: kRBg,
        appBar: AppBar(
          elevation: 0,
          foregroundColor: Colors.white,
          surfaceTintColor: Colors.transparent,
          flexibleSpace: Container(decoration: const BoxDecoration(gradient: kRPurpleGradient)),
          title: const Text('All Results', style: TextStyle(fontWeight: FontWeight.w800)),
          actions: [IconButton(tooltip: 'Refresh', icon: const Icon(Icons.refresh), onPressed: _progress != null ? null : _first)],
        ),
        body: Stack(children: [
          _loading
              ? const Center(child: CircularProgressIndicator(color: kRPrimary))
              : _error != null
                  ? _errorBox()
                  : _cards.isEmpty
                      ? _empty()
                      : _list(),
          if (_progress != null) _overlay(),
        ]),
      ),
    );
  }

  Widget _errorBox() => Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const Icon(Icons.error_outline, color: Colors.red, size: 44),
            const SizedBox(height: 10),
            Text(_error!, textAlign: TextAlign.center, style: const TextStyle(color: Colors.red)),
            const SizedBox(height: 14),
            ElevatedButton.icon(onPressed: _first, icon: const Icon(Icons.refresh), label: const Text('Retry')),
          ]),
        ),
      );

  Widget _empty() => Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const Icon(Icons.group_off, size: 64, color: kRMuted),
            const SizedBox(height: 12),
            const Text('No Finalized Results Found', style: TextStyle(fontSize: 21, fontWeight: FontWeight.w800)),
            const SizedBox(height: 6),
            const Text('No students have finalized results for the selected criteria.', textAlign: TextAlign.center, style: TextStyle(color: kRMuted)),
            const SizedBox(height: 16),
            ElevatedButton.icon(onPressed: () => Navigator.of(context).maybePop(), icon: const Icon(Icons.arrow_back), label: const Text('Go Back')),
          ]),
        ),
      );

  Widget _overlay() => Positioned.fill(
        child: Container(
          color: Colors.black.withOpacity(0.78),
          alignment: Alignment.center,
          child: Container(
            width: 300,
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(18)),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              const SizedBox(width: 38, height: 38, child: CircularProgressIndicator(strokeWidth: 4, color: kRPrimary)),
              const SizedBox(height: 14),
              const Text('Generating PDF... Please wait', style: TextStyle(fontWeight: FontWeight.w800)),
              const SizedBox(height: 12),
              ClipRRect(borderRadius: BorderRadius.circular(6), child: LinearProgressIndicator(value: _progress, minHeight: 8, color: kRPrimary, backgroundColor: const Color(0xFFE9ECEF))),
              const SizedBox(height: 8),
              Text('${((_progress ?? 0) * 100).round()}%  ·  $_progressText', style: const TextStyle(color: kRMuted, fontSize: 12.5)),
            ]),
          ),
        ),
      );

  Widget _list() {
    return ListView(
      controller: _scroll,
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 40),
      children: [
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(gradient: kRPurpleGradient, borderRadius: BorderRadius.circular(12)),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(widget.className, style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.w800)),
            const SizedBox(height: 4),
            Text('${widget.sessionName}  •  ${widget.termName}', style: const TextStyle(color: Colors.white70)),
          ]),
        ),
        const SizedBox(height: 12),
        Wrap(spacing: 10, runSpacing: 10, crossAxisAlignment: WrapCrossAlignment.center, children: [
          Text.rich(TextSpan(style: const TextStyle(fontSize: 14), children: [
            const TextSpan(text: 'Displaying '),
            TextSpan(text: '$_total', style: const TextStyle(fontWeight: FontWeight.w800, color: kRPrimary)),
            TextSpan(text: ' student${_total > 1 ? 's' : ''} with finalized results'),
          ])),
        ]),
        const SizedBox(height: 10),
        Wrap(spacing: 10, runSpacing: 10, children: [
          ElevatedButton.icon(
            onPressed: _progress != null ? null : () => _export(print: false),
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFDC3545), foregroundColor: Colors.white),
            icon: const Icon(Icons.picture_as_pdf, size: 18),
            label: const Text('Download All as PDF'),
          ),
          ElevatedButton.icon(
            onPressed: _progress != null ? null : () => _export(print: true),
            style: ElevatedButton.styleFrom(backgroundColor: kRPrimary, foregroundColor: Colors.white),
            icon: const Icon(Icons.print, size: 18),
            label: const Text('Print'),
          ),
        ]),
        const SizedBox(height: 14),
        for (var i = 0; i < _cards.length; i++) _studentBlock(_cards[i], i),
        if (_loadingMore) const Padding(padding: EdgeInsets.all(20), child: Center(child: CircularProgressIndicator(color: kRPrimary))),
        if (_hasMore && !_loadingMore) Center(child: TextButton.icon(onPressed: _loadMore, icon: const Icon(Icons.expand_more), label: Text('Load more (${_cards.length}/$_total)'))),
      ],
    );
  }

  Widget _studentBlock(Map<String, dynamic> card, int i) {
    final st = rMap(card['student']);
    final sum = rMap(card['summary']);
    final id = rInt(st['user_id']);
    final open = _open.contains(id);
    final pos = '${sum['position'] ?? ''}'.trim();
    final adm = '${st['admission_number'] ?? ''}';
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12), boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.07), blurRadius: 10, offset: const Offset(0, 3))]),
      clipBehavior: Clip.antiAlias,
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        InkWell(
          onTap: () => setState(() {
            if (open) {
              _open.remove(id);
            } else {
              _open.add(id);
            }
          }),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Row(children: [
              SizedBox(width: 24, child: Text('${i + 1}', style: const TextStyle(fontWeight: FontWeight.w800, color: kRMuted))),
              RAvatar(name: '${st['fullname']}', url: '${st['photo_url'] ?? ''}', size: 44),
              const SizedBox(width: 12),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('${st['fullname']}', style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15.5)),
                  const SizedBox(height: 2),
                  Text.rich(TextSpan(style: const TextStyle(fontSize: 12, color: kRMuted), children: [
                    TextSpan(text: 'ID: ${st['idnumber']}'),
                    if (adm.isNotEmpty) TextSpan(text: '  |  Admission: $adm'),
                    if (st['is_transferred'] == true) TextSpan(text: '  |  (Transferred to: ${st['class_name']})', style: const TextStyle(color: Color(0xFFE74C3C))),
                  ])),
                  const SizedBox(height: 4),
                  Text.rich(TextSpan(style: const TextStyle(fontSize: 12.5, color: Color(0xFF666666)), children: [
                    const TextSpan(text: 'Position: '),
                    TextSpan(text: pos.isEmpty ? 'N/A' : pos, style: const TextStyle(fontWeight: FontWeight.w800, color: kRText)),
                    const TextSpan(text: '   |   Average: '),
                    TextSpan(text: rNum(sum['average_score']), style: TextStyle(fontWeight: FontWeight.w800, color: scoreColor(rDouble(sum['average_score'])))),
                  ])),
                ]),
              ),
              Icon(open ? Icons.expand_less : Icons.expand_more, color: kRMuted),
            ]),
          ),
        ),
        if (open)
          Container(
            color: const Color(0xFFF0F4FF),
            padding: const EdgeInsets.all(10),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              ReportCardView(card: card),
              const SizedBox(height: 8),
              Align(
                alignment: Alignment.centerRight,
                child: TextButton.icon(
                  onPressed: () => Navigator.of(context).push(MaterialPageRoute(
                    builder: (_) => FlutterResultCardScreen(
                      token: _token,
                      idnumber: '${st['idnumber']}',
                      sessionId: widget.sessionId,
                      termId: widget.termId,
                      classId: widget.classId,
                      studentName: '${st['fullname']}',
                    ),
                  )),
                  icon: const Icon(Icons.open_in_full, size: 16),
                  label: const Text('Open full screen (PDF / Reveal)'),
                ),
              ),
            ]),
          ),
      ]),
    );
  }
}
