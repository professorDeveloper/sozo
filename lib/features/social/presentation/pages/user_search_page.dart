import 'dart:async';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'package:soplay/core/di/injection.dart';
import 'package:soplay/core/system/responsive.dart';
import 'package:soplay/core/theme/app_colors.dart';
import 'package:soplay/features/social/data/social_service.dart';
import 'package:soplay/features/social/domain/social_models.dart';
import 'package:soplay/features/social/presentation/widgets/relation_actions.dart';
import 'package:soplay/features/social/presentation/widgets/social_widgets.dart';

/// Find people by username.
class UserSearchPage extends StatefulWidget {
  const UserSearchPage({super.key});

  static const int minLength = 2;

  /// What is sent: trimmed, a leading @ dropped, as people paste handles.
  static String normalise(String raw) {
    var q = raw.trim();
    if (q.startsWith('@')) q = q.substring(1);
    return q.trim();
  }

  @override
  State<UserSearchPage> createState() => _UserSearchPageState();
}

class _UserSearchPageState extends State<UserSearchPage> {
  final SocialService _social = getIt<SocialService>();
  final TextEditingController _input = TextEditingController();
  Timer? _debounce;
  String _query = '';
  List<UserSearchResult>? _results;
  Object? _error;
  bool _loading = false;
  int _seq = 0;

  @override
  void dispose() {
    _debounce?.cancel();
    _input.dispose();
    super.dispose();
  }

  void _onChanged(String raw) {
    _debounce?.cancel();
    final q = UserSearchPage.normalise(raw);
    if (q.length < UserSearchPage.minLength) {
      _seq++;
      setState(() {
        _query = q;
        _results = null;
        _error = null;
        _loading = false;
      });
      return;
    }
    _debounce = Timer(const Duration(milliseconds: 350), () => _search(q));
  }

  Future<void> _search(String q) async {
    final seq = ++_seq;
    setState(() {
      _query = q;
      _loading = true;
      _error = null;
    });
    try {
      final results = await _social.remote.search(q);
      if (!mounted || seq != _seq) return;
      setState(() => _results = results);
    } catch (e) {
      if (!mounted || seq != _seq) return;
      setState(() => _error = e);
    } finally {
      if (mounted && seq == _seq) setState(() => _loading = false);
    }
  }

  void _update(int index, SocialRelation relation, String? requestId) {
    final list = _results;
    if (list == null || index >= list.length) return;
    setState(() {
      _results = [
        for (var i = 0; i < list.length; i++)
          i == index
              ? list[i].copyWith(
                  relation: relation,
                  requestId: requestId,
                  clearRequest: requestId == null,
                )
              : list[i],
      ];
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.background,
        surfaceTintColor: Colors.transparent,
        scrolledUnderElevation: 0,
        elevation: 0,
        titleSpacing: 0,
        title: Padding(
          padding: const EdgeInsetsDirectional.only(end: 16),
          child: TextField(
            controller: _input,
            autofocus: true,
            onChanged: _onChanged,
            onSubmitted: (v) {
              final q = UserSearchPage.normalise(v);
              if (q.length >= UserSearchPage.minLength) {
                _debounce?.cancel();
                _search(q);
              }
            },
            textInputAction: TextInputAction.search,
            autocorrect: false,
            enableSuggestions: false,
            maxLength: 30,
            style: const TextStyle(color: AppColors.textPrimary, fontSize: 15),
            decoration: InputDecoration(
              counterText: '',
              hintText: 'social.search_hint'.tr(),
              hintStyle: const TextStyle(color: AppColors.textHint),
              prefixIcon: const Icon(
                Icons.alternate_email_rounded,
                color: AppColors.textHint,
                size: 18,
              ),
              filled: true,
              fillColor: AppColors.surface,
              isDense: true,
              contentPadding: const EdgeInsets.symmetric(vertical: 10),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide.none,
              ),
              suffixIcon: _query.isEmpty
                  ? null
                  : IconButton(
                      icon: const Icon(
                        Icons.close_rounded,
                        color: AppColors.textHint,
                        size: 18,
                      ),
                      onPressed: () {
                        _input.clear();
                        _onChanged('');
                      },
                    ),
            ),
          ),
        ),
        bottom: _loading
            ? PreferredSize(
                preferredSize: const Size.fromHeight(2),
                child: LinearProgressIndicator(
                  minHeight: 2,
                  color: AppColors.primary,
                  backgroundColor: Colors.transparent,
                ),
              )
            : null,
      ),
      body: MaxWidthBox(maxWidth: 640, child: _body()),
    );
  }

  Widget _body() {
    final results = _results;
    if (_error != null && results == null) {
      return SocialStateView.error(_error, () => _search(_query));
    }
    if (_query.length < UserSearchPage.minLength || results == null) {
      return SocialStateView(
        icon: Icons.person_search_rounded,
        title: 'social.search_intro_title'.tr(),
        body: 'social.search_intro_body'.tr(),
      );
    }
    if (results.isEmpty) {
      return SocialStateView(
        icon: Icons.search_off_rounded,
        title: 'social.search_empty'.tr(),
        body: 'social.search_empty_body'.tr(),
      );
    }
    return ListView.builder(
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      padding: EdgeInsets.only(
        top: 8,
        bottom: MediaQuery.paddingOf(context).bottom + 24,
      ),
      itemCount: results.length,
      itemBuilder: (context, i) {
        final r = results[i];
        return SocialUserTile(
          key: ValueKey(r.user.id),
          user: r.user,
          onTap: () async {
            await context.push('/u/${Uri.encodeComponent(r.user.username)}');
            if (mounted && _query.length >= UserSearchPage.minLength) {
              _search(_query);
            }
          },
          trailing: RelationActions(
            user: r.user,
            relation: r.relation,
            requestId: r.requestId,
            onChanged: (rel, id) => _update(i, rel, id),
          ),
        );
      },
    );
  }
}
