class ProgressThrottler {
  final Duration throttleDuration;
  final double percentageThreshold;
  final void Function(int received, int total) onUpdate;

  DateTime? _lastUpdateTime;
  int? _lastReportedPercentage;

  ProgressThrottler({
    this.throttleDuration = const Duration(milliseconds: 200),
    this.percentageThreshold = 1.0,
    required this.onUpdate,
  });

  void call(int received, int total) {
    if (total <= 0) return;

    final currentPercentage = (received / total * 100).floor();
    final now = DateTime.now();

    // First update (show 0%)
    if (_lastUpdateTime == null) {
      _dispatchUpdate(received, total, now, currentPercentage);
      return;
    }

    // Final update (show 100%)
    if (received >= total) {
      _dispatchUpdate(received, total, now, 100);
      return;
    }

    final timeElapsed = now.difference(_lastUpdateTime!);
    final percentageChanged = (currentPercentage - (_lastReportedPercentage ?? 0)).abs();

    // Time-based or percentage-based update
    if (timeElapsed > throttleDuration || percentageChanged >= percentageThreshold) {
      _dispatchUpdate(received, total, now, currentPercentage);
    }
  }

  void _dispatchUpdate(int received, int total, DateTime time, int percentage) {
    _lastUpdateTime = time;
    _lastReportedPercentage = percentage;
    onUpdate(received, total);
  }

  void reset() {
    _lastUpdateTime = null;
    _lastReportedPercentage = null;
  }
}