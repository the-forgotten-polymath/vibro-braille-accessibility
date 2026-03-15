class RevisionManager {
  static final RevisionManager _instance = RevisionManager._internal();
  factory RevisionManager() => _instance;
  RevisionManager._internal();

  String _currentResponseId = "";
  int _revisionCount = 0;
  bool _isInterrupted = false;

  String get currentResponseId => _currentResponseId;
  int get revisionCount => _revisionCount;
  bool get isInterrupted => _isInterrupted;

  void startNewResponse(String responseId) {
    _currentResponseId = responseId;
    _revisionCount = 0;
    _isInterrupted = false;
    print("🔄 [RevisionManager] New response: $_currentResponseId");
  }

  void incrementRevision() {
    _revisionCount++;
    print("🔄 [RevisionManager] Revision count incremented to $_revisionCount");
  }

  void triggerInterruption() {
    _isInterrupted = true;
    _currentResponseId = "";
    print("🔄 [RevisionManager] Interruption detected. Active response invalidated.");
  }

  bool isEventValid(String responseId, int revision) {
    if (_isInterrupted) return false;
    if (_currentResponseId.isNotEmpty && responseId != _currentResponseId) return false;
    return true;
  }
}
