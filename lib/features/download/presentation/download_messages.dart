import 'package:easy_localization/easy_localization.dart';

import 'package:soplay/features/download/domain/entities/download_item.dart';
import 'package:soplay/features/download/domain/entities/download_kind.dart';
import 'package:soplay/features/download/domain/entities/download_location.dart';
import 'package:soplay/features/download/domain/entities/download_status.dart';
import 'package:soplay/features/download/domain/repositories/download_repository.dart';

/// What to say after asking for a download.
///
/// Five outcomes, five sentences. The old code returned a bare bool and every
/// screen printed "Download started" for it, so a refusal because the device
/// was full, a refusal because the link was an embed page, and a download that
/// was already finished all read as success.
String downloadOutcomeMessage(EnqueueOutcome outcome) => switch (outcome) {
      EnqueueOutcome.started => 'detail.download_started'.tr(),
      EnqueueOutcome.alreadyPresent => 'detail.download_already'.tr(),
      EnqueueOutcome.noSpace => 'downloads.error.no_space'.tr(),
      EnqueueOutcome.notDownloadable =>
        'detail.download_needs_playback'.tr(),
      EnqueueOutcome.refused => 'detail.download_needs_permission'.tr(),
    };

/// The one-line state of a row, in the viewer's language.
String downloadStatusLabel(DownloadItem item) => switch (item.status) {
      DownloadStatus.pending => 'downloads.pending'.tr(),
      DownloadStatus.downloading => 'downloads.downloading'.tr(),
      DownloadStatus.paused => 'downloads.paused'.tr(),
      DownloadStatus.completed => 'downloads.downloaded'.tr(),
      DownloadStatus.missing => 'downloads.missing'.tr(),
      DownloadStatus.failed => item.failure == null
          ? 'downloads.failed'.tr()
          : item.failure!.messageKey.tr(),
    };

/// Bytes, as a person reads them.
///
/// A decimal earns its place under 10 and stops helping above it: "1.5 GB" is
/// worth knowing, "16.0 GB" reads worse than "16 GB".
String formatBytes(int bytes) {
  if (bytes <= 0) return '0 MB';
  const units = ['B', 'KB', 'MB', 'GB', 'TB'];
  var value = bytes.toDouble();
  var unit = 0;
  while (value >= 1024 && unit < units.length - 1) {
    value /= 1024;
    unit++;
  }
  final text = value >= 10 || unit == 0
      ? value.toStringAsFixed(0)
      : value.toStringAsFixed(1);
  return '$text ${units[unit]}';
}

/// The line under a row's title while it is running.
///
/// Reads the unit off the item rather than guessing from the url, which is
/// what made a 214 MB episode print "648 B": the counters held segments during
/// the transfer and bytes after it, and the widget had no way to tell which.
String downloadProgressLabel(DownloadItem item) {
  switch (item.unit) {
    case DownloadUnit.segments:
      return 'downloads.segments_progress'
          .tr(args: ['${item.completedUnits}', '${item.totalUnits}']);
    case DownloadUnit.pages:
      return 'manga.downloaded_pages'
          .tr(args: ['${item.completedUnits}', '${item.totalUnits}']);
    case DownloadUnit.bytes:
      if (item.totalUnits > 0) {
        return '${formatBytes(item.completedUnits)} / '
            '${formatBytes(item.totalUnits)}';
      }
      return 'downloads.downloaded_amount'
          .tr(args: [formatBytes(item.completedUnits)]);
  }
}

/// What a finished row shows on its second line.
String downloadSizeLabel(DownloadItem item) {
  if (item.isManga) {
    return 'downloads.pages_count'.tr(args: ['${item.totalUnits}']);
  }
  return item.sizeBytes > 0
      ? formatBytes(item.sizeBytes)
      : 'downloads.downloaded'.tr();
}

/// The name of a volume, in the viewer's language.
///
/// The platform hands back a key rather than a phrase — a device's own label
/// for its SD card is not translated, and half of them do not have one.
String locationLabel(DownloadLocation location) => switch (location.label) {
      'internal' => 'downloads.location_internal'.tr(),
      'external' => 'downloads.location_external'.tr(),
      'sdcard' => 'downloads.location_sdcard'.tr(),
      _ => location.path,
    };

/// What to say after a move.
String moveOutcomeMessage(MoveLocationOutcome outcome) => switch (outcome) {
      MoveLocationOutcome.moved => 'downloads.location_moved'.tr(),
      MoveLocationOutcome.unchanged => 'downloads.location_unchanged'.tr(),
      MoveLocationOutcome.noSpace => 'downloads.error.no_space'.tr(),
      MoveLocationOutcome.failed => 'downloads.location_failed'.tr(),
    };
