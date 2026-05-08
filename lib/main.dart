import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';

import 'package:firebase_core/firebase_core.dart';
import 'package:rev4_quadikran_monitoring/firebase_options.dart';

import 'package:provider/provider.dart';
import 'package:restart_app/restart_app.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';

import 'package:rev4_quadikran_monitoring/utils/app_globals.dart';
import 'package:rev4_quadikran_monitoring/screens/splash_screen.dart';
import 'package:rev4_quadikran_monitoring/screens/main_nav_screen.dart';
import 'package:rev4_quadikran_monitoring/screens/login_page_screen.dart';
import 'package:rev4_quadikran_monitoring/services/plc_bluetooth_service.dart';
import 'package:rev4_quadikran_monitoring/services/emergency_alert_service.dart';

ThemeData _buildTheme() {
  final colorScheme = ColorScheme.fromSeed(
    seedColor: const Color(0xFF0B2C5D),
    brightness: Brightness.light,
    primary: const Color(0xFF0B2C5D),
    secondary: const Color(0xFFF39C12),
    surface: const Color(0xFF1F3F7A),
  );

  final textTheme = ThemeData.light().textTheme
      .apply(fontFamily: 'Asul')
      .copyWith(
        titleLarge: const TextStyle(
          fontFamily: 'Asul',
          color: Color.fromARGB(255, 255, 255, 255),
          fontWeight: FontWeight.bold,
        ),
        displayLarge: const TextStyle(
          fontFamily: 'Asul',
          fontSize: 32,
          fontWeight: FontWeight.w700,
        ),
        bodyLarge: const TextStyle(
          fontFamily: 'Asul',
          fontSize: 16,
          fontWeight: FontWeight.w400,
        ),
        labelLarge: const TextStyle(
          fontFamily: 'Asul',
          color: Colors.white,
          fontSize: 14,
          fontWeight: FontWeight.w500,
        ),
      );

  return ThemeData(
    scaffoldBackgroundColor: Colors.white,
    useMaterial3: true,
    colorScheme: colorScheme,
    fontFamily: 'Asul',
    textTheme: textTheme,
  );
}

void main() {
  runZonedGuarded(
    () async {
      WidgetsFlutterBinding.ensureInitialized();
      setupErrorHandling();
      await _appMain();
    },
    (error, stack) =>
        _reportUnhandledError(source: 'Zone', error: error, stackTrace: stack),
  );
}

Future<void> _appMain() async {
  String? firebaseError;

  try {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
    debugPrint(' Firebase initialized successfully ');
  } catch (e) {
    debugPrint(' Firebase initialization failed: $e ');
    firebaseError = e.toString();
  }
  try {
    FlutterForegroundTask.initCommunicationPort();
  } catch (e) {
    debugPrint('Failed to initialize foreground task communication: $e');
  }

  runApp(MyApp(firebaseError: firebaseError));
}

class InitializerWidget extends StatelessWidget {
  const InitializerWidget({super.key, this.firebaseError});
  final String? firebaseError;

  @override
  Widget build(BuildContext context) {
    if (firebaseError != null) {
      return _FirebaseErrorScreen(error: firebaseError!);
    }
    return const SplashScreen(key: ValueKey('splash'));
  }
}

class _FirebaseErrorScreen extends StatelessWidget {
  const _FirebaseErrorScreen({required this.error});

  final String error;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF030B1F),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              const Icon(
                Icons.cloud_off_rounded,
                color: Color(0xFFF39C12),
                size: 72,
              ),
              const SizedBox(height: 24),
              const Text(
                'Connection Failed',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 12),
              const Text(
                'Could not connect to Firebase. Please check your internet connection and try again.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Color(0xFFADB5C8),
                  fontSize: 14,
                  height: 1.5,
                ),
              ),
              const SizedBox(height: 16),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xFF0B2C5D),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: const Color(0xFF1F3F7A)),
                ),
                child: Text(
                  error,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: Color(0xFF9BA8BB),
                    fontSize: 11,
                    fontFamily: 'monospace',
                  ),
                ),
              ),
              const SizedBox(height: 32),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: () => Restart.restartApp(),
                  icon: const Icon(Icons.refresh_rounded),
                  label: const Text('Retry'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFF39C12),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    textStyle: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.bold,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class MyApp extends StatefulWidget {
  const MyApp({super.key, this.firebaseError});

  final String? firebaseError;

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> with WidgetsBindingObserver {
  static final ThemeData _appTheme = _buildTheme();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) => _enableWakelock());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    WakelockPlus.disable();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _enableWakelock();
    } else if (state == AppLifecycleState.paused) {
      WakelockPlus.disable();
    }
  }

  Future<void> _enableWakelock() async {
    for (var attempt = 1; attempt <= 3; attempt++) {
      try {
        await WakelockPlus.enable();
        return;
      } catch (_) {
        if (attempt < 3) {
          await Future.delayed(Duration(milliseconds: 300 * attempt));
        }
      }
    }
    debugPrint('WakelockPlus: could not enable (native channel not ready)');
  }

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => PLCBluetoothService()),
        ChangeNotifierProxyProvider<PLCBluetoothService, EmergencyAlertService>(
          create: (ctx) =>
              EmergencyAlertService(ctx.read<PLCBluetoothService>()),
          // EmergencyAlertService holds its own BLE reference
          update: (_, _, previous) => previous!,
        ),
      ],
      child: MaterialApp(
        title: 'QuadiKran Connect',
        theme: _appTheme,
        navigatorKey: appNavigatorKey,
        home: InitializerWidget(firebaseError: widget.firebaseError),
        routes: {
          '/home': (context) => const MainNavScreen(),
          '/login': (context) => const LoginPage(),
        },
        debugShowCheckedModeBanner: false,
      ),
    );
  }
}

void setupErrorHandling() {
  FlutterError.onError = (FlutterErrorDetails details) {
    FlutterError.presentError(details);
    _reportUnhandledError(
      source: details.library ?? 'Flutter framework',
      error: details.exception,
      stackTrace: details.stack,
    );
  };

  PlatformDispatcher.instance.onError = (Object error, StackTrace stack) {
    _reportUnhandledError(
      source: 'PlatformDispatcher',
      error: error,
      stackTrace: stack,
    );
    return true;
  };

  ErrorWidget.builder = (FlutterErrorDetails details) =>
      _BuildErrorFallback(details: details);
}

void _reportUnhandledError({
  required String source,
  required Object error,
  StackTrace? stackTrace,
}) {
  final timestamp = DateTime.now().toIso8601String();
  debugPrint('[$timestamp][$source] $error');
  debugPrintStack(
    label: '[$timestamp][$source] Stack trace',
    stackTrace: stackTrace,
  );
}

class _BuildErrorFallback extends StatelessWidget {
  const _BuildErrorFallback({required this.details});

  final FlutterErrorDetails details;

  @override
  Widget build(BuildContext context) {
    final errorText = details.exceptionAsString();

    return Material(
      color: const Color(0xFF030B1F),
      child: Directionality(
        textDirection: TextDirection.ltr,
        child: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 560),
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [Color(0xFF0F2A57), Color(0xFF081930)],
                    ),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: const Color(0xFF1F3F7A)),
                    boxShadow: const [
                      BoxShadow(
                        color: Color.fromARGB(60, 11, 44, 93),
                        blurRadius: 24,
                        offset: Offset(0, 12),
                      ),
                    ],
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(
                          Icons.error_outline_rounded,
                          color: Color(0xFFF39C12),
                          size: 68,
                        ),
                        const SizedBox(height: 16),
                        const Text(
                          'Something went wrong',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 22,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 8),
                        const Text(
                          'The app hit an unexpected issue. You can restart now and continue.',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: Color(0xFFBDC8DB),
                            height: 1.4,
                            fontSize: 14,
                          ),
                        ),
                        if (kDebugMode) ...[
                          const SizedBox(height: 16),
                          Container(
                            width: double.infinity,
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: const Color(0xFF0A1E40),
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(
                                color: const Color(0xFF2A4E88),
                              ),
                            ),
                            child: SelectableText(
                              errorText,
                              style: const TextStyle(
                                color: Color(0xFFD7E1F4),
                                fontSize: 11,
                                fontFamily: 'monospace',
                              ),
                            ),
                          ),
                        ],
                        const SizedBox(height: 20),
                        Semantics(
                          button: true,
                          child: InkWell(
                            onTap: () => Restart.restartApp(),
                            borderRadius: BorderRadius.circular(12),
                            child: Ink(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 18,
                                vertical: 12,
                              ),
                              decoration: BoxDecoration(
                                color: const Color(0xFFF39C12),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: const Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(Icons.restart_alt, color: Colors.white),
                                  SizedBox(width: 8),
                                  Text(
                                    'Restart App',
                                    style: TextStyle(
                                      color: Colors.white,
                                      fontSize: 14,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ],
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
