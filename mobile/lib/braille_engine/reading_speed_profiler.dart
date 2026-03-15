class ReadingSpeedProfiler {
  double currentWpm = 20.0;
  final List<DateTime> _inputTimestamps = [];

  /// Records a character input to calculate WPM.
  void recordInput() {
    final now = DateTime.now();
    _inputTimestamps.add(now);
    
    // Keep only last 10 inputs for rolling average
    if (_inputTimestamps.length > 10) {
      _inputTimestamps.removeAt(0);
    }

    if (_inputTimestamps.length >= 2) {
      final totalTime = _inputTimestamps.last.difference(_inputTimestamps.first).inMilliseconds;
      final charsPerMs = (_inputTimestamps.length - 1) / totalTime;
      // WPM = (Chars / 5) / (Ms / 60000)
      currentWpm = (charsPerMs * 60000) / 5;
    }
  }

  /// Suggests a character delay (ms) based on current speed.
  int getSuggestedCharDelay() {
    // Standard: 60 WPM = 1 char per 200ms
    // Delay = 60000 / (WPM * 5)
    return (60000 / (currentWpm.clamp(5, 100) * 5)).toInt();
  }
}
