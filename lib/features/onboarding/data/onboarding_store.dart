import 'package:soplay/core/storage/hive_service.dart';

/// Where the setup in progress is kept between launches.
abstract class OnboardingStore {
  Map<String, dynamic>? read();
  Future<void> write(Map<String, dynamic>? value);
}

class HiveOnboardingStore implements OnboardingStore {
  HiveOnboardingStore(this.hive);

  final HiveService hive;

  @override
  Map<String, dynamic>? read() => hive.getOnboardingFlow();

  @override
  Future<void> write(Map<String, dynamic>? value) =>
      hive.saveOnboardingFlow(value);
}

class MemoryOnboardingStore implements OnboardingStore {
  MemoryOnboardingStore([this.value]);

  Map<String, dynamic>? value;

  @override
  Map<String, dynamic>? read() => value;

  @override
  Future<void> write(Map<String, dynamic>? value) async => this.value = value;
}
