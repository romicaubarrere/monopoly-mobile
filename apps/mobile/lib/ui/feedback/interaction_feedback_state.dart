enum InteractionFeedbackState {
  idle,
  pending,
  confirmed,
  rejected,
  stale,
  uncertain,
  offline,
  disabled,
}

extension InteractionFeedbackStateX on InteractionFeedbackState {
  bool get isActionable => this == InteractionFeedbackState.idle;

  bool get isPending => this == InteractionFeedbackState.pending;

  bool get blocksConflictingIntent => switch (this) {
    InteractionFeedbackState.pending ||
    InteractionFeedbackState.uncertain ||
    InteractionFeedbackState.offline =>
      true,
    _ => false,
  };
}
