class SpawnSubAgentInput {
  const SpawnSubAgentInput({
    required this.task,
    required this.agentType,
    this.maxSteps = 8,
  });

  /// The task description for the sub-agent.
  final String task;

  /// One of: 'research', 'summarize', 'verify'.
  final String agentType;

  /// Maximum tool-use iterations (clamped to 1..15).
  final int maxSteps;

  factory SpawnSubAgentInput.fromJson(Map<String, dynamic> json) {
    return SpawnSubAgentInput(
      task: json['task'] as String,
      agentType: json['agentType'] as String? ?? 'research',
      maxSteps: (json['maxSteps'] as int?)?.clamp(1, 15) ?? 8,
    );
  }
}
