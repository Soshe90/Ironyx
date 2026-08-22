import 'package:flutter/material.dart';

import 'responsive.dart';

/// Centres page content, caps its width, and applies the responsive gutter.
///
/// Before this existed every screen repeated its own
/// `Center` → `ConstrainedBox` → `Padding` stack, and they disagreed: some
/// capped the width, some did not, and the horizontal padding was written
/// as a literal in each one. Wrapping the scroll view (rather than each
/// child) keeps the scrollbar at the true screen edge on desktop.
class PageBody extends StatelessWidget {
  const PageBody({required this.child, this.gutter = true, super.key});

  final Widget child;

  /// Set false when the child is a scroll view that applies its own
  /// horizontal padding per sliver — the cap and centring still apply.
  final bool gutter;

  @override
  Widget build(BuildContext context) {
    return Center(
      // Shrink-wrap vertically. A plain Center expands to the tallest
      // constraint it is given, which is harmless around a scroll view but
      // makes a short child — a bottom action bar, say — claim the whole
      // screen and swallow every tap above it.
      heightFactor: 1,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: context.contentMaxWidth),
        child: gutter
            ? Padding(
                padding: EdgeInsets.symmetric(horizontal: context.pageGutter),
                child: child,
              )
            : child,
      ),
    );
  }
}

/// Sliver-list equivalent of [PageBody]'s gutter, for `CustomScrollView`
/// screens that need padding per section rather than around the whole view.
extension SliverGutter on BuildContext {
  EdgeInsets get sliverGutter => EdgeInsets.symmetric(horizontal: pageGutter);
}
