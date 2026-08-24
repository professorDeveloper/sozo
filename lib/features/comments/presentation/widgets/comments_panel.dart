import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:soplay/core/di/injection.dart';
import 'package:soplay/core/theme/app_colors.dart';
import 'package:soplay/core/theme/app_theme.dart';
import 'package:soplay/features/comments/domain/entities/comment_entity.dart';
import 'package:soplay/features/comments/presentation/blocs/comments_bloc/comments_bloc.dart';
import 'package:soplay/features/comments/presentation/widgets/comment_card.dart';
import 'package:soplay/features/comments/presentation/widgets/comment_compose.dart';

class CommentsPanel extends StatelessWidget {
  const CommentsPanel({
    super.key,
    required this.provider,
    required this.contentUrl,
  });

  final String provider;
  final String contentUrl;

  @override
  Widget build(BuildContext context) {
    return BlocProvider<CommentsBloc>(
      create: (_) => getIt<CommentsBloc>()
        ..add(CommentsInit(provider: provider, contentUrl: contentUrl)),
      child: const _CommentsView(),
    );
  }
}

class _CommentsView extends StatefulWidget {
  const _CommentsView();

  @override
  State<_CommentsView> createState() => _CommentsViewState();
}

class _CommentsViewState extends State<_CommentsView> {
  String? _replyTo;
  String? _replyToName;
  String? _editId;
  String _initialText = '';

  void _startReply(CommentEntity c) {
    setState(() {
      _replyTo = c.id;
      _replyToName = c.user.nameOrUsername;
      _editId = null;
      _initialText = '';
    });
  }

  void _startEdit(CommentEntity c) {
    setState(() {
      _editId = c.id;
      _initialText = c.text;
      _replyTo = null;
      _replyToName = null;
    });
  }

  void _cancel() {
    setState(() {
      _replyTo = null;
      _replyToName = null;
      _editId = null;
      _initialText = '';
    });
  }

  Future<void> _submit(String text) async {
    final bloc = context.read<CommentsBloc>();
    if (_editId != null) {
      bloc.add(CommentsEdit(id: _editId!, text: text));
    } else {
      bloc.add(CommentsCreate(text: text, parentId: _replyTo));
    }
    _cancel();
  }

  Widget _buildList(
    BuildContext context,
    CommentsState state,
    CommentsBloc bloc,
    String? currentUserId,
    bool loggedIn,
  ) {
    if (state.loading) {
      return Center(
        child: CircularProgressIndicator(
          color: AppColors.primary,
          strokeWidth: 2.4,
        ),
      );
    }
    if (state.items.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.chat_bubble_outline_rounded,
              color: AppColors.textHint,
              size: 48,
            ),
            const SizedBox(height: 12),
            Text(
              'comments.empty_title'.tr(),
              style: const TextStyle(
                color: AppColors.textPrimary,
                fontSize: 15,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'comments.empty_subtitle'.tr(),
              style: const TextStyle(
                color: AppColors.textHint,
                fontSize: 12,
              ),
            ),
          ],
        ),
      );
    }
    return ListView(
      padding: const EdgeInsets.only(bottom: 8),
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
          child: Row(
            children: [
              Text(
                state.total == 1
                    ? 'comments.count_one'.tr()
                    : 'comments.count_other'.tr(args: ['${state.total}']),
                style: const TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: 13,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
        ),
        for (final c in state.items)
          _CommentTree(
            comment: c,
            replies: state.repliesByParent[c.id] ?? const [],
            repliesLoading: state.repliesLoading.contains(c.id),
            expanded: state.expandedIds.contains(c.id),
            currentUserId: currentUserId,
            canInteract: loggedIn,
            onLike: () => bloc.add(CommentsToggleLike(c.id)),
            onReply: () => _startReply(c),
            onEdit: () => _startEdit(c),
            onDelete: () => _confirmDelete(c),
            onToggle: () => bloc.add(CommentsToggleReplies(c.id)),
            onReplyLike: (id) => bloc.add(CommentsToggleLike(id)),
            onReplyEdit: _startEdit,
            onReplyDelete: _confirmDelete,
          ),
        if (state.hasMore)
          Padding(
            padding: const EdgeInsets.only(top: 8, bottom: 16),
            child: TextButton(
              onPressed: state.loadingMore
                  ? null
                  : () => bloc.add(const CommentsLoadMore()),
              child: Text(state.loadingMore
                  ? 'general.loading'.tr()
                  : 'comments.show_more'.tr()),
            ),
          ),
      ],
    );
  }

  Future<void> _confirmDelete(CommentEntity c) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: Text(
          'comments.delete_confirm_title'.tr(),
          style: const TextStyle(color: AppColors.textPrimary, fontSize: 15),
        ),
        content: Text(
          'comments.delete_confirm_body'.tr(),
          style: const TextStyle(color: AppColors.textSecondary, fontSize: 13),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text('general.cancel'.tr()),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(
              'general.delete'.tr(),
              style: const TextStyle(color: Colors.redAccent),
            ),
          ),
        ],
      ),
    );
    if (ok == true && mounted) {
      context.read<CommentsBloc>().add(CommentsDelete(c.id));
    }
  }

  @override
  Widget build(BuildContext context) {
    return BlocConsumer<CommentsBloc, CommentsState>(
      listenWhen: (a, b) => a.error != b.error && b.error != null,
      listener: (context, state) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(state.error ?? ''),
            backgroundColor: AppColors.surface,
            behavior: SnackBarBehavior.floating,
          ),
        );
      },
      builder: (context, state) {
        final bloc = context.read<CommentsBloc>();
        final currentUserId = bloc.currentUserId;
        final loggedIn = bloc.isLoggedIn;
        return Column(
          children: [
            Expanded(
              child: _buildList(context, state, bloc, currentUserId, loggedIn),
            ),
            if (!loggedIn)
              const _SignInPrompt()
            else
              Container(
                decoration: BoxDecoration(
                  color: AppColors.background,
                  border: Border(
                    top: BorderSide(color: AppColors.divider, width: 0.6),
                  ),
                ),
                child: CommentCompose(
                  enabled: loggedIn,
                  submitting: state.submitting,
                  onSubmit: _submit,
                  replyTarget: _replyToName,
                  editTarget: _editId,
                  initialText: _initialText,
                  onCancel: _cancel,
                ),
              ),
          ],
        );
      },
    );
  }
}

class _SignInPrompt extends StatelessWidget {
  const _SignInPrompt();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            'comments.sign_in_prompt'.tr(),
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: AppColors.textSecondary,
              fontSize: 12,
            ),
          ),
          const SizedBox(height: 10),
          SizedBox(
            width: double.infinity,
            height: 44,
            child: ElevatedButton.icon(
              onPressed: () => context.push('/login'),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: Colors.white,
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(kButtonRadius),
                ),
              ),
              icon: const Icon(Icons.login_rounded, size: 18),
              label: Text(
                'auth.sign_in'.tr(),
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _CommentTree extends StatelessWidget {
  const _CommentTree({
    required this.comment,
    required this.replies,
    required this.repliesLoading,
    required this.expanded,
    required this.currentUserId,
    required this.canInteract,
    required this.onLike,
    required this.onReply,
    required this.onEdit,
    required this.onDelete,
    required this.onToggle,
    required this.onReplyLike,
    required this.onReplyEdit,
    required this.onReplyDelete,
  });

  final CommentEntity comment;
  final List<CommentEntity> replies;
  final bool repliesLoading;
  final bool expanded;
  final String? currentUserId;
  final bool canInteract;
  final VoidCallback onLike;
  final VoidCallback onReply;
  final VoidCallback onEdit;
  final VoidCallback onDelete;
  final VoidCallback onToggle;
  final void Function(String id) onReplyLike;
  final void Function(CommentEntity c) onReplyEdit;
  final void Function(CommentEntity c) onReplyDelete;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        CommentCard(
          comment: comment,
          isOwner: currentUserId != null && currentUserId == comment.user.id,
          canInteract: canInteract,
          onLike: onLike,
          onReply: onReply,
          onEdit: onEdit,
          onDelete: onDelete,
          onToggleReplies: onToggle,
          repliesExpanded: expanded,
        ),
        if (expanded)
          Padding(
            padding: const EdgeInsets.only(left: 46),
            child: Column(
              children: [
                if (repliesLoading && replies.isEmpty)
                  Padding(
                    padding: EdgeInsets.symmetric(vertical: 16),
                    child: SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: AppColors.primary,
                      ),
                    ),
                  ),
                for (final r in replies)
                  CommentCard(
                    comment: r,
                    compact: true,
                    isOwner:
                        currentUserId != null && currentUserId == r.user.id,
                    canInteract: canInteract,
                    onLike: () => onReplyLike(r.id),
                    onReply: () {},
                    onEdit: () => onReplyEdit(r),
                    onDelete: () => onReplyDelete(r),
                    onToggleReplies: () {},
                    repliesExpanded: false,
                  ),
              ],
            ),
          ),
      ],
    );
  }
}
