package ai.garad.agent

import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Handler
import android.os.Looper
import android.provider.Settings
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.embedding.engine.plugins.activity.ActivityAware
import io.flutter.embedding.engine.plugins.activity.ActivityPluginBinding
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.util.concurrent.Executors

/**
 * Dart API for the Garad agent (see lib/garad_agent.dart). Replaces the Expo module of the
 * React Native app; the agent itself (AgentController, the services, PageBridge) is unchanged.
 */
class GaradAgentPlugin : FlutterPlugin, MethodChannel.MethodCallHandler, ActivityAware {
  private lateinit var channel: MethodChannel
  private lateinit var context: Context
  private val main = Handler(Looper.getMainLooper())

  /** Screen actions block while they wait for the screen to settle, so they run off the main thread. */
  private val worker = Executors.newSingleThreadExecutor()

  override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
    context = binding.applicationContext
    channel = MethodChannel(binding.binaryMessenger, "ai.garad/agent")
    channel.setMethodCallHandler(this)
    AgentController.onNotice = PageBridge::notice
  }

  override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
    channel.setMethodCallHandler(null)
  }

  override fun onAttachedToActivity(binding: ActivityPluginBinding) = PageBridge.remember(binding.activity)
  override fun onReattachedToActivityForConfigChanges(binding: ActivityPluginBinding) = PageBridge.remember(binding.activity)
  override fun onDetachedFromActivityForConfigChanges() = Unit
  override fun onDetachedFromActivity() = Unit

  override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
    when (call.method) {
      "isEnabled" -> result.success(isServiceEnabled())
      "isConnected" -> result.success(GaradAccessibilityService.instance != null)
      "openSettings" -> {
        startSettings(Intent(Settings.ACTION_ACCESSIBILITY_SETTINGS))
        result.success(null)
      }
      "isNotificationAccessEnabled" -> {
        val component = ComponentName(context, GaradNotificationListener::class.java).flattenToString()
        result.success(
          Settings.Secure.getString(context.contentResolver, "enabled_notification_listeners")
            ?.split(':')?.any { it.equals(component, ignoreCase = true) } ?: false
        )
      }
      "openNotificationSettings" -> {
        startSettings(Intent(Settings.ACTION_NOTIFICATION_LISTENER_SETTINGS))
        result.success(null)
      }
      /** The app's own page in the phone settings (Voice: "open settings"). */
      "openAppSettings" -> {
        startSettings(
          Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS, Uri.parse("package:${context.packageName}"))
        )
        result.success(null)
      }
      "getAnnounceAloud" -> result.success(GaradNotificationListener.announceAloud(context))
      "setAnnounceAloud" -> {
        GaradNotificationListener.setAnnounceAloud(context, call.arguments as? Boolean ?: false)
        result.success(null)
      }
      "disable" -> {
        GaradAccessibilityService.instance?.disableSelf()
        result.success(null)
      }
      /** The delay runs natively so the user can switch to another app first. */
      "readScreen" -> {
        val delay = ((call.arguments as? Number)?.toLong() ?: 0L).coerceIn(0L, 30_000L)
        main.postDelayed({
          result.success(
            GaradAccessibilityService.instance?.readScreen()
              ?: mapOf<String, Any?>("available" to false, "reason" to "not_enabled")
          )
        }, delay)
      }
      "perform" -> {
        val name = call.argument<String>("name") ?: return result.error("args", "name is missing", null)
        val args = call.argument<Map<String, Any?>>("args") ?: emptyMap()
        worker.execute {
          val outcome = try {
            AgentController.perform(name, args)
          } catch (error: Exception) {
            mapOf("ok" to false, "message" to "The action failed on the phone.")
          }
          main.post { result.success(outcome) }
        }
      }
      /** Runs a script in the Garad web page, also while the app is in the background. */
      "evaluateInPage" -> {
        PageBridge.evaluate(call.arguments as? String ?: "")
        result.success(true)
      }
      else -> result.notImplemented()
    }
  }

  private fun startSettings(intent: Intent) {
    context.startActivity(intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
  }

  private fun isServiceEnabled(): Boolean {
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
