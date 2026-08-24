import 'package:intl/intl.dart';

/// Presentation helpers. Prices used to be interpolated raw, so a listing at
/// 125000 rendered as "PKR 125000".
class Fmt {
  Fmt._();

  static final NumberFormat _pkr =
      NumberFormat.currency(locale: 'en_PK', symbol: 'PKR ', decimalDigits: 0);

  static final NumberFormat _compact = NumberFormat.compact(locale: 'en');

  static final DateFormat _day = DateFormat('MMM d, yyyy');
  static final DateFormat _dayShort = DateFormat('MMM d');
  static final DateFormat _iso = DateFormat('yyyy-MM-dd');

  /// "PKR 125,000"
  static String money(num? value) => _pkr.format(value ?? 0);

  /// "125K" — for tiles and chips where the full number will not fit.
  static String moneyCompact(num? value) => 'PKR ${_compact.format(value ?? 0)}';

  /// "Mar 4, 2026"
  static String date(DateTime d) => _day.format(d);

  /// "Mar 4"
  static String dateShort(DateTime d) => _dayShort.format(d);

  /// "2026-03-04" — the wire format Postgres expects for a date column.
  static String isoDate(DateTime d) => _iso.format(d);

  /// "Mar 4 - Mar 9, 2026"
  static String dateRange(DateTime from, DateTime to) =>
      '${_dayShort.format(from)} - ${_day.format(to)}';

  static String nights(int n) => '$n ${n == 1 ? 'night' : 'nights'}';

  static String guests(int n) => '$n ${n == 1 ? 'guest' : 'guests'}';

  /// "1.2 km away" / "840 m away"
  static String distance(double? km) {
    if (km == null) return '';
    if (km < 1) return '${(km * 1000).round()} m away';
    if (km < 10) return '${km.toStringAsFixed(1)} km away';
    return '${km.round()} km away';
  }

  static String rating(num? value) =>
      (value == null || value == 0) ? 'New' : value.toStringAsFixed(1);
}
