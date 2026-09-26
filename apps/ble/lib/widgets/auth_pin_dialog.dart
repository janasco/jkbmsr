import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'motion_kit.dart';

class AuthPinDialog extends StatefulWidget {
  final String target; // 'CONTROL' or 'SETTINGS'
  /// Returns true if [pin] is correct. The dialog shows an inline error and
  /// stays open on false instead of unlocking.
  final Future<bool> Function(String pin) onVerifyPin;
  final ValueChanged<String> onVerified;
  final VoidCallback onDismiss;

  const AuthPinDialog({
    super.key,
    required this.target,
    required this.onVerifyPin,
    required this.onVerified,
    required this.onDismiss,
  });

  @override
  State<AuthPinDialog> createState() => _AuthPinDialogState();
}

class _AuthPinDialogState extends State<AuthPinDialog>
    with SingleTickerProviderStateMixin {
  final TextEditingController _pinController = TextEditingController();
  String? _errorMessage;
  bool _verifying = false;

  // Drives the horizontal shake when a wrong PIN is rejected — a physical
  // "no" that reads instantly, instead of a text-only error.
  late final AnimationController _shakeController;

  @override
  void initState() {
    super.initState();
    _shakeController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 420),
    );
  }

  @override
  void dispose() {
    _shakeController.dispose();
    _pinController.dispose();
    super.dispose();
  }

  void _shake() {
    _shakeController.forward(from: 0);
  }

  Future<void> _submit() async {
    final pin = _pinController.text.trim();
    if (pin.isEmpty) return;
    setState(() {
      _verifying = true;
      _errorMessage = null;
    });
    final ok = await widget.onVerifyPin(pin);
    if (!mounted) return;
    if (ok) {
      widget.onVerified(pin);
    } else {
      setState(() {
        _verifying = false;
        _errorMessage = 'Incorrect PIN. Try again.';
      });
      _shake();
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 24),
      child: StaggerIn(
        stepMs: 50,
        children: [
          AnimatedBuilder(
            animation: _shakeController,
            builder: (context, child) {
              // 2.5 damped oscillation: two full side-to-side swings that
              // decay to rest.
              final t = _shakeController.value;
              // 1.5 decaying oscillations: a quick physical "no" that
              // settles instead of a text-only error.
              final dx =
                  t == 0.0 ? 0.0 : math.sin(t * 3 * math.pi) * 10 * (1 - t);
              return Transform.translate(offset: Offset(dx, 0), child: child);
            },
            child: Container(
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF131A20) : const Color(0xFFFFFFFF),
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: isDark ? const Color(0xFF1E2830) : const Color(0xFFE2E8F0)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.6),
              blurRadius: 28,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 52,
              height: 52,
              decoration: BoxDecoration(
                color: const Color(0xFF10B981).withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: const Color(0xFF10B981).withValues(alpha: 0.3)),
              ),
              child: const Icon(Icons.lock_outline_rounded, color: Color(0xFF10B981), size: 28),
            ),
            const SizedBox(height: 14),
            Text(
              widget.target == 'CONTROL' ? 'Unlock Controls' : 'Unlock Settings',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: isDark ? const Color(0xFFF1F5F9) : const Color(0xFF0F172A)),
            ),
            const SizedBox(height: 6),
            const Text(
              'Enter JKBMS security PIN to modify parameters (Default: 1234)',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 12, color: Color(0xFF64748B), height: 1.4),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _pinController,
              obscureText: true,
              keyboardType: TextInputType.number,
              autofocus: true,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                letterSpacing: 8,
                color: isDark ? const Color(0xFFF1F5F9) : const Color(0xFF0F172A),
              ),
              decoration: InputDecoration(
                filled: true,
                fillColor: isDark ? const Color(0xFF1E2830) : const Color(0xFFF1F5F9),
                hintText: 'PIN Code',
                hintStyle: const TextStyle(letterSpacing: 0, fontSize: 13, color: Color(0xFF64748B)),
                contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: BorderSide(color: isDark ? const Color(0xFF1E2830) : const Color(0xFFE2E8F0)),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: const BorderSide(color: Color(0xFF10B981), width: 1.5),
                ),
              ),
            ),
            if (_errorMessage != null) ...[
              const SizedBox(height: 8),
              Text(
                _errorMessage!,
                style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Color(0xFFEF4444)),
              ),
            ],
            const SizedBox(height: 20),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    style: OutlinedButton.styleFrom(
                      foregroundColor: const Color(0xFF64748B),
                      side: const BorderSide(color: Color(0xFF1E2830)),
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                    ),
                    onPressed: widget.onDismiss,
                    child: const Text('CANCEL', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF10B981),
                      foregroundColor: const Color(0xFF090D10),
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                      shadowColor: const Color(0xFF10B981).withValues(alpha: 0.4),
                      elevation: 4,
                    ),
                    onPressed: _verifying ? null : _submit,
                    child: _verifying
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFF090D10)),
                          )
                        : const Text('UNLOCK', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w900)),
                  ),
                ),
              ],
            ),
          ],
        ),
          ),
          ),
        ],
      ),
    );
  }
}
