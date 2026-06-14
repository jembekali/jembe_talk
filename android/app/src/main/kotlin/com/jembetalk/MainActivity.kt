package com.jembetalk.app

import android.content.Intent
import android.os.Bundle
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity: FlutterActivity() {
    private val CHANNEL = "app.channel.shared.data"
    private var sharedData = mutableMapOf<String, String?>()

    // 🚀 FIXED: Twakuyemo FlutterShellArgs kuko itera crash kuri Android 14+
    // Gukoresha Impeller cyangwa Skia ubu byamaze gukosorerwa muri AndroidManifest.xml

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        // 🔗 METHOD CHANNEL: Bituma Flutter ishobora gusoma amakuru ava hanze (Sharing)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler { call, result ->
            if (call.method == "getSharedData") {
                // Tanga data, hanyuma uyisibe muri memory kugira ngo itazagaruka kabiri
                val dataToSend = HashMap(sharedData)
                result.success(dataToSend)
                sharedData.clear() 
            } else {
                result.notImplemented()
            }
        }
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        // Genzura niba hari data yinjiye app igifunguka
        intent?.let { handleIntent(it) }
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent) 
        handleIntent(intent)
    }

    // 📂 INTENT HANDLER: Ibi bituma "Share to Jembe Talk" ikora neza
    private fun handleIntent(intent: Intent) {
        val action = intent.action
        val type = intent.type
        
        if (Intent.ACTION_SEND == action && type != null) {
            if ("text/plain" == type) {
                intent.getStringExtra(Intent.EXTRA_TEXT)?.let { text ->
                    sharedData["type"] = "share"
                    sharedData["value"] = text
                }
            }
        } else if (Intent.ACTION_VIEW == action) {
            val data = intent.dataString
            if (data != null) {
                sharedData["type"] = "view"
                sharedData["value"] = data
            }
        }
    }
}