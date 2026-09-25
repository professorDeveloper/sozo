// The Sources header used to collapse in one step once a threshold was
// crossed, resizing the list under the finger. These are the rules of the
// floating header that replaced it.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:soplay/core/widgets/quick_return_header.dart';

class _Host extends StatefulWidget {
  const _Host({required this.scroll, this.onRow, this.onBar, this.onHeader});
  final ScrollController scroll;
  final ValueChanged<int>? onRow;
  final VoidCallback? onBar;
  final VoidCallback? onHeader;
  @override
  State<_Host> createState() => _HostState();
}

class _HostState extends State<_Host> with TickerProviderStateMixin {
  late final header = QuickReturnController(vsync: this);

  @override
  void dispose() {
    header.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => MaterialApp(
    home: Scaffold(
      body: Column(
        children: [
          // Stands in for the pinned search field above the floating part.
          GestureDetector(
            onTap: widget.onBar,
            child: const SizedBox(height: 56, child: Text('BAR')),
          ),
          Expanded(
            child: QuickReturnLayout(
              controller: header,
              background: Colors.black,
              header: GestureDetector(
                onTap: widget.onHeader,
                child: const SizedBox(height: 100, child: Text('HEADER')),
              ),
              body: CustomScrollView(
                controller: widget.scroll,
                slivers: [
                  QuickReturnSpacer.sliver(header),
                  SliverList.builder(
                    itemCount: 100,
                    itemBuilder: (_, i) => GestureDetector(
                      onTap: () => widget.onRow?.call(i),
                      child: SizedBox(height: 60, child: Text('row $i')),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    ),
  );
}

void main() {
  late ScrollController scroll;
  // Relative to the top of the layout, which sits under a 56px bar.
  double headerTop(WidgetTester tester) =>
      tester.getTopLeft(find.text('HEADER')).dy - 56;

  setUp(() => scroll = ScrollController());
  tearDown(() => scroll.dispose());

  testWidgets('the list starts below the header, not under it', (tester) async {
    await tester.pumpWidget(_Host(scroll: scroll));
    await tester.pumpAndSettle();
    expect(tester.getTopLeft(find.text('row 0')).dy - 56, 100);
    expect(headerTop(tester), 0);
  });

  testWidgets('it follows the finger one to one, and comes straight back', (
    tester,
  ) async {
    await tester.pumpWidget(_Host(scroll: scroll));
    await tester.pumpAndSettle();

    final gesture = await tester.startGesture(const Offset(200, 400));
    await gesture.moveBy(const Offset(0, -20)); // past the touch slop
    await gesture.moveBy(const Offset(0, -40));
    await tester.pump();
    final hiddenBy = -headerTop(tester);
    expect(
      hiddenBy,
      closeTo(scroll.offset, 0.01),
      reason: 'header and rows move together, at the same speed',
    );

    await gesture.moveBy(const Offset(0, -300));
    await tester.pump();
    expect(headerTop(tester), -100, reason: 'fully out, no further');

    // Pulling back reveals it at once, while the list is still far down.
    await gesture.moveBy(const Offset(0, 30));
    await tester.pump();
    expect(headerTop(tester), closeTo(-70, 0.01));
    expect(scroll.offset, greaterThan(200));
    await gesture.up();
  });

  testWidgets('on release it settles fully in or fully out', (tester) async {
    await tester.pumpWidget(_Host(scroll: scroll));
    await tester.pumpAndSettle();

    // Down a long way, then back up a little: a third showing.
    final gesture = await tester.startGesture(const Offset(200, 400));
    await gesture.moveBy(const Offset(0, -20));
    await gesture.moveBy(const Offset(0, -380));
    await gesture.moveBy(const Offset(0, 30));
    await gesture.up();
    await tester.pumpAndSettle();
    expect(headerTop(tester), -100);

    final back = await tester.startGesture(const Offset(200, 400));
    await back.moveBy(const Offset(0, 20));
    await back.moveBy(const Offset(0, 50));
    await back.up();
    await tester.pumpAndSettle();
    expect(headerTop(tester), 0);
  });

  testWidgets('a jump the app makes itself leaves the header alone', (
    tester,
  ) async {
    await tester.pumpWidget(_Host(scroll: scroll));
    await tester.pumpAndSettle();
    scroll.jumpTo(1200);
    await tester.pumpAndSettle();
    expect(headerTop(tester), 0);
  });

  testWidgets('never a gap at the top of a barely scrolled list', (
    tester,
  ) async {
    await tester.pumpWidget(_Host(scroll: scroll));
    await tester.pumpAndSettle();
    final gesture = await tester.startGesture(const Offset(200, 400));
    await gesture.moveBy(const Offset(0, -20));
    await gesture.moveBy(const Offset(0, -60));
    await gesture.up();
    await tester.pumpAndSettle();
    // Scrolled less than the header is tall: it returns rather than leave
    // the empty spacer showing.
    expect(-headerTop(tester), lessThanOrEqualTo(scroll.offset + 0.01));
  });

  testWidgets('a header scrolled away is not drawn over what sits above it', (
    tester,
  ) async {
    var bar = 0;
    var header = 0;
    await tester.pumpWidget(
      _Host(scroll: scroll, onBar: () => bar++, onHeader: () => header++),
    );
    await tester.pumpAndSettle();
    final gesture = await tester.startGesture(const Offset(200, 400));
    await gesture.moveBy(const Offset(0, -20));
    await gesture.moveBy(const Offset(0, -300));
    await gesture.up();
    await tester.pumpAndSettle();
    expect(headerTop(tester), -100);

    // It is clipped to its own box, so nothing of it covers the bar...
    final clip = find.ancestor(
      of: find.text('HEADER'),
      matching: find.byType(ClipRect),
    );
    expect(clip, findsWidgets);
    expect(tester.getTopLeft(clip.first).dy, 56);
    // ...and a tap on the bar is the bar's.
    await tester.tap(find.text('BAR'));
    expect(bar, 1);
    expect(header, 0);
  });

  testWidgets('a tap on the header never reaches the row beneath it', (
    tester,
  ) async {
    final rows = <int>[];
    var header = 0;
    await tester.pumpWidget(
      _Host(scroll: scroll, onRow: rows.add, onHeader: () => header++),
    );
    await tester.pumpAndSettle();
    // Scroll far, then pull back so the header returns over the rows.
    final gesture = await tester.startGesture(const Offset(200, 400));
    await gesture.moveBy(const Offset(0, -20));
    await gesture.moveBy(const Offset(0, -500));
    await gesture.moveBy(const Offset(0, 150));
    await gesture.up();
    await tester.pumpAndSettle();
    expect(headerTop(tester), 0);
    expect(scroll.offset, greaterThan(200), reason: 'rows are under it');

    // Anywhere on the header, including space its child does not fill.
    await tester.tapAt(const Offset(10, 56 + 50));
    await tester.tapAt(const Offset(390, 56 + 90));
    expect(rows, isEmpty);
    expect(header, 2);
  });
}
