import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:soplay/core/tv/tv_keys.dart';

void main() {
  test('the remote search and voice keys start voice search', () {
    expect(TvKeys.isVoiceSearch(LogicalKeyboardKey.browserSearch), isTrue);
    expect(TvKeys.isVoiceSearch(LogicalKeyboardKey.launchAssistant), isTrue);
    expect(
      TvKeys.isVoiceSearch(
        const LogicalKeyboardKey(LogicalKeyboardKey.androidPlane | 231),
      ),
      isTrue,
    );
    expect(TvKeys.isVoiceSearch(LogicalKeyboardKey.select), isFalse);
    expect(TvKeys.isVoiceSearch(LogicalKeyboardKey.keyS), isFalse);
  });
}
