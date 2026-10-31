import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:soplay/core/localization/line_height.dart';

void main() {
  Future<double> heightIn(WidgetTester tester, Locale locale, double h) async {
    late double out;
    await tester.pumpWidget(
      Localizations(
        locale: locale,
        delegates: const [
          DefaultWidgetsLocalizations.delegate,
          DefaultMaterialLocalizations.delegate,
        ],
        child: Builder(
          builder: (context) {
            out = lineHeightFor(context, h);
            return const SizedBox();
          },
        ),
      ),
    );
    return out;
  }

  testWidgets('Vietnamese gets room for its stacked marks', (tester) async {
    expect(await heightIn(tester, const Locale('vi'), 1.08), 1.25);
  });

  testWidgets('a roomier design is left alone', (tester) async {
    expect(await heightIn(tester, const Locale('vi'), 1.4), 1.4);
  });

  testWidgets('other languages keep the design', (tester) async {
    expect(await heightIn(tester, const Locale('en'), 1.08), 1.08);
  });
}
