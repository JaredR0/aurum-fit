import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_theme.dart';
import 'auth_controller.dart';
import 'pin_pad.dart';

/// Creación del PIN (primer arranque o cambio de PIN desde Ajustes).
class PinSetupScreen extends ConsumerStatefulWidget {
  const PinSetupScreen({super.key, this.isChange = false});

  final bool isChange;

  @override
  ConsumerState<PinSetupScreen> createState() => _PinSetupScreenState();
}

class _PinSetupScreenState extends ConsumerState<PinSetupScreen> {
  static const int _pinLength = 6;
  String _first = '';
  String _second = '';
  bool _confirming = false;
  bool _useBiometrics = true;
  bool _saving = false;
  String? _error;

  String get _current => _confirming ? _second : _first;

  Future<void> _onDigit(String d) async {
    setState(() {
      _error = null;
      if (_confirming) {
        _second += d;
      } else {
        _first += d;
      }
    });

    if (!_confirming && _first.length == _pinLength) {
      if (_isTrivial(_first)) {
        setState(() {
          _error = 'Ese PIN es muy fácil de adivinar';
          _first = '';
        });
        return;
      }
      setState(() => _confirming = true);
      return;
    }

    if (_confirming && _second.length == _pinLength) {
      if (_second != _first) {
        setState(() {
          _error = 'Los PIN no coinciden. Empieza de nuevo.';
          _first = '';
          _second = '';
          _confirming = false;
        });
        return;
      }
      setState(() => _saving = true);
      await ref
          .read(authProvider.notifier)
          .setPin(_first, enableBiometrics: _useBiometrics);
      if (!mounted) return;
      if (widget.isChange) Navigator.of(context).pop();
    }
  }

  /// Rechaza 000000, 123456, 654321, etc.
  bool _isTrivial(String pin) {
    final allSame = pin.split('').toSet().length == 1;
    const asc = '0123456789';
    const desc = '9876543210';
    return allSame || asc.contains(pin) || desc.contains(pin);
  }

  @override
  Widget build(BuildContext context) {
    final auth = ref.watch(authProvider);

    return Scaffold(
      appBar: widget.isChange ? AppBar(title: const Text('Cambiar PIN')) : null,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.shield_outlined,
                    size: 44, color: AurumColors.gold),
                const SizedBox(height: 16),
                Text(
                  _confirming ? 'Confirma tu PIN' : 'Crea un PIN de 6 dígitos',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 8),
                Text(
                  _error ??
                      'Protege tus datos biométricos y fotos. Todo se guarda cifrado solo en este teléfono.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: _error != null
                        ? AurumColors.danger
                        : AurumColors.textMuted,
                  ),
                ),
                const SizedBox(height: 28),
                if (_saving)
                  const CircularProgressIndicator()
                else
                  PinPad(
                    length: _current.length,
                    maxLength: _pinLength,
                    onDigit: _onDigit,
                    onDelete: () => setState(() {
                      if (_confirming && _second.isNotEmpty) {
                        _second = _second.substring(0, _second.length - 1);
                      } else if (!_confirming && _first.isNotEmpty) {
                        _first = _first.substring(0, _first.length - 1);
                      }
                    }),
                  ),
                if (auth.biometricsAvailable) ...[
                  const SizedBox(height: 16),
                  SwitchListTile(
                    value: _useBiometrics,
                    onChanged: (v) => setState(() => _useBiometrics = v),
                    title: const Text('Desbloquear con huella o rostro'),
                    contentPadding: EdgeInsets.zero,
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
