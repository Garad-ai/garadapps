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

    OnCreate {
      AgentController.onNotice = PageBridge::notice
    }

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

    /** True when the user has given Garad notification access (messages and calls). */
    Function("isNotificationAccessEnabled") {
      val component = ComponentName(context, GaradNotificationListener::class.java).flattenToString()
      Settings.Secure.getString(context.contentResolver, "enabled_notification_listeners")
        ?.split(':')?.any { it.equals(component, ignoreCase = true) } ?: false
    }

    Function("openNotificationSettings") {
      val intent = Intent(Settings.ACTION_NOTIFICATION_LISTENER_SETTINGS).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
      context.startActivity(intent)
    }

    /** Whether new messages and calls are read aloud while Garad Voice is closed (off by default). */
    Function("getAnnounceAloud") {
      GaradNotificationListener.announceAloud(context)
    }

    Function("setAnnounceAloud") { value: Boolean ->
      GaradNotificationListener.setAnnounceAloud(context, value)
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

    /** A screen action from Garad Voice: read_screen, tap, type_text, scroll, phone_button, confirm_action, stop. */
    AsyncFunction("perform") { name: String, args: Map<String, Any?> ->
      AgentController.perform(name, args)
    }

    /** Runs a script in the Garad web page, also while the app is in the background. */
    Function("evaluateInPage") { script: String ->
      PageBridge.remember(appContext.currentActivity)
      PageBridge.evaluate(script)
      Unit
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
