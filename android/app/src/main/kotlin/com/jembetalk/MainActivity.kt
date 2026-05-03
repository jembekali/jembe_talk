package com.jembetalk.app

import android.content.Intent
import android.os.Bundle
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.engine.FlutterShellArgs // 🔥 IYI NIYO TWONGEREYE
import io.flutter.plugin.common.MethodChannel

class MainActivity: FlutterActivity() {
    private val CHANNEL = "app.channel.shared.data"
    private var sharedData = mutableMapOf<String, String?>()

    // 🚀 OPTIMIZATION: Ibi bituma App yihuta kandi ntigire crash kuri S9
    // Twakuyemo "skia" renderer kugira ngo telefone ikoreshe uburyo bwayo bwihuta (Default Stable)
    override fun getFlutterShellArgs(): FlutterShellArgs {
        val args = super.getFlutterShellArgs()
        args.add("--disable-impeller") 
        return args
    }

    // 🔗 METHOD CHANNEL: Bituma Flutter ishobora gusoma amakuru ava hanze (Sharing)
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler { call, result ->
            if (call.method == "getSharedData") {
                result.success(sharedData)
                sharedData = mutableMapOf() 
            } else {
                result.notImplemented()
            }
        }
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        handleIntent(intent)
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
        val data = intent.dataString 

        if (Intent.ACTION_SEND == action && type != null) {
            if ("text/plain" == type) {
                intent.getStringExtra(Intent.EXTRA_TEXT)?.let { text ->
                    sharedData["type"] = "share"
                    sharedData["value"] = text
                }
            }
        }
        else if (Intent.ACTION_VIEW == action && data != null) {
            sharedData["type"] = "view"
            sharedData["value"] = data
        }
    }
}