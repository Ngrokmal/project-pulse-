/// The three things a visitor may do to end something, with the exact words
/// the confirmation sheet uses.
///
/// Copy lives here, not in widgets, so the same sentence is used by the row and
/// the sheet that row opens — a mismatch between them is how a "Clear" button
/// ends up asking "Block?".
enum SafetyAction {
  clearChat(
    title: 'Clear this chat?',
    body: 'Every message and file leaves this phone. The other person keeps '
        'their own copy — you just stop seeing it here.',
    confirmLabel: 'Clear',
    doneLabel: 'Chat cleared',
  ),
  block(
    title: 'Block ?name?',
    body: 'Messages and calls stop, both ways. They are never told.',
    confirmLabel: 'Block',
    doneLabel: 'Blocked',
  ),
  report(
    title: 'Report ?name?',
    body: 'Your report goes to the Pulse safety team. They are never told you '
        'sent it.',
    confirmLabel: 'Report',
    doneLabel: 'Report sent',
  );

  const SafetyAction({
    required this.title,
    required this.body,
    required this.confirmLabel,
    required this.doneLabel,
  });

  final String title;
  final String body;
  final String confirmLabel;
  final String doneLabel;

  /// Fills `?name?` with the person's first name, or with "this person" when
  /// the card has not loaded.
  String titleFor(String givenName) =>
      title.replaceAll('?name?', givenName.trim().isEmpty ? 'this person' : givenName.trim());

  bool get isDestructive => true;
}

/// Why someone is reporting a card. Kept short and factual — the safety team
/// reads these, so no free-text is required to file one.
enum ReportReason {
  spam('Spam or a fake account'),
  harassment('Harassment or threats'),
  impersonation('Pretending to be someone else'),
  other('Something else');

  const ReportReason(this.label);

  final String label;

  /// Fits `reports.reason` (≤ 60 chars) without a client-side truncation race.
  String get value => label;
}
