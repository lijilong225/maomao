/// Formatting helpers shared by the UI.
library;

const _byteUnits = ['B', 'KB', 'MB', 'GB', 'TB', 'PB'];

String formatBytes(int bytes) {
  if (bytes <= 0) return '0 B';
  var value = bytes.toDouble();
  var unit = 0;
  while (value >= 1024 && unit < _byteUnits.length - 1) {
    value /= 1024;
    unit++;
  }
  final digits = value >= 100 || unit == 0 ? 0 : 1;
  return '${value.toStringAsFixed(digits)} ${_byteUnits[unit]}';
}

String formatRate(int bytesPerSecond) => '${formatBytes(bytesPerSecond)}/s';

String formatDelay(int milliseconds) =>
    milliseconds <= 0 ? '—' : '$milliseconds ms';

String formatDuration(Duration duration) {
  final hours = duration.inHours;
  final minutes = duration.inMinutes.remainder(60);
  final seconds = duration.inSeconds.remainder(60);
  if (hours > 0) return '${hours}h ${minutes}m';
  if (minutes > 0) return '${minutes}m ${seconds}s';
  return '${seconds}s';
}

String formatTimestamp(DateTime time) {
  final h = time.hour.toString().padLeft(2, '0');
  final m = time.minute.toString().padLeft(2, '0');
  final s = time.second.toString().padLeft(2, '0');
  return '$h:$m:$s';
}

String formatRelative(DateTime? time) {
  if (time == null) return 'never';
  final delta = DateTime.now().difference(time);
  if (delta.inSeconds < 60) return 'just now';
  if (delta.inMinutes < 60) return '${delta.inMinutes}m ago';
  if (delta.inHours < 24) return '${delta.inHours}h ago';
  return '${delta.inDays}d ago';
}

String formatDate(DateTime time) {
  final month = time.month.toString().padLeft(2, '0');
  final day = time.day.toString().padLeft(2, '0');
  return '${time.year}-$month-$day';
}
