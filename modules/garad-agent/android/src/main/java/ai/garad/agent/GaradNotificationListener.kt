package ai.garad.agent

import android.app.Notification
import android.app.PendingIntent
import android.app.RemoteInput
import android.content.Context
import android.content.Intent
import android.os.Bundle
import android.os.SystemClock
import android.provider.Telephony
import android.service.notification.NotificationListenerService
import android.service.notification.StatusBarNotification
import android.speech.tts.TextToSpeech

/**
 * Garad's notification access, which the user turns on separately in the phone settings.
 * It keeps the last few messaging notifications so Garad Voice can read them and reply
 * through the notification's own Reply action, and it tracks a ringing call so Garad can
 * announce it and answer or decline it with the call notification's buttons. It needs no
 * phone, SMS or contacts permission.
 *
 * - Only messaging notifications are kept, never from blocked apps (banks, mobile money)
 *   and never Garad's own.
 * - Codes in messages that look like one-time codes are masked.
 * - New messages and calls go to the Garad page (spoken by Garad Voice when it is open) and,
 *   only if the user turned it on, are read aloud while Voice is closed.
 */
class GaradNotificationListener : NotificationListenerService() {
  class Message(
    val id: Int,
    val key: String,
    val packageName: String,
    val app: String,
    val sender: String,
    val text: String,
    val postedAt: Long,
    val reply: Notification.Action?,
  )

  class Call(val key: String, val caller: String, val answer: Notification.Action?, val decline: Notification.Action?)

  private val messages = LinkedHashMap<String, Message>()
  private var nextId = 1
  @Volatile var ringing: Call? = null
    private set
  private var tts: TextToSpeech? = null
  private var ttsReady = false

  override fun onListenerConnected() {
    super.onListenerConnected()
    instance = this
    runCatching { activeNotifications }.getOrNull()?.forEach { remember(it, announce = false) }
  }

  override fun onListenerDisconnected() {
    if (instance === this) instance = null
    super.onListenerDisconnected()
  }

  override fun onDestroy() {
    if (instance === this) instance = null
    tts?.shutdown()
    tts = null
    super.onDestroy()
  }

  override fun onNotificationPosted(sbn: StatusBarNotification?) {
    if (sbn != null) remember(sbn, announce = true)
  }

  override fun onNotificationRemoved(sbn: StatusBarNotification?) {
    val key = sbn?.key ?: return
    synchronized(messages) { messages.remove(key) }
    if (ringing?.key == key) {
      ringing = null
      AgentController.onNotice?.invoke(mapOf("type" to "call_ended"))
    }
  }

  /** The newest messages first, at most `limit`. */
  fun recentMessages(limit: Int): List<Message> =
    synchronized(messages) { messages.values.sortedByDescending { it.postedAt }.take(limit) }

  fun message(id: Int): Message? = synchronized(messages) { messages.values.firstOrNull { it.id == id } }

  /** Sends `text` through the notification's Reply action. */
  fun reply(message: Message, text: String): Boolean {
    val action = message.reply ?: return false
    val inputs = action.remoteInputs?.filter { it.allowFreeFormInput } ?: return false
    if (inputs.isEmpty()) return false
    val intent = Intent().addFlags(Intent.FLAG_RECEIVER_FOREGROUND)
    val results = Bundle().apply { inputs.forEach { putCharSequence(it.resultKey, text) } }
    RemoteInput.addResultsToIntent(inputs.toTypedArray(), intent, results)
    return send(action.actionIntent, intent)
  }

  fun press(action: Notification.Action?): Boolean = action != null && send(action.actionIntent, null)

  private fun send(pendingIntent: PendingIntent?, fill: Intent?): Boolean = try {
    if (pendingIntent == null) false else {
      pendingIntent.send(this, 0, fill)
      true
    }
  } catch (_: PendingIntent.CanceledException) {
    false
  }

  private fun remember(sbn: StatusBarNotification, announce: Boolean) {
    val notification = sbn.notification ?: return
    val packageName = sbn.packageName ?: return
    if (packageName == this.packageName || ScreenReader.isBlocked(packageName)) return
    if (notification.flags and Notification.FLAG_GROUP_SUMMARY != 0) return

    if (notification.category == Notification.CATEGORY_CALL) {
      rememberCall(sbn, notification, announce)
      return
    }
    if (!isMessaging(packageName, notification)) return

    val extras = notification.extras ?: return
    val (sender, rawText) = lastMessage(extras) ?: return
    val text = maskCodes(rawText)
    val app = appLabel(packageName)
    val message = synchronized(messages) {
      val existing = messages[sbn.key]
      // Notifications are reposted when they update; only a new text counts as new.
      if (existing != null && existing.text == text && existing.sender == sender) return
      Message(nextId++, sbn.key, packageName, app, sender, text, sbn.postTime, replyAction(notification))
        .also {
          messages[sbn.key] = it
          while (messages.size > MAX_MESSAGES) messages.remove(messages.keys.first())
        }
    }
    if (!announce) return
    AgentController.onNotice?.invoke(
      mapOf("type" to "message", "id" to message.id, "app" to app, "sender" to sender, "text" to text,
        "canReply" to (message.reply != null)),
    )
    if (!AgentController.voiceActive && announceAloud(this)) speak("$app. $sender: $text")
  }

  private fun rememberCall(sbn: StatusBarNotification, notification: Notification, announce: Boolean) {
    val actions = notification.actions ?: return
    // Only a ringing call shows both answer and decline.
    if (actions.size < 2) return
    val caller = notification.extras?.getCharSequence(Notification.EXTRA_TITLE)?.toString()?.takeIf { it.isNotBlank() }
      ?: "Unknown caller"
    val answer = actions.firstOrNull { ANSWER.containsMatchIn(it.title ?: "") } ?: actions.last()
    val decline = actions.firstOrNull { DECLINE.containsMatchIn(it.title ?: "") } ?: actions.first()
    if (answer === decline) return
    val wasRinging = ringing?.key == sbn.key
    ringing = Call(sbn.key, caller, answer, decline)
    if (!announce || wasRinging) return
    AgentController.onNotice?.invoke(mapOf("type" to "call", "caller" to caller))
    if (!AgentController.voiceActive && announceAloud(this)) speak(getString(R.string.garad_agent_call_from, caller))
  }

  private fun isMessaging(packageName: String, notification: Notification): Boolean =
    notification.category == Notification.CATEGORY_MESSAGE ||
      packageName in MESSAGING_PACKAGES ||
      packageName == Telephony.Sms.getDefaultSmsPackage(this)

  /** Sender and text of the newest message, from MessagingStyle when the app uses it. */
  private fun lastMessage(extras: Bundle): Pair<String, String>? {
    val title = extras.getCharSequence(Notification.EXTRA_CONVERSATION_TITLE)?.toString()
      ?: extras.getCharSequence(Notification.EXTRA_TITLE)?.toString()
    val styled = extras.getParcelableArray(Notification.EXTRA_MESSAGES)?.lastOrNull() as? Bundle
    if (styled != null) {
      val text = styled.getCharSequence("text")?.toString()
      val sender = styled.getCharSequence("sender")?.toString()
      if (!text.isNullOrBlank()) {
        val from = when {
          sender.isNullOrBlank() -> title ?: "Unknown"
          title != null && title != sender -> "$sender ($title)"
          else -> sender
        }
        return from to text
      }
    }
    val text = (extras.getCharSequence(Notification.EXTRA_BIG_TEXT) ?: extras.getCharSequence(Notification.EXTRA_TEXT))
      ?.toString()
    if (text.isNullOrBlank()) return null
    return (title ?: "Unknown") to text
  }

  private fun replyAction(notification: Notification): Notification.Action? {
    val own = notification.actions?.firstOrNull { action -> action.remoteInputs?.any { it.allowFreeFormInput } == true }
    if (own != null) return own
    // Some apps only put the reply action on the wearable extension.
    return Notification.WearableExtender(notification).actions
      .firstOrNull { action -> action.remoteInputs?.any { it.allowFreeFormInput } == true }
  }

  private fun appLabel(packageName: String): String = try {
    packageManager.getApplicationLabel(packageManager.getApplicationInfo(packageName, 0)).toString()
  } catch (_: Exception) {
    packageName
  }

  private fun speak(text: String) {
    val engine = tts
    if (engine != null && ttsReady) {
      engine.speak(text.take(400), TextToSpeech.QUEUE_ADD, null, "garad-${SystemClock.elapsedRealtime()}")
      return
    }
    if (engine == null) {
      tts = TextToSpeech(this) { status ->
        ttsReady = status == TextToSpeech.SUCCESS
        if (ttsReady) speak(text)
      }
    }
  }

  companion object {
    private const val MAX_MESSAGES = 30
    private const val PREFS = "garad_agent"
    private const val KEY_ANNOUNCE = "announce_aloud"

    @Volatile
    var instance: GaradNotificationListener? = null
      private set

    private val MESSAGING_PACKAGES = setOf(
      "com.whatsapp", "com.whatsapp.w4b", "org.telegram.messenger", "com.facebook.orca",
      "com.google.android.apps.messaging", "com.samsung.android.messaging", "com.instagram.android",
      "com.viber.voip", "com.imo.android.imoim", "com.snapchat.android",
    )

    private val ANSWER = Regex("answer|accept|qaado|ka jawaab", RegexOption.IGNORE_CASE)
    private val DECLINE = Regex("decline|reject|dismiss|hang up|diid|dami", RegexOption.IGNORE_CASE)

    private val CODE_WORDS = Regex("code|otp|pin|password|verification|verify|koodh|kood|furaha|sir", RegexOption.IGNORE_CASE)
    private val DIGITS = Regex("\\b\\d{4,8}\\b")

    /** "Your code is 482913" becomes "Your code is ••••". */
    fun maskCodes(text: String): String =
      if (CODE_WORDS.containsMatchIn(text)) DIGITS.replace(text, "••••") else text

    fun announceAloud(context: Context): Boolean =
      context.getSharedPreferences(PREFS, Context.MODE_PRIVATE).getBoolean(KEY_ANNOUNCE, false)

    fun setAnnounceAloud(context: Context, value: Boolean) {
      context.getSharedPreferences(PREFS, Context.MODE_PRIVATE).edit().putBoolean(KEY_ANNOUNCE, value).apply()
    }
  }
}
