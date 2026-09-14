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
  const ProviderSelect(this.providerId);
}
