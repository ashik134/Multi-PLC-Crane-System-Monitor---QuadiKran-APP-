import 'package:flutter_foreground_task/flutter_foreground_task.dart';

/// Minimal task handler that keeps the Flutter engine alive in the background
/// so that active BLE connections are maintained when the app is minimised.
class BleForegroundTaskHandler extends TaskHandler {
  @override
  Future<void> onStart(DateTime timestamp, TaskStarter starter) async {
    // Nothing to do – the mere presence of the foreground service is
    // enough to prevent Android from killing the process.
  }

  @override
  void onRepeatEvent(DateTime timestamp) {
    // Periodic keep-alive tick. No work needed.
  }

  @override
  Future<void> onDestroy(DateTime timestamp, bool isTimedout) async {}

  /// Called when the user taps a button on the persistent notification.
  /// Sends a message to the main isolate so [PLCBluetoothService] can
  /// disconnect all PLCs and stop the foreground service cleanly.
  /// Also stops the service directly so the notification is dismissed even
  /// if the main isolate is no longer alive.
  @override
  void onNotificationButtonPressed(String id) {
    if (id == 'stop_service') {
      FlutterForegroundTask.sendDataToMain({'action': 'ble_force_stop'});
      FlutterForegroundTask.stopService();
    }
  }
}

/// Entry-point called by the foreground service isolate on Android.
@pragma('vm:entry-point')
void bleTaskEntryPoint() {
  FlutterForegroundTask.setTaskHandler(BleForegroundTaskHandler());
}
