import 'package:soplay/features/home/presentation/bloc/home/home_state.dart';

/// Whether the current source's front page loaded — as a type, so nothing can
/// assume it did.
///
/// Home used to be all-or-nothing. `HomeBloc` emitted `HomeError`, `HomePage`
/// swapped the whole body for an error card, and `HomeContent` would not build
/// without a `HomeLoaded`. So one cloud provider timing out took down Continue
/// Watching and completed downloads with it — both of which are rows in Hive
/// and files on disk, and neither of which needs a network at all.
///
/// The device that is genuinely offline never gets here: `NoInternetInterceptor`
/// catches the Dio error and routes to `/no-internet`, which already shows the
/// downloads. This is the online-but-the-provider-is-broken case, which is the
/// common one.
///
/// Sealed on purpose. Making the catalogue optional turns a null-safety problem
/// into a semantics one, and a sealed type is what makes the compiler name
/// every place that assumed success instead of leaving them to be found later.
sealed class CatalogueStatus {
  const CatalogueStatus();
}

/// The provider's front page arrived. Everything that needs it is available.
final class CatalogueReady extends CatalogueStatus {
  const CatalogueReady(this.data);

  final HomeLoaded data;
}

/// It did not. Everything local still renders; this only decides what the strip
/// at the top says.
final class CatalogueFailed extends CatalogueStatus {
  const CatalogueFailed(this.message);

  final String message;
}
