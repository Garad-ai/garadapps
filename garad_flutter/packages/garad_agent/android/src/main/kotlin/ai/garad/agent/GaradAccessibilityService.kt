package ai.garad.agent

import android.accessibilityservice.AccessibilityService
import android.content.Intent
import android.content.pm.PackageManager
import android.os.SystemClock
import android.view.accessibility.AccessibilityEvent

/**
 * The Garad agent's accessibility service. The user turns it on in the phone's
 * Accessibility settings after the in-app consent screen. It reads the active window and acts
 * on it only when Garad Voice asks (see AgentController); events are only used to tell when
 * an app has finished changing its screen.
 */
class GaradAccessibilityService : AccessibilityService() {
  @Volatile private var lastEventAt = 0L

  override fun onServiceConnected() {
    super.onServiceConnected()
    instance = this
    AgentController.attach(this)
  }

  override fun onAccessibilityEvent(event: AccessibilityEvent?) {
    lastEventAt = SystemClock.elapsedRealtime()
  }

  override fun onInterrupt() = Unit

  override fun onUnbind(intent: Intent?): Boolean {
    release()
    return super.onUnbind(intent)
  }

  override fun onDestroy() {
    release()
    super.onDestroy()
  }

  private fun release() {
    if (instance === this) {
      instance = null
      AgentController.detach()
    }
  }

  fun readScreen(): Map<String, Any?> = ScreenReader.read(rootInActiveWindow)

  /** Waits until the screen has stopped changing for a moment (at most `maxMs`). */
  fun waitForIdle(quietMs: Long = 400, maxMs: Long = 2500) {
    val start = SystemClock.elapsedRealtime()
    SystemClock.sleep(250)
    while (SystemClock.elapsedRealtime() - start < maxMs) {
      if (SystemClock.elapsedRealtime() - lastEventAt >= quietMs) return
      SystemClock.sleep(100)
    }
  }

  /** "WhatsApp" for com.whatsapp, or null when the app is unknown. */
  fun appLabel(packageName: String?): String? {
    if (packageName == null) return null
    return try {
      packageManager.getApplicationLabel(packageManager.getApplicationInfo(packageName, 0)).toString()
    } catch (_: PackageManager.NameNotFoundException) {
      null
    }
  }

  companion object {
    /** The running service, or null while it is turned off. */
    @Volatile
    var instance: GaradAccessibilityService? = null
      private set
  }
}
