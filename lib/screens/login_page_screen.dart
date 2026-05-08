import 'dart:io';
import 'dart:async';

import 'package:flutter/material.dart';

import 'package:firebase_auth/firebase_auth.dart';

import 'package:shared_preferences/shared_preferences.dart';

const _kPrimaryCyan = Color(0xFF06B6D4);
const _kEmerald = Color(0xFF10B981);
const _kAmber = Color(0xFFF39C12);
const _kSlate900 = Color(0xFF030B1F);
const _kSlate800 = Color(0xFF0B2C5D);
const _kSlate700 = Color(0xFF1F3F7A);
const _kSlate600 = Color(0xFF2D568F);
const _kSlate500 = Color(0xFF4A78B0);
const _kSlate400 = Color(0xFFC19A35);

class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  final TextEditingController _usernameController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();

  bool _showPassword = false;
  bool _isLoading = false;
  bool _isSuccess = false;
  String _errorMessage = '';
  bool _rememberDevice = false;
  bool _isOffline = false;
  // bool _networkRestored = false;
  Timer? _connectivityTimer;
  Timer? _restoreChipTimer;

  // Focus nodes for better keyboard handling
  late final FocusNode _usernameFocusNode;
  late final FocusNode _passwordFocusNode;

  static final Map<String, String> _errorMessages = {
    'user-not-found': 'Invalid email or password.',
    'wrong-password': 'Invalid email or password.',
    'invalid-credential': 'Invalid email or password.',
    'invalid-email': 'Please enter a valid email address.',
    'user-disabled': 'This account has been disabled.',
    'too-many-requests': 'Too many failed attempts. Try again later.',
    'network-request-failed': 'No internet connection. Please try again.',
  };

  @override
  void initState() {
    super.initState();
    _usernameFocusNode = FocusNode();
    _passwordFocusNode = FocusNode();
    _loadSavedCredentials();
  }

  @override
  void dispose() {
    _usernameController.dispose();
    _passwordController.dispose();
    _usernameFocusNode.dispose();
    _passwordFocusNode.dispose();
    _connectivityTimer?.cancel();
    _restoreChipTimer?.cancel();
    super.dispose();
  }

  Future<bool> _hasInternet() async {
    try {
      final result = await InternetAddress.lookup('8.8.8.8');
      return result.isNotEmpty && result[0].rawAddress.isNotEmpty;
    } on SocketException {
      return false;
    }
  }

  void _startConnectivityMonitor() {
    _connectivityTimer?.cancel();
    _connectivityTimer = Timer.periodic(const Duration(seconds: 3), (_) async {
      final online = await _hasInternet();
      if (online && mounted) {
        _connectivityTimer?.cancel();
        setState(() {
          _isOffline = false;
          // _networkRestored = true;
        });
        _restoreChipTimer?.cancel();
        // _restoreChipTimer = Timer(const Duration(seconds: 6), () {
        //   if (mounted) setState(() => _networkRestored = false);
        // });
      }
    });
  }

  Future<void> _loadSavedCredentials() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final savedEmail = prefs.getString('saved_email');
      final remember = prefs.getBool('remember_device') ?? false;

      if (mounted && savedEmail != null && remember) {
        setState(() {
          _usernameController.text = savedEmail;
          _rememberDevice = remember;
        });
      }
    } catch (e) {
      debugPrint('Failed to load saved credentials: $e');
    }
  }

  Future<void> _saveCredentials(String email) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (_rememberDevice) {
        await prefs.setString('saved_email', email);
        await prefs.setBool('remember_device', true);
      } else {
        await prefs.remove('saved_email');
        await prefs.setBool('remember_device', false);
      }
    } catch (e) {
      debugPrint('Failed to save credentials: $e');
    }
  }

  Future<void> _handleLogin() async {
    if (_errorMessage.isNotEmpty) {
      setState(() => _errorMessage = '');
    }

    final email = _usernameController.text.trim();
    final password = _passwordController.text;

    if (email.isEmpty || password.isEmpty) {
      setState(() => _errorMessage = 'Please enter your credentials.');
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = '';
    });

    try {
      final credential = await FirebaseAuth.instance.signInWithEmailAndPassword(
        email: email,
        password: password,
      );

      if (credential.user != null && mounted) {
        await _saveCredentials(email);

        setState(() {
          _isLoading = false;
          _isSuccess = true;
        });
        final prefs = await SharedPreferences.getInstance();
        await prefs.setBool('isLoggedIn', true);
        Future.delayed(const Duration(milliseconds: 500), () {
          if (mounted) {
            Navigator.pushReplacementNamed(context, '/home');
          }
        });
      }
    } on FirebaseAuthException catch (e) {
      final isNetworkError = e.code == 'network-request-failed';
      setState(() {
        _isLoading = false;
        _errorMessage =
            _errorMessages[e.code] ??
            'Authentication failed. Check your internet connection.';
        if (isNetworkError) {
          _isOffline = true;
          // _networkRestored = false;
        }
      });
      if (isNetworkError) _startConnectivityMonitor();
    } catch (e) {
      final isNetworkError = e is SocketException;
      setState(() {
        _isLoading = false;
        _errorMessage = isNetworkError
            ? 'No internet connection. Please try again.'
            : 'An unexpected error occurred. Please try again.';
        if (isNetworkError) {
          _isOffline = true;
          // _networkRestored = false;
        }
      });
      if (isNetworkError) _startConnectivityMonitor();
    }
  }

  void _handleForgotPassword() {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Contact administrator to reset password'),
        backgroundColor: _kAmber,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _kSlate900,
      body: Stack(
        children: [
          const _BackgroundGradient(),

          const _AnimatedGrid(),

          const _GlowBlobs(),

          Center(
            child: Container(
              constraints: const BoxConstraints(maxWidth: 480),
              margin: const EdgeInsets.symmetric(horizontal: 16),
              child: Card(
                elevation: 24,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(24),
                  side: const BorderSide(color: Colors.black),
                ),
                color: _kSlate900.withAlpha(153),
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(28),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Center(
                        child: Container(
                          width: 60,
                          height: 60,
                          padding: const EdgeInsets.symmetric(horizontal: 6),
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            gradient: const LinearGradient(
                              colors: [
                                Color.fromARGB(255, 255, 255, 255),
                                Color.fromARGB(255, 255, 255, 255),
                              ],
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                            ),
                            boxShadow: [
                              BoxShadow(
                                color: const Color.fromARGB(
                                  255,
                                  255,
                                  255,
                                  255,
                                ).withValues(alpha: 0.3),
                                blurRadius: 3,
                              ),
                            ],
                          ),
                          child: ClipRRect(
                            child: Image.asset(
                              'assets/images/Intellicontrol Final Logo300PPI.png',
                              fit: BoxFit.contain,
                              errorBuilder: (context, error, stackTrace) {
                                return const Icon(
                                  Icons.business,
                                  size: 16,
                                  color: Colors.white,
                                );
                              },
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 8),
                      const _LoginHeader(),
                      const SizedBox(height: 12),
                      if (_isOffline) const _OfflineChip(),
                      // if (!_isOffline && _networkRestored)
                      //   const _NetworkRestoredChip(),
                      const SizedBox(height: 12),
                      _LoginForm(
                        formKey: _formKey,
                        usernameController: _usernameController,
                        passwordController: _passwordController,
                        usernameFocusNode: _usernameFocusNode,
                        passwordFocusNode: _passwordFocusNode,
                        showPassword: _showPassword,
                        rememberDevice: _rememberDevice,
                        isLoading: _isLoading,
                        isSuccess: _isSuccess,
                        errorMessage: _errorMessage,
                        onTogglePassword: () =>
                            setState(() => _showPassword = !_showPassword),
                        onRememberChanged: (value) =>
                            setState(() => _rememberDevice = value ?? false),
                        onLogin: _handleLogin,
                        onForgotPassword: _handleForgotPassword,
                      ),
                      const SizedBox(height: 20),
                      const _Divider(),
                      const SizedBox(height: 20),
                      const _BleQuickAuth(),
                      const SizedBox(height: 24),
                      const _VersionFooter(),
                    ],
                  ),
                ),
              ),
            ),
          ),
          const _CornerDecorations(),
        ],
      ),
    );
  }
}

class _BackgroundGradient extends StatelessWidget {
  const _BackgroundGradient();

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Color.fromARGB(255, 6, 62, 153),
            _kSlate700,
            _kSlate800,
            _kSlate900,
          ],
        ),
      ),
    );
  }
}

class _AnimatedGrid extends StatelessWidget {
  const _AnimatedGrid();

  @override
  Widget build(BuildContext context) {
    return Positioned.fill(
      child: IgnorePointer(
        child: Container(
          decoration: BoxDecoration(
            backgroundBlendMode: BlendMode.overlay,
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [_kAmber.withAlpha(5), Colors.transparent],
            ),
          ),
          child: const CustomPaint(painter: _GridPainter()),
        ),
      ),
    );
  }
}

class _GlowBlobs extends StatelessWidget {
  const _GlowBlobs();

  @override
  Widget build(BuildContext context) {
    return const Stack(
      children: [
        Positioned(top: -100, left: -50, child: _TopGlowBlob()),
        Positioned(bottom: -100, right: -50, child: _BottomGlowBlob()),
      ],
    );
  }
}

class _TopGlowBlob extends StatelessWidget {
  const _TopGlowBlob();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 200,
      height: 200,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: RadialGradient(
          colors: [
            _kSlate600.withAlpha(20),
            Colors.transparent,
            _kSlate900.withAlpha(90),
          ],
        ),
      ),
    );
  }
}

class _BottomGlowBlob extends StatelessWidget {
  const _BottomGlowBlob();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 350,
      height: 350,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: RadialGradient(
          colors: [_kPrimaryCyan.withAlpha(13), Colors.transparent],
        ),
      ),
    );
  }
}

class _LoginHeader extends StatelessWidget {
  const _LoginHeader();

  @override
  Widget build(BuildContext context) {
    return const Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Sign in',
          style: TextStyle(
            fontFamily: 'Rajdhani',
            fontSize: 24,
            fontWeight: FontWeight.bold,
            color: Colors.white,
          ),
        ),
        SizedBox(height: 4),
        Text(
          'Use your operator credentials to continue.',
          style: TextStyle(
            fontFamily: 'Rajdhani',
            fontSize: 11,
            color: _kSlate500,
          ),
        ),
      ],
    );
  }
}

class _LoginForm extends StatelessWidget {
  const _LoginForm({
    required this.formKey,
    required this.usernameController,
    required this.passwordController,
    required this.usernameFocusNode,
    required this.passwordFocusNode,
    required this.showPassword,
    required this.rememberDevice,
    required this.isLoading,
    required this.isSuccess,
    required this.errorMessage,
    required this.onTogglePassword,
    required this.onRememberChanged,
    required this.onLogin,
    required this.onForgotPassword,
  });

  final GlobalKey<FormState> formKey;
  final TextEditingController usernameController;
  final TextEditingController passwordController;
  final FocusNode usernameFocusNode;
  final FocusNode passwordFocusNode;
  final bool showPassword;
  final bool rememberDevice;
  final bool isLoading;
  final bool isSuccess;
  final String errorMessage;
  final VoidCallback onTogglePassword;
  final ValueChanged<bool?> onRememberChanged;
  final VoidCallback onLogin;
  final VoidCallback onForgotPassword;

  @override
  Widget build(BuildContext context) {
    return Form(
      key: formKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Username
          const _FormLabel(text: 'USERNAME'),
          const SizedBox(height: 6),
          TextFormField(
            controller: usernameController,
            focusNode: usernameFocusNode,
            style: const TextStyle(color: Colors.white),
            cursorColor: _kAmber,
            keyboardType: TextInputType.emailAddress,
            textInputAction: TextInputAction.next,
            onEditingComplete: () => passwordFocusNode.requestFocus(),
            decoration: _FormDecoration(
              prefixIcon: const Icon(Icons.person, size: 18, color: _kSlate500),
              hintText: 'admin@example.com',
            ),
          ),
          const SizedBox(height: 16),

          // Password
          const _FormLabel(text: 'PASSWORD'),
          const SizedBox(height: 6),
          TextFormField(
            controller: passwordController,
            focusNode: passwordFocusNode,
            obscureText: !showPassword,
            style: const TextStyle(color: Colors.white),
            cursorColor: _kAmber,
            keyboardType: TextInputType.visiblePassword,
            textInputAction: TextInputAction.done,
            onEditingComplete: onLogin,
            decoration: _PasswordFormDecoration(
              showPassword: showPassword,
              onTogglePassword: onTogglePassword,
            ),
          ),
          const SizedBox(height: 12),

          // Remember & Forgot
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              _RememberCheckbox(
                value: rememberDevice,
                onChanged: onRememberChanged,
              ),
              TextButton(
                onPressed: onForgotPassword,
                style: const ButtonStyle(
                  padding: WidgetStatePropertyAll(EdgeInsets.zero),
                  minimumSize: WidgetStatePropertyAll(Size.zero),
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                child: const Text(
                  'Forgot password?',
                  style: TextStyle(
                    fontFamily: 'Rajdhani',
                    fontSize: 11,
                    color: Color(0xB306B6D4),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),

          if (errorMessage.isNotEmpty) _ErrorMessage(message: errorMessage),

          if (isSuccess) const _SuccessMessage(),

          const SizedBox(height: 20),

          _LoginButton(
            isLoading: isLoading,
            isSuccess: isSuccess,
            onPressed: onLogin,
          ),
        ],
      ),
    );
  }
}

class _FormLabel extends StatelessWidget {
  const _FormLabel({required this.text});
  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: const TextStyle(
        fontFamily: 'Rajdhani',
        fontSize: 10,
        fontWeight: FontWeight.w600,
        color: _kSlate400,
        letterSpacing: 1,
      ),
    );
  }
}

class _FormDecoration extends InputDecoration {
  _FormDecoration({required Widget prefixIcon, required String hintText})
    : super(
        prefixIcon: prefixIcon,
        hintText: hintText,
        hintStyle: const TextStyle(color: _kSlate600, fontSize: 13),
        filled: true,
        fillColor: _kSlate800.withAlpha(153),
        border: const OutlineInputBorder(
          borderRadius: BorderRadius.all(Radius.circular(12)),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: const BorderRadius.all(Radius.circular(12)),
          borderSide: BorderSide(color: _kSlate700.withAlpha(153)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: const BorderRadius.all(Radius.circular(12)),
          borderSide: BorderSide(color: _kPrimaryCyan.withAlpha(153)),
        ),
        contentPadding: const EdgeInsets.symmetric(vertical: 14),
      );
}

class _PasswordFormDecoration extends InputDecoration {
  _PasswordFormDecoration({
    required this.showPassword,
    required this.onTogglePassword,
  }) : super(
         prefixIcon: const Icon(Icons.lock, size: 18, color: _kSlate500),
         suffixIcon: IconButton(
           icon: Icon(
             showPassword ? Icons.visibility_off : Icons.visibility,
             size: 18,
             color: _kSlate500,
           ),
           onPressed: onTogglePassword,
         ),
         hintText: '••••••••',
         hintStyle: const TextStyle(color: _kSlate600, fontSize: 13),
         filled: true,
         fillColor: _kSlate800.withAlpha(153),
         border: const OutlineInputBorder(
           borderRadius: BorderRadius.all(Radius.circular(12)),
           borderSide: BorderSide.none,
         ),
         enabledBorder: OutlineInputBorder(
           borderRadius: const BorderRadius.all(Radius.circular(12)),
           borderSide: BorderSide(color: _kSlate700.withAlpha(153)),
         ),
         focusedBorder: OutlineInputBorder(
           borderRadius: const BorderRadius.all(Radius.circular(12)),
           borderSide: BorderSide(color: _kPrimaryCyan.withAlpha(153)),
         ),
         contentPadding: const EdgeInsets.symmetric(vertical: 14),
       );

  final bool showPassword;
  final VoidCallback onTogglePassword;
}

class _RememberCheckbox extends StatelessWidget {
  const _RememberCheckbox({required this.value, required this.onChanged});

  final bool value;
  final ValueChanged<bool?> onChanged;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        SizedBox(
          width: 16,
          height: 16,
          child: Checkbox(
            value: value,
            onChanged: onChanged,
            materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
            visualDensity: VisualDensity.compact,
            activeColor: _kPrimaryCyan,
            side: const BorderSide(color: _kSlate600),
          ),
        ),
        const SizedBox(width: 6),
        const Text(
          'Remember device',
          style: TextStyle(
            fontFamily: 'Rajdhani',
            fontSize: 11,
            color: _kSlate500,
          ),
        ),
      ],
    );
  }
}

class _ErrorMessage extends StatelessWidget {
  const _ErrorMessage({required this.message});
  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Colors.red.withAlpha(26),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.red.withAlpha(51)),
      ),
      child: Row(
        children: [
          const Icon(Icons.warning_amber, size: 14, color: Colors.red),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              message,
              style: const TextStyle(
                fontFamily: 'Rajdhani',
                fontSize: 11,
                color: Colors.red,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SuccessMessage extends StatelessWidget {
  const _SuccessMessage();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: _kEmerald.withAlpha(26),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: _kEmerald.withAlpha(51)),
      ),
      child: const Row(
        children: [
          Icon(Icons.check_circle, size: 14, color: _kEmerald),
          SizedBox(width: 8),
          Expanded(
            child: Text(
              'Authenticated! Launching dashboard…',
              style: TextStyle(
                fontFamily: 'Rajdhani',
                fontSize: 11,
                color: _kEmerald,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _LoginButton extends StatelessWidget {
  const _LoginButton({
    required this.isLoading,
    required this.isSuccess,
    required this.onPressed,
  });

  final bool isLoading;
  final bool isSuccess;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      height: 48,
      child: ElevatedButton(
        onPressed: isLoading || isSuccess ? null : onPressed,
        style: ElevatedButton.styleFrom(
          backgroundColor: Colors.transparent,
          elevation: 0,
          padding: EdgeInsets.zero,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
        child: Container(
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [_kAmber, _kAmber],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Center(
            child: _LoginButtonContent(
              isLoading: isLoading,
              isSuccess: isSuccess,
            ),
          ),
        ),
      ),
    );
  }
}

class _LoginButtonContent extends StatelessWidget {
  const _LoginButtonContent({required this.isLoading, required this.isSuccess});

  final bool isLoading;
  final bool isSuccess;

  @override
  Widget build(BuildContext context) {
    if (isLoading) {
      return const SizedBox(
        width: 20,
        height: 20,
        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
      );
    }

    if (isSuccess) {
      return const Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.check_circle, size: 16),
          SizedBox(width: 8),
          Text('Access Granted'),
        ],
      );
    }

    return const Text(
      'Sign In to Dashboard',
      style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
    );
  }
}

class _Divider extends StatelessWidget {
  const _Divider();

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(child: Container(height: 1, color: _kSlate700.withAlpha(128))),
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: 12),
          child: Text(
            'or',
            style: TextStyle(
              fontFamily: 'Rajdhani',
              fontSize: 10,
              color: _kSlate600,
              letterSpacing: 1,
            ),
          ),
        ),
        Expanded(child: Container(height: 1, color: _kSlate700.withAlpha(128))),
      ],
    );
  }
}

class _BleQuickAuth extends StatelessWidget {
  const _BleQuickAuth();

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      height: 44,
      child: OutlinedButton(
        onPressed: null, // Disabled until BLE integration is implemented
        style: OutlinedButton.styleFrom(
          side: BorderSide(color: _kPrimaryCyan.withAlpha(77)),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
        child: const Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.bluetooth, size: 16, color: _kPrimaryCyan),
            SizedBox(width: 8),
            Text(
              'Authenticate via BLE Badge',
              style: TextStyle(
                fontFamily: 'Rajdhani',
                fontSize: 12,
                color: _kPrimaryCyan,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _VersionFooter extends StatelessWidget {
  const _VersionFooter();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Text(
        'PLCMonitor v1.0.0 • Industrial BLE Suite • INTELLIKRAN\n INTELLICONTROL © 2026',
        style: TextStyle(
          fontFamily: 'Rajdhani',
          fontSize: 11,
          color: _kSlate500,
        ),
      ),
    );
  }
}

class _CornerDecorations extends StatelessWidget {
  const _CornerDecorations();

  @override
  Widget build(BuildContext context) {
    return const Stack(
      children: [
        Positioned(bottom: 16, left: 16, child: _LeftCornerDecorations()),
        Positioned(top: 16, right: 16, child: _RightCornerDecorations()),
      ],
    );
  }
}

class _LeftCornerDecorations extends StatelessWidget {
  const _LeftCornerDecorations();

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(width: 40, height: 1, color: _kAmber.withAlpha(77)),
        Container(
          width: 28,
          height: 1,
          margin: const EdgeInsets.only(top: 4),
          color: _kAmber.withAlpha(77),
        ),
        Container(
          width: 16,
          height: 1,
          margin: const EdgeInsets.only(top: 4),
          color: _kAmber.withAlpha(77),
        ),
      ],
    );
  }
}

class _RightCornerDecorations extends StatelessWidget {
  const _RightCornerDecorations();

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Container(width: 16, height: 1, color: _kAmber.withAlpha(77)),
        Container(
          width: 28,
          height: 1,
          margin: const EdgeInsets.only(top: 4),
          color: _kAmber.withAlpha(77),
        ),
        Container(
          width: 40,
          height: 1,
          margin: const EdgeInsets.only(top: 4),
          color: _kAmber.withAlpha(77),
        ),
      ],
    );
  }
}

class _OfflineChip extends StatelessWidget {
  const _OfflineChip();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.red.withAlpha(20),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.red.withAlpha(60)),
      ),
      child: const Row(
        children: [
          Icon(Icons.wifi_off_rounded, size: 14, color: Colors.red),
          SizedBox(width: 8),
          Expanded(
            child: Text(
              'No internet connection. Check your network.',
              style: TextStyle(
                fontFamily: 'Rajdhani',
                fontSize: 11,
                color: Colors.red,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// class _NetworkRestoredChip extends StatelessWidget {
//   const _NetworkRestoredChip();

//   @override
//   Widget build(BuildContext context) {
//     return Container(
//       padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
//       decoration: BoxDecoration(
//         color: _kEmerald.withAlpha(20),
//         borderRadius: BorderRadius.circular(10),
//         border: Border.all(color: _kEmerald.withAlpha(60)),
//       ),
//       child: const Row(
//         children: [
//           Icon(Icons.wifi_rounded, size: 14, color: _kEmerald),
//           SizedBox(width: 8),
//           Expanded(
//             child: Text(
//               'Network available — please try again.',
//               style: TextStyle(
//                 fontFamily: 'Rajdhani',
//                 fontSize: 11,
//                 color: _kEmerald,
//               ),
//             ),
//           ),
//         ],
//       ),
//     );
//   }
// }

class _GridPainter extends CustomPainter {
  const _GridPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = _kAmber.withAlpha(8)
      ..strokeWidth = 0.5
      ..style = PaintingStyle.stroke;

    const spacing = 48.0;
    for (double x = 0; x < size.width; x += spacing) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), paint);
    }
    for (double y = 0; y < size.height; y += spacing) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
