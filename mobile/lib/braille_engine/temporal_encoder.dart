class BrailleHapticPattern {
  final List<int> timings;
  final List<int> amplitudes;

  BrailleHapticPattern(this.timings, this.amplitudes);
}

class TemporalEncoder {
  int baseDotDuration; // ms
  int baseInterDotDelay; // ms
  int baseInterCharDelay; // ms
  double amplitudeScale;
  double speed; // 1.0 = normal, < 1.0 = slower, > 1.0 = faster

  TemporalEncoder({
    this.baseDotDuration = 100, // Balanced for recognition
    this.baseInterDotDelay = 60, // Sharper separation
    this.baseInterCharDelay = 300,
    this.amplitudeScale = 1.0,
    this.speed = 1.0,
  });

  // Calculate actual timings based on speed
  int get dotDuration => (baseDotDuration / speed).toInt();
  int get interDotDelay => (baseInterDotDelay / speed).toInt();
  int get interCharDelay => (baseInterCharDelay / speed).toInt();

  /// Encodes a single Braille character (list of dots) into haptic timings and amplitudes.
  /// Uses the Fixed 6-Slot standard (serialized dots 1-6) to ensure characters are distinguishable.
  BrailleHapticPattern encodeCharacter(List<int> dots) {
    if (dots.isEmpty) {
      // Space or unknown: just a character-length silence
      int totalSilences = (6 * dotDuration) + (5 * interDotDelay) + interCharDelay;
      return BrailleHapticPattern([totalSilences], [0]);
    }

    List<int> timings = [];
    List<int> amplitudes = [];

    // Serialize the 6-dot cell in order: 1, 2, 3, 4, 5, 6
    for (int dot = 1; dot <= 6; dot++) {
      if (dots.contains(dot)) {
        // Dot is active: Vibrate
        timings.add(dotDuration);
        amplitudes.add((255 * amplitudeScale).toInt());
      } else {
        // Dot is inactive: Play silence placeholder
        timings.add(dotDuration);
        amplitudes.add(0);
      }

      // Add inter-dot gap between slots (except after dot 6)
      if (dot < 6) {
        timings.add(interDotDelay);
        amplitudes.add(0);
      }
    }

    // Add inter-character delay at the end
    timings.add(interCharDelay);
    amplitudes.add(0);

    return BrailleHapticPattern(timings, amplitudes);
  }

  /// Encodes a full string into a single large waveform.
  BrailleHapticPattern encodeText(List<List<int>> translatedText) {
    List<int> allTimings = [];
    List<int> allAmplitudes = [];

    for (var dots in translatedText) {
      var pattern = encodeCharacter(dots);
      allTimings.addAll(pattern.timings);
      allAmplitudes.addAll(pattern.amplitudes);
    }

    return BrailleHapticPattern(allTimings, allAmplitudes);
  }
}
