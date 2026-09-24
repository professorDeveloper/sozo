abstract class ProviderEvent {
  const ProviderEvent();
}

class ProviderLoad extends ProviderEvent {
  const ProviderLoad({this.localOnly = false});

  /// Refresh installed extensions without waiting on an unchanged server list.
  final bool localOnly;
}

class ProviderSelect extends ProviderEvent {
  final String providerId;

  /// Whether this becomes the source the mode returns to. False only for a
  /// stand-in picked because the remembered one is not available right now,
  /// so the memory survives until it is.
  final bool remember;
  const ProviderSelect(this.providerId, {this.remember = true});
}
