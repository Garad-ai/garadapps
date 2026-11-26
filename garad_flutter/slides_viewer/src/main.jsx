// The Garad app's slide viewer. The app (lib/screens/slides_screen.dart) hosts this page in a web view,
// hands it the deck, and draws its own controls around it (‹ 3 / 8 ›, Grid, Present). The slides are
// drawn by the same renderer as garad.ai's slide view (frontend/src/core/ArtifactPanel.tsx), so a deck
// looks the same in the app and on the website.

import "@extend-ai/react-pptx/styles.css"
import "./style.css"

import { createPptxThumbnailRenderer, ReactPptxViewer } from "@extend-ai/react-pptx"
import { StrictMode, useCallback, useEffect, useRef, useState } from "react"
import { createRoot } from "react-dom/client"

import { previewablePptx } from "./previewable.js"

const params = new URLSearchParams(window.location.search)
document.documentElement.dataset.theme = params.get("theme") === "dark" ? "dark" : "light"

/** Messages to the app (flutter_inappwebview's JavaScript handlers). */
function tell(name, data) {
  try {
    window.flutter_inappwebview?.callHandler(name, data)
  } catch {
    // Outside the app (a browser while developing): nothing to tell.
  }
}

/** The deck from the app, as bytes. The app answers the "deck" handler with the file in base64. */
async function deckFromApp() {
  const base64 = await window.flutter_inappwebview.callHandler("deck")
  if (typeof base64 !== "string" || base64 === "") throw new Error("The presentation could not be read.")
  const binary = atob(base64)
  const bytes = new Uint8Array(binary.length)
  for (let i = 0; i < binary.length; i++) bytes[i] = binary.charCodeAt(i)
  return previewablePptx(bytes)
}

function whenAppReady() {
  return new Promise((resolve) => {
    if (window.flutter_inappwebview?.callHandler) resolve()
    else window.addEventListener("flutterInAppWebViewPlatformReady", () => resolve(), { once: true })
  })
}

/** Slide pictures for the Grid, made once the deck is parsed (like the website's Grid view). */
function useSlidePictures(presentation, wanted) {
  const [pictures, setPictures] = useState([])

  useEffect(() => {
    if (!presentation || !wanted) return
    let cancelled = false
    const urls = []
    const renderer = createPptxThumbnailRenderer(presentation)
    void (async () => {
      await renderer.ready
      const count = presentation.document.slides.length
      for (let index = 0; index < count && !cancelled; index++) {
        try {
          const result = await renderer.renderSlide(index, { output: "blob", maxWidth: 480, pixelRatio: 2 })
          const url = URL.createObjectURL(result.data)
          urls.push(url)
          if (!cancelled)
            setPictures((current) => {
              const next = [...current]
              next[index] = url
              return next
            })
        } catch {
          // A slide that cannot be drawn keeps its numbered placeholder.
        }
      }
    })()

    return () => {
      cancelled = true
      renderer.destroy()
      urls.forEach((url) => URL.revokeObjectURL(url))
      setPictures([])
    }
  }, [presentation, wanted])

  return pictures
}

function App() {
  const [source, setSource] = useState(null)
  const [error, setError] = useState("")
  const [presentation, setPresentation] = useState(null)
  const [slide, setSlide] = useState(0)
  const [view, setView] = useState("one")
  const [presenting, setPresenting] = useState(false)
  const [notes, setNotes] = useState(false)
  const count = presentation?.document.slides.length ?? 0
  const pictures = useSlidePictures(presentation, view === "grid")

  const go = useCallback(
    (index) => setSlide((current) => {
      const last = Math.max(count - 1, 0)
      const next = typeof index === "function" ? index(current) : index
      return Math.min(Math.max(next, 0), last)
    }),
    [count],
  )

  // The app's controls call these.
  useEffect(() => {
    window.garadSlides = {
      go: (index) => go(index),
      next: () => go((current) => current + 1),
      previous: () => go((current) => current - 1),
      setView: (next) => setView(next === "grid" ? "grid" : "one"),
      setPresenting: (on) => setPresenting(Boolean(on)),
      setNotes: (on) => setNotes(Boolean(on)),
    }
  }, [go])

  useEffect(() => {
    let cancelled = false
    whenAppReady()
      .then(deckFromApp)
      .then((bytes) => !cancelled && setSource(bytes))
      .catch((reason) => !cancelled && setError(reason instanceof Error ? reason.message : String(reason)))
    return () => {
      cancelled = true
    }
  }, [])

  useEffect(() => {
    if (error) tell("slides", { error })
  }, [error])

  useEffect(() => {
    if (count > 0) tell("slides", { count, slide, view })
  }, [count, slide, view])

  // Swipe left / right for the next / previous slide; in Present, a tap is the next slide.
  const touch = useRef(null)
  const onTouchStart = (event) => {
    const t = event.touches[0]
    touch.current = { x: t.clientX, y: t.clientY, at: Date.now() }
  }
  const onTouchEnd = (event) => {
    const start = touch.current
    touch.current = null
    if (!start) return
    const t = event.changedTouches[0]
    const dx = t.clientX - start.x
    const dy = t.clientY - start.y
    if (Math.abs(dx) > 40 && Math.abs(dx) > Math.abs(dy) * 1.3) {
      go((current) => current + (dx < 0 ? 1 : -1))
    } else if (presenting && Math.abs(dx) < 10 && Math.abs(dy) < 10 && Date.now() - start.at < 400) {
      go((current) => current + 1)
    }
  }

  if (error) return <div className="message">{error}</div>
  if (!source) return <div className="message"><span className="spinner" /></div>

  return (
    <>
      <div
        className={`slide-area${presenting ? " presenting" : ""}${view === "grid" && !presenting ? " hidden" : ""}`}
        onTouchStart={onTouchStart}
        onTouchEnd={onTouchEnd}
      >
        <ReactPptxViewer
          source={source}
          mode="slide"
          slideIndex={slide}
          onSlideChange={go}
          onLoad={setPresentation}
          onError={(reason) => setError(reason?.message || "This presentation could not be shown.")}
          defaultZoom="fit-page"
          height="100%"
          showToolbar={false}
          showThumbnails={false}
          showNotes={notes && !presenting}
          renderLoading={() => <div className="message"><span className="spinner" /></div>}
        />
      </div>
      {view === "grid" && !presenting && (
        <div className="grid">
          {Array.from({ length: count }, (_, index) => (
            <button
              type="button"
              key={index}
              className={index === slide ? "active" : ""}
              onClick={() => {
                go(index)
                setView("one")
              }}
            >
              <div className="frame">{pictures[index] ? <img src={pictures[index]} alt="" /> : <i />}</div>
              <span>{index + 1}</span>
            </button>
          ))}
        </div>
      )}
    </>
  )
}

createRoot(document.getElementById("root")).render(
  <StrictMode>
    <App />
  </StrictMode>,
)
