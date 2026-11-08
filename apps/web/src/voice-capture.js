/* global AudioWorkletProcessor, registerProcessor */
// 16 kHz mono PCM, 80 ms per frame. Runs outside React/the UI thread.
class VoiceCapture extends AudioWorkletProcessor {
  constructor() {
    super()
    this.frame = new Int16Array(1280)
    this.position = 0
  }
  process(inputs) {
    const samples = inputs[0]?.[0]
    if (samples) for (const sample of samples) {
      this.frame[this.position++] = Math.round(Math.max(-1, Math.min(1, sample)) * 32767)
      if (this.position === this.frame.length) {
        this.port.postMessage(this.frame.buffer, [this.frame.buffer])
        this.frame = new Int16Array(1280)
        this.position = 0
      }
    }
    return true
  }
}
registerProcessor('nobarsync-voice-capture', VoiceCapture)
