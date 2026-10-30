package ai.garad.agent

import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.os.Handler
import android.os.Looper
import android.provider.Settings
import expo.modules.kotlin.Promise
import expo.modules.kotlin.modules.Module
import expo.modules.kotlin.modules.ModuleDefinition

/** JS API for the Garad agent (see modules/garad-agent/index.ts). */
class GaradAgentModule : Module() {
  private val context: Context
    get() = requireNotNull(appContext.reactContext) { "React context is not available" }

  override fun definition() = ModuleDefinition {
    Name("GaradAgent")

    /** True when the user has turned the service on in Accessibility settings. */
    Function("isEnabled") {
      isServiceEnabled(context)
    }

    /** True when the service is on and connected to the app right now. */
    Function("isConnected") {
      GaradAccessibilityService.instance != null
    }

    Function("openSettings") {
      val intent = Intent(Settings.ACTION_ACCESSIBILITY_SETTINGS).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
      context.startActivity(intent)
    }

    /** Turns the service off without leaving the app. Turning it on needs the settings screen. */
    Function("disable") {
      GaradAccessibilityService.instance?.disableSelf()
      Unit
    }

    /**
     * The visible elements of the app in front, or a reason it cannot be read. The delay runs
     * natively because JS timers pause while Garad is in the background, which is exactly
     * when the user wants another app read.
     */
    AsyncFunction("readScreen") { delayMs: Int?, promise: Promise ->
      Handler(Looper.getMainLooper()).postDelayed({
        val service = GaradAccessibilityService.instance
        promise.resolve(
          service?.readScreen() ?: mapOf<String, Any?>("available" to false, "reason" to "not_enabled")
        )
      }, (delayMs ?: 0).coerceIn(0, 30_000).toLong())
    }
  }

  private fun isServiceEnabled(context: Context): Boolean {
    val component = ComponentName(context, GaradAccessibilityService::class.java)
    val enabled = Settings.Secure.getString(
      context.contentResolver,
      Settings.Secure.ENABLED_ACCESSIBILITY_SERVICES,
    ) ?: return false
    return enabled.split(':').any {
      it.equals(component.flattenToString(), ignoreCase = true) ||
        it.equals(component.flattenToShortString(), ignoreCase = true)
    }
  }
}
