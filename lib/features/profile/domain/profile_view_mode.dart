/// Who is looking at the card.
///
/// Not a permission system — a *preview*: "Visitor" shows exactly what someone
/// else sees, so the owner can check the card before trusting it.
enum ProfileViewMode {
  owner,
  visitor;

  bool get isVisitor => this == ProfileViewMode.visitor;

  /// Copy that changes with the viewer. Kept in one place so a label can never
  /// say "your" to a visitor.
  String pick({required String owner, required String visitor}) =>
      isVisitor ? visitor : owner;
}
