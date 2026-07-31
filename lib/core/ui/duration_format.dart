/// Formats a span of seconds for the player: "Instant", "45s", "3m 20s",
/// "2h 05m", "1d 6h".
///
/// It lived in build_menu_sheet.dart, and the energy sheet and the settlement
/// map both reached across to import it from there — a general formatter
/// hiding inside one menu's file. Moved here when that menu became a screen.
String fmtDuration(double seconds) {
  if (seconds <= 0) return 'Instant';
  if (seconds < 60) return '${seconds.toInt()}s';
  final m = (seconds / 60).floor();
  final s = (seconds % 60).toInt();
  if (m < 60) return '${m}m ${s.toString().padLeft(2, '0')}s';
  final h = (m / 60).floor();
  final rm = m % 60;
  if (h < 24) return '${h}h ${rm.toString().padLeft(2, '0')}m';
  final d = (h / 24).floor();
  return '${d}d ${(h % 24)}h';
}
