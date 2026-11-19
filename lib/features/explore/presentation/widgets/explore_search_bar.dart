import 'package:material_ui/material_ui.dart';

import '../../domain/explore_motion.dart';
import '../../domain/explore_palette.dart';
import 'explore_pressable.dart';

/// The third line of the header: type here, then ask.
///
/// Typing is free — it changes nothing but this widget. The purple button (or
/// the keyboard's search key) is the only thing that talks to the server, which
/// is the whole point of the reference: one deliberate round trip instead of
/// fifteen.
class ExploreSearchBar extends StatefulWidget {
  const ExploreSearchBar({
    super.key,
    required this.controller,
    required this.onSubmit,
    this.autofocus = false,
    this.readOnly = false,
    this.onTapField,
    this.showBack = false,
    this.onBack,
  });

  final TextEditingController controller;
  final ValueChanged<String> onSubmit;
  final bool autofocus;
  final bool readOnly;
  final VoidCallback? onTapField;

  /// The sheet has a back chevron; the header does not.
  final bool showBack;
  final VoidCallback? onBack;

  @override
  State<ExploreSearchBar> createState() => _ExploreSearchBarState();
}

class _ExploreSearchBarState extends State<ExploreSearchBar> {
  bool _focused = false;
  bool _spin = false;

  void _submit() {
    setState(() => _spin = true);
    Future<void>.delayed(const Duration(milliseconds: 520), () {
      if (mounted) setState(() => _spin = false);
    });
    final query = widget.controller.text.trim();
    if (query.isEmpty) {
      widget.onTapField?.call();
      return;
    }
    widget.onSubmit(query);
  }

  @override
  Widget build(BuildContext context) {
    final hasText = widget.controller.text.trim().isNotEmpty;

    return Row(
      children: [
        if (widget.showBack) ...[
          ExplorePressable(
            onTap: widget.onBack,
            child: Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(13),
                border: Border.all(color: ExplorePalette.hairline),
              ),
              alignment: Alignment.center,
              child: const Icon(
                Icons.chevron_left_rounded,
                size: 22,
                color: ExplorePalette.chipInk,
              ),
            ),
          ),
          const SizedBox(width: 8),
        ],
        Expanded(
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 240),
            height: ExploreMotion.fieldHeight,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(ExploreMotion.fieldRadius),
              border: Border.all(
                color: _focused
                    ? ExplorePalette.brand500.withValues(alpha: 0.45)
                    : ExplorePalette.hairline,
              ),
              boxShadow: _focused
                  ? ExplorePalette.fieldFocused
                  : ExplorePalette.field,
            ),
            child: Row(
              children: [
                const Icon(
                  Icons.search_rounded,
                  size: 18,
                  color: ExplorePalette.metaInk,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Focus(
                    onFocusChange: (value) => setState(() => _focused = value),
                    child: TextField(
                      controller: widget.controller,
                      autofocus: widget.autofocus,
                      readOnly: widget.readOnly,
                      onTap: widget.onTapField,
                      textInputAction: TextInputAction.search,
                      onSubmitted: (_) => _submit(),
                      onChanged: (_) => setState(() {}),
                      cursorColor: ExplorePalette.brand600,
                      cursorWidth: 1.6,
                      style: const TextStyle(
                        fontSize: 13.5,
                        fontWeight: FontWeight.w600,
                        color: ExplorePalette.ink,
                        height: 1.2,
                      ),
                      decoration: const InputDecoration(
                        isDense: true,
                        border: InputBorder.none,
                        contentPadding: EdgeInsets.zero,
                        hintText: 'Search people, @handle',
                        hintStyle: TextStyle(
                          fontSize: 13.5,
                          fontWeight: FontWeight.w600,
                          color: ExplorePalette.placeholder,
                        ),
                      ),
                    ),
                  ),
                ),
                if (hasText && !widget.readOnly)
                  GestureDetector(
                    onTap: () {
                      widget.controller.clear();
                      setState(() {});
                    },
                    behavior: HitTestBehavior.opaque,
                    child: Container(
                      width: 22,
                      height: 22,
                      margin: const EdgeInsets.only(right: 6),
                      decoration: const BoxDecoration(
                        color: Color(0xFFEFECF8),
                        shape: BoxShape.circle,
                      ),
                      alignment: Alignment.center,
                      child: const Icon(
                        Icons.close_rounded,
                        size: 13,
                        color: Color(0xFF7C7890),
                      ),
                    ),
                  ),
                ExplorePressable(
                  onTap: _submit,
                  scale: 0.9,
                  child: Container(
                    width: 34,
                    height: 34,
                    decoration: BoxDecoration(
                      gradient: ExplorePalette.brand,
                      borderRadius: BorderRadius.circular(11),
                      boxShadow: ExplorePalette.primaryButton,
                    ),
                    alignment: Alignment.center,
                    child: AnimatedRotation(
                      turns: _spin ? 1 : 0,
                      duration: const Duration(milliseconds: 520),
                      curve: ExploreMotion.easeOut,
                      child: const Icon(
                        Icons.search_rounded,
                        size: 17,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
