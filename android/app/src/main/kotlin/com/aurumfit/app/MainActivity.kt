package com.aurumfit.app

import android.os.Bundle
import android.view.WindowManager
import io.flutter.embedding.android.FlutterFragmentActivity

// FlutterFragmentActivity es obligatoria para local_auth (biometría) y para
// el diálogo de permisos de Health Connect.
class MainActivity : FlutterFragmentActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        // Bloquea capturas de pantalla y oculta el contenido en "recientes":
        // la app guarda fotos corporales y datos biométricos.
        window.setFlags(
            WindowManager.LayoutParams.FLAG_SECURE,
            WindowManager.LayoutParams.FLAG_SECURE,
        )
    }
}
