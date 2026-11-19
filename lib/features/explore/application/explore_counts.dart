/// The three numbers behind the segmented control, in one value object so a
/// widget reads them together and a test can assert on them together.
class ExploreCounts {
  const ExploreCounts({this.requests = 0, this.sent = 0, this.friends = 0});

  final int requests;
  final int sent;
  final int friends;

  bool get isEmpty => requests == 0 && sent == 0;

  ExploreCounts copyWith({int? requests, int? sent, int? friends}) =>
      ExploreCounts(
        requests: requests ?? this.requests,
        sent: sent ?? this.sent,
        friends: friends ?? this.friends,
      );

  @override
  bool operator ==(Object other) =>
      other is ExploreCounts &&
      other.requests == requests &&
      other.sent == sent &&
      other.friends == friends;

  @override
  int get hashCode => Object.hash(requests, sent, friends);
}
