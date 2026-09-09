import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:soplay/core/theme/app_colors.dart';

class CommentCompose extends StatefulWidget {
  const CommentCompose({
    super.key,
    required this.onSubmit,
    required this.enabled,
    required this.submitting,
    this.replyTarget,
    this.editTarget,
    this.initialText = '',
    this.onCancel,
  });

  final Future<void> Function(String text) onSubmit;
  final bool enabled;
  final bool submitting;
  final String? replyTarget;
  final String? editTarget;
  final String initialText;
  final VoidCallback? onCancel;

  @override
  State<CommentCompose> createState() => _CommentComposeState();
}

class _CommentComposeState extends State<CommentCompose> {
  late TextEditingController _controller;
  final FocusNode _focus = FocusNode();

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialText);
    if (widget.replyTarget != null || widget.editTarget != null) {
      WidgetsBinding.instance.addPostFrameCallback(
        (_) => _focus.requestFocus(),
      );
    }
  }

  @override
  void didUpdateWidget(covariant CommentCompose old) {
    super.didUpdateWidget(old);
    if (widget.editTarget != old.editTarget ||
        widget.initialText != old.initialText) {
      _controller.text = widget.initialText;
      _controller.selection = TextSelection.collapsed(
        offset: widget.initialText.length,
      );
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    _focus.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final text = _controller.text.trim();
    if (text.isEmpty || text.length > 2000 || widget.submitting) return;
    await widget.onSubmit(text);
    if (!mounted) return;
    _controller.clear();
    _focus.unfocus();
  }

  @override
  Widget build(BuildContext context) {
    final hint = widget.editTarget != null
        ? 'comments.edit_hint'.tr()
        : widget.replyTarget != null
            ? 'comments.reply_hint'.tr()
            : 'comments.comment_hint'.tr();

    return Material(
      color: AppColors.background,
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          12,
          8,
          12,
          MediaQuery.viewInsetsOf(context).bottom + 8,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            if (widget.replyTarget != null || widget.editTarget != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 6, left: 4, right: 4),
                child: Row(
                  children: [
                    Icon(
                      widget.editTarget != null
                          ? Icons.edit_rounded
                          : Icons.reply_rounded,
                      color: AppColors.textHint,
                      size: 14,
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        widget.editTarget != null
                            ? 'comments.editing'.tr()
                            : 'comments.replying_to'
                                .tr(args: ['${widget.replyTarget}']),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: AppColors.textHint,
                          fontSize: 11,
                        ),
                      ),
                    ),
                    GestureDetector(
                      onTap: widget.onCancel,
                      child: const Icon(
                        Icons.close_rounded,
                        color: AppColors.textHint,
                        size: 16,
                      ),
                    ),
                  ],
                ),
              ),
            Container(
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
                      controller: _controller,
                      focusNode: _focus,
                      enabled: widget.enabled && !widget.submitting,
                      maxLines: 4,
                      minLines: 1,
                      maxLength: 2000,
                      style: const TextStyle(
                        color: AppColors.textPrimary,
                        fontSize: 13,
                      ),
                      decoration: InputDecoration(
                        hintText: widget.enabled
                            ? hint
                            : 'comments.sign_in_to_comment'.tr(),
                        hintStyle: const TextStyle(
                          color: AppColors.textHint,
                          fontSize: 13,
                        ),
                        border: InputBorder.none,
                        counterText: '',
                        isCollapsed: true,
                        contentPadding:
                            const EdgeInsets.symmetric(vertical: 10),
                      ),
                    ),
                  ),
                  const SizedBox(width: 4),
                  Material(
                    color: widget.enabled && !widget.submitting
                        ? AppColors.primary
                        : AppColors.surfaceVariant,
                    shape: const CircleBorder(),
                    child: InkWell(
                      onTap: widget.enabled && !widget.submitting
                          ? _submit
                          : null,
                      customBorder: const CircleBorder(),
                      child: SizedBox(
                        width: 36,
                        height: 36,
                        child: widget.submitting
                            ? const Padding(
                                padding: EdgeInsets.all(8),
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white,
                                ),
                              )
                            : const Icon(
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
          ],
        ),
      ),
    );
  }
}
