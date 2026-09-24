import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:soplay/features/profiles/presentation/widgets/profile_avatar.dart';

void main() {
  test('every offered avatar is bundled', () {
    expect(ProfileAvatars.images, hasLength(24));
    for (final id in ProfileAvatars.images) {
      final path = ProfileAvatars.imageFor(id)!;
      expect(File(path).existsSync(), isTrue, reason: path);
    }
  });

  test('ids fit what the server accepts', () {
    final re = RegExp(r'^[a-z0-9][a-z0-9_-]{0,39}$');
    for (final id in ProfileAvatars.images) {
      expect(re.hasMatch(id), isTrue, reason: id);
    }
  });

  testWidgets('an illustrated avatar draws its image, an old one its icon', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Row(
          children: [
            ProfileAvatar(name: 'A', avatar: 'lorelei-1'),
            ProfileAvatar(name: 'B', avatar: 'star'),
          ],
        ),
      ),
    );
    expect(find.byType(Image), findsOneWidget);
    expect(find.byIcon(Icons.star_rounded), findsOneWidget);
  });
}
