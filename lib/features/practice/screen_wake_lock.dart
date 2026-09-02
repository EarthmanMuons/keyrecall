import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

final screenWakeLockProvider = Provider<ScreenWakeLock>(
  (ref) => const PlatformScreenWakeLock(),
);

abstract interface class ScreenWakeLock {
  Future<void> setEnabled(bool enabled);
}

class PlatformScreenWakeLock implements ScreenWakeLock {
  const PlatformScreenWakeLock();

  @override
  Future<void> setEnabled(bool enabled) => WakelockPlus.toggle(enable: enabled);
}
