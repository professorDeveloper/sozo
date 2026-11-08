import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:soplay/features/detail/presentation/widgets/detail_tab_panes.dart';

class _Counting extends StatefulWidget {
  const _Counting(this.tab, this.counts);
  final String tab;
  final Map<String, ({int inits, int builds})> counts;

  @override
  State<_Counting> createState() => _CountingState();
}

class _CountingState extends State<_Counting> {
  int taps = 0;

  @override
  void initState() {
    super.initState();
    final c = widget.counts[widget.tab] ?? (inits: 0, builds: 0);
    widget.counts[widget.tab] = (inits: c.inits + 1, builds: c.builds);
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.counts[widget.tab]!;
    widget.counts[widget.tab] = (inits: c.inits, builds: c.builds + 1);
    return GestureDetector(
      onTap: () => setState(() => taps++),
      child: SizedBox(height: 200, child: Text('${widget.tab}:$taps')),
    );
  }
}

class _Host extends StatefulWidget {
  const _Host(this.counts, this.hostBuilds);
  final Map<String, ({int inits, int builds})> counts;
  final List<int> hostBuilds;

  @override
  State<_Host> createState() => _HostState();
}

class _HostState extends State<_Host> with SingleTickerProviderStateMixin {
  static const tabs = ['A', 'B', 'C'];
  late final TabController controller = TabController(
    length: tabs.length,
    vsync: this,
  );

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    widget.hostBuilds[0]++;
    return MaterialApp(
      home: Scaffold(
        body: DetailTabPanes(
          controller: controller,
          tabs: tabs,
          paneBuilder: (_, tab) => _Counting(tab, widget.counts),
        ),
      ),
    );
  }
}

void main() {
  late Map<String, ({int inits, int builds})> counts;
  late List<int> hostBuilds;

  Future<TabController> pump(WidgetTester tester) async {
    counts = {};
    hostBuilds = [0];
    await tester.pumpWidget(_Host(counts, hostBuilds));
    return tester.state<_HostState>(find.byType(_Host)).controller;
  }

  testWidgets('only the open tab is built at first', (tester) async {
    await pump(tester);
    expect(counts.keys, ['A']);
    expect(find.text('A:0'), findsOneWidget);
  });

  testWidgets('a pane keeps its state when the tab is left and reopened', (
    tester,
  ) async {
    final controller = await pump(tester);
    await tester.tap(find.text('A:0'));
    await tester.pump();
    expect(find.text('A:1'), findsOneWidget);

    controller.animateTo(1);
    await tester.pumpAndSettle();
    expect(find.text('B:0'), findsOneWidget);
    expect(find.text('A:1'), findsNothing);

    controller.animateTo(0);
    await tester.pumpAndSettle();
    expect(find.text('A:1'), findsOneWidget);
    expect(counts['A']!.inits, 1);
    expect(counts['B']!.inits, 1);
  });

  testWidgets('a tab switch rebuilds neither the page nor idle panes', (
    tester,
  ) async {
    final controller = await pump(tester);
    controller.animateTo(1);
    await tester.pumpAndSettle();
    final aBuilds = counts['A']!.builds;

    controller.animateTo(2);
    await tester.pumpAndSettle();
    controller.animateTo(1);
    await tester.pumpAndSettle();

    expect(hostBuilds[0], 1);
    expect(counts['A']!.builds, aBuilds);
    expect(counts['B']!.inits, 1);
    expect(counts['C']!.inits, 1);
  });

  testWidgets('the outgoing pane cross-fades, then leaves the screen', (
    tester,
  ) async {
    final controller = await pump(tester);
    controller.animateTo(1);
    await tester.pump();
    await tester.pump(DetailTabPanes.fade ~/ 2);
    expect(find.text('A:0'), findsOneWidget);
    expect(find.text('B:0'), findsOneWidget);

    await tester.pumpAndSettle();
    expect(find.text('A:0'), findsNothing);
    expect(find.text('A:0', skipOffstage: false), findsOneWidget);
  });

  testWidgets('taps reach only the open pane', (tester) async {
    final controller = await pump(tester);
    controller.animateTo(1);
    await tester.pumpAndSettle();
    await tester.tap(find.text('B:0'));
    await tester.pump();
    expect(find.text('B:1'), findsOneWidget);
    expect(find.text('A:0', skipOffstage: false), findsOneWidget);
  });
}
