package ai.garad.agent

import android.accessibilityservice.AccessibilityService
import android.graphics.PixelFormat
import android.graphics.drawable.GradientDrawable
import android.os.Handler
import android.os.Looper
import android.util.TypedValue
import android.view.Gravity
import android.view.View
import android.view.WindowManager
import android.widget.Button
import android.widget.LinearLayout
import android.widget.TextView

/**
 * Windows the agent draws over other apps (accessibility overlays need no extra permission):
 * - a small "Garad · Stop" pill while it is acting;
 * - a confirmation panel before anything that is hard to undo, with Yes and No buttons.
 * Everything here runs on the main thread.
 */
class AgentOverlay(private val service: AccessibilityService) {
  private val main = Handler(Looper.getMainLooper())
  private val windowManager = service.getSystemService(WindowManager::class.java)
  private var pill: View? = null
  private var panel: View? = null
  private val hidePill = Runnable { removePill() }

  /** Shows the Stop pill and keeps it up for a while after the last action. */
  fun showWorking(onStop: () -> Unit) = main.post {
    main.removeCallbacks(hidePill)
    if (pill == null) {
      val button = Button(service).apply {
        text = service.getString(R.string.garad_agent_stop)
        isAllCaps = false
        setTextColor(WHITE)
        textSize = 15f
        background = rounded(BRAND, dp(24f))
        minHeight = dp(48f).toInt()
        setPadding(dp(20f).toInt(), 0, dp(20f).toInt(), 0)
        setOnClickListener { onStop() }
      }
      add(button, Gravity.TOP or Gravity.CENTER_HORIZONTAL, matchWidth = false)
      pill = button
    }
    main.postDelayed(hidePill, PILL_MS)
  }

  fun hideWorking() = main.post {
    main.removeCallbacks(hidePill)
    removePill()
  }

  /** Asks the user, on screen, to confirm one action. Exactly one callback runs. */
  fun askToConfirm(message: String, onAnswer: (Boolean) -> Unit) = main.post {
    removePanel()
    var answered = false
    val answer = { yes: Boolean ->
      if (!answered) {
        answered = true
        removePanel()
        onAnswer(yes)
      }
    }
    val padding = dp(18f).toInt()
    val layout = LinearLayout(service).apply {
      orientation = LinearLayout.VERTICAL
      background = rounded(PANEL, dp(22f))
      setPadding(padding, padding, padding, padding)
    }
    val title = TextView(service).apply {
      text = message
      setTextColor(WHITE)
      textSize = 17f
      setPadding(0, 0, 0, padding)
    }
    val row = LinearLayout(service).apply { orientation = LinearLayout.HORIZONTAL }
    val no = button(service.getString(R.string.garad_agent_confirm_no), SURFACE) { answer(false) }
    val yes = button(service.getString(R.string.garad_agent_confirm_yes), BRAND) { answer(true) }
    row.addView(no, LinearLayout.LayoutParams(0, dp(56f).toInt(), 1f).apply { marginEnd = dp(10f).toInt() })
    row.addView(yes, LinearLayout.LayoutParams(0, dp(56f).toInt(), 1f))
    layout.addView(title)
    layout.addView(row)
    add(layout, Gravity.BOTTOM, matchWidth = true)
    panel = layout
    layout.announceForAccessibility(message)
    // The phone forgets an unanswered confirmation after 90 s (AgentController); so does the panel.
    main.postDelayed({ if (panel === layout) removePanel() }, CONFIRM_MS)
  }

  fun hideConfirmation() = main.post { removePanel() }

  fun hideAll() = main.post {
    main.removeCallbacks(hidePill)
    removePill()
    removePanel()
  }

  private fun add(view: View, gravity: Int, matchWidth: Boolean) {
    val params = WindowManager.LayoutParams(
      if (matchWidth) WindowManager.LayoutParams.MATCH_PARENT else WindowManager.LayoutParams.WRAP_CONTENT,
      WindowManager.LayoutParams.WRAP_CONTENT,
      WindowManager.LayoutParams.TYPE_ACCESSIBILITY_OVERLAY,
      WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE or WindowManager.LayoutParams.FLAG_NOT_TOUCH_MODAL,
      PixelFormat.TRANSLUCENT,
    ).apply {
      this.gravity = gravity
      val margin = dp(12f).toInt()
      x = 0
      y = if (gravity and Gravity.TOP == Gravity.TOP) dp(36f).toInt() else margin * 2
      if (matchWidth) horizontalMargin = 0.03f
    }
    runCatching { windowManager.addView(view, params) }
  }

  private fun removePill() {
    pill?.let { runCatching { windowManager.removeView(it) } }
    pill = null
  }

  private fun removePanel() {
    panel?.let { runCatching { windowManager.removeView(it) } }
    panel = null
  }

  private fun button(label: String, color: Int, onClick: () -> Unit) = Button(service).apply {
    text = label
    isAllCaps = false
    setTextColor(WHITE)
    textSize = 16f
    background = rounded(color, dp(16f))
    setOnClickListener { onClick() }
  }

  private fun rounded(color: Int, radius: Float) = GradientDrawable().apply {
    setColor(color)
    cornerRadius = radius
  }

  private fun dp(value: Float) =
    TypedValue.applyDimension(TypedValue.COMPLEX_UNIT_DIP, value, service.resources.displayMetrics)

  private companion object {
    const val PILL_MS = 10_000L
    const val CONFIRM_MS = 90_000L
    const val WHITE = 0xFFFFFFFF.toInt()
    const val BRAND = 0xFF514CFF.toInt()
    const val PANEL = 0xF2262624.toInt()
    const val SURFACE = 0xFF3A3A37.toInt()
  }
}
