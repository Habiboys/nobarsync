declare module "phoenix" {
  export class Socket {
    constructor(endpoint: string, opts?: { timeout?: number; params?: () => Record<string, string> })
    onError(callback: () => void): void
    connect(): void
    disconnect(): void
    channel(topic: string, params?: object): Channel
  }
  export class Channel {
    onError(callback: () => void): void
    onClose(callback: () => void): void
    join(): Push
    leave(): void
    on(event: string, callback: (payload: Record<string, unknown>) => void): void
    push(event: string, payload: object): Push
  }
  export class Push {
    receive(status: string, callback: (response: Record<string, unknown>) => void): Push
  }
}

interface YtPlayer {
  setVolume(value: number): void
  mute(): void
  unMute(): void
  playVideo(): void
  pauseVideo(): void
  seekTo(seconds: number, allowSeekAhead: boolean): void
  getCurrentTime(): number
  getDuration(): number
  setPlaybackRate(rate: number): void
  getPlayerState(): number
  destroy(): void
}

interface Window {
  YT?: {
    Player: new (element: HTMLElement, options: Record<string, unknown>) => YtPlayer
  }
  onYouTubeIframeAPIReady?: () => void
}

