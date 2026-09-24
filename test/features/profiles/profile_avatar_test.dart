import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:soplay/features/profiles/presentation/widgets/profile_avatar.dart';

void main() {
  test('every avatar, offered or retired, is bundled', () {
    expect(ProfileAvatars.images, hasLength(20));
    for (final id in ProfileAvatars.imageColors.keys) {
      final path = ProfileAvatars.imageFor(id)!;
      expect(File(path).existsSync(), isTrue, reason: path);
    }
  });

  test('ids fit what the server accepts', () {
    final re = RegExp(r'^[a-z0-9][a-z0-9_-]{0,39}$');
    for (final id in ProfileAvatars.imageColors.keys) {
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

  test('a retired avatar still draws but is not offered', () {
    expect(ProfileAvatars.images, isNot(contains('thumbs-3')));
    expect(ProfileAvatars.imageFor('thumbs-3'), 'assets/avatars/thumbs-3.png');
  });
}
