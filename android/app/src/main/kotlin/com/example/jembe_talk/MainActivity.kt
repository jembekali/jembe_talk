package com.example.jembe_talk

import android.content.Intent
import android.os.Bundle
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity: FlutterActivity() {
    private val CHANNEL = "app.channel.shared.data"
    private var sharedText: String? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler { call, result ->
            if (call.method == "getSharedText") {
                result.success(sharedText)
                sharedText = null
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
        handleIntent(intent)
    }

    private fun handleIntent(intent: Intent) {
        val action = intent.action
        val type = intent.type
        val data = intent.dataString // Iyi niyo Link (URL)

        // 1. Iyo ukoze SHARE (inyandiko cyangwa link uvuye ahandi)
        if (Intent.ACTION_SEND == action && type != null) {
            if ("text/plain" == type) {
                intent.getStringExtra(Intent.EXTRA_TEXT)?.let { text ->
                    sharedText = text
                }
            }
        }
        // 2. Iyo UKANZE KURI LINK (Deep Link: jembe-talk.web.app)
        // Ibi nibyo byari bibuze!
        else if (Intent.ACTION_VIEW == action && data != null) {
            sharedText = data
        }
    }
}