import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../widgets/shared/design_system/colors.dart';
import '../../../widgets/shared/design_system/tokens.dart';

/// Six digits, one box each.
///
/// A single field with `maxLength: 6` technically works, but it reads as a
/// generic input and hides the one thing the user has to get right: the count.
/// Separated boxes make "six digits" visible, advance on their own, and accept a
/// paste from a code they copied out of the flasher console.
class SetupCodeField extends StatefulWidget {
  const SetupCodeField({
    super.key,
    required this.onChanged,
    this.autofocus = true,
  });

  static const length = 6;

  final ValueChanged<String> onChanged;
  final bool autofocus;

  @override
  State<SetupCodeField> createState() => SetupCodeFieldState();
}

class SetupCodeFieldState extends State<SetupCodeField> {
  final _controllers = List.generate(
    SetupCodeField.length,
    (_) => TextEditingController(),
  );
  final _focusNodes = List.generate(
    SetupCodeField.length,
    (_) => FocusNode(),
  );

  String get code => _controllers.map((c) => c.text).join();

  @override
  void initState() {
    super.initState();
    for (final node in _focusNodes) {
      node.addListener(() => setState(() {}));
    }
  }

  @override
  void dispose() {
    for (final controller in _controllers) {
      controller.dispose();
    }
    for (final node in _focusNodes) {
      node.dispose();
    }
    super.dispose();
  }

  void _handleChanged(int index, String value) {
    // A paste arrives as one long string in whichever box had focus.
    if (value.length > 1) {
      _distribute(value, from: index);
      return;
    }
    if (value.isNotEmpty && index < SetupCodeField.length - 1) {
      _focusNodes[index + 1].requestFocus();
    }
    _emit();
  }

  void _distribute(String digits, {required int from}) {
    final cleaned = digits.replaceAll(RegExp(r'\D'), '');
    for (var i = 0; i < cleaned.length && from + i < SetupCodeField.length; i++) {
      _controllers[from + i].text = cleaned[i];
    }
    final next = (from + cleaned.length).clamp(0, SetupCodeField.length - 1);
    _focusNodes[next].requestFocus();
    // The paste lands in the first box; a second paste in the same box would
    // otherwise append rather than replace.
    _emit();
  }

  void _emit() {
    widget.onChanged(code);
  }

  KeyEventResult _handleKey(int index, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    if (event.logicalKey != LogicalKeyboardKey.backspace) {
      return KeyEventResult.ignored;
    }
    // Backspace in an empty box moves back and clears the previous one, which is
    // what every code-entry field does and what people expect.
    if (_controllers[index].text.isEmpty && index > 0) {
      _controllers[index - 1].clear();
      _focusNodes[index - 1].requestFocus();
      _emit();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<JKBMSRColors>()!;
    return Semantics(
      label: 'Six digit setup code',
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          for (var i = 0; i < SetupCodeField.length; i++)
            Flexible(
              child: Padding(
                padding: EdgeInsets.only(
                  right: i == SetupCodeField.length - 1
                      ? 0
                      : JKBMSRTokens.space8,
                ),
                child: Focus(
                  onKeyEvent: (node, event) => _handleKey(i, event),
                  child: AspectRatio(
                    aspectRatio: 0.82,
                    child: TextField(
                      controller: _controllers[i],
                      focusNode: _focusNodes[i],
                      autofocus: widget.autofocus && i == 0,
                      textAlign: TextAlign.center,
                      keyboardType: TextInputType.number,
                      textInputAction: TextInputAction.next,
                      maxLength: SetupCodeField.length,
                      style: const TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.w600,
                        letterSpacing: 1,
                        fontFeatures: [FontFeature.tabularFigures()],
                      ),
                      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                      decoration: InputDecoration(
                        counterText: '',
                        filled: true,
                        fillColor: _controllers[i].text.isEmpty
                            ? colors.inset
                            : colors.accent.withValues(alpha: 0.10),
                        contentPadding: EdgeInsets.zero,
                        enabledBorder: OutlineInputBorder(
                          borderRadius:
                              BorderRadius.circular(JKBMSRTokens.radius12),
                          borderSide: BorderSide(color: colors.line),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius:
                              BorderRadius.circular(JKBMSRTokens.radius12),
                          borderSide: BorderSide(
                            color: colors.accent,
                            width: 1.6,
                          ),
                        ),
                      ),
                      onChanged: (value) => _handleChanged(i, value),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
