/// The recorder is a real state machine: a tap starts it and it keeps rolling,
/// the mic pauses and resumes it, the bin discards it, and only the send button
/// commits it (reference v2 record model).
enum RecordStage {
  idle,
  recording,
  paused,
  sending;

  bool get showsPill => this == recording || this == paused || this == sending;
  bool get isLive => this == recording;
}

class InboxRecordState {
  const InboxRecordState({
    this.stage = RecordStage.idle,
    this.elapsedMs = 0,
    this.path,
    this.sizeBytes = 0,
    this.error,
  });

  final RecordStage stage;
  final int elapsedMs;
  final String? path;
  final int sizeBytes;
  final String? error;

  bool get hasTake => path != null && elapsedMs > 0;
  bool get isBusy => stage == RecordStage.sending;

  Duration get duration =>
      Duration(milliseconds: elapsedMs < 600 ? 600 : elapsedMs);

  InboxRecordState copyWith({
    RecordStage? stage,
    int? elapsedMs,
    String? path,
    int? sizeBytes,
    String? error,
    bool clearError = false,
  }) => InboxRecordState(
    stage: stage ?? this.stage,
    elapsedMs: elapsedMs ?? this.elapsedMs,
    path: path ?? this.path,
    sizeBytes: sizeBytes ?? this.sizeBytes,
    error: clearError ? null : (error ?? this.error),
  );

  static const InboxRecordState idle = InboxRecordState();
}
