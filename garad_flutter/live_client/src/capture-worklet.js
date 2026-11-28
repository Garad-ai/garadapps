// The microphone, as 16 kHz 16-bit PCM in ~100 ms pieces: what Google's Live API takes.
// Runs on the audio thread; the page sends each piece to Gemini.
class Capture extends AudioWorkletProcessor {
  constructor() {
    super()
    this.ratio = sampleRate / 16000
    this.pos = 0
    this.out = new Int16Array(1600)
    this.n = 0
    this.level = 0
  }

  process(inputs) {
    const input = inputs[0] && inputs[0][0]
    if (!input) return true
    let peak = 0
    // Simple downsampling: average the samples that fall into each 16 kHz step.
    for (let i = 0; i < input.length; i++) {
      const s = input[i]
      if (Math.abs(s) > peak) peak = Math.abs(s)
      this.pos += 1
      if (this.pos >= this.ratio) {
        this.pos -= this.ratio
        const v = Math.max(-1, Math.min(1, s))
        this.out[this.n++] = v < 0 ? v * 0x8000 : v * 0x7fff
        if (this.n === this.out.length) {
          this.port.postMessage({ pcm: this.out.buffer, level: this.level }, [this.out.buffer])
          this.out = new Int16Array(1600)
          this.n = 0
          this.level = 0
        }
      }
    }
    this.level = Math.max(this.level, peak)
    return true
  }
}

registerProcessor("garad-capture", Capture)
