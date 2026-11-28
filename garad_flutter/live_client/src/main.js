// Garad Live: a real-time video call with Garad, like Gemini Live. The page streams the microphone (16 kHz
// PCM) and one camera picture a second to Google's Live API and plays Garad's spoken answers (24 kHz PCM)
// as they arrive; speaking over Garad interrupts it. The app (lib/screens/live_video_screen.dart) gives a
// one-use key for each ~2-minute block (paid for on garad.ai first); the call moves to the next block's
// connection with Google's session resumption, so Garad remembers what was said.

import "./style.css"
import workletUrl from "./capture-worklet.js?url"

const params = new URLSearchParams(location.search)
const somali = params.get("lang") === "so"
const t = (so, en) => (somali ? so : en)

// ---- The app bridge (flutter_inappwebview) ----

function app(name, data) {
  try {
    return window.flutter_inappwebview?.callHandler(name, data)
  } catch {
    return undefined
  }
}

function appReady() {
  return new Promise((resolve) => {
    if (window.flutter_inappwebview?.callHandler) resolve()
    else window.addEventListener("flutterInAppWebViewPlatformReady", () => resolve(), { once: true })
  })
}

// ---- Page ----

const root = document.getElementById("app")
root.innerHTML = `
  <video id="camera" playsinline muted autoplay></video>
  <div id="orb" class="orb"><i></i><i></i><i></i></div>
  <header>
    <span class="pill"><b class="dot"></b><span id="title">Garad Live</span><span id="clock">0:00</span></span>
    <span id="free" class="free"></span>
  </header>
  <div id="captions"><p id="you"></p><p id="garad"></p></div>
  <div id="notice" hidden><p id="notice-text"></p><div class="notice-actions"></div></div>
  <nav>
    <button id="cam" aria-label="${t("Kamaradda", "Camera")}">${icon("cam")}</button>
    <button id="flip" aria-label="${t("Beddel kamaradda", "Flip camera")}">${icon("flip")}</button>
    <button id="mic" aria-label="${t("Makarafoonka", "Microphone")}">${icon("mic")}</button>
    <button id="end" class="end" aria-label="${t("Dhammee", "End")}">${icon("end")}</button>
  </nav>`

const $ = (id) => document.getElementById(id)
const video = $("camera")

function icon(name) {
  const paths = {
    cam: '<path d="M4 7h11a2 2 0 0 1 2 2v1.5l4-2.5v8l-4-2.5V15a2 2 0 0 1-2 2H4a2 2 0 0 1-2-2V9a2 2 0 0 1 2-2z"/>',
    camoff: '<path d="M4 7h11a2 2 0 0 1 2 2v1.5l4-2.5v8l-4-2.5V15a2 2 0 0 1-2 2H4a2 2 0 0 1-2-2V9a2 2 0 0 1 2-2z"/><path d="M3 3l18 18"/>',
    flip: '<path d="M4 9a8 8 0 0 1 14-3l2 2M20 15a8 8 0 0 1-14 3l-2-2"/><path d="M20 4v4h-4M4 20v-4h4"/>',
    mic: '<rect x="9" y="3" width="6" height="11" rx="3"/><path d="M5 11a7 7 0 0 0 14 0M12 18v3"/>',
    micoff: '<rect x="9" y="3" width="6" height="11" rx="3"/><path d="M5 11a7 7 0 0 0 14 0M12 18v3M3 3l18 18"/>',
    end: '<path d="M3 15c5-5 13-5 18 0l-2.5 2.5-3.5-2v-2.5a10 10 0 0 0-6 0v2.5l-3.5 2z" fill="currentColor"/>',
  }
  return `<svg viewBox="0 0 24 24" width="26" height="26" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round">${paths[name]}</svg>`
}

// ---- State ----

let stream = null // camera + microphone
let facing = "environment" // the back camera first: show Garad the world
let camOn = true
let micOn = true
let ended = false
let active = null // the WebSocket the call is on
let handle = "" // Google's session-resumption handle: the next connection continues the conversation
let renewTimer = 0
let renewing = false
let startedAt = 0
let freeLeft = null

// ---- Microphone in ----

let micCtx = null
let micNode = null

async function startMicrophone() {
  micCtx = new AudioContext()
  await micCtx.audioWorklet.addModule(workletUrl)
  const source = micCtx.createMediaStreamSource(stream)
  micNode = new AudioWorkletNode(micCtx, "garad-capture")
  micNode.port.onmessage = ({ data }) => {
    if (!micOn) return
    showLevel(data.level)
    send({ realtimeInput: { audio: { data: base64(new Uint8Array(data.pcm)), mimeType: "audio/pcm;rate=16000" } } })
  }
  source.connect(micNode)
}

// ---- Garad's voice out ----

const voiceCtx = new AudioContext({ sampleRate: 24000 })
let playAt = 0
const playing = new Set()

function playPcm(b64) {
  // A web view may start the audio context suspended; make sure it is playing.
  if (voiceCtx.state !== "running") voiceCtx.resume().catch(() => {})
  const bytes = Uint8Array.from(atob(b64), (c) => c.charCodeAt(0))
  const samples = new Int16Array(bytes.buffer, 0, bytes.length >> 1)
  if (samples.length === 0) return
  const buffer = voiceCtx.createBuffer(1, samples.length, 24000)
  const channel = buffer.getChannelData(0)
  for (let i = 0; i < samples.length; i++) channel[i] = samples[i] / 0x8000
  const node = voiceCtx.createBufferSource()
  node.buffer = buffer
  node.connect(voiceCtx.destination)
  playAt = Math.max(playAt, voiceCtx.currentTime + 0.03)
  node.start(playAt)
  playAt += buffer.duration
  playing.add(node)
  setSpeaking(true)
  node.onended = () => {
    playing.delete(node)
    if (playing.size === 0) setSpeaking(false)
  }
}

/** The user spoke over Garad: stop its voice at once (Gemini says so with "interrupted"). */
function stopVoice() {
  for (const node of playing) {
    try {
      node.stop()
    } catch {}
  }
  playing.clear()
  playAt = 0
  setSpeaking(false)
}

// ---- Camera frames ----

const canvas = document.createElement("canvas")

function sendFrame() {
  if (!camOn || !active || active.readyState !== WebSocket.OPEN || !video.videoWidth) return
  // 768 px on the long side: sharp enough to read print, small enough for one frame a second.
  const scale = Math.min(1, 768 / Math.max(video.videoWidth, video.videoHeight))
  canvas.width = Math.round(video.videoWidth * scale)
  canvas.height = Math.round(video.videoHeight * scale)
  canvas.getContext("2d").drawImage(video, 0, 0, canvas.width, canvas.height)
  const jpeg = canvas.toDataURL("image/jpeg", 0.7).split(",")[1]
  send({ realtimeInput: { video: { data: jpeg, mimeType: "image/jpeg" } } })
}

// ---- Connection to Google, block by block ----

function send(message) {
  if (active && active.readyState === WebSocket.OPEN && active.ready) active.send(JSON.stringify(message))
}

/** Opens the next block's connection; it takes over the call once Google has set it up. */
async function connect() {
  if (ended || renewing) return
  renewing = true
  clearTimeout(renewTimer)
  let key
  try {
    key = await app("liveToken")
  } catch {
    key = null
  }
  if (ended) return
  if (!key || key.error) {
    renewing = false
    // Out of minutes or credits: the call stops, with a way to get more.
    return fail(key?.error || t("Wicitaanka lama bilaabi karo. Isku day mar kale.", "The call could not start. Please try again."), key?.code)
  }
  if (typeof key.free_seconds_left === "number") freeLeft = key.free_seconds_left
  showFree()

  const ws = new WebSocket(`${key.url}?access_token=${encodeURIComponent(key.token)}`)
  ws.ready = false
  ws.onopen = () => ws.send(JSON.stringify({ setup: { model: `models/${key.model}`, sessionResumption: handle ? { handle } : {} } }))
  ws.onmessage = async (event) => {
    const text = typeof event.data === "string" ? event.data : await event.data.text()
    let message
    try {
      message = JSON.parse(text)
    } catch {
      return
    }
    if (message.setupComplete) {
      // This connection now carries the call; the previous one (if any) is closed.
      const previous = active
      ws.ready = true
      active = ws
      renewing = false
      if (previous && previous !== ws) {
        previous.replaced = true
        previous.close()
      }
      if (!startedAt) {
        startedAt = Date.now()
        // Garad greets first, like picking up a call.
        ws.send(JSON.stringify({ realtimeInput: { text: t("Salaan si gaaban, adiga oo Soomaali ku hadlaya.", "Greet me briefly.") } }))
      }
      // The next block's key before this one runs out (keys live 20 s longer than their block).
      renewTimer = setTimeout(connect, Math.max(20, key.seconds - 10) * 1000)
      return
    }
    if (ws !== active) return
    handleServer(message)
  }
  ws.onclose = (event) => {
    if (ws.replaced || ended) return
    if (ws === active) {
      active = null
      // Closed by Google (time up, network): continue on a new connection.
      renewing = false
      if (event.code !== 1000 || handle) setTimeout(connect, 300)
    } else if (!ws.ready) {
      renewing = false
      fail(t("Isku xirka wuu go'ay. Isku day mar kale.", "The connection dropped. Please try again."))
    }
  }
}

function handleServer(message) {
  const content = message.serverContent
  if (content) {
    if (content.interrupted) stopVoice()
    for (const part of content.modelTurn?.parts || []) {
      if (part.inlineData?.data && (part.inlineData.mimeType || "").startsWith("audio/pcm")) playPcm(part.inlineData.data)
    }
    if (content.inputTranscription?.text) caption("you", content.inputTranscription.text)
    if (content.outputTranscription?.text) caption("garad", content.outputTranscription.text)
    if (content.turnComplete) {
      captions.you.final = true
      captions.garad.final = true
    }
  }
  if (message.sessionResumptionUpdate?.resumable && message.sessionResumptionUpdate.newHandle) {
    handle = message.sessionResumptionUpdate.newHandle
  }
  // Google is about to close this connection: move to the next one now.
  if (message.goAway) connect()
}

// ---- Captions ----

const captions = { you: { text: "", final: true }, garad: { text: "", final: true } }

function caption(who, piece) {
  const line = captions[who]
  if (line.final) {
    line.text = ""
    line.final = false
    if (who === "you") {
      captions.garad.text = ""
      $("garad").textContent = ""
    }
  }
  line.text += piece
  // The latest ~2 lines: a caption, not a transcript.
  const words = line.text.trim().split(/\s+/)
  $(who).textContent = (words.length > 24 ? "… " + words.slice(-24).join(" ") : line.text).trim()
}

// ---- Camera ----

async function openMedia() {
  const constraints = {
    audio: { echoCancellation: true, noiseSuppression: true, autoGainControl: true, channelCount: 1 },
    video: camOn ? { facingMode: facing, width: { ideal: 1280 }, height: { ideal: 720 } } : false,
  }
  stream = await navigator.mediaDevices.getUserMedia(constraints)
  showCamera()
}

function showCamera() {
  const track = stream?.getVideoTracks()[0]
  video.srcObject = track ? new MediaStream([track]) : null
  video.classList.toggle("mirrored", facing === "user")
  document.body.classList.toggle("camera-off", !track)
  $("cam").innerHTML = icon(camOn ? "cam" : "camoff")
  $("cam").classList.toggle("off", !camOn)
  $("flip").disabled = !camOn
}

async function toggleCamera() {
  camOn = !camOn
  if (!camOn) {
    for (const track of stream.getVideoTracks()) {
      track.stop()
      stream.removeTrack(track)
    }
  } else {
    try {
      const extra = await navigator.mediaDevices.getUserMedia({ video: { facingMode: facing, width: { ideal: 1280 }, height: { ideal: 720 } } })
      stream.addTrack(extra.getVideoTracks()[0])
    } catch {
      camOn = false
    }
  }
  showCamera()
}

async function flipCamera() {
  if (!camOn) return
  facing = facing === "user" ? "environment" : "user"
  for (const track of stream.getVideoTracks()) {
    track.stop()
    stream.removeTrack(track)
  }
  try {
    const extra = await navigator.mediaDevices.getUserMedia({ video: { facingMode: facing, width: { ideal: 1280 }, height: { ideal: 720 } } })
    stream.addTrack(extra.getVideoTracks()[0])
  } catch {
    facing = facing === "user" ? "environment" : "user"
  }
  showCamera()
}

function toggleMic() {
  micOn = !micOn
  // Tell Gemini the user stopped talking, so it answers what it heard instead of waiting.
  if (!micOn) send({ realtimeInput: { audioStreamEnd: true } })
  $("mic").innerHTML = icon(micOn ? "mic" : "micoff")
  $("mic").classList.toggle("off", !micOn)
  showLevel(0)
}

// ---- Look ----

function setSpeaking(on) {
  document.body.classList.toggle("speaking", on)
}

let levelShown = 0
function showLevel(level) {
  levelShown = levelShown * 0.6 + Math.min(1, level * 3) * 0.4
  document.body.style.setProperty("--level", micOn ? levelShown.toFixed(2) : "0")
}

function showFree() {
  $("free").textContent =
    freeLeft === null
      ? ""
      : freeLeft > 0
        ? t(`Bilaash: ${Math.ceil(freeLeft / 60)} daqiiqo ayaa maanta kuu haray`, `Free: ${Math.ceil(freeLeft / 60)} min left today`)
        : ""
}

setInterval(() => {
  if (!startedAt || ended) return
  const s = Math.floor((Date.now() - startedAt) / 1000)
  $("clock").textContent = `${Math.floor(s / 60)}:${String(s % 60).padStart(2, "0")}`
}, 500)

function fail(text, code) {
  ended = true
  stopAll()
  $("notice-text").textContent = text
  const actions = document.querySelector(".notice-actions")
  actions.innerHTML = ""
  if (code === "live_minutes_used") {
    const upgrade = document.createElement("button")
    upgrade.className = "primary"
    upgrade.textContent = t("Kor u qaad qorshaha", "Upgrade")
    upgrade.onclick = () => app("upgrade")
    actions.append(upgrade)
  }
  const close = document.createElement("button")
  close.textContent = t("Xir", "Close")
  close.onclick = () => app("end")
  actions.append(close)
  $("notice").hidden = false
}

function stopAll() {
  clearTimeout(renewTimer)
  stopVoice()
  try {
    active?.close()
  } catch {}
  active = null
  for (const track of stream?.getTracks() || []) track.stop()
  micCtx?.close().catch(() => {})
}

function end() {
  if (!ended) {
    ended = true
    stopAll()
  }
  app("end")
}

// ---- Start ----

$("cam").onclick = toggleCamera
$("flip").onclick = flipCamera
$("mic").onclick = toggleMic
$("end").onclick = end
window.garadLive = { end: () => end() }

function base64(bytes) {
  let binary = ""
  for (let i = 0; i < bytes.length; i += 0x8000) binary += String.fromCharCode(...bytes.subarray(i, i + 0x8000))
  return btoa(binary)
}

;(async () => {
  $("title").textContent = "Garad Live"
  document.body.classList.toggle("dark", true)
  await appReady()
  try {
    await openMedia()
  } catch {
    return fail(t("Kamaradda iyo makarafoonka lama furi karo. Hubi oggolaanshaha.", "The camera and microphone could not be opened. Check the permissions."))
  }
  await voiceCtx.resume().catch(() => {})
  await startMicrophone()
  // The microphone switched the phone to call mode: the app puts Garad's voice on the loudspeaker.
  app("audioReady")
  setInterval(sendFrame, 1000)
  connect()
})()
