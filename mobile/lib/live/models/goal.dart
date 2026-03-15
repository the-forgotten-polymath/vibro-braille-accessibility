class Goal {
  final String id;
  final String description;
  final bool isCompleted;
  final Map<String, dynamic> criteria;

  Goal({
    required this.id,
    required this.description,
    required this.isCompleted,
    required this.criteria,
  });

  Goal copyWith({
    String? id,
    String? description,
    bool? isCompleted,
    Map<String, dynamic>? criteria,
  }) {
    return Goal(
      id: id ?? this.id,
      description: description ?? this.description,
      isCompleted: isCompleted ?? this.isCompleted,
      criteria: criteria ?? this.criteria,
    );
  }
}
