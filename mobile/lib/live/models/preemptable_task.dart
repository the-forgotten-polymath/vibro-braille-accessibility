import '../models/tdl_event.dart';

enum TaskStatus {
  pending,
  active,
  paused,
  completed,
}

class PreemptableTask {
  final String id;
  final InteractionType type;
  final int priority;
  final String content;
  
  // Checkpoint metadata
  int wordIndex;
  TaskStatus status;

  PreemptableTask({
    required this.id,
    required this.type,
    required this.priority,
    required this.content,
    this.wordIndex = 0,
    this.status = TaskStatus.pending,
  });

  @override
  String toString() {
    return 'PreemptableTask(id: $id, type: $type, priority: $priority, wordIndex: $wordIndex, status: $status)';
  }
}
