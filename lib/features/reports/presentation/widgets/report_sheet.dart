import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:soplay/core/di/injection.dart';
import 'package:soplay/core/error/result.dart';
import 'package:soplay/core/system/responsive.dart';
import 'package:soplay/core/theme/app_colors.dart';
import 'package:soplay/core/theme/app_theme.dart';
import 'package:soplay/features/reports/domain/entities/report_payload.dart';
import 'package:soplay/features/reports/domain/repositories/reports_repository.dart';

Future<bool> showReportSheet(
  BuildContext context, {
  required String targetType,
  String? targetId,
  String? provider,
  String? contentUrl,
}) async {
  final result = await showAdaptiveModal<bool>(
    context: context,
    backgroundColor: AppColors.surface,
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (_) => _ReportSheet(
      targetType: targetType,
      targetId: targetId,
      provider: provider,
      contentUrl: contentUrl,
    ),
  );
  return result ?? false;
}

class _ReportSheet extends StatefulWidget {
  const _ReportSheet({
    required this.targetType,
    this.targetId,
    this.provider,
    this.contentUrl,
  });
  final String targetType;
  final String? targetId;
  final String? provider;
  final String? contentUrl;

  @override
  State<_ReportSheet> createState() => _ReportSheetState();
}

class _ReportSheetState extends State<_ReportSheet> {
  String _reason = ReportReason.spam;
  final TextEditingController _message = TextEditingController();
  bool _sending = false;
  String? _error;

  @override
  void dispose() {
    _message.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    setState(() {
      _sending = true;
      _error = null;
    });
    final repo = getIt<ReportsRepository>();
    final result = await repo.submit(
      ReportPayload(
        targetType: widget.targetType,
        targetId: widget.targetId,
        provider: widget.provider,
        contentUrl: widget.contentUrl,
        reason: _reason,
        message: _message.text.trim(),
      ),
    );
    if (!mounted) return;
    switch (result) {
      case Success():
        Navigator.of(context).pop(true);
      case Failure(:final error):
        setState(() {
          _sending = false;
          _error = error.toString().replaceFirst('Exception: ', '');
        });
    }
  }

  @override
  Widget build(BuildContext context) {
    final viewInsets = MediaQuery.viewInsetsOf(context).bottom;
    return Padding(
      padding: EdgeInsets.only(bottom: viewInsets),
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: AppColors.border,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 14),
              Text(
                'reports.title'.tr(),
                style: const TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 16),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: ReportReason.all.map((r) {
                  final selected = r == _reason;
                  return ChoiceChip(
                    label: Text(ReportReason.label(r)),
                    selected: selected,
                    onSelected: _sending
                        ? null
                        : (_) => setState(() => _reason = r),
                    backgroundColor: AppColors.surfaceVariant,
                    selectedColor: AppColors.primary,
                    labelStyle: TextStyle(
                      color: selected ? Colors.white : AppColors.textSecondary,
                      fontWeight:
                          selected ? FontWeight.w700 : FontWeight.w500,
                    ),
                    side: BorderSide(
                      color: selected ? AppColors.primary : AppColors.border,
                      width: 0.8,
                    ),
                  );
                }).toList(),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _message,
                enabled: !_sending,
                maxLines: 4,
                maxLength: 500,
                style: const TextStyle(color: AppColors.textPrimary),
                decoration: InputDecoration(
                  hintText: 'reports.note_hint'.tr(),
                  hintStyle: const TextStyle(color: AppColors.textHint),
                  filled: true,
                  fillColor: AppColors.surfaceVariant,
                  counterStyle: const TextStyle(color: AppColors.textHint),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide.none,
                  ),
                ),
              ),
              if (_error != null) ...[
                const SizedBox(height: 8),
                Text(
                  _error!,
                  style: const TextStyle(color: AppColors.error, fontSize: 13),
                ),
              ],
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(kButtonRadius),
                    ),
                  ),
                  onPressed: _sending ? null : _submit,
                  child: _sending
                      ? const SizedBox(
                          height: 18,
                          width: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : Text(
                          'reports.submit'.tr(),
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
