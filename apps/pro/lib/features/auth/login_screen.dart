import 'package:flutter/material.dart';
import '../../widgets/shared/design_system/colors.dart';
import 'package:go_router/go_router.dart';
import '../../widgets/shared/design_system/tokens.dart';
import '../../widgets/shared/design_system/typography.dart';
import '../../widgets/shared/design_system/components.dart';
import '../../services/api_client.dart';
import '../../services/google_auth_service.dart';
import '../../services/biometric_auth_service.dart';
import '../../services/biometric_relogin.dart';
import '../../services/secure_credential_store.dart';
import '../../utils/error_messages.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({Key? key}) : super(key: key);

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _otpController = TextEditingController();
  final _apiClient = APIClient();
  bool _isLoading = false;
  bool _isGoogleLoading = false;
  bool _obscurePassword = true;
  // Set once login reports the account needs its OTP code verified — the
  // account genuinely has no session yet (registration doesn't issue one
  // until this step), so this replaces the form rather than just showing
  // an error.
  String? _pendingVerifyEmail;

  @override
  void initState() {
    super.initState();
    // If Biometric Unlock is enabled and a token is stored, prompt for the
    // fingerprint/face automatically. This screen is where an idle-timeout
    // sign-out lands, so the user shouldn't have to type a password.
    WidgetsBinding.instance.addPostFrameCallback((_) => _tryBiometricLogin());
  }

  Future<void> _tryBiometricLogin() async {
    if (!await BiometricAuthService.instance.isReady) return;
    if (await SecureCredentialStore.instance.readToken() == null) return;
    final ok = await BiometricRelogin.attempt(reason: 'Sign in to JKBMSR');
    if (!mounted) return;
    if (ok) context.go('/dashboard');
  }

  void _handleLogin() async {
    final email = _emailController.text.trim();
    final password = _passwordController.text;
    if (email.isEmpty || password.isEmpty) {
      JKBMSRToast.show(context, 'Please enter email and password', isError: true);
      return;
    }

    setState(() {
      _isLoading = true;
    });

    try {
      await _apiClient.login(email, password);
      if (mounted) {
        context.go('/dashboard');
        JKBMSRToast.show(context, 'Logged in successfully');
      }
    } on EmailVerificationRequiredException catch (e) {
      try {
        await _apiClient.requestOtpCode(e.email);
      } catch (_) {
        // Best-effort resend — registration already sent one, this is just
        // a fresh one in case the first expired. Ignore failures here so
        // the verify screen still shows; the user can tap "Resend code".
      }
      if (mounted) {
        setState(() {
          _pendingVerifyEmail = e.email;
        });
      }
    } catch (e) {
      if (mounted) {
        JKBMSRToast.show(
          context,
          friendlyErrorMessage(e),
          isError: true,
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  void _handleOtpVerify() async {
    final email = _pendingVerifyEmail;
    final code = _otpController.text.trim();
    if (email == null) return;
    if (code.length != 6) {
      JKBMSRToast.show(context, 'Enter the 6-digit code', isError: true);
      return;
    }

    setState(() {
      _isLoading = true;
    });

    try {
      await _apiClient.verifyOtpCode(email, code);
      if (mounted) {
        context.go('/dashboard');
        JKBMSRToast.show(context, 'Logged in successfully');
      }
    } catch (e) {
      if (mounted) {
        JKBMSRToast.show(
          context,
          friendlyErrorMessage(e),
          isError: true,
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  void _handleResendCode() async {
    final email = _pendingVerifyEmail;
    if (email == null) return;
    try {
      await _apiClient.requestOtpCode(email);
      if (mounted) {
        JKBMSRToast.show(context, 'Code resent');
      }
    } catch (e) {
      if (mounted) {
        JKBMSRToast.show(
          context,
          friendlyErrorMessage(e),
          isError: true,
        );
      }
    }
  }

  void _handleGoogleSignIn() async {
    setState(() {
      _isGoogleLoading = true;
    });

    try {
      final idToken = await GoogleAuthService.signInAndGetIdToken();
      if (idToken == null) {
        // User cancelled the account picker.
        return;
      }
      await _apiClient.loginWithGoogle(idToken);
      if (mounted) {
        context.go('/dashboard');
        JKBMSRToast.show(context, 'Logged in successfully');
      }
    } catch (e) {
      if (mounted) {
        // Common cause on sideloaded/debug builds: this app's package name
        // + signing-certificate SHA-1 isn't registered as an Android OAuth
        // client in Google Cloud Console, so the native flow fails with
        // ApiException code 10 (DEVELOPER_ERROR) before any account picker
        // appears. Email/password sign-in is unaffected.
        final message = e.toString().toLowerCase().contains('apiexception') ||
                e.toString().contains('code 10') ||
                e.toString().contains('DEVELOPER_ERROR')
            ? 'Google sign-in is not configured for this build. Use email and password instead.'
            : friendlyErrorMessage(e);
        JKBMSRToast.show(context, message, isError: true);
      }
    } finally {
      if (mounted) {
        setState(() {
          _isGoogleLoading = false;
        });
      }
    }
  }

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    _otpController.dispose();
    super.dispose();
  }

  Widget _buildLoginForm(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Image.asset(
          'assets/icon/icon.png',
          height: 64,
          width: 64,
        ),
        const SizedBox(height: JKBMSRTokens.space16),
        Text(
          'JKBMSR Pro',
          textAlign: TextAlign.center,
          style: JKBMSRTypography.pageHeading.copyWith(
            color: context.colors.accent,
            letterSpacing: 2.0,
          ),
        ),
        const SizedBox(height: JKBMSRTokens.space8),
        Text(
          'Remote Monitoring for JK-BMS',
          textAlign: TextAlign.center,
          style: JKBMSRTypography.bodySecondary,
        ),
        const SizedBox(height: JKBMSRTokens.space32),
        TextField(
          controller: _emailController,
          decoration: InputDecoration(
            labelText: 'Email Address',
            prefixIcon: Icon(Icons.email_outlined, color: context.colors.textMuted),
          ),
          keyboardType: TextInputType.emailAddress,
          textInputAction: TextInputAction.next,
        ),
        const SizedBox(height: JKBMSRTokens.space16),
        TextField(
          controller: _passwordController,
          decoration: InputDecoration(
            labelText: 'Password',
            prefixIcon: Icon(Icons.lock_outlined, color: context.colors.textMuted),
            suffixIcon: IconButton(
              icon: Icon(
                _obscurePassword ? Icons.visibility_outlined : Icons.visibility_off_outlined,
                color: context.colors.textMuted,
              ),
              tooltip: _obscurePassword ? 'Show password' : 'Hide password',
              onPressed: () {
                setState(() {
                  _obscurePassword = !_obscurePassword;
                });
              },
            ),
          ),
          obscureText: _obscurePassword,
          textInputAction: TextInputAction.done,
          onSubmitted: (_) => _handleLogin(),
        ),
        const SizedBox(height: JKBMSRTokens.space24),
        _isLoading
            ? Center(child: CircularProgressIndicator(color: context.colors.accent))
            : ElevatedButton(
                onPressed: _handleLogin,
                child: const Text('Sign In'),
              ),
        const SizedBox(height: JKBMSRTokens.space24),
        Row(
          children: [
            Expanded(child: Divider(color: context.colors.line)),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: JKBMSRTokens.space8),
              child: Text(
                'OR',
                style: JKBMSRTypography.bodySecondary,
              ),
            ),
            Expanded(child: Divider(color: context.colors.line)),
          ],
        ),
        const SizedBox(height: JKBMSRTokens.space16),
        OutlinedButton.icon(
          onPressed: _isGoogleLoading ? null : _handleGoogleSignIn,
          icon: _isGoogleLoading
              ? SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: context.colors.accent,
                  ),
                )
              : const Icon(Icons.g_mobiledata, size: 28),
          label: const Text('Sign in with Google'),
          style: OutlinedButton.styleFrom(
            padding: const EdgeInsets.symmetric(vertical: JKBMSRTokens.space12),
            side: BorderSide(color: context.colors.line),
          ),
        ),
      ],
    );
  }

  Widget _buildOtpVerifyForm(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Icon(Icons.mark_email_read_outlined, size: 48, color: context.colors.accent),
        const SizedBox(height: JKBMSRTokens.space16),
        Text(
          'Verify your email',
          textAlign: TextAlign.center,
          style: JKBMSRTypography.pageHeading.copyWith(color: context.colors.accent),
        ),
        const SizedBox(height: JKBMSRTokens.space8),
        Text(
          'Enter the 6-digit code we sent to ${_pendingVerifyEmail ?? ''}.',
          textAlign: TextAlign.center,
          style: JKBMSRTypography.bodySecondary,
        ),
        const SizedBox(height: JKBMSRTokens.space24),
        TextField(
          controller: _otpController,
          decoration: InputDecoration(
            labelText: 'Verification code',
            prefixIcon: Icon(Icons.password_outlined, color: context.colors.textMuted),
          ),
          keyboardType: TextInputType.number,
          textInputAction: TextInputAction.done,
          maxLength: 6,
          textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 22, letterSpacing: 8),
          onSubmitted: (_) => _handleOtpVerify(),
        ),
        _isLoading
            ? Center(child: CircularProgressIndicator(color: context.colors.accent))
            : ElevatedButton(
                onPressed: _handleOtpVerify,
                child: const Text('Verify & Sign In'),
              ),
        const SizedBox(height: JKBMSRTokens.space8),
        TextButton(
          onPressed: _handleResendCode,
          child: const Text('Resend code'),
        ),
        TextButton(
          onPressed: () {
            setState(() {
              _pendingVerifyEmail = null;
              _otpController.clear();
            });
          },
          child: const Text('Back to sign in'),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: context.colors.canvas,
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(JKBMSRTokens.space24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 400),
            child: Card(
              child: Padding(
                padding: const EdgeInsets.all(JKBMSRTokens.space32),
                child: _pendingVerifyEmail != null ? _buildOtpVerifyForm(context) : _buildLoginForm(context),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
