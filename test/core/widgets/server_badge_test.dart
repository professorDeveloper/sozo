import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:soplay/core/widgets/server_badge.dart';

void main() {
  group('monogram', () {
    test('a numbered server keeps its number', () {
      // The number is the ONLY thing separating "Server 3" from its five
      // siblings; a badge reading "SE" for all of them is no badge at all.
      expect(ServerBadge.monogramFor('Server 1'), 'S1');
      expect(ServerBadge.monogramFor('Server 12'), 'S12');
      expect(ServerBadge.monogramFor('3'), '3');
    });

    test('a leading number is kept too', () {
      expect(ServerBadge.monogramFor('10Gbps'), '10');
      expect(ServerBadge.monogramFor('4K Server'), '4');
    });

    test('two words give their initials', () {
      expect(ServerBadge.monogramFor('FSL Server'), 'FS');
      expect(ServerBadge.monogramFor('Pixel Drain'), 'PD');
      expect(ServerBadge.monogramFor('vid-hide'), 'VH');
    });

    test('one word gives its first two letters', () {
      expect(ServerBadge.monogramFor('Doodstream'), 'DO');
      expect(ServerBadge.monogramFor('Mp4upload'), 'MP');
    });

    test('empty and whitespace do not throw', () {
      expect(ServerBadge.monogramFor(''), '?');
      expect(ServerBadge.monogramFor('   '), '?');
    });
  });

  group('colour', () {
    test('is stable for the same name', () {
      // Dart's String.hashCode is randomised per run, so the obvious
      // implementation gives somebody a different colour every launch —
      // which destroys the one property this badge exists to have.
      final a = ServerBadge.colorFor('Doodstream');
      final b = ServerBadge.colorFor('Doodstream');
      expect(a, b);
    });

    test('ignores case and punctuation', () {
      expect(ServerBadge.colorFor('FSL Server'), ServerBadge.colorFor('fsl-server'));
    });

    test('differs between different servers', () {
      final colors = ['Server 1', 'Server 2', 'Doodstream', 'Pixeldrain']
          .map(ServerBadge.colorFor)
          .toSet();
      // Every server rendering the same colour is the same as no colour.
      expect(colors.length, greaterThan(1));
    });
  });

  testWidgets('renders its monogram', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(body: Center(child: ServerBadge(name: 'FSL Server'))),
      ),
    );
    expect(find.text('FS'), findsOneWidget);
  });

  testWidgets('a selected badge draws a ring', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: Center(child: ServerBadge(name: 'Server 2', selected: true)),
        ),
      ),
    );
    final container = tester.widget<Container>(find.byType(Container));
    expect((container.decoration as BoxDecoration).border, isNotNull);
  });
}
