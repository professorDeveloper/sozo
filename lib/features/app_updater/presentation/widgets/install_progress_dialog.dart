import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:soplay/core/theme/app_colors.dart';

class InstallProgressController extends ChangeNotifier {
  double progress = 0;
  bool done = false;
  String? error;

  void update(double v) {
    progress = v.clamp(0, 1);
    notifyListeners();
  }

  void close() {
    done = true;
    notifyListeners();
  }

  void fail(String message) {
    error = message;
    done = true;
    notifyListeners();
  }
}

void showInstallProgressDialog(
  BuildContext context,
  InstallProgressController controller,
) {
  showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (ctx) {
      controller.addListener(() {
        if (controller.done && Navigator.of(ctx).canPop()) {
          Navigator.of(ctx).pop();
        }
      });
      return PopScope(
        canPop: false,
        child: AlertDialog(
          backgroundColor: AppColors.surface,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          content: AnimatedBuilder(
            animation: controller,
            builder: (_, _) {
              final pct = (controller.progress * 100).toInt();
              return Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'update.downloading'.tr(),
                    style: const TextStyle(
                      color: AppColors.textPrimary,
                      fontWeight: FontWeight.w700,
                      fontSize: 15,
                    ),
                  ),
                  const SizedBox(height: 16),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(6),
                    child: LinearProgressIndicator(
                      value: controller.progress > 0 ? controller.progress : null,
                      minHeight: 8,
                      backgroundColor: AppColors.surfaceVariant,
                      valueColor: const AlwaysStoppedAnimation(
                        Color(0xFF10B981),
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    '$pct%',
                    style: const TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: 13,
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      );
    },
  );
}
