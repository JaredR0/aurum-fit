# iOS

El código Dart ya es compatible con iOS (HealthKit, Keychain, Face ID, voz con atenuación de la música). Lo que falta es la carpeta `ios/` y la firma de Apple.

## Requisitos

- Una Mac con Xcode 16+.
- Cuenta [Apple Developer Program](https://developer.apple.com/programs/) (99 USD/año). Sin ella no hay forma de instalar en iPhones de otras personas fuera de la App Store: ni `.ipa` ad-hoc, ni TestFlight, ni Firebase App Distribution. Expo Go tampoco aplica: es solo para proyectos React Native y no soporta HealthKit ni pinning.

## 1. Generar la carpeta iOS

```bash
flutter create --platforms=ios --org com.aurumfit .
```

No sobrescribe nada de `lib/` ni de `android/`.

## 2. Permisos en `ios/Runner/Info.plist`

Agrega dentro de `<dict>`:

```xml
<key>NSHealthShareUsageDescription</key>
<string>Leemos tus pasos para medir tu meta diaria. No salen del teléfono.</string>
<key>NSHealthUpdateUsageDescription</key>
<string>Aurum Fit no escribe datos en Salud.</string>
<key>NSMotionUsageDescription</key>
<string>Usamos el sensor de movimiento para contar tus pasos.</string>
<key>NSFaceIDUsageDescription</key>
<string>Desbloquea Aurum Fit con Face ID.</string>
<key>NSCameraUsageDescription</key>
<string>Para tomar fotos de progreso que se guardan cifradas en la app.</string>
<key>NSPhotoLibraryUsageDescription</key>
<string>Para elegir fotos de progreso que se guardan cifradas en la app.</string>
```

En Xcode: *Runner → Signing & Capabilities → + Capability → HealthKit*.

En `ios/Podfile` descomenta `platform :ios, '14.0'`.

## 3. Distribución por enlace (TestFlight)

1. Crea la app en [App Store Connect](https://appstoreconnect.apple.com/) con el bundle id `com.aurumfit.app`.
2. `flutter build ipa --release --dart-define=PROXY_URL=https://…`
3. Sube `build/ios/ipa/*.ipa` con la app **Transporter**.
4. En TestFlight → *External Testing* activa un **enlace público**: cualquiera lo abre en su iPhone, instala TestFlight y luego la app (hasta 10 000 personas, la primera vez Apple revisa el build en ~1 día).

Para automatizarlo en GitHub Actions hace falta un job en `macos-latest` con los certificados y el perfil de aprovisionamiento como Secrets (`fastlane match` o `apple-actions/import-codesign-certs`). Se puede agregar cuando tengas la cuenta de Apple.
