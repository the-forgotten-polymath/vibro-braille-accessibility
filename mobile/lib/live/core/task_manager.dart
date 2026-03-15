import 'dart:collection';
import '../models/preemptable_task.dart';
import '../models/tdl_event.dart';

class TaskManager {
  static final TaskManager _instance = TaskManager._internal();
  factory TaskManager() => _instance;
  TaskManager._internal();

  final ListQueue<PreemptableTask> _taskStack = ListQueue<PreemptableTask>();
  
  PreemptableTask? get activeTask {
    if (_taskStack.isEmpty) return null;
    return _taskStack.first;
  }

  List<PreemptableTask> get stack => _taskStack.toList();

  /// Pushes a task to the stack, pre-empting the current active task if the new task has higher priority.
  /// Returns true if a pre-emption occurred.
  bool pushTask(PreemptableTask newTask) {
    print("📋 [TaskManager] Attempting to push task: $newTask");

    if (_taskStack.isNotEmpty) {
      final current = _taskStack.first;
      if (newTask.priority >= current.priority) {
        print("📋 [TaskManager] Pre-empting active task: ${current.id} with higher priority task: ${newTask.id}");
        current.status = TaskStatus.paused;
        _taskStack.addFirst(newTask);
        newTask.status = TaskStatus.active;
        return true;
      } else {
        // Lower priority task: queue it behind the active task
        print("📋 [TaskManager] Queuing lower priority task ${newTask.id} under current task ${current.id}");
        _taskStack.addLast(newTask);
        return false;
      }
    } else {
      _taskStack.addFirst(newTask);
      newTask.status = TaskStatus.active;
      return true;
    }
  }

  /// Removes the finished active task. Returns the next task to resume, if any.
  PreemptableTask? completeActiveTask() {
    if (_taskStack.isEmpty) return null;
    final completed = _taskStack.removeFirst();
    completed.status = TaskStatus.completed;
    print("📋 [TaskManager] Completed task: ${completed.id}");

    if (_taskStack.isNotEmpty) {
      final nextTask = _taskStack.first;
      nextTask.status = TaskStatus.active;
      print("📋 [TaskManager] Resuming task: ${nextTask.id} from checkpoint wordIndex: ${nextTask.wordIndex}");
      return nextTask;
    }
    return null;
  }

  /// Clears all tasks in the queue (e.g. for emergency stops).
  void clearAll() {
    print("📋 [TaskManager] Clearing all tasks in stack.");
    _taskStack.clear();
  }
}
