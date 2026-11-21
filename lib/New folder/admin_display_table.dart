import 'package:flutter/material.dart';

class AdminColumn<T> {
  final String header;
  final Widget Function(T row) cell;
  final double width;
  const AdminColumn(
      {required this.header, required this.cell, this.width = 140});
}

class AdminDisplayTable<T> extends StatelessWidget {
  final List<T> rows;
  final List<AdminColumn<T>> columns;
  final bool loading;
  final String? error;
  final VoidCallback? onRetry;
  final String emptyMessage;
  final void Function(T row)? onTap;

  const AdminDisplayTable({
    super.key,
    required this.rows,
    required this.columns,
    this.loading = false,
    this.error,
    this.onRetry,
    this.emptyMessage = 'No records found',
    this.onTap,
  });

  static const _primary = Color(0xFF4361ee);
  static const _muted = Color(0xFF64748b);
  static const _border = Color(0xFFe2e8f0);

  @override
  Widget build(BuildContext context) {
    if (loading)
      return const Padding(
          padding: EdgeInsets.all(40),
          child: Center(child: CircularProgressIndicator()));
    if (error != null) {
      return Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
            color: Colors.red.shade50,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: Colors.red.shade200)),
        child: Column(children: [
          Icon(Icons.error_outline, color: Colors.red.shade700, size: 32),
          const SizedBox(height: 8),
          Text(error!,
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.red.shade800, fontSize: 13)),
          if (onRetry != null) ...[
            const SizedBox(height: 12),
            OutlinedButton.icon(
                onPressed: onRetry,
                icon: const Icon(Icons.refresh, size: 16),
                label: const Text('Retry')),
          ],
        ]),
      );
    }
    if (rows.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(32),
        alignment: Alignment.center,
        decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: _border)),
        child: Column(children: [
          Icon(Icons.inbox_outlined, size: 42, color: Colors.grey.shade300),
          const SizedBox(height: 8),
          Text(emptyMessage,
              style: const TextStyle(color: _muted, fontSize: 13)),
        ]),
      );
    }

    final wide = MediaQuery.of(context).size.width >= 760;
    return wide ? _buildTable(context) : _buildCards(context);
  }

  Widget _buildTable(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: _border)),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(14),
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: DataTable(
            headingRowColor:
                WidgetStateProperty.all(_primary.withOpacity(0.06)),
            dataRowMinHeight: 48,
            dataRowMaxHeight: 64,
            columns: columns
                .map((c) => DataColumn(
                    label: Text(c.header.toUpperCase(),
                        style: const TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w800,
                            color: _muted))))
                .toList(),
            rows: rows
                .map((r) => DataRow(
                      onSelectChanged: onTap == null ? null : (_) => onTap!(r),
                      cells: columns
                          .map((c) => DataCell(
                              SizedBox(width: c.width, child: c.cell(r))))
                          .toList(),
                    ))
                .toList(),
          ),
        ),
      ),
    );
  }

  Widget _buildCards(BuildContext context) {
    return Column(
      children: rows
          .map((r) => Container(
                width: double.infinity,
                margin: const EdgeInsets.only(bottom: 10),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: _border)),
                child: InkWell(
                  onTap: onTap == null ? null : () => onTap!(r),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: columns
                        .map((c) => Padding(
                              padding: const EdgeInsets.symmetric(vertical: 3),
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  SizedBox(
                                      width: 110,
                                      child: Text(c.header,
                                          style: const TextStyle(
                                              fontSize: 11,
                                              color: _muted,
                                              fontWeight: FontWeight.w700))),
                                  Expanded(child: c.cell(r)),
                                ],
                              ),
                            ))
                        .toList(),
                  ),
                ),
              ))
          .toList(),
    );
  }
}
