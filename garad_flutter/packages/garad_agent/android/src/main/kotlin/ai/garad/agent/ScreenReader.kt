package ai.garad.agent

import android.graphics.Rect
import android.view.accessibility.AccessibilityNodeInfo

/**
 * Turns the active window into a short list of visible elements that Garad can describe and
 * act on. Password fields are masked, and apps whose package looks like banking, mobile money
 * or a password manager are not read at all.
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

  /** One read of the screen. `nodes[i]` is the live node behind `elements[i]`. */
  class Snapshot(
    val packageName: String?,
    val elements: List<Map<String, Any?>>,
    val nodes: List<AccessibilityNodeInfo>,
  ) {
    val truncated get() = elements.size >= MAX_ELEMENTS

    fun toMap(): Map<String, Any?> = mapOf(
      "available" to true,
      "package" to packageName,
      "elements" to elements,
      "truncated" to truncated,
    )
  }

  /** Why a window cannot be read, in the same shape the JS API returns. */
  fun unavailable(root: AccessibilityNodeInfo?): Map<String, Any?>? = when {
    root == null -> mapOf("available" to false, "reason" to "no_window")
    isBlocked(root.packageName?.toString()) ->
      mapOf("available" to false, "reason" to "blocked_app", "package" to root.packageName?.toString())
    else -> null
  }

  fun read(root: AccessibilityNodeInfo?): Map<String, Any?> =
    unavailable(root) ?: snapshot(root!!).toMap()

  fun snapshot(root: AccessibilityNodeInfo): Snapshot {
    val elements = ArrayList<Map<String, Any?>>()
    val nodes = ArrayList<AccessibilityNodeInfo>()
    walk(root, 0, elements, nodes)
    return Snapshot(root.packageName?.toString(), elements, nodes)
  }

  private fun walk(
    node: AccessibilityNodeInfo,
    depth: Int,
    out: MutableList<Map<String, Any?>>,
    nodes: MutableList<AccessibilityNodeInfo>,
  ) {
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
      nodes.add(node)
    }

    for (index in 0 until node.childCount) {
      val child = node.getChild(index) ?: continue
      walk(child, depth + 1, out, nodes)
    }
  }

  private const val MAX_LINES = 150
  private const val MAX_LINE_TEXT = 120

  /**
   * The snapshot as short lines for the voice model, e.g. `[4] button "Send"` or
   * `[7] field "Message" (empty)`. Elements with nothing to say or do are left out.
   */
  fun describe(snapshot: Snapshot, appLabel: String?): String {
    val lines = ArrayList<String>()
    lines.add("App: ${appLabel ?: snapshot.packageName ?: "unknown"}")
    for (element in snapshot.elements) {
      if (lines.size > MAX_LINES) {
        lines.add("… more elements not shown; scroll to see more")
        break
      }
      val label = (element["text"] as String?)?.takeIf { it.isNotBlank() }
        ?: (element["description"] as String?)?.takeIf { it.isNotBlank() }
      val editable = element["editable"] == true
      val clickable = element["clickable"] == true
      val scrollable = element["scrollable"] == true
      val checked = element["checked"] as Boolean?
      val kind = when {
        editable -> "field"
        checked != null -> if (checked) "checkbox (on)" else "checkbox (off)"
        clickable -> "button"
        scrollable -> "list"
        else -> "text"
      }
      val hint = (element["viewId"] as String?)?.substringAfterLast('/')
      val shown = when {
        label != null -> "\"${label.replace('\n', ' ').take(MAX_LINE_TEXT)}\""
        editable -> "(empty)"
        hint != null && (clickable || scrollable) -> "(no label, id: $hint)"
        scrollable -> ""
        clickable -> "(no label)"
        else -> continue
      }
      val extra = if (scrollable && kind != "list") ", scrollable" else ""
      lines.add("[${element["id"]}] $kind $shown$extra".trimEnd())
    }
    return lines.joinToString("\n")
  }
}
