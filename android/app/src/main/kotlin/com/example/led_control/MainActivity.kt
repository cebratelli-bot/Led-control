package com.example.led_control

import android.content.Context
import android.net.ConnectivityManager
import android.net.NetworkCapabilities
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

// Quando o celular está na rede da fita (sem internet), o Android manda o
// tráfego pelos dados móveis. Aqui forçamos o app a usar o Wi-Fi.
class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "led_control/net")
            .setMethodCallHandler { call, result ->
                val cm = getSystemService(Context.CONNECTIVITY_SERVICE) as ConnectivityManager
                when (call.method) {
                    "bindWifi" -> {
                        @Suppress("DEPRECATION")
                        val wifi = cm.allNetworks.firstOrNull {
                            cm.getNetworkCapabilities(it)
                                ?.hasTransport(NetworkCapabilities.TRANSPORT_WIFI) == true
                        }
                        result.success(wifi != null && cm.bindProcessToNetwork(wifi))
                    }
                    "unbind" -> result.success(cm.bindProcessToNetwork(null))
                    else -> result.notImplemented()
                }
            }
    }
}
