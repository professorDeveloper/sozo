import 'package:flutter/material.dart';
import 'package:flutter_html/flutter_html.dart';
import 'package:markdown/markdown.dart' as md;
import 'package:soplay/core/theme/app_colors.dart';

class ReleaseNotesView extends StatelessWidget {
  const ReleaseNotesView({
    super.key,
    required this.text,
    this.fontSize = 13,
  });

  final String text;
  final double fontSize;

  static final _htmlTagPattern = RegExp(r'<[a-zA-Z][^>]*>');

  bool get _looksLikeHtml => _htmlTagPattern.hasMatch(text);

  String get _html => _looksLikeHtml
      ? text
      : md.markdownToHtml(
          text,
          extensionSet: md.ExtensionSet.gitHubWeb,
          inlineSyntaxes: [md.InlineHtmlSyntax()],
        );

  @override
  Widget build(BuildContext context) {
    final fs = fontSize;
    return Html(
      data: _html,
      style: {
        'body': Style(
          margin: Margins.zero,
          padding: HtmlPaddings.zero,
          color: AppColors.textSecondary,
          fontSize: FontSize(fs),
          lineHeight: const LineHeight(1.45),
        ),
        'p': Style(
          margin: Margins.only(bottom: 8),
        ),
        'h1': Style(
          fontSize: FontSize(fs + 6),
          fontWeight: FontWeight.w800,
          color: AppColors.textPrimary,
          margin: Margins.only(bottom: 8),
        ),
        'h2': Style(
          fontSize: FontSize(fs + 4),
          fontWeight: FontWeight.w800,
          color: AppColors.textPrimary,
          margin: Margins.only(bottom: 6),
        ),
        'h3': Style(
          fontSize: FontSize(fs + 2),
          fontWeight: FontWeight.w700,
          color: AppColors.textPrimary,
          margin: Margins.only(bottom: 6),
        ),
        'strong': Style(
          color: AppColors.textPrimary,
          fontWeight: FontWeight.w700,
        ),
        'em': Style(fontStyle: FontStyle.italic),
        'a': Style(
          color: AppColors.primary,
          textDecoration: TextDecoration.underline,
        ),
        'ul': Style(
          margin: Margins.only(left: 4, bottom: 8),
          padding: HtmlPaddings.only(left: 16),
        ),
        'ol': Style(
          margin: Margins.only(left: 4, bottom: 8),
          padding: HtmlPaddings.only(left: 16),
        ),
        'li': Style(margin: Margins.only(bottom: 4)),
        'code': Style(
          backgroundColor: AppColors.surfaceVariant,
          color: AppColors.textPrimary,
          fontFamily: 'monospace',
          fontSize: FontSize(fs - 1),
          padding: HtmlPaddings.symmetric(horizontal: 4, vertical: 1),
        ),
        'pre': Style(
          backgroundColor: AppColors.surfaceVariant,
          color: AppColors.textPrimary,
          padding: HtmlPaddings.all(10),
          margin: Margins.only(bottom: 8),
          fontFamily: 'monospace',
          fontSize: FontSize(fs - 1),
        ),
        'blockquote': Style(
          margin: Margins.only(bottom: 8),
          padding: HtmlPaddings.only(left: 10),
          border: Border(
            left: BorderSide(color: AppColors.border, width: 3),
          ),
          color: AppColors.textSecondary,
          fontStyle: FontStyle.italic,
        ),
        'hr': Style(
          backgroundColor: AppColors.border,
          height: Height(1),
          margin: Margins.symmetric(vertical: 8),
        ),
      },
    );
  }
}
