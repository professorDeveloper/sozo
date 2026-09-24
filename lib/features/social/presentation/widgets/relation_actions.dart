import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';

import 'package:soplay/core/di/injection.dart';
import 'package:soplay/features/social/data/social_service.dart';
import 'package:soplay/features/social/domain/social_models.dart';
import 'package:soplay/features/social/presentation/widgets/social_widgets.dart';

typedef RelationChanged =
    void Function(SocialRelation relation, String? requestId);

/// The friendship button(s) for one person, for whatever state the pair is in.
class RelationActions extends StatefulWidget {
  const RelationActions({
    super.key,
    required this.user,
    required this.relation,
    required this.onChanged,
    this.requestId,
    this.acceptsRequests = true,
  });

  final SocialUser user;
  final SocialRelation relation;
  final String? requestId;
  final bool acceptsRequests;
  final RelationChanged onChanged;

  @override
  State<RelationActions> createState() => _RelationActionsState();
}

class _RelationActionsState extends State<RelationActions> {
  final SocialService _social = getIt<SocialService>();
  bool _busy = false;

  Future<void> _run(Future<void> Function() task) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await task();
    } catch (e) {
      if (mounted) showSocialSnack(context, socialErrorText(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _add() => _run(() async {
    final out = await _social.sendRequest(userId: widget.user.id);
    if (!mounted) return;
    widget.onChanged(out.relation, out.requestId);
    showSocialSnack(
      context,
      out.relation == SocialRelation.friends
          ? 'social.accepted_snack'.tr(args: [widget.user.name])
          : 'social.sent_snack'.tr(),
    );
  });

  Future<void> _accept() => _run(() async {
    final id = widget.requestId;
    // Without the id, sending a request to someone who already asked
    // accepts theirs.
    final out = id != null
        ? await _social.accept(id)
        : await _social.sendRequest(userId: widget.user.id);
    if (!mounted) return;
    widget.onChanged(SocialRelation.friends, null);
    if (out.relation == SocialRelation.friends) {
      showSocialSnack(
        context,
        'social.accepted_snack'.tr(args: [widget.user.name]),
      );
    }
  });

  Future<void> _decline() => _run(() async {
    final id = widget.requestId;
    if (id == null) return;
    await _social.deleteRequest(id);
    if (!mounted) return;
    widget.onChanged(SocialRelation.none, null);
    showSocialSnack(context, 'social.declined_snack'.tr());
  });

  Future<void> _cancel() async {
    final id = widget.requestId;
    if (id == null) return;
    final ok = await confirmSocial(
      context,
      title: 'social.cancel_request_title'.tr(),
      body: 'social.cancel_request_body'.tr(args: [widget.user.name]),
      confirm: 'social.action_cancel_request'.tr(),
      destructive: true,
    );
    if (!ok || !mounted) return;
    await _run(() async {
      await _social.deleteRequest(id);
      if (mounted) widget.onChanged(SocialRelation.none, null);
    });
  }

  Future<void> _remove() async {
    final ok = await confirmSocial(
      context,
      title: 'social.remove_title'.tr(args: [widget.user.name]),
      body: 'social.remove_body'.tr(),
      confirm: 'social.action_remove'.tr(),
      destructive: true,
    );
    if (!ok || !mounted) return;
    await _run(() async {
      await _social.removeFriend(widget.user.id);
      if (!mounted) return;
      widget.onChanged(SocialRelation.none, null);
      showSocialSnack(context, 'social.removed_snack'.tr());
    });
  }

  @override
  Widget build(BuildContext context) {
    return switch (widget.relation) {
      SocialRelation.self => const SizedBox.shrink(),
      SocialRelation.none => SocialPillButton(
        label: widget.acceptsRequests
            ? 'social.action_add'.tr()
            : 'social.action_closed'.tr(),
        icon: widget.acceptsRequests ? Icons.person_add_alt_1_rounded : null,
        filled: widget.acceptsRequests,
        busy: _busy,
        onPressed: widget.acceptsRequests ? _add : null,
      ),
      SocialRelation.outgoing => SocialPillButton(
        label: 'social.action_requested'.tr(),
        icon: Icons.schedule_rounded,
        busy: _busy,
        onPressed: widget.requestId == null ? null : _cancel,
      ),
      SocialRelation.incoming => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          SocialPillButton(
            label: 'social.action_accept'.tr(),
            filled: true,
            busy: _busy,
            onPressed: _accept,
          ),
          if (widget.requestId != null) ...[
            const SizedBox(width: 6),
            SocialPillButton(
              label: 'social.action_decline'.tr(),
              onPressed: _busy ? null : _decline,
            ),
          ],
        ],
      ),
      SocialRelation.friends => SocialPillButton(
        label: 'social.action_friends'.tr(),
        icon: Icons.check_rounded,
        busy: _busy,
        onPressed: _remove,
      ),
    };
  }
}
