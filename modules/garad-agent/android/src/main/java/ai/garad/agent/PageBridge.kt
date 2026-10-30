package ai.garad.agent

import android.app.Activity
import android.os.Handler
import android.os.Looper
import android.view.View
import android.view.ViewGroup
import android.webkit.WebView
import org.json.JSONObject
import java.lang.ref.WeakReference

/**
 * Runs JavaScript in the Garad web page straight from Kotlin. React Native holds back
 * `injectJavaScript` while the app is in the background, which is exactly when the agent works
 * in another app, so agent results and notices go through here instead.
 */
object PageBridge {
  private val main = Handler(Looper.getMainLooper())
  private var activity = WeakReference<Activity>(null)
  private var webView = WeakReference<WebView>(null)

  fun remember(current: Activity?) {
    if (current != null) activity = WeakReference(current)
  }

  /** Runs `script` in the page, on the main thread. Dropped if the page is gone. */
  fun evaluate(script: String) = main.post {
    val found = webView.get()?.takeIf { it.isAttachedToWindow }
      ?: activity.get()?.window?.decorView?.let(::findWebView)?.also { webView = WeakReference(it) }
    found?.evaluateJavascript(script, null)
  }

  /** Delivers an unasked event (a confirmation answered on screen, Stop) to the page. */
  fun notice(event: Map<String, Any?>) {
    evaluate("window.__garadAgentNotice && window.__garadAgentNotice(${JSONObject(event)}); true;")
  }

  private fun findWebView(view: View): WebView? {
    if (view is WebView) return view
    if (view is ViewGroup) {
      for (index in 0 until view.childCount) {
        findWebView(view.getChildAt(index))?.let { return it }
      }
    }
    return null
  }
}
