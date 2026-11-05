package ai.garad.agent

import android.accessibilityservice.AccessibilityService
import android.os.Bundle
import android.os.SystemClock
import android.view.accessibility.AccessibilityNodeInfo

/**
 * Carries out the screen actions Garad Voice asks for (see GARAD_AGENT_TOOLS in
 * Garad_ai/frontend/src/core/appShell.ts). The safety rules live here, on the phone, so
 * nothing the model is told or reads on screen can switch them off:
 * - no reading or acting in blocked apps, and no acting in Garad itself, system settings,
 *   permission screens or app stores;
 * - no typing into password fields;
 * - element ids are only valid for the latest screen read, so the model always acts on what
 *   is actually on screen;
 * - a tap that looks like send, post, call, pay, delete and similar waits for the user's
 *   confirmation: the on-screen Yes button, or a spoken yes checked by the web page against
 *   the user's own transcript (`confirm_action`);
 * - Stop (the on-screen pill, or saying "stop"/"jooji") refuses all actions for a while.
 *
 * Messages and calls (notification access) are handled by `Messages`, with the same
 * confirmation and Stop.
 *
 * Results are maps for the model: `ok`, `message`, and usually `screen`, a fresh description
 * of the screen after the action. Calls arrive on a background thread.
 */
object AgentController {
  private const val CONFIRMATION_TTL_MS = 90_000L
  private const val STOP_MS = 20_000L
  private const val MAX_SENSITIVE_LABEL = 40

  private val MESSAGE_ACTIONS = setOf("read_messages", "reply_to_message", "answer_call", "decline_call")

  /** Acting (not reading) is refused in these packages. */
  private val NO_ACTION_PACKAGES = setOf(
    "com.android.settings",
    "com.android.vending",
    "com.android.packageinstaller",
    "com.google.android.packageinstaller",
    "com.android.permissioncontroller",
    "com.google.android.permissioncontroller",
  )

  /** Labels that make a tap need confirmation (English and Somali). */
  private val SENSITIVE = Regex(
    "\\b(send|post|publish|share|call|pay|payment|buy|purchase|order|checkout|delete|remove|" +
      "transfer|confirm|submit|install|uninstall|subscribe|accept|allow|sign out|log out|logout|" +
      "dir|u dir|wac|bixi|iibso|tirtir|xaqiiji|gudbi|daabac|ogolow|oggolow|lacag)\\b",
    RegexOption.IGNORE_CASE,
  )

  private class Pending(val description: String, val createdAt: Long, val run: () -> Map<String, Any?>)

  @Volatile private var snapshot: ScreenReader.Snapshot? = null
  @Volatile private var pending: Pending? = null
  @Volatile private var stoppedAt = 0L
  private var overlay: AgentOverlay? = null

  /** Called by the page bridge when the user answers on screen or presses Stop. */
  var onNotice: ((Map<String, Any?>) -> Unit)? = null

  /** True while Garad Voice is open, so new messages are spoken by Voice and not read aloud. */
  @Volatile var voiceActive = false

  fun attach(service: GaradAccessibilityService) {
    overlay = AgentOverlay(service)
  }

  fun detach() {
    overlay?.hideAll()
    overlay = null
    snapshot = null
    pending = null
  }

  @Synchronized
  fun perform(name: String, args: Map<String, Any?>): Map<String, Any?> {
    if (name == "voice_session") {
      voiceActive = args["active"] == true
      return mapOf("ok" to true, "message" to "Noted.")
    }
    if (name == "stop") return stop(byUser = false)
    if (isStopped()) {
      return fail("The user pressed Stop. Do not continue; ask the user what they want to do.")
    }
    if (name == "confirm_action") return confirm(args["approve"] == true, viaOverlay = false)
    if (name in MESSAGE_ACTIONS) return Messages.perform(name, args)

    val service = GaradAccessibilityService.instance
      ?: return fail(
        "Garad agent is turned off. Tell the user to open the Garad app menu, choose Garad agent " +
          "and turn it on.",
      )

    return when (name) {
      "read_screen" -> readScreen(service)
      "tap" -> act(service, args) { node, label -> tap(service, node, label) }
      "type_text" -> act(service, args) { node, label -> typeText(service, node, label, args["text"]) }
      "scroll" -> scroll(service, args)
      "phone_button" -> phoneButton(service, args["button"] as? String)
      else -> fail("The action \"$name\" is not supported.")
    }
  }

  private fun readScreen(service: GaradAccessibilityService): Map<String, Any?> {
    val screen = describeScreen(service) ?: return fail(unreadableMessage(service))
    return mapOf("ok" to true, "message" to "This is what is on the screen now.", "screen" to screen)
  }

  /** Reads the screen, keeps the snapshot for later actions, and describes it. */
  private fun describeScreen(service: GaradAccessibilityService): String? {
    val root = service.rootInActiveWindow
    if (ScreenReader.unavailable(root) != null) {
      snapshot = null
      return null
    }
    val next = ScreenReader.snapshot(root!!)
    snapshot = next
    return ScreenReader.describe(next, service.appLabel(next.packageName))
  }

  private fun unreadableMessage(service: GaradAccessibilityService): String {
    val reason = ScreenReader.unavailable(service.rootInActiveWindow)?.get("reason")
    return if (reason == "blocked_app") {
      "This app is protected (banking, mobile money or passwords). Garad cannot read or use it; " +
        "the user has to do this themselves."
    } else {
      "The screen could not be read. Wait a moment and try read_screen again."
    }
  }

  /** Resolves `element_id` against the latest read and checks the app may be acted on. */
  private fun act(
    service: GaradAccessibilityService,
    args: Map<String, Any?>,
    action: (AccessibilityNodeInfo, String) -> Map<String, Any?>,
  ): Map<String, Any?> {
    val current = snapshot ?: return fail("Call read_screen first, then use an element id from it.")
    val id = (args["element_id"] as? Number)?.toInt()
      ?: return fail("element_id is missing.")
    val node = current.nodes.getOrNull(id) ?: return fail("There is no element $id on the screen.")

    val root = service.rootInActiveWindow
    val packageName = root?.packageName?.toString()
    if (packageName != current.packageName || !node.refresh()) {
      snapshot = null
      return fail("The screen has changed. Call read_screen again and use the new ids.")
    }
    refusal(service, packageName)?.let { return fail(it) }
    return action(node, labelOf(node))
  }

  private fun refusal(service: GaradAccessibilityService, packageName: String?): String? = when {
    ScreenReader.isBlocked(packageName) ->
      "This app is protected (banking, mobile money or passwords). The user has to do this themselves."
    packageName == service.packageName ->
      "Garad does not act inside its own app. Describe the step and let the user do it."
    packageName in NO_ACTION_PACKAGES ->
      "Garad does not act in phone settings, permission screens or app stores. " +
        "Describe the step and let the user do it."
    else -> null
  }

  private fun tap(service: GaradAccessibilityService, node: AccessibilityNodeInfo, label: String): Map<String, Any?> {
    val target = clickableSelfOrAncestor(node)
      ?: return fail("That element cannot be tapped. Choose a button or a row.")
    val targetLabel = label.ifBlank { labelOf(target) }

    if (isSensitive(node) || isSensitive(target)) {
      val app = service.appLabel(snapshot?.packageName) ?: "this app"
      val shown = targetLabel.ifBlank { "this button" }
      return askFirst(service.getString(R.string.garad_agent_confirm_tap, shown, app)) {
        if (!target.refresh()) {
          fail("The screen changed before the user confirmed. Read the screen again.")
        } else {
          after(service, target.performAction(AccessibilityNodeInfo.ACTION_CLICK), "Pressed \"$shown\".")
        }
      }
    }
    return after(service, target.performAction(AccessibilityNodeInfo.ACTION_CLICK), "Tapped \"$targetLabel\".")
  }

  private fun typeText(
    service: GaradAccessibilityService,
    node: AccessibilityNodeInfo,
    label: String,
    value: Any?,
  ): Map<String, Any?> {
    val text = value as? String ?: return fail("text is missing.")
    if (node.isPassword) return fail("Garad never types into password fields. The user has to type it.")
    if (!node.isEditable) return fail("Element is not a text field. Choose a field from read_screen.")
    node.performAction(AccessibilityNodeInfo.ACTION_FOCUS)
    val arguments = Bundle().apply {
      putCharSequence(AccessibilityNodeInfo.ACTION_ARGUMENT_SET_TEXT_CHARSEQUENCE, text)
    }
    val done = node.performAction(AccessibilityNodeInfo.ACTION_SET_TEXT, arguments)
    val field = label.ifBlank { "the field" }
    return after(service, done, "Typed the text into $field. Nothing has been sent.")
  }

  private fun scroll(service: GaradAccessibilityService, args: Map<String, Any?>): Map<String, Any?> {
    val current = snapshot ?: return fail("Call read_screen first.")
    if (service.rootInActiveWindow?.packageName?.toString() != current.packageName) {
      snapshot = null
      return fail("The screen has changed. Call read_screen again.")
    }
    refusal(service, current.packageName)?.let { return fail(it) }

    val id = (args["element_id"] as? Number)?.toInt()
    val node = if (id != null) {
      current.nodes.getOrNull(id) ?: return fail("There is no element $id on the screen.")
    } else {
      largestScrollable(current) ?: return fail("Nothing on this screen scrolls.")
    }
    val action = if (args["direction"] == "up") {
      AccessibilityNodeInfo.ACTION_SCROLL_BACKWARD
    } else {
      AccessibilityNodeInfo.ACTION_SCROLL_FORWARD
    }
    val target = scrollableSelfOrAncestor(node) ?: return fail("That element does not scroll.")
    return after(service, target.refresh() && target.performAction(action), "Scrolled ${args["direction"] ?: "down"}.")
  }

  private fun phoneButton(service: GaradAccessibilityService, button: String?): Map<String, Any?> {
    val action = when (button) {
      "back" -> AccessibilityService.GLOBAL_ACTION_BACK
      "home" -> AccessibilityService.GLOBAL_ACTION_HOME
      "recent_apps" -> AccessibilityService.GLOBAL_ACTION_RECENTS
      "notifications" -> AccessibilityService.GLOBAL_ACTION_NOTIFICATIONS
      else -> return fail("button must be back, home, recent_apps or notifications.")
    }
    return after(service, service.performGlobalAction(action), "Pressed $button.")
  }

  /**
   * Holds `run` until the user confirms. The on-screen panel needs the accessibility service;
   * without it the user answers by voice only.
   */
  fun askFirst(description: String, run: () -> Map<String, Any?>): Map<String, Any?> {
    pending = Pending(description, SystemClock.elapsedRealtime(), run)
    overlay?.askToConfirm(description) { yes ->
      Thread {
        val result = synchronized(this) { confirm(yes, viaOverlay = true) }
        onNotice?.invoke(mapOf("type" to "confirmation", "approved" to yes, "result" to result))
      }.start()
    }
    return mapOf(
      "ok" to false,
      "needs_confirmation" to true,
      "message" to "Waiting for the user: \"$description\". Tell the user exactly what will happen " +
        "(the text and who it goes to) and ask them to say yes or no, or tap Yes or No on screen. " +
        "When they answer by voice, call confirm_action. Do not tap the button again.",
    )
  }

  private fun confirm(approve: Boolean, viaOverlay: Boolean): Map<String, Any?> {
    val waiting = pending ?: return fail("Nothing is waiting for confirmation.")
    pending = null
    if (!viaOverlay) overlay?.hideConfirmation()
    if (SystemClock.elapsedRealtime() - waiting.createdAt > CONFIRMATION_TTL_MS) {
      return fail("The confirmation expired. Read the screen and ask again if the user still wants it.")
    }
    if (!approve) return mapOf("ok" to true, "message" to "The user said no. Nothing was done.")
    if (isStopped()) return fail("The user pressed Stop. Nothing was done.")
    return waiting.run()
  }

  /** Stop from the pill (byUser) or from the web page when the user says stop. */
  fun stop(byUser: Boolean): Map<String, Any?> {
    stoppedAt = SystemClock.elapsedRealtime()
    pending = null
    snapshot = null
    overlay?.hideAll()
    if (byUser) onNotice?.invoke(mapOf("type" to "stopped"))
    return mapOf("ok" to true, "message" to "Stopped. Garad will not act until the user asks again.")
  }

  private fun isStopped() = stoppedAt != 0L && SystemClock.elapsedRealtime() - stoppedAt < STOP_MS

  /** Waits for the app to settle, then returns the result with a fresh screen. */
  private fun after(service: GaradAccessibilityService, done: Boolean, message: String): Map<String, Any?> {
    snapshot = null
    overlay?.showWorking { stop(byUser = true) }
    if (!done) return fail("The phone did not accept that action. Read the screen and try another way.")
    service.waitForIdle()
    val screen = describeScreen(service)
    return mapOf(
      "ok" to true,
      "message" to message,
      "screen" to (screen ?: unreadableMessage(service)),
    )
  }

  fun fail(message: String): Map<String, Any?> = mapOf("ok" to false, "message" to message)

  private fun labelOf(node: AccessibilityNodeInfo): String =
    (node.text?.toString()?.takeIf { it.isNotBlank() && !node.isPassword }
      ?: node.contentDescription?.toString()
      ?: "").trim().take(80)

  private fun isSensitive(node: AccessibilityNodeInfo): Boolean {
    val label = labelOf(node)
    if (label.isNotEmpty() && label.length <= MAX_SENSITIVE_LABEL && SENSITIVE.containsMatchIn(label)) return true
    val viewId = node.viewIdResourceName?.substringAfterLast('/')?.replace('_', ' ') ?: return false
    return SENSITIVE.containsMatchIn(viewId)
  }

  private fun clickableSelfOrAncestor(node: AccessibilityNodeInfo): AccessibilityNodeInfo? {
    var current: AccessibilityNodeInfo? = node
    repeat(6) {
      val candidate = current ?: return null
      if (candidate.isClickable && candidate.isEnabled) return candidate
      current = candidate.parent
    }
    return null
  }

  private fun scrollableSelfOrAncestor(node: AccessibilityNodeInfo): AccessibilityNodeInfo? {
    var current: AccessibilityNodeInfo? = node
    repeat(8) {
      val candidate = current ?: return null
      if (candidate.isScrollable) return candidate
      current = candidate.parent
    }
    return null
  }

  private fun largestScrollable(current: ScreenReader.Snapshot): AccessibilityNodeInfo? =
    current.nodes.filter { it.isScrollable }.maxByOrNull { node ->
      val bounds = android.graphics.Rect()
      node.getBoundsInScreen(bounds)
      bounds.width().toLong() * bounds.height()
    }
}
