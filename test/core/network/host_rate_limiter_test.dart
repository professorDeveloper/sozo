import 'package:flutter_test/flutter_test.dart';
import 'package:soplay/core/network/host_rate_limiter.dart';

void main() {
  late DateTime clock;
  late List<Duration> slept;
  late HostRateLimiter limiter;

  setUp(() {
    clock = DateTime.utc(2026, 9, 24, 12);
    slept = [];
    limiter = HostRateLimiter(
      now: () => clock,
      sleep: (d) async {
        slept.add(d);
        clock = clock.add(d);
      },
    );
  });

  test('a host that never objected is not slowed down', () async {
    await limiter.acquire('novelfire.net');
    await limiter.acquire('novelfire.net');
    expect(slept, isEmpty);
    expect(limiter.isPaced('novelfire.net'), isFalse);
  });

  test('after a 429 the retry waits, then requests are spaced out', () async {
    final wait = limiter.throttled('novelfire.net');
    expect(wait, const Duration(seconds: 2));

    await limiter.acquire('novelfire.net');
    await limiter.acquire('novelfire.net');
    await limiter.acquire('novelfire.net');
    expect(slept, [
      const Duration(seconds: 2),
      const Duration(milliseconds: 400),
      const Duration(milliseconds: 400),
    ]);
    expect(limiter.isPaced('other.site'), isFalse);
  });

  test('backoff doubles per attempt, honours Retry-After, and is capped', () {
    expect(limiter.throttled('h', attempt: 1), const Duration(seconds: 4));
    expect(limiter.throttled('h', attempt: 2), const Duration(seconds: 8));
    expect(
      limiter.throttled('h', retryAfter: const Duration(seconds: 5)),
      const Duration(seconds: 5),
    );
    expect(
      limiter.throttled('h', retryAfter: const Duration(minutes: 5)),
      const Duration(seconds: 15),
    );
  });

  test('Retry-After is read as seconds or as an HTTP date', () {
    final now = DateTime.utc(2026, 9, 24, 12, 0, 0);
    expect(HostRateLimiter.parseRetryAfter('7'), const Duration(seconds: 7));
    expect(
      HostRateLimiter.parseRetryAfter(
        'Thu, 24 Sep 2026 12:00:10 GMT',
        now: now,
      ),
      const Duration(seconds: 10),
    );
    expect(HostRateLimiter.parseRetryAfter(''), isNull);
    expect(HostRateLimiter.parseRetryAfter('soon'), isNull);
  });
}
