import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:soplay/core/di/injection.dart';
import 'package:soplay/core/theme/app_colors.dart';
import 'package:soplay/features/support/data/support_models.dart';
import 'package:soplay/features/support/data/support_repository.dart';
import 'package:soplay/features/support/presentation/support_style.dart';

/// One conversation with support. Opening it marks the answer read.
class SupportTicketPage extends StatefulWidget {
  const SupportTicketPage({super.key, required this.id});

  final String id;

  @override
  State<SupportTicketPage> createState() => _SupportTicketPageState();
}

class _SupportTicketPageState extends State<SupportTicketPage> {
  final SupportRepository _repo = getIt<SupportRepository>();
  final TextEditingController _reply = TextEditingController();
  final ScrollController _scroll = ScrollController();

  SupportTicket? _ticket;
  String? _error;
  bool _sending = false;

  @override
  void initState() {
    super.initState();
    _reply.addListener(() => setState(() {}));
    _load();
  }

  @override
  void dispose() {
    _reply.dispose();
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final t = await _repo.get(widget.id);
      if (!mounted) return;
      setState(() {
        _ticket = t;
        _error = null;
      });
      _toBottom();
    } on SupportException catch (e) {
      if (mounted) setState(() => _error = e.message);
    }
  }

  void _toBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) {
        _scroll.jumpTo(_scroll.position.maxScrollExtent);
      }
    });
  }

  Future<void> _send() async {
    final text = _reply.text.trim();
    if (text.length < 3 || _sending) return;
    setState(() => _sending = true);
    try {
      final t = await _repo.reply(widget.id, text);
      if (!mounted) return;
      _reply.clear();
      setState(() {
        _ticket = t;
        _sending = false;
      });
      _toBottom();
    } on SupportException catch (e) {
      if (!mounted) return;
      setState(() => _sending = false);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(e.message)));
    }
  }

  Future<void> _close() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: Text('support.close_confirm_title'.tr()),
        content: Text('support.close_confirm_body'.tr()),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text('general.cancel'.tr()),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text('support.close'.tr()),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    try {
      final t = await _repo.close(widget.id);
      if (mounted) setState(() => _ticket = t);
    } on SupportException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(e.message)));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = _ticket;
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.background,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        title: Text(
          t?.category.label ?? 'profile.help'.tr(),
          style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
        ),
        actions: [
          if (t != null && t.status != SupportStatus.closed)
            IconButton(
              tooltip: 'support.close'.tr(),
              icon: const Icon(Icons.check_circle_outline_rounded),
              onPressed: _close,
            ),
        ],
      ),
      body: t == null
          ? Center(
              child: _error == null
                  ? const CircularProgressIndicator()
                  : Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          _error!,
                          style: const TextStyle(
                            color: AppColors.textSecondary,
                          ),
                        ),
                        TextButton(
                          onPressed: () {
                            setState(() => _error = null);
                            _load();
                          },
                          child: Text('general.retry'.tr()),
                        ),
                      ],
                    ),
            )
          : Column(
              children: [
                Expanded(
                  child: RefreshIndicator(
                    color: AppColors.primary,
                    onRefresh: _load,
                    child: ListView(
                      controller: _scroll,
                      physics: const AlwaysScrollableScrollPhysics(),
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                      children: [
                        Center(child: SupportStatusChip(status: t.status)),
                        const SizedBox(height: 14),
                        for (final m in t.messages) _Bubble(message: m),
                        if (t.status == SupportStatus.open &&
                            !t.messages.any((m) => m.fromSupport))
                          _Note(text: 'support.waiting_note'.tr()),
                        if (t.status == SupportStatus.closed)
                          _Note(text: 'support.closed_note'.tr()),
                      ],
                    ),
                  ),
                ),
                _Composer(
                  controller: _reply,
                  sending: _sending,
                  onSend: _reply.text.trim().length >= 3 ? _send : null,
                ),
              ],
            ),
    );
  }
}

class _Bubble extends StatelessWidget {
  const _Bubble({required this.message});

  final SupportMessage message;

  @override
  Widget build(BuildContext context) {
    final mine = !message.fromSupport;
    final radius = BorderRadius.only(
      topLeft: const Radius.circular(16),
      topRight: const Radius.circular(16),
      bottomLeft: Radius.circular(mine ? 16 : 4),
      bottomRight: Radius.circular(mine ? 4 : 16),
    );
    return Align(
      alignment: mine
          ? AlignmentDirectional.centerEnd
          : AlignmentDirectional.centerStart,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: MediaQuery.sizeOf(context).width * 0.8,
        ),
        child: Container(
          margin: const EdgeInsets.only(bottom: 10),
          padding: const EdgeInsets.fromLTRB(12, 9, 12, 7),
          decoration: BoxDecoration(
            color: mine
                ? AppColors.primary.withValues(alpha: 0.16)
                : AppColors.surface,
            borderRadius: radius,
            border: Border.all(
              color: mine
                  ? AppColors.primary.withValues(alpha: 0.25)
                  : Colors.white.withValues(alpha: 0.06),
              width: 0.6,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (!mine)
                Padding(
                  padding: const EdgeInsets.only(bottom: 3),
                  child: Text(
                    'support.team'.tr(),
                    style: TextStyle(
                      color: AppColors.primary,
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              SelectableText(
                message.body,
                style: const TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: 14.5,
                  height: 1.4,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                supportTime(message.at),
                style: const TextStyle(color: AppColors.textHint, fontSize: 11),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Note extends StatelessWidget {
  const _Note({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
      child: Text(
        text,
        textAlign: TextAlign.center,
        style: const TextStyle(
          color: AppColors.textHint,
          fontSize: 12.5,
          height: 1.4,
        ),
      ),
    );
  }
}

class _Composer extends StatelessWidget {
  const _Composer({
    required this.controller,
    required this.sending,
    required this.onSend,
  });

  final TextEditingController controller;
  final bool sending;
  final VoidCallback? onSend;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.fromLTRB(
        12,
        8,
        8,
        8 + MediaQuery.paddingOf(context).bottom,
      ),
      decoration: BoxDecoration(
        color: AppColors.background,
        border: Border(
          top: BorderSide(color: Colors.white.withValues(alpha: 0.06)),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Expanded(
            child: TextField(
              controller: controller,
              enabled: !sending,
              minLines: 1,
              maxLines: 5,
              maxLength: 2000,
              textCapitalization: TextCapitalization.sentences,
              style: const TextStyle(
                color: AppColors.textPrimary,
                fontSize: 14.5,
              ),
              decoration: InputDecoration(
                hintText: 'support.reply_hint'.tr(),
                hintStyle: const TextStyle(color: AppColors.textHint),
                counterText: '',
                filled: true,
                fillColor: AppColors.surface,
                isDense: true,
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 11,
                ),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(22),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
          ),
          const SizedBox(width: 6),
          SizedBox(
            width: 44,
            height: 44,
            child: sending
                ? const Padding(
                    padding: EdgeInsets.all(11),
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : IconButton(
                    onPressed: onSend,
                    icon: Icon(
                      Icons.send_rounded,
                      color: onSend == null
                          ? AppColors.textHint
                          : AppColors.primary,
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}
