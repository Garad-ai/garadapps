package ai.garad.agent

import android.accessibilityservice.AccessibilityService
import android.content.Intent
import android.view.accessibility.AccessibilityEvent

/**
 * The Garad agent's accessibility service. The user turns it on in the phone's
 * Accessibility settings after the in-app consent screen. Milestone 1 only reads the
 * active window when the app asks; it does not watch events or act on the screen.
 */
class GaradAccessibilityService : AccessibilityService() {
  override fun onServiceConnected() {
    super.onServiceConnected()
    instance = this
  }

  override fun onAccessibilityEvent(event: AccessibilityEvent?) = Unit

  override fun onInterrupt() = Unit

  override fun onUnbind(intent: Intent?): Boolean {
    instance = null
    return super.onUnbind(intent)
  }

  override fun onDestroy() {
    instance = null
    super.onDestroy()
  }

  fun readScreen(): Map<String, Any?> = ScreenReader.read(rootInActiveWindow)

  companion object {
    /** The running service, or null while it is turned off. */
    @Volatile
    var instance: GaradAccessibilityService? = null
      private set
  }
}
