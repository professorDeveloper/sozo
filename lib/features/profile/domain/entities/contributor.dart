/// Someone who has committed to one of the open-source Sozo repositories.
class Contributor {
  const Contributor({
    required this.login,
    required this.avatarUrl,
    required this.htmlUrl,
    required this.contributions,
  });

  final String login;
  final String avatarUrl;
  final String htmlUrl;
  final int contributions;

  /// Null for anything without a login. A profile link that is not on
  /// github.com is replaced, so a tap can only ever open GitHub.
  static Contributor? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final login = raw['login'];
    if (login is! String || login.trim().isEmpty) return null;
    final name = login.trim();
    final html = raw['htmlUrl'];
    final avatar = raw['avatarUrl'];
    final count = raw['contributions'];
    return Contributor(
      login: name,
      avatarUrl: avatar is String && avatar.startsWith('https://')
          ? avatar
          : '',
      htmlUrl: html is String && html.startsWith('https://github.com/')
          ? html
          : 'https://github.com/$name',
      contributions: count is num ? count.toInt() : 0,
    );
  }

  /// Reads `{contributors: [...]}` or a bare list, skipping bad rows.
  static List<Contributor> listFrom(Object? data) {
    final rows = data is Map ? data['contributors'] : data;
    if (rows is! List) return const [];
    return [for (final row in rows) ?Contributor.fromJson(row)];
  }

  /// GitHub serves an avatar at any size through `s`; the default is 460 px.
  static String sizedAvatar(String url, int px) {
    if (url.isEmpty) return url;
    final uri = Uri.tryParse(url);
    if (uri == null) return url;
    return uri
        .replace(queryParameters: {...uri.queryParameters, 's': '$px'})
        .toString();
  }

  Map<String, Object> toJson() => {
    'login': login,
    'avatarUrl': avatarUrl,
    'htmlUrl': htmlUrl,
    'contributions': contributions,
  };
}
