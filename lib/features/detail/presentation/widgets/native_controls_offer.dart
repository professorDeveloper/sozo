import 'dart:async';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/cupertino.dart';
import 'package:soplay/core/native/player_controls_style.dart';
import 'package:soplay/core/storage/hive_service.dart';

/// "Try the new player?", asked once over the player.
class NativeControlsOfferDialog extends StatelessWidget {
  const NativeControlsOfferDialog({super.key});

  @override
  Widget build(BuildContext context) {
    return CupertinoTheme(
      data: const CupertinoThemeData(brightness: Brightness.dark),
      child: CupertinoAlertDialog(
        title: Text('player.native_offer_title'.tr()),
        content: Text('player.native_offer_body'.tr()),
        actions: [
          CupertinoDialogAction(
            key: const ValueKey('native-offer-not-now'),
            onPressed: () => Navigator.of(context).pop(false),
            child: Text('player.native_offer_not_now'.tr()),
          ),
          CupertinoDialogAction(
            key: const ValueKey('native-offer-try'),
            isDefaultAction: true,
            onPressed: () => Navigator.of(context).pop(true),
            child: Text('player.native_offer_try'.tr()),
          ),
        ],
      ),
    );
  }
}

/// Marks the offer shown before it appears, so a crash never asks twice,
/// then stores the answer and returns it. Anything but "Try it" is "Not now".
Future<PlayerControlsStyle> presentNativeControlsOffer(
  BuildContext context,
  HiveService hive,
) async {
  unawaited(hive.markNativeControlsOffered());
  final accepted = await showCupertinoDialog<bool>(
    context: context,
    barrierDismissible: true,
    builder: (_) => const NativeControlsOfferDialog(),
  );
  final style = nativeOfferOutcome(accepted);
  unawaited(hive.setPlayerControlsStyle(style));
  return style;
}
