import 'dart:async';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:soplay/core/theme/app_colors.dart';
import 'package:soplay/features/comments/domain/entities/comment_author.dart';
import 'package:soplay/features/comments/presentation/widgets/comment_avatar.dart';
import 'package:soplay/features/watch_party/data/watch_party_service.dart';
import 'package:soplay/features/watch_party/domain/entities/party_chat_message.dart';

/// Live chat for a watch party: a scrolling message list fed by
/// `service.chat`, plus a composer wired to `service.sendChat`.
class PartyChatPanel extends StatefulWidget {
  const PartyChatPanel({super.key, required this.service, this.myUserId});

  final WatchPartyService service;
  final String? myUserId;

  @override
  State<PartyChatPanel> createState() => _PartyChatPanelState();
}

class _PartyChatPanelState extends State<PartyChatPanel> {
  static const int _maxMessages = 200;

  final List<PartyChatMessage> _messages = [];
  final TextEditingController _controller = TextEditingController();
  final FocusNode _focus = FocusNode();
  final ScrollController _scroll = ScrollController();
  StreamSubscription<PartyChatMessage>? _sub;

  @override
  void initState() {
    super.initState();
    _sub = widget.service.chat.listen(_onMessage);
  }

  @override
  void dispose() {
    _sub?.cancel();
    _controller.dispose();
    _focus.dispose();
    _scroll.dispose();
    super.dispose();
  }

  void _onMessage(PartyChatMessage msg) {
    if (!mounted) return;
    setState(() {
      _messages.add(msg);
      if (_messages.length > _maxMessages) {
        _messages.removeRange(0, _messages.length - _maxMessages);
      }
    });
    WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToEnd());
  }

  void _scrollToEnd() {
    if (!_scroll.hasClients) return;
    _scroll.animateTo(
      _scroll.position.maxScrollExtent,
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOut,
    );
  }

  void _send() {
    final text = _controller.text.trim();
    if (text.isEmpty) return;
    widget.service.sendChat(text);
    _controller.clear();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Expanded(
          child: _messages.isEmpty
              ? _EmptyChat()
              : ListView.builder(
                  controller: _scroll,
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  itemCount: _messages.length,
                  itemBuilder: (_, i) {
                    final m = _messages[i];
                    return _ChatRow(
                      message: m,
                      isMe: widget.myUserId != null &&
                          m.userId == widget.myUserId,
                    );
                  },
                ),
        ),
        _Composer(
          controller: _controller,
          focus: _focus,
          onSend: _send,
        ),
      ],
    );
  }
}

class _EmptyChat extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(
            Icons.forum_outlined,
            color: AppColors.textHint,
            size: 40,
          ),
          const SizedBox(height: 10),
          Text(
            'watch_party.chat_empty'.tr(),
            textAlign: TextAlign.center,
            style: const TextStyle(color: AppColors.textHint, fontSize: 12.5),
          ),
        ],
      ),
    );
  }
}

class _ChatRow extends StatelessWidget {
  const _ChatRow({required this.message, required this.isMe});

  final PartyChatMessage message;
  final bool isMe;

  @override
  Widget build(BuildContext context) {
    final author = CommentAuthor(
      id: message.userId,
      username: message.username ?? '',
      photoURL: message.photoURL,
    );
    final name = isMe
        ? 'watch_party.you'.tr()
        : (message.username ?? '').trim().isNotEmpty
            ? message.username!.trim()
            : '—';

    return Padding(
      padding: const EdgeInsetsDirectional.fromSTEB(4, 6, 12, 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CommentAvatar(author: author, size: 30),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: isMe ? AppColors.primaryLight : AppColors.textPrimary,
                    fontSize: 12.5,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  message.text,
                  style: const TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 13,
                    height: 1.35,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Composer extends StatelessWidget {
  const _Composer({
    required this.controller,
    required this.focus,
    required this.onSend,
  });

  final TextEditingController controller;
  final FocusNode focus;
  final VoidCallback onSend;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.background,
        border: Border(
          top: BorderSide(color: AppColors.divider, width: 0.6),
        ),
      ),
      padding: EdgeInsets.fromLTRB(
        12,
        8,
        12,
        MediaQuery.viewInsetsOf(context).bottom + 8,
      ),
      child: Container(
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: AppColors.border, width: 0.6),
        ),
        padding: const EdgeInsetsDirectional.fromSTEB(12, 4, 4, 4),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Expanded(
              child: TextField(
                controller: controller,
                focusNode: focus,
                maxLines: 4,
                minLines: 1,
                maxLength: 500,
                textInputAction: TextInputAction.send,
                onSubmitted: (_) => onSend(),
                style: const TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: 13,
                ),
                decoration: InputDecoration(
                  hintText: 'watch_party.chat_hint'.tr(),
                  hintStyle: const TextStyle(
                    color: AppColors.textHint,
                    fontSize: 13,
                  ),
                  border: InputBorder.none,
                  counterText: '',
                  isCollapsed: true,
                  contentPadding: const EdgeInsets.symmetric(vertical: 10),
                ),
              ),
            ),
            const SizedBox(width: 4),
            Material(
              color: AppColors.primary,
              shape: const CircleBorder(),
              child: InkWell(
                onTap: onSend,
                customBorder: const CircleBorder(),
                child: const SizedBox(
                  width: 36,
                  height: 36,
                  child: Icon(
                    Icons.send_rounded,
                    color: Colors.white,
                    size: 16,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
