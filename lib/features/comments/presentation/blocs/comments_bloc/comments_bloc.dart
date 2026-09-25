import 'package:easy_localization/easy_localization.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:soplay/core/error/result.dart';
import 'package:soplay/core/storage/hive_service.dart';
import 'package:soplay/features/comments/domain/entities/comment_entity.dart';
import 'package:soplay/features/comments/domain/repositories/comments_repository.dart';

part 'comments_event.dart';
part 'comments_state.dart';

class CommentsBloc extends Bloc<CommentsEvent, CommentsState> {
  final CommentsRepository repository;
  final HiveService hiveService;

  String _provider = '';
  String _contentUrl = '';

  CommentsBloc({required this.repository, required this.hiveService})
      : super(const CommentsState.initial()) {
    on<CommentsInit>(_onInit);
    on<CommentsRefresh>(_onRefresh);
    on<CommentsLoadMore>(_onLoadMore);
    on<CommentsLoadReplies>(_onLoadReplies);
    on<CommentsToggleReplies>(_onToggleReplies);
    on<CommentsCreate>(_onCreate);
    on<CommentsEdit>(_onEdit);
    on<CommentsDelete>(_onDelete);
    on<CommentsToggleLike>(_onToggleLike);
  }

  String? get currentUserId => hiveService.getUser()?.id;
  bool get isLoggedIn => hiveService.isLoggedIn;

  Future<void> _onInit(CommentsInit event, Emitter<CommentsState> emit) async {
    _provider = event.provider;
    _contentUrl = event.contentUrl;
    emit(state.copyWith(loading: true, error: null, items: const []));
    final result = await repository.getComments(
      provider: _provider,
      contentUrl: _contentUrl,
      page: 1,
    );
    switch (result) {
      case Success(:final value):
        emit(state.copyWith(
          loading: false,
          error: null,
          items: value.items,
          page: value.page,
          totalPages: value.totalPages,
          total: value.total,
        ));
      case Failure(:final error):
        emit(state.copyWith(
          loading: false,
          error: _msg(error),
        ));
    }
  }

  Future<void> _onRefresh(
    CommentsRefresh event,
    Emitter<CommentsState> emit,
  ) async {
    emit(state.copyWith(refreshing: true, error: null));
    final result = await repository.getComments(
      provider: _provider,
      contentUrl: _contentUrl,
      page: 1,
    );
    switch (result) {
      case Success(:final value):
        emit(state.copyWith(
          refreshing: false,
          error: null,
          items: value.items,
          page: value.page,
          totalPages: value.totalPages,
          total: value.total,
        ));
      case Failure(:final error):
        emit(state.copyWith(refreshing: false, error: _msg(error)));
    }
  }

  Future<void> _onLoadMore(
    CommentsLoadMore event,
    Emitter<CommentsState> emit,
  ) async {
    if (state.loadingMore || state.page >= state.totalPages) return;
    emit(state.copyWith(loadingMore: true));
    final result = await repository.getComments(
      provider: _provider,
      contentUrl: _contentUrl,
      page: state.page + 1,
    );
    switch (result) {
      case Success(:final value):
        emit(state.copyWith(
          loadingMore: false,
          items: [...state.items, ...value.items],
          page: value.page,
          totalPages: value.totalPages,
          total: value.total,
        ));
      case Failure(:final error):
        emit(state.copyWith(loadingMore: false, error: _msg(error)));
    }
  }

  Future<void> _onToggleReplies(
    CommentsToggleReplies event,
    Emitter<CommentsState> emit,
  ) async {
    final expanded = Set<String>.from(state.expandedIds);
    if (expanded.contains(event.commentId)) {
      expanded.remove(event.commentId);
      emit(state.copyWith(expandedIds: expanded));
      return;
    }
    expanded.add(event.commentId);
    emit(state.copyWith(expandedIds: expanded));
    if (state.repliesByParent[event.commentId] == null) {
      add(CommentsLoadReplies(event.commentId));
    }
  }

  Future<void> _onLoadReplies(
    CommentsLoadReplies event,
    Emitter<CommentsState> emit,
  ) async {
    final loading = Set<String>.from(state.repliesLoading)
      ..add(event.commentId);
    emit(state.copyWith(repliesLoading: loading));
    final result = await repository.getReplies(parentId: event.commentId);
    final next = Set<String>.from(state.repliesLoading)
      ..remove(event.commentId);
    switch (result) {
      case Success(:final value):
        final map = Map<String, List<CommentEntity>>.from(state.repliesByParent);
        map[event.commentId] = value.items;
        emit(state.copyWith(
          repliesByParent: map,
          repliesLoading: next,
        ));
      case Failure(:final error):
        emit(state.copyWith(
          repliesLoading: next,
          error: _msg(error),
        ));
    }
  }

  Future<void> _onCreate(
    CommentsCreate event,
    Emitter<CommentsState> emit,
  ) async {
    if (!isLoggedIn) {
      emit(state.copyWith(error: 'comments.please_sign_in'.tr()));
      return;
    }
    emit(state.copyWith(submitting: true, error: null));
    final result = await repository.create(
      provider: _provider,
      contentUrl: _contentUrl,
      text: event.text,
      parentId: event.parentId,
    );
    switch (result) {
      case Success(:final value):
        if (event.parentId == null) {
          emit(state.copyWith(
            submitting: false,
            items: [value, ...state.items],
            total: state.total + 1,
          ));
        } else {
          final updatedItems = state.items.map((c) {
            if (c.id == event.parentId) {
              return c.copyWith(replyCount: c.replyCount + 1);
            }
            return c;
          }).toList();
          final map = Map<String, List<CommentEntity>>.from(
            state.repliesByParent,
          );
          final expanded = Set<String>.from(state.expandedIds)
            ..add(event.parentId!);
          // Only insert optimistically when this parent's replies were already
          // fetched. Seeding the map with just the new reply would permanently
          // block loading the existing replies (the toggle only fetches when
          // the entry is null) — so fetch the full list instead.
          if (map.containsKey(event.parentId)) {
            map[event.parentId!] = [...map[event.parentId]!, value];
          } else {
            add(CommentsLoadReplies(event.parentId!));
          }
          emit(state.copyWith(
            submitting: false,
            items: updatedItems,
            repliesByParent: map,
            expandedIds: expanded,
          ));
        }
      case Failure(:final error):
        emit(state.copyWith(submitting: false, error: _msg(error)));
    }
  }

  Future<void> _onEdit(
    CommentsEdit event,
    Emitter<CommentsState> emit,
  ) async {
    // `submitting` around the write, as create already does. It draws the
    // spinner on the compose bar, and — the reason it was added — it is how
    // the panel knows an edit has LANDED, so it can stop holding on to the
    // text it would otherwise have to put back.
    emit(state.copyWith(submitting: true, error: null));
    final result = await repository.edit(id: event.id, text: event.text);
    switch (result) {
      case Success(:final value):
        emit(_replaceComment(state, value).copyWith(submitting: false));
      case Failure(:final error):
        emit(state.copyWith(submitting: false, error: _msg(error)));
    }
  }

  Future<void> _onDelete(
    CommentsDelete event,
    Emitter<CommentsState> emit,
  ) async {
    final result = await repository.delete(event.id);
    switch (result) {
      case Success():
        emit(_removeComment(state, event.id));
      case Failure(:final error):
        emit(state.copyWith(error: _msg(error)));
    }
  }

  Future<void> _onToggleLike(
    CommentsToggleLike event,
    Emitter<CommentsState> emit,
  ) async {
    if (!isLoggedIn) {
      emit(state.copyWith(error: 'comments.please_sign_in'.tr()));
      return;
    }
    final before = state;
    final optimistic = _optimisticLike(state, event.id);
    if (optimistic != null) emit(optimistic);
    final result = await repository.toggleLike(event.id);
    switch (result) {
      case Success(:final value):
        emit(_applyLike(before, event.id, value.liked, value.likeCount));
      case Failure(:final error):
        // Revert the optimistic like — otherwise the heart stays filled with a
        // wrong count and the next tap toggles from a bad baseline.
        emit(before.copyWith(error: _msg(error)));
    }
  }

  CommentsState _replaceComment(CommentsState s, CommentEntity replaced) {
    final items = s.items.map((c) => c.id == replaced.id ? replaced : c).toList();
    final map = <String, List<CommentEntity>>{};
    s.repliesByParent.forEach((k, v) {
      map[k] = v.map((c) => c.id == replaced.id ? replaced : c).toList();
    });
    return s.copyWith(items: items, repliesByParent: map);
  }

  CommentsState _removeComment(CommentsState s, String id) {
    final topRemoved = s.items.where((c) => c.id == id).isNotEmpty;
    final items = s.items.where((c) => c.id != id).toList();
    final map = <String, List<CommentEntity>>{};
    s.repliesByParent.forEach((parentId, replies) {
      if (parentId == id) return;
      map[parentId] = replies.where((c) => c.id != id).toList();
    });
    final updatedItems = items.map((c) {
      final r = map[c.id];
      if (r != null && r.length != c.replyCount) {
        return c.copyWith(replyCount: r.length);
      }
      String? parentForId;
      s.repliesByParent.forEach((parentId, replies) {
        for (final reply in replies) {
          if (reply.id == id) parentForId = parentId;
        }
      });
      if (parentForId == c.id && c.replyCount > 0) {
        return c.copyWith(replyCount: c.replyCount - 1);
      }
      return c;
    }).toList();
    return s.copyWith(
      items: updatedItems,
      repliesByParent: map,
      total: topRemoved ? (s.total - 1).clamp(0, 1 << 30) : s.total,
    );
  }

  CommentsState? _optimisticLike(CommentsState s, String id) {
    final updated = _applyLike(s, id, null, null);
    return updated;
  }

  CommentsState _applyLike(
    CommentsState s,
    String id,
    bool? liked,
    int? likeCount,
  ) {
    CommentEntity update(CommentEntity c) {
      if (c.id != id) return c;
      final newLiked = liked ?? !c.likedByMe;
      final newCount = likeCount ??
          (c.likedByMe ? c.likeCount - 1 : c.likeCount + 1).clamp(
            0,
            1 << 30,
          );
      return c.copyWith(likedByMe: newLiked, likeCount: newCount);
    }

    final items = s.items.map(update).toList();
    final map = <String, List<CommentEntity>>{};
    s.repliesByParent.forEach((k, v) {
      map[k] = v.map(update).toList();
    });
    return s.copyWith(items: items, repliesByParent: map);
  }

  String _msg(Object e) =>
      e.toString().replaceFirst('Exception: ', '');
}
