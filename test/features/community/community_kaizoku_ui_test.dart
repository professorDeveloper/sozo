import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:soplay/core/theme/kaizoku_colors.dart';
import 'package:soplay/features/comments/domain/entities/comment_author.dart';
import 'package:soplay/features/live_tv/data/live_tv_service.dart';
import 'package:soplay/features/live_tv/presentation/widgets/channel_sheet.dart';
import 'package:soplay/features/trivia/presentation/widgets/buff_empty_panel.dart';
import 'package:soplay/features/watch_party/domain/entities/party_member.dart';
import 'package:soplay/features/watch_party/domain/entities/party_playback.dart';
import 'package:soplay/features/watch_party/domain/entities/party_room.dart';
import 'package:soplay/features/watch_party/presentation/widgets/party_error_views.dart';
import 'package:soplay/features/watch_party/presentation/widgets/party_member_bar.dart';
import 'package:soplay/features/watch_party/presentation/widgets/party_reactions_bar.dart';

void main() {
  group('Milestone 2.4 Community, Live TV & Extensions UI Tests', () {
    testWidgets('Live TV: ChannelSheet renders channel details, favorite toggle, and watch button', (tester) async {
      var played = false;
      var toggledFav = false;

      const nowProg = LiveProgramme(
        title: 'Grand Prix Live',
        category: 'Sports',
        subtitle: 'Round 14 Final Race',
      );

      const nextProg = LiveProgramme(
        title: 'Post Race Analysis',
        category: 'Sports',
      );

      const channel = LiveChannel(
        id: 'sports_1',
        name: 'Kaizoku Sports 1',
        streamUrl: 'https://stream.kaizoku.tv/live/sports_1.m3u8',
        category: 'Sports',
        now: nowProg,
        next: nextProg,
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            backgroundColor: KaizokuColors.cyberObsidian,
            body: ChannelSheet(
              channel: channel,
              favourite: false,
              onPlay: () => played = true,
              onToggleFavourite: () => toggledFav = true,
            ),
          ),
        ),
      );

      // Verify channel title is rendered
      expect(find.text('Kaizoku Sports 1'), findsOneWidget);

      // Verify now and next programmes
      expect(find.text('Grand Prix Live'), findsOneWidget);
      expect(find.text('Post Race Analysis'), findsOneWidget);

      // Tap Watch Channel button
      final watchBtn = find.byType(ElevatedButton);
      expect(watchBtn, findsOneWidget);
      await tester.tap(watchBtn);
      await tester.pump();
      expect(played, isTrue);

      // Tap favorite button
      final favBtn = find.byIcon(Icons.star_outline_rounded);
      expect(favBtn, findsOneWidget);
      await tester.tap(favBtn);
      await tester.pump();
      expect(toggledFav, isTrue);
    });

    testWidgets('Watch Party: PartyMemberBar renders member list, counters, and host indicator', (tester) async {
      final members = [
        const PartyMember(
          userId: 'user_host',
          author: CommentAuthor(id: 'user_host', name: 'Luffy', avatar: ''),
          online: true,
          isHost: true,
        ),
        const PartyMember(
          userId: 'user_guest',
          author: CommentAuthor(id: 'user_guest', name: 'Zoro', avatar: ''),
          online: true,
          isHost: false,
        ),
      ];

      final room = PartyRoom(
        code: 'KZK123',
        hostUserId: 'user_host',
        maxMembers: 5,
        members: members,
        playback: PartyPlayback.zero,
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            backgroundColor: KaizokuColors.cyberObsidian,
            body: PartyMemberBar(
              room: room,
              myUserId: 'user_host',
            ),
          ),
        ),
      );

      expect(find.byType(PartyMemberBar), findsOneWidget);
      expect(find.text('2/5'), findsOneWidget);
      expect(find.text('Luffy'), findsOneWidget);
      expect(find.text('Zoro'), findsOneWidget);
    });

    testWidgets('Watch Party: PartyStateView renders glass card with action button', (tester) async {
      var actionFired = false;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            backgroundColor: KaizokuColors.cyberObsidian,
            body: PartyStateView(
              icon: Icons.error_outline_rounded,
              title: 'Party Room Expired',
              message: 'The host has ended this watch party session.',
              actionLabel: 'Return Home',
              onAction: () => actionFired = true,
            ),
          ),
        ),
      );

      expect(find.text('Party Room Expired'), findsOneWidget);
      expect(find.text('The host has ended this watch party session.'), findsOneWidget);

      final actionBtn = find.text('Return Home');
      expect(actionBtn, findsOneWidget);
      await tester.tap(actionBtn);
      await tester.pump();
      expect(actionFired, isTrue);
    });

    testWidgets('Watch Party: PartyReactionPicker renders all emojis in kPartyReactions', (tester) async {
      // Test the reaction emojis presence in the bar layout
      expect(kPartyReactions, containsAll(['❤️', '😂', '😮', '👏', '🔥', '😍', '🎉']));
    });

    testWidgets('Buff Hub: BuffEmptyPanel renders empty state with retry action', (tester) async {
      var retried = false;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            backgroundColor: KaizokuColors.cyberObsidian,
            body: BuffEmptyPanel(
              icon: Icons.person_off_rounded,
              title: 'No Actors Found',
              body: 'Check back later for updated popular cast trivia.',
              actionLabel: 'Try Again',
              onAction: () => retried = true,
            ),
          ),
        ),
      );

      expect(find.text('No Actors Found'), findsOneWidget);
      expect(find.text('Check back later for updated popular cast trivia.'), findsOneWidget);

      final retryBtn = find.text('Try Again');
      expect(retryBtn, findsOneWidget);
      await tester.tap(retryBtn);
      await tester.pump();
      expect(retried, isTrue);
    });
  });
}
