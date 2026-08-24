import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:table_calendar/table_calendar.dart';

import 'app_theme.dart';
import 'formatting.dart';

/// Lets a host take dates off the market (B7).
///
/// Before this, the only thing that could write to a property's calendar was a
/// guest booking — a host could not close a week for maintenance or because
/// they were using the place themselves.
class ManageAvailabilityPage extends StatefulWidget {
  final String propertyId;
  final String propertyName;

  const ManageAvailabilityPage({
    super.key,
    required this.propertyId,
    required this.propertyName,
  });

  @override
  State<ManageAvailabilityPage> createState() => _ManageAvailabilityPageState();
}

class _ManageAvailabilityPageState extends State<ManageAvailabilityPage> {
  final supabase = Supabase.instance.client;

  bool loading = true;
  bool saving = false;

  /// Dates taken by a live booking. Read-only — a host cannot block a date a
  /// guest has already reserved.
  final Set<DateTime> _booked = {};

  /// Dates the host has closed themselves.
  final Set<DateTime> _blocked = {};

  DateTime _focusedDay = DateTime.now();

  @override
  void initState() {
    super.initState();
    _load();
  }

  DateTime _norm(DateTime d) => DateTime(d.year, d.month, d.day);

  Future<void> _load() async {
    if (mounted) setState(() => loading = true);
    try {
      final blockedRes = await supabase
          .from('property_blocked_dates')
          .select('blocked_date')
          .eq('property_id', widget.propertyId);

      final unavailable = await supabase.rpc(
        'property_unavailable_dates',
        params: {'p_property_id': widget.propertyId},
      );

      final blocked = <DateTime>{};
      for (final r in List<Map<String, dynamic>>.from(blockedRes)) {
        final d = DateTime.tryParse(r['blocked_date'].toString());
        if (d != null) blocked.add(_norm(d));
      }

      final booked = <DateTime>{};
      for (final r in List<Map<String, dynamic>>.from(unavailable as List)) {
        if (r['reason'] != 'booked') continue;
        final d = DateTime.tryParse(r['d'].toString());
        if (d != null) booked.add(_norm(d));
      }

      if (!mounted) return;
      setState(() {
        _blocked
          ..clear()
          ..addAll(blocked);
        _booked
          ..clear()
          ..addAll(booked);
        loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => loading = false);
      _snack('Could not load the calendar: $e', error: true);
    }
  }

  Future<void> _toggleDay(DateTime day) async {
    final d = _norm(day);

    if (_booked.contains(d)) {
      _snack('A guest has already booked this date.');
      return;
    }
    if (d.isBefore(_norm(DateTime.now()))) {
      _snack('That date is in the past.');
      return;
    }

    final wasBlocked = _blocked.contains(d);

    // Optimistic: the calendar should respond instantly, and a failure below
    // puts it back.
    setState(() {
      wasBlocked ? _blocked.remove(d) : _blocked.add(d);
      saving = true;
    });

    try {
      if (wasBlocked) {
        await supabase
            .from('property_blocked_dates')
            .delete()
            .eq('property_id', widget.propertyId)
            .eq('blocked_date', Fmt.isoDate(d));
      } else {
        await supabase.from('property_blocked_dates').insert({
          'property_id': widget.propertyId,
          'blocked_date': Fmt.isoDate(d),
        });
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => wasBlocked ? _blocked.add(d) : _blocked.remove(d));
      _snack('Could not update that date: $e', error: true);
    } finally {
      if (mounted) setState(() => saving = false);
    }
  }

  Future<void> _blockRange() async {
    final now = DateTime.now();
    final range = await showDateRangePicker(
      context: context,
      firstDate: _norm(now),
      lastDate: now.add(const Duration(days: 365)),
      helpText: 'Select dates to close',
    );
    if (range == null) return;

    final days = <DateTime>[];
    for (var d = _norm(range.start);
        !d.isAfter(_norm(range.end));
        d = d.add(const Duration(days: 1))) {
      if (_booked.contains(d) || _blocked.contains(d)) continue;
      days.add(d);
    }

    if (days.isEmpty) {
      _snack('Nothing to close in that range.');
      return;
    }

    setState(() => saving = true);
    try {
      await supabase.from('property_blocked_dates').insert([
        for (final d in days)
          {
            'property_id': widget.propertyId,
            'blocked_date': Fmt.isoDate(d),
          }
      ]);
      if (!mounted) return;
      setState(() => _blocked.addAll(days));
      _snack('Closed ${days.length} date${days.length == 1 ? '' : 's'}.');
    } catch (e) {
      if (!mounted) return;
      _snack('Could not close those dates: $e', error: true);
    } finally {
      if (mounted) setState(() => saving = false);
    }
  }

  Future<void> _clearAllBlocks() async {
    if (_blocked.isEmpty) return;

    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('Reopen all closed dates?'),
        content: Text(
            '${_blocked.length} date${_blocked.length == 1 ? '' : 's'} will '
            'become bookable again. Guest bookings are not affected.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel', style: TextStyle(color: Colors.grey)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Reopen all',
                style: TextStyle(
                    color: Colors.red, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
    if (ok != true) return;

    setState(() => saving = true);
    try {
      await supabase
          .from('property_blocked_dates')
          .delete()
          .eq('property_id', widget.propertyId);
      if (!mounted) return;
      setState(() => _blocked.clear());
    } catch (e) {
      if (!mounted) return;
      _snack('Could not reopen: $e', error: true);
    } finally {
      if (mounted) setState(() => saving = false);
    }
  }

  void _snack(String msg, {bool error = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(SnackBar(
        content: Text(msg),
        backgroundColor: error ? Colors.red : AppColors.darkTeal,
        duration: const Duration(seconds: 2),
      ));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F7FA),
      appBar: AppBar(
        title: const Text('Availability'),
        backgroundColor: AppColors.darkTeal,
        foregroundColor: Colors.white,
        actions: [
          if (_blocked.isNotEmpty)
            IconButton(
              tooltip: 'Reopen all closed dates',
              icon: const Icon(Icons.lock_open_rounded),
              onPressed: saving ? null : _clearAllBlocks,
            ),
        ],
      ),
      body: loading
          ? const Center(
              child: CircularProgressIndicator(color: AppColors.darkTeal))
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Text(
                  widget.propertyName,
                  style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: AppColors.darkTeal),
                ),
                const SizedBox(height: 4),
                const Text(
                  'Tap a date to close or reopen it. Guests cannot book closed '
                  'dates.',
                  style: TextStyle(fontSize: 12.5, color: Colors.black54),
                ),
                const SizedBox(height: 16),

                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(20),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.04),
                        blurRadius: 12,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: TableCalendar(
                    firstDay: _norm(DateTime.now()),
                    lastDay: DateTime.now().add(const Duration(days: 365)),
                    focusedDay: _focusedDay,
                    headerStyle: const HeaderStyle(
                      formatButtonVisible: false,
                      titleCentered: true,
                      titleTextStyle: TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.bold,
                          color: AppColors.darkTeal),
                    ),
                    onPageChanged: (d) => _focusedDay = d,
                    onDaySelected: (selected, focused) {
                      setState(() => _focusedDay = focused);
                      _toggleDay(selected);
                    },
                    calendarBuilders: CalendarBuilders(
                      defaultBuilder: (context, day, _) => _dayCell(day),
                      todayBuilder: (context, day, _) =>
                          _dayCell(day, isToday: true),
                      outsideBuilder: (context, day, _) => Center(
                        child: Text('${day.day}',
                            style: TextStyle(color: Colors.grey.shade300)),
                      ),
                    ),
                  ),
                ),

                const SizedBox(height: 16),
                Row(
                  children: [
                    _legend(Colors.red.shade400, 'Booked'),
                    const SizedBox(width: 16),
                    _legend(Colors.grey.shade600, 'Closed by you'),
                    const SizedBox(width: 16),
                    _legend(Colors.green.shade500, 'Open'),
                  ],
                ),

                const SizedBox(height: 20),
                GradientButton(
                  text: 'Close a date range',
                  icon: Icons.event_busy_rounded,
                  loading: saving,
                  onPressed: saving ? null : _blockRange,
                ),
                const SizedBox(height: 12),
                Center(
                  child: Text(
                    '${_blocked.length} closed · ${_booked.length} booked',
                    style: const TextStyle(fontSize: 12, color: Colors.black45),
                  ),
                ),
              ],
            ),
    );
  }

  Widget _dayCell(DateTime day, {bool isToday = false}) {
    final d = _norm(day);
    final isBooked = _booked.contains(d);
    final isBlocked = _blocked.contains(d);

    Color? bg;
    Color fg = Colors.black87;
    if (isBooked) {
      bg = Colors.red.shade400;
      fg = Colors.white;
    } else if (isBlocked) {
      bg = Colors.grey.shade600;
      fg = Colors.white;
    }

    return Container(
      margin: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: bg,
        shape: BoxShape.circle,
        border: isToday && bg == null
            ? Border.all(color: AppColors.lightTeal, width: 2)
            : null,
      ),
      child: Center(
        child: Text(
          '${day.day}',
          style: TextStyle(
            color: fg,
            fontWeight: bg != null ? FontWeight.bold : FontWeight.normal,
          ),
        ),
      ),
    );
  }

  Widget _legend(Color color, String label) => Row(
        children: [
          Container(
            width: 12,
            height: 12,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 6),
          Text(label,
              style: const TextStyle(fontSize: 11.5, color: Colors.black54)),
        ],
      );
}
