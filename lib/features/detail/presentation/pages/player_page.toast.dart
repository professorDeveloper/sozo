// ignore_for_file: invalid_use_of_protected_member
part of 'player_page.dart';

/// The player's notices, drawn by the page rather than as SnackBars: those sat
/// at the bottom, over the seek bar the viewer was reaching for.
extension _PlayerToasts on _PlayerPageState {
  void _toast(
    String message, {
    IconData icon = Icons.info_outline_rounded,
    Duration duration = const Duration(seconds: 2),
    String? action,
    VoidCallback? onAction,
  }) {
    if (!mounted) return;
    _toastTimer?.cancel();
    _toastNote.value = _PlayerToast(
      message,
      icon: icon,
      action: action,
      onAction: onAction,
    );
    _toastTimer = Timer(duration, () {
      if (mounted) _toastNote.value = null;
    });
  }

  void _dismissToast() {
    _toastTimer?.cancel();
    _toastNote.value = null;
  }

  Widget _buildPlayerToast() {
    return Positioned(
      top: 0,
      left: 16,
      right: 16,
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.only(top: 12),
          child: Center(
            child: ValueListenableBuilder<_PlayerToast?>(
              valueListenable: _toastNote,
              builder: (context, toast, _) => AnimatedSwitcher(
                duration: const Duration(milliseconds: 180),
                transitionBuilder: (child, a) => FadeTransition(
                  opacity: a,
                  child: SlideTransition(
                    position: Tween<Offset>(
                      begin: const Offset(0, -0.3),
                      end: Offset.zero,
                    ).animate(a),
                    child: child,
                  ),
                ),
                child: toast == null
                    ? const SizedBox.shrink()
                    : ConstrainedBox(
                        key: ObjectKey(toast),
                        constraints: const BoxConstraints(maxWidth: 520),
                        child: IgnorePointer(
                          ignoring: toast.action == null,
                          child: _PlayerToastView(
                            toast: toast,
                            onAction: () {
                              _dismissToast();
                              toast.onAction?.call();
                            },
                          ),
                        ),
                      ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
