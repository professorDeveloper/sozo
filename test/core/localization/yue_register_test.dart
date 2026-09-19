import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Guards the things about `yue.json` that only a Cantonese reader would
/// notice, and that therefore nothing else in the suite can catch.
///
/// The structural checks in `test/core/localization_test.dart` pass on a file
/// that is word-for-word Mandarin, or Simplified, or that calls a server three
/// different names — every key is present and every placeholder survives. That
/// is how this file was first written: eight agents produced one slice each in
/// a single pass, and nobody who reads the language had seen it. The
/// groups below freeze what a Cantonese reader found wrong in that pass, and
/// in the editing passes since, so a later pass cannot quietly undo the fix.
void main() {
  final yue = _flatten(
    jsonDecode(File('assets/translations/yue.json').readAsStringSync())
        as Map<String, dynamic>,
  );

  test('the file being guarded is actually there', () {
    // Everything below is "find nothing", which an empty map also satisfies.
    expect(yue.length, greaterThan(1500));
  });

  group('reads as 廣東話 rather than 書面語', () {
    // Mandarin function words, each mapped to the Cantonese counterpart this
    // file already uses everywhere else. Machine translation reaches for the
    // Mandarin one, and a sentence carrying two or three of them reads to a
    // Hong Kong user as written Chinese with Cantonese words sprinkled on top.
    //
    // These are single characters, so this is a tripwire and not a proof. Each
    // of them also lives inside Traditional compounds a correct file could want
    // — 與 in 參與, 的 in 目的地, 是 in 是否 — so a hit does not by itself mean
    // the string is wrong. What a hit means is that yue.json contained none of
    // this character until now and an edit introduced one, which is worth a
    // human looking at: if it is a bare function word it is Mandarin leakage,
    // and if it is a genuine compound the exception belongs in this table the
    // way 和 (飽和度) and 里 (里程碑) are already left out of it.
    const mandarinOnly = {
      '的': '嘅', '是': '係', '沒': '冇', '看': '睇',
      '這': '呢', '那': '嗰', '很': '好', '們': '哋',
      '什': '咩', '怎': '點', '給': '畀', '找': '搵',
      '您': '你', '與': '同',
    };

    mandarinOnly.forEach((mandarin, cantonese) {
      test('no "$mandarin"', () {
        final hits = yue.entries.where((e) => e.value.contains(mandarin));
        expect(
          hits.map((e) => '${e.key}: ${e.value}'),
          isEmpty,
          reason: 'Nothing in yue.json used "$mandarin" before this edit. '
              'Read the hit: a bare function word is Mandarin leakage, and '
              '"$cantonese" is what this file writes instead. A real '
              'Traditional compound (參與, 目的地, 是否) is fine — drop '
              '"$mandarin" from this table and name the compound, the way 和 '
              'and 里 are already left out.',
        );
      });
    });
  });

  group('every character is Traditional', () {
    // Hong Kong reads Traditional. A Simplified character is not a style
    // choice the way a word is — it renders as the wrong script and marks the
    // whole app as machine-made. This is the subset a Mandarin model emits
    // most often; 后 and 里 are left out because they are also real
    // Traditional characters (皇后, 公里) and would fire on correct text.
    const simplified = [
      '处', '学', '国', '时', '会', '来', '开', '关', '应', '个', '门',
      '义', '对', '发', '无', '电', '视', '网', '击', '说', '读', '书',
      '华', '单', '双', '点', '样', '组', '级', '过', '还', '内', '图',
      '为', '长', '问', '间', '车', '马', '东', '买', '卖', '纸', '经',
    ];

    for (final ch in simplified) {
      test('no "$ch"', () {
        final hits = yue.entries.where((e) => e.value.contains(ch));
        expect(
          hits.map((e) => '${e.key}: ${e.value}'),
          isEmpty,
          reason: 'Simplified "$ch" — rewrite the hit in Traditional. If '
              'this character is also correct Traditional here, take it out '
              'of this list and say why, as 后 (皇后) and 里 (公里) are.',
        );
      });
    }
  });

  group('one word per concept', () {
    // Eight writers split the file, so the same English word came back in up
    // to three Cantonese renderings — "repo" was 儲存庫, 倉庫 and a bare
    // "repo" in the same settings screen. The left side is the agreed term;
    // the right side is a synonym that is not wrong in isolation, which is
    // exactly why it survives a proofread and only shows up when a user sees
    // both spellings two rows apart.
    const strays = {
      '服務器': '伺服器',
      '搜索': '搜尋',
      '設置': '設定',
      '記錄': '紀錄',
      '登錄': '登入',
      '倉庫': '儲存庫',
      '品質': '畫質',
      '質量': '畫質',
      '插件': '外掛',
      '鏈接': '連結',
      '卡通': '動畫',
      '圖書館': '書架',
    };

    strays.forEach((stray, agreed) {
      test('"$stray" is written "$agreed"', () {
        final hits = yue.entries.where((e) => e.value.contains(stray));
        expect(
          hits.map((e) => '${e.key}: ${e.value}'),
          isEmpty,
          reason: 'This file writes this concept "$agreed". Neither '
              'spelling is wrong on its own — 記錄 is ordinary Hong Kong '
              'Chinese — but a user must not meet both. Change the hit to '
              '"$agreed", or move the house term here if it has changed.',
        );
      });
    });
  });

  group('one shape per action', () {
    // Same-concept strings that a later pass pulled apart again. Each of these
    // is a phrasing the whole file agrees on, held by the one key most likely
    // to drift, so a re-edit of that screen alone cannot reopen the split.

    test('"Connections" names the whole screen, not a list of hyperlinks', () {
      // Two things have to be true at once here. 連結 is this file's word for
      // "hyperlink" (已複製連結, 你嘅連結), so a bare 連結 title reads "Links" —
      // and 連結帳戶, the first attempt at fixing that, named only half the
      // screen: profile_connections_page.dart:89 and :98 put linked ACCOUNTS
      // and paired DEVICES under this one title.
      for (final key in ['profile.connections', 'profile.section_connections']) {
        expect(
          yue[key],
          '帳戶同裝置',
          reason: '$key titles the screen where AniList, MyAnimeList and '
              'Discord are signed in. Bare 連結 reads as "Links" there. '
              'anilist.connections_title is the same English word.',
        );
      }
    });

    test('"remove from X" is written 喺X移除 everywhere', () {
      // home.remove_from_continue is deliberately absent: its ground is the
      // quoted section name 「繼續睇」, which ends in a verb, so it needs the
      // 度 that these do not.
      const removals = [
        'anilist.remove_entry', 'anilist.remove_confirm', 'anilist.removed',
        'mal.remove_entry', 'mal.remove_confirm', 'mal.removed',
        'detail.remove_from_my_list_action', 'detail.removed_from_my_list',
        'detail.tracking_remove', 'detail.tracking_removed',
        'app_lock.removed_from_private',
        'live_tv.favourite_remove', 'profile.remove_favorite',
      ];
      for (final key in removals) {
        expect(
          yue[key],
          matches(RegExp(r'^(已|要)?喺[^度]+移除')),
          reason: '$key is "remove from <somewhere>", which this file writes '
              '喺X移除 — not 移出X, and not 喺X度移除.',
        );
      }
    });

    test('連線 keeps the object it already carries', () {
      // 連線 is verb-object; appending 首播 stacks a second object onto it.
      for (final key in [
        'premiere.connecting', 'premiere.reconnecting',
        'watch_party.connecting', 'watch_party.reconnecting',
      ]) {
        expect(
          yue[key],
          matches(RegExp(r'連線緊…$')),
          reason: '$key must end at 連線緊… — 連線 already means "connect a '
              'line", so a noun after it (連線緊首播) is one object too many. '
              'The screen supplies what is being connected to.',
        );
      }
    });
  });
}

Map<String, String> _flatten(Map<String, dynamic> map, [String prefix = '']) {
  final out = <String, String>{};
  map.forEach((k, v) {
    final key = prefix.isEmpty ? k : '$prefix.$k';
    if (v is Map<String, dynamic>) {
      out.addAll(_flatten(v, key));
    } else {
      out[key] = v.toString();
    }
  });
  return out;
}
