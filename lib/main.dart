import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app.dart';
import 'core/security/secure_vault.dart';
import 'core/storage/local_db.dart';
import 'core/theme/app_theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);

  try {
    await LocalDb.init();
    runApp(const ProviderScope(child: AurumApp()));
  } catch (e) {
    // Ocurre si el Keystore perdió la llave (p. ej. tras restaurar el
    // teléfono): los datos cifrados ya no se pueden abrir.
    runApp(const _StorageErrorApp());
  }
}

class _StorageErrorApp extends StatelessWidget {
  const _StorageErrorApp();

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: AppTheme.dark(),
      home: Builder(
        builder: (context) => Scaffold(
          body: SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.lock_reset, size: 48, color: AurumColors.danger),
                  const SizedBox(height: 16),
                  const Text(
                    'No se pudo abrir la base de datos cifrada. La llave de este '
                    'teléfono ya no coincide con los datos guardados.',
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 24),
                  FilledButton(
                    onPressed: () async {
                      await LocalDb.nukeFromDisk();
                      await SecureVault.wipe();
                      await LocalDb.init();
                      runApp(const ProviderScope(child: AurumApp()));
                    },
                    child: const Text('Restablecer y empezar de nuevo'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
