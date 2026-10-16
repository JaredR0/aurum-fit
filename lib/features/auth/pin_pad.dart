import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/theme/app_theme.dart';

/// Teclado numérico propio: evita el teclado del sistema (y sus sugerencias,
/// historial o teclados de terceros que podrían registrar el PIN).
class PinPad extends StatelessWidget {
  const PinPad({
    super.key,
    required this.length,
    required this.maxLength,
    required this.onDigit,
    required this.onDelete,
    this.onBiometric,
    this.enabled = true,
  });

  final int length;
  final int maxLength;
  final ValueChanged<String> onDigit;
  final VoidCallback onDelete;
  final VoidCallback? onBiometric;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: List.generate(maxLength, (i) {
            final filled = i < length;
            return AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              margin: const EdgeInsets.symmetric(horizontal: 8),
              width: 14,
              height: 14,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: filled ? AurumColors.gold : Colors.transparent,
                border: Border.all(
                  color: filled ? AurumColors.gold : AurumColors.textMuted,
                  width: 1.5,
                ),
              ),
            );
          }),
        ),
        const SizedBox(height: 32),
        for (final row in const [
          ['1', '2', '3'],
          ['4', '5', '6'],
          ['7', '8', '9'],
        ])
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [for (final d in row) _key(context, d)],
          ),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            _iconKey(
              icon: Icons.fingerprint,
              onTap: onBiometric,
              tooltip: 'Usar biometría',
            ),
            _key(context, '0'),
            _iconKey(
              icon: Icons.backspace_outlined,
              onTap: enabled ? onDelete : null,
              tooltip: 'Borrar',
            ),
          ],
        ),
      ],
    );
  }

  Widget _key(BuildContext context, String digit) {
    return Padding(
      padding: const EdgeInsets.all(8),
      child: SizedBox(
        width: 72,
        height: 72,
        child: Material(
          color: AurumColors.surfaceHigh,
          shape: const CircleBorder(),
          child: InkWell(
            customBorder: const CircleBorder(),
            onTap: enabled && length < maxLength
                ? () {
                    HapticFeedback.selectionClick();
                    onDigit(digit);
                  }
                : null,
            child: Center(
              child: Text(
                digit,
                style: Theme.of(context)
                    .textTheme
                    .headlineSmall
                    ?.copyWith(fontWeight: FontWeight.w600),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _iconKey({
    required IconData icon,
    required VoidCallback? onTap,
    required String tooltip,
  }) {
    return Padding(
      padding: const EdgeInsets.all(8),
      child: SizedBox(
        width: 72,
        height: 72,
        // Sin Tooltip: la pantalla de bloqueo vive fuera del Navigator (sin Overlay).
        child: onTap == null
            ? const SizedBox.shrink()
            : Semantics(
                button: true,
                label: tooltip,
                child: InkWell(
                  customBorder: const CircleBorder(),
                  onTap: onTap,
                  child: Icon(icon, size: 28, color: AurumColors.textMuted),
                ),
              ),
      ),
    );
  }
}
