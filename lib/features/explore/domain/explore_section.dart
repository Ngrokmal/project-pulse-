/// The three things one tab has to hold, in the reference's order.
enum ExploreSection {
  requests('Requests', 'Friend requests'),
  sent('Sent', 'Waiting for them'),
  friends('Friends', 'Your circle');

  const ExploreSection(this.label, this.heading);

  /// The word inside the segment.
  final String label;

  /// The heading above the list.
  final String heading;
}
