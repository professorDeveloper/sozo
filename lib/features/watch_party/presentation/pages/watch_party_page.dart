import 'dart:async';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:share_plus/share_plus.dart';
import 'package:soplay/core/di/injection.dart';
import 'package:soplay/core/error/result.dart';
import 'package:soplay/core/theme/app_colors.dart';
import 'package:soplay/features/detail/domain/entities/player_args.dart';
import 'package:soplay/features/detail/domain/usecases/resolve_media_usecase.dart';
import 'package:soplay/features/watch_party/data/watch_party_service.dart';
import 'package:soplay/features/watch_party/domain/entities/party_content.dart';
import 'package:soplay/features/watch_party/domain/entities/party_room.dart';
import 'package:soplay/features/watch_party/domain/entities/party_state.dart';
import 'package:soplay/features/watch_party/domain/party_resolve_gate.dart';
import 'package:soplay/features/watch_party/presentation/widgets/party_chat_panel.dart';
import 'package:soplay/features/watch_party/presentation/widgets/party_code_sheet.dart';
import 'package:soplay/features/watch_party/presentation/widgets/party_error_views.dart';
import 'package:soplay/features/watch_party/presentation/widgets/party_member_bar.dart';
import 'package:soplay/features/watch_party/presentation/widgets/party_plugin_required_view.dart';
import 'package:soplay/features/watch_party/presentation/widgets/party_reactions_bar.dart';

/// The watch-party lobby (`/watch-party`).
///
/// Joins the room (if a code was supplied via `state.extra` or `?code=`), then
/// renders members, chat and reactions while the host picks a title.
///
/// When playback starts, this page resolves the stream **on this device** from
/// the party's identity payload (`provider` + `mediaRef`) — a peer's URL is
/// never reused, because local sources bind their stream to the requesting
/// device's IP/session. Subsequent host episode switches are handled inside the
/// player by `player_page.party.dart`.
class WatchPartyPage extends StatefulWidget {
  const WatchPartyPage({super.key, this.code});

  final String? code;

  @override
  State<WatchPartyPage> createState() => _WatchPartyPageState();
}

class _WatchPartyPageState extends State<WatchPartyPage> {
  final WatchPartyService _service = getIt<WatchPartyService>();

  StreamSubscription<String>? _errorSub;
  Timer? _watchdog;
  bool _joining = false;
  bool _opening = false;
  bool _slow = false;
  String? _joinErrorCode;
  PartyResolveCapability? _blocked;
  String? _blockedProvider;

  @override
  void initState() {
    super.initState();
    _errorSub = _service.errors.listen(_toast);
    _service.state.addListener(_onServiceState);
    WidgetsBinding.instance.addPostFrameCallback((_) => _bootstrap());
  }

  @override
  void dispose() {
    _service.state.removeListener(_onServiceState);
    _watchdog?.cancel();
    unawaited(_errorSub?.cancel());
    super.dispose();
  }

  /// Arms a one-shot watchdog: if the join handshake hasn't put us in the room
  /// after a grace period (e.g. the socket connected but `party:state` never
  /// arrived, or it is silently retrying), flip to a retry view instead of an
  /// endless spinner.
  void _armWatchdog() {
    _watchdog?.cancel();
    _slow = false;
    _watchdog = Timer(const Duration(seconds: 12), () {
      if (!mounted) return;
      if (!_service.state.value.inParty) setState(() => _slow = true);
    });
  }

  Future<void> _retryConnect() async {
    setState(() {
      _slow = false;
      _joinErrorCode = null;
    });
    _armWatchdog();
    await _service.retryConnection();
  }

  /// Clears a latched plugin-required block once the party's content identity
  /// moves off the provider that could not be resolved (e.g. the host switches
  /// to a server-resolvable source), so the guest is not stranded on the
  /// install view.
  void _onServiceState() {
    if (!mounted) return;
    final s = _service.state.value;
    // Once we're actually in the room (or it terminated), stop the watchdog and
    // clear the "slow" flag.
    if (s.inParty || s.phase == PartyPhase.closed) {
      _watchdog?.cancel();
      if (_slow) setState(() => _slow = false);
    }
    final blockedProvider = _blockedProvider;
    if (blockedProvider == null) return;
    final currentProvider = s.room?.content?.provider;
    if (currentProvider != blockedProvider) {
      setState(() {
        _blocked = null;
        _blockedProvider = null;
      });
    }
  }

  Future<void> _bootstrap() async {
    final code = widget.code?.trim().toUpperCase();
    if (code == null || code.isEmpty) return;

    final current = _service.state.value;
    if (current.inParty && current.code == code) return;

    setState(() {
      _joining = true;
      _joinErrorCode = null;
    });
    _armWatchdog();
    try {
      await _service.joinParty(code);
    } catch (_) {
      if (mounted) setState(() => _joinErrorCode = 'not_found');
    } finally {
      if (mounted) setState(() => _joining = false);
    }
  }

  void _toast(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.black87,
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 2),
      ),
    );
  }

  Future<void> _copyCode(String code) async {
    await Clipboard.setData(ClipboardData(text: code));
    if (!mounted) return;
    _toast('watch_party.copied'.tr());
  }

  Future<void> _leave() async {
    await _service.leaveParty();
    if (!mounted) return;
    context.pop();
  }

  Future<void> _closeParty() async {
    // closeParty already tears down the local session in its finally (socket
    // disconnect + state reset). If the DELETE throws, still pop — otherwise the
    // host is stranded on a perpetual "Connecting…" view.
    try {
      await _service.closeParty();
    } catch (_) {}
    if (!mounted) return;
    context.pop();
  }

  /// Resolve the party's content on THIS device, then open the player.
  Future<void> _openPlayer(PartyContent content) async {
    if (_opening) return;
    final ref = content.mediaRef;
    final provider = content.provider;
    if (ref == null || ref.isEmpty || provider == null || provider.isEmpty) {
      return;
    }

    setState(() {
      _opening = true;
      // Clear any stale block so a retry (e.g. after installing the plugin)
      // re-evaluates the capability from scratch.
      _blocked = null;
      _blockedProvider = null;
    });
    try {
      final cap = await PartyResolveGate.canResolve(provider);
      if (!mounted) return;
      if (!cap.ok) {
        setState(() {
          _blocked = cap;
          _blockedProvider = provider;
        });
        return;
      }

      final result = await getIt<ResolveMediaUseCase>()(
        ref: ref,
        provider: provider,
        lang: content.lang,
      );
      if (!mounted) return;

      switch (result) {
        case Success(:final value):
          final sources = value.videoSources;
          final url = sources.isNotEmpty ? sources.first.videoUrl : value.videoUrl;
          if (!mounted) return;
          context.push(
            '/player',
            extra: PlayerArgs(
              title: content.title ?? 'watch_party.title'.tr(),
              provider: provider,
              headers: value.headers,
              contentUrl: content.contentUrl,
              thumbnail: content.thumbnail,
              movieUrl: url,
              type: value.type,
              videoSources: sources,
              thumbnails: value.thumbnails,
              mediaRef: ref,
              lang: content.lang ?? value.activeLang,
              partyCode: _service.state.value.code,
              showDownloadAction: false,
            ),
          );
        case Failure():
          _toast('watch_party.resolve_failed'.tr());
      }
    } finally {
      if (mounted) setState(() => _opening = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<PartyState>(
      valueListenable: _service.state,
      builder: (context, s, _) {
        final blocked = _blocked;
        final room = s.room;

        return PopScope(
          canPop: true,
          onPopInvokedWithResult: (didPop, _) {
            // Backing out of the lobby leaves the party (disconnects the socket);
            // an empty room is then auto-closed by the server's grace timer.
            if (didPop && _service.state.value.inParty) {
              _service.leaveParty();
            }
          },
          child: Scaffold(
          // The chat composer lifts itself over the keyboard via its own
          // viewInsets padding. Letting the Scaffold ALSO resize double-counts
          // the inset and shoves the composer (and the send button) off screen,
          // so typing/sending becomes impossible — disable the auto-resize.
          resizeToAvoidBottomInset: false,
          backgroundColor: AppColors.background,
          appBar: AppBar(
            backgroundColor: AppColors.background,
            elevation: 0,
            title: Text(
              'watch_party.title'.tr(),
              style: const TextStyle(fontWeight: FontWeight.w800),
            ),
            actions: [
              if (room != null)
                IconButton(
                  tooltip: 'watch_party.share_invite'.tr(),
                  icon: const Icon(Icons.ios_share_rounded),
                  onPressed: () => Share.share(partyInviteLink(room.code)),
                ),
            ],
          ),
          body: SafeArea(
            top: false,
            child: _buildBody(s, room, blocked),
          ),
          ),
        );
      },
    );
  }

  Widget _buildBody(PartyState s, PartyRoom? room, PartyResolveCapability? blocked) {
    if (blocked != null) {
      return PartyPluginRequiredView(
        provider: s.room?.content?.provider,
        installTarget: blocked.installTarget,
        onBack: () {
          setState(() {
            _blocked = null;
            _blockedProvider = null;
          });
        },
      );
    }

    if (s.phase == PartyPhase.closed) {
      return PartyClosedView(reason: s.closedReason);
    }

    if (!s.inParty || room == null) {
      final code = s.errorCode ?? _joinErrorCode;
      if (code != null && !_joining) {
        return PartyErrorView(
          code: code,
          actionLabel: 'general.try_again'.tr(),
          onAction: _retryConnect,
        );
      }
      // A failed connection, or a join that never lands, must NOT sit forever
      // on a bare spinner — surface it with a retry so the room isn't a dead
      // black screen.
      if (s.connection == PartyConnection.error || _slow) {
        final detail = s.errorMessage;
        return PartyStateView(
          icon: Icons.wifi_off_rounded,
          title: 'watch_party.connect_failed_title'.tr(),
          message: (detail != null && detail.trim().isNotEmpty)
              ? '${'watch_party.connect_failed_msg'.tr()}\n\n$detail'
              : 'watch_party.connect_failed_msg'.tr(),
          actionLabel: 'general.try_again'.tr(),
          onAction: _retryConnect,
          secondaryLabel: 'watch_party.leave_party'.tr(),
          onSecondary: _leave,
        );
      }
      return _ConnectingView(connection: s.connection);
    }

    final content = room.content;
    final playable = content != null && content.playable;

    // Two flex regions so the layout never overflows when the keyboard opens:
    // a scrollable top (room info + actions + reaction picker) that can shrink,
    // and the chat below with the composer lifting over the keyboard.
    return Column(
      children: [
        Expanded(
          flex: 5,
          child: SingleChildScrollView(
            padding: const EdgeInsets.only(bottom: 8),
            child: Column(
              children: [
                _CodeBar(code: room.code, onCopy: _copyCode),
                _ContentCard(content: content),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: PartyMemberBar(room: room, myUserId: s.myUserId),
                ),
                const SizedBox(height: 8),
                _BottomActions(
                  isHost: s.isHost,
                  playable: playable,
                  busy: _opening,
                  onStart: playable ? () => _openPlayer(content) : null,
                  onLeave: _leave,
                  onClose: _closeParty,
                ),
              ],
            ),
          ),
        ),
        Divider(height: 1, color: AppColors.border),
        // Fixed reaction bar directly above the chat — always reachable instead
        // of buried at the bottom of the scrollable top region.
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Center(child: PartyReactionPicker(service: _service)),
        ),
        Divider(height: 1, color: AppColors.border),
        Expanded(
          flex: 6,
          child: Stack(
            children: [
              PartyChatPanel(service: _service, myUserId: s.myUserId),
              // Floats reactions up across the whole chat area (ignores
              // pointers, so chat stays fully tappable).
              Positioned.fill(
                child: PartyReactionsOverlay(service: _service),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _ConnectingView extends StatelessWidget {
  const _ConnectingView({required this.connection});

  final PartyConnection connection;

  @override
  Widget build(BuildContext context) {
    final label = connection == PartyConnection.reconnecting
        ? 'watch_party.reconnecting'.tr()
        : 'watch_party.connecting'.tr();
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: 34,
            height: 34,
            child: CircularProgressIndicator(
              strokeWidth: 2.6,
              color: AppColors.primary,
            ),
          ),
          const SizedBox(height: 16),
          Text(
            label,
            style: const TextStyle(
              color: AppColors.textSecondary,
              fontSize: 13.5,
            ),
          ),
        ],
      ),
    );
  }
}

class _CodeBar extends StatelessWidget {
  const _CodeBar({required this.code, required this.onCopy});

  final String code;
  final Future<void> Function(String) onCopy;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: () => onCopy(code),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            color: AppColors.card,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
          ),
          child: Row(
            children: [
              Text(
                'watch_party.code_label'.tr(),
                style: const TextStyle(
                  color: AppColors.textSecondary,
                  fontSize: 12.5,
                ),
              ),
              const Spacer(),
              Text(
                code,
                style: const TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: 18,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 3,
                ),
              ),
              const SizedBox(width: 10),
              const Icon(Icons.copy_rounded, size: 18, color: AppColors.textHint),
            ],
          ),
        ),
      ),
    );
  }
}

class _ContentCard extends StatelessWidget {
  const _ContentCard({this.content});

  final PartyContent? content;

  @override
  Widget build(BuildContext context) {
    final c = content;
    if (c == null || c.isEmpty) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
        child: Text(
          'watch_party.content_none'.tr(),
          style: const TextStyle(color: AppColors.textHint, fontSize: 13),
        ),
      );
    }

    final thumb = c.thumbnail;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
      child: Row(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: SizedBox(
              width: 54,
              height: 78,
              child: thumb == null
                  ? Container(color: AppColors.surfaceVariant)
                  : CachedNetworkImage(
                      imageUrl: thumb,
                      fit: BoxFit.cover,
                      placeholder: (_, _) =>
                          Container(color: AppColors.surfaceVariant),
                      errorWidget: (_, _, _) =>
                          Container(color: AppColors.surfaceVariant),
                    ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  c.title ?? '',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                if (c.episode != null) ...[
                  const SizedBox(height: 4),
                  Text(
                    'E${c.episode}',
                    style: const TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: 12.5,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _BottomActions extends StatelessWidget {
  const _BottomActions({
    required this.isHost,
    required this.playable,
    required this.busy,
    required this.onLeave,
    required this.onClose,
    this.onStart,
  });

  final bool isHost;
  final bool playable;
  final bool busy;
  final VoidCallback? onStart;
  final Future<void> Function() onLeave;
  final Future<void> Function() onClose;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (playable)
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: busy ? null : onStart,
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
                icon: busy
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Icon(Icons.play_arrow_rounded),
                label: Text(
                  busy
                      ? 'watch_party.resolving'.tr()
                      : 'watch_party.start_watching'.tr(),
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
              ),
            )
          else
            Text(
              'watch_party.lobby_waiting_host'.tr(),
              textAlign: TextAlign.center,
              style: const TextStyle(color: AppColors.textHint, fontSize: 13),
            ),
          const SizedBox(height: 8),
          TextButton(
            onPressed: () => isHost ? onClose() : onLeave(),
            child: Text(
              isHost
                  ? 'watch_party.close_party'.tr()
                  : 'watch_party.leave_party'.tr(),
              style: const TextStyle(color: AppColors.error),
            ),
          ),
        ],
      ),
    );
  }
}
