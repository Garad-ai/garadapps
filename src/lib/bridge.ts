import * as Clipboard from 'expo-clipboard';
import { File, Paths } from 'expo-file-system';
import * as Sharing from 'expo-sharing';
import * as Speech from 'expo-speech';

/**
 * JavaScript injected into Chat Pro before it loads. Mobile WebViews cannot save
 * `blob:`/`data:` downloads (documents, images and exports Chat Pro builds in the
 * page) and the async clipboard is unreliable, so both are forwarded to the app:
 * - clicks on download links and programmatic `a.click()` downloads become
 *   `{ type: 'download', name, mime, base64 }` messages
 * - `window.open(blob:…)` is treated as a download
 * - `navigator.clipboard.writeText` becomes `{ type: 'copy', text }`
 * - `window.__garadDownload(url)` fetches a site URL with the user's cookies (used
 *   for iOS file downloads, which the WebView reports without saving them)
 * - where the WebView has no `speechSynthesis` (Android), "read aloud" becomes
 *   `{ type: 'speak', text, lang, rate }` / `{ type: 'speakStop' }` and the app reports
 *   progress back through `window.__garadSpeech('start' | 'end' | 'error')`
 * - a download that cannot be fetched (e.g. another domain without CORS) is reported
 *   as `{ type: 'downloadError', url }` so the app can open it in the browser instead
 */
export const BRIDGE_SCRIPT = `
(function () {
  if (window.__garadBridge || !window.ReactNativeWebView) return;
  window.__garadBridge = true;

  function post(message) {
    window.ReactNativeWebView.postMessage(JSON.stringify(message));
  }

  function sendBlob(blob, name) {
    var reader = new FileReader();
    reader.onload = function () {
      var result = String(reader.result);
      post({
        type: 'download',
        name: name || 'download',
        mime: blob.type || 'application/octet-stream',
        base64: result.slice(result.indexOf(',') + 1)
      });
    };
    reader.readAsDataURL(blob);
  }

  function nameFrom(response, url, fallback) {
    var disposition = response.headers.get('content-disposition') || '';
    var match = /filename\\*?=(?:UTF-8'')?"?([^";]+)"?/i.exec(disposition);
    if (fallback) return fallback;
    if (match) return decodeURIComponent(match[1]);
    return url.split('?')[0].split('/').pop() || 'download';
  }

  function fetchAndSend(url, name) {
    fetch(url, { credentials: 'include' })
      .then(function (response) {
        if (!response.ok) throw new Error('HTTP ' + response.status);
        var fileName = nameFrom(response, url, name);
        return response.blob().then(function (blob) { sendBlob(blob, fileName); });
      })
      .catch(function (error) { post({ type: 'downloadError', url: url, message: String(error) }); });
  }

  // Keep blobs reachable after the page revokes their URL right after clicking.
  var blobs = {};
  var createObjectURL = URL.createObjectURL;
  URL.createObjectURL = function (object) {
    var url = createObjectURL.apply(URL, arguments);
    if (object instanceof Blob) blobs[url] = object;
    return url;
  };
  var revokeObjectURL = URL.revokeObjectURL;
  URL.revokeObjectURL = function (url) {
    setTimeout(function () { delete blobs[url]; revokeObjectURL.call(URL, url); }, 60000);
  };

  function handleUrl(url, name) {
    if (/^blob:/i.test(url)) {
      if (blobs[url]) sendBlob(blobs[url], name);
      else fetch(url).then(function (r) { return r.blob(); }).then(function (b) { sendBlob(b, name); });
      return true;
    }
    if (/^data:/i.test(url)) {
      fetch(url).then(function (r) { return r.blob(); }).then(function (b) { sendBlob(b, name); });
      return true;
    }
    return false;
  }

  function handleAnchor(anchor) {
    var href = anchor.href || '';
    var name = anchor.getAttribute('download');
    if (handleUrl(href, name)) return true;
    if (name !== null && /^https?:/i.test(href)) {
      fetchAndSend(href, name || null);
      return true;
    }
    return false;
  }

  document.addEventListener('click', function (event) {
    var target = event.target;
    var anchor = target && target.closest ? target.closest('a') : null;
    if (anchor && handleAnchor(anchor)) {
      event.preventDefault();
      event.stopPropagation();
    }
  }, true);

  var anchorClick = HTMLAnchorElement.prototype.click;
  HTMLAnchorElement.prototype.click = function () {
    if (handleAnchor(this)) return;
    return anchorClick.apply(this, arguments);
  };

  var open = window.open;
  window.open = function (url) {
    if (typeof url === 'string' && handleUrl(url, null)) return null;
    return open.apply(window, arguments);
  };

  var copy = function (text) {
    post({ type: 'copy', text: String(text) });
    return Promise.resolve();
  };
  try {
    if (navigator.clipboard) navigator.clipboard.writeText = copy;
    else Object.defineProperty(navigator, 'clipboard', { value: { writeText: copy }, configurable: true });
  } catch (error) {}

  window.__garadDownload = function (url) { fetchAndSend(url, null); };

  // Android WebView has no speechSynthesis; read text aloud with the phone's voice instead.
  if (!window.speechSynthesis) {
    var current = null;
    if (!window.SpeechSynthesisUtterance) {
      window.SpeechSynthesisUtterance = function (text) {
        this.text = text || '';
        this.lang = '';
        this.rate = 1;
        this.onstart = null;
        this.onend = null;
        this.onerror = null;
      };
    }
    window.speechSynthesis = {
      speaking: false,
      pending: false,
      paused: false,
      speak: function (utterance) {
        current = utterance;
        this.speaking = true;
        post({ type: 'speak', text: String(utterance.text || ''), lang: utterance.lang || '', rate: utterance.rate || 1 });
      },
      cancel: function () {
        if (!current) return;
        current = null;
        this.speaking = false;
        post({ type: 'speakStop' });
      },
      pause: function () {},
      resume: function () {},
      getVoices: function () { return []; },
      addEventListener: function () {},
      removeEventListener: function () {}
    };
    window.__garadSpeech = function (event) {
      var utterance = current;
      if (!utterance) return;
      if (event === 'start') {
        if (utterance.onstart) utterance.onstart({});
        return;
      }
      current = null;
      window.speechSynthesis.speaking = false;
      var handler = event === 'error' ? utterance.onerror : utterance.onend;
      if (handler) handler({});
    };
  }
})();
true;
`;

/** Makes a name safe to use as a file name on Android and iOS. */
function safeFileName(name: string): string {
  const cleaned = name.replace(/[\\/:*?"<>|\u0000-\u001f]+/g, '_').trim().slice(0, 120);
  return cleaned || 'download';
}

/** Saves a downloaded file to the app cache and opens the share sheet to save or send it. */
export async function saveDownload(name: string, mime: string, base64: string): Promise<void> {
  const file = new File(Paths.cache, safeFileName(name));
  if (file.exists) file.delete();
  file.create();
  await file.write(base64, { encoding: 'base64' });
  if (await Sharing.isAvailableAsync()) {
    await Sharing.shareAsync(file.uri, { mimeType: mime, dialogTitle: file.name });
  }
}

export async function copyText(text: string): Promise<void> {
  await Clipboard.setStringAsync(text);
}

/** Reads text aloud with the device voice and reports progress back to the page. */
export function speak(
  text: string,
  options: { language?: string; rate?: number },
  notify: (event: 'start' | 'end' | 'error') => void
): void {
  void Speech.stop();
  Speech.speak(text, {
    language: options.language || undefined,
    rate: options.rate,
    onStart: () => notify('start'),
    onDone: () => notify('end'),
    onStopped: () => notify('end'),
    onError: () => notify('error'),
  });
}

export function stopSpeaking(): void {
  void Speech.stop();
}
