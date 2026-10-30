package ai.garad.agent

import android.graphics.Rect
import android.view.accessibility.AccessibilityNodeInfo

/**
 * Turns the active window into a short list of visible elements that Garad can describe.
 * Read-only: nothing here clicks or types. Password fields are masked, and apps whose
 * package looks like banking, mobile money or a password manager are not read at all.
 */
object ScreenReader {
  const val MAX_ELEMENTS = 300
  private const val MAX_DEPTH = 40
  private const val MAX_TEXT = 300

  /**
   * Matched against the package name. A heuristic until the admin can manage the list:
   * it errs on the side of not reading.
   */
  private val BLOCKED_PACKAGE_KEYWORDS = listOf(
    "bank", "wallet", "pay", "evc", "zaad", "edahab", "dahabshiil", "premierbank",
    "salaambank", "authenticator", "password", "keepass", "bitwarden", "lastpass",
  )

  fun isBlocked(packageName: String?): Boolean {
    val name = packageName?.lowercase() ?: return false
    return BLOCKED_PACKAGE_KEYWORDS.any { name.contains(it) }
  }

  fun read(root: AccessibilityNodeInfo?): Map<String, Any?> {
    if (root == null) return mapOf("available" to false, "reason" to "no_window")
    val packageName = root.packageName?.toString()
    if (isBlocked(packageName)) {
      return mapOf("available" to false, "reason" to "blocked_app", "package" to packageName)
    }
    val elements = ArrayList<Map<String, Any?>>()
    walk(root, 0, elements)
    return mapOf(
      "available" to true,
      "package" to packageName,
      "elements" to elements,
      "truncated" to (elements.size >= MAX_ELEMENTS),
    )
  }

  private fun walk(node: AccessibilityNodeInfo, depth: Int, out: MutableList<Map<String, Any?>>) {
    if (out.size >= MAX_ELEMENTS || depth > MAX_DEPTH || !node.isVisibleToUser) return

    val text = if (node.isPassword) "••••" else node.text?.toString()?.take(MAX_TEXT)
    val description = node.contentDescription?.toString()?.take(MAX_TEXT)
    val useful = !text.isNullOrBlank() || !description.isNullOrBlank() ||
      node.isClickable || node.isEditable || node.isScrollable || node.isCheckable

    if (useful) {
      val bounds = Rect()
      node.getBoundsInScreen(bounds)
      out.add(
        mapOf(
          "id" to out.size,
          "role" to node.className?.toString()?.substringAfterLast('.'),
          "text" to text,
          "description" to description,
          "viewId" to node.viewIdResourceName,
          "clickable" to node.isClickable,
          "editable" to node.isEditable,
          "scrollable" to node.isScrollable,
          "checked" to if (node.isCheckable) node.isChecked else null,
          "password" to node.isPassword,
          "bounds" to listOf(bounds.left, bounds.top, bounds.right, bounds.bottom),
        )
      )
    }

    for (index in 0 until node.childCount) {
      val child = node.getChild(index) ?: continue
      walk(child, depth + 1, out)
    }
  }
}
