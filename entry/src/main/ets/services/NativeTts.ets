import { textToSpeech } from '@kit.CoreSpeechKit';
import { BusinessError } from '@kit.BasicServicesKit';

interface TtsVoice { id: string; name: string; lang: string }

/**
 * Core Speech Kit backend for readest's plugin:native-tts surface.
 *
 * Contract (readest services/tts/NativeTTSClient.ts):
 * - init -> {success}; speak {payload:{text, preload}} -> {utteranceId};
 *   progress arrives as 'tts_events' plugin events {utteranceId, code,
 *   message, mark} (code: 'start'|'mark'|'end'|'error') through the Channel
 *   registered via plugin:native-tts|register_listener.
 * - OHOS callbacks expose start/complete/stop/error only (no sentence
 *   boundaries), so highlight advances per utterance — the frontend tolerates
 *   missing 'mark' events (Android TextToSpeech behaves the same way).
 * - pause maps to stop (the engine has no pause); resume is a no-op, both
 *   matching the Android reference semantics.
 */
export class NativeTts {
  private engine: textToSpeech.TextToSpeechEngine | null = null;
  private lang: string = 'zh-CN';
  private rate: number = 1.0;
  private pitch: number = 1.0;
  private person: number = 13;
  private onEvent: ((utteranceId: string, code: string, message: string) => void) | null = null;
  private utterSeq: number = 0;

  setEventListener(cb: (utteranceId: string, code: string, message: string) => void): void {
    this.onEvent = cb;
  }

  async init(): Promise<boolean> {
    try {
      if (this.engine === null) {
        this.engine = await textToSpeech.createEngine({
          language: this.lang,
          person: this.person,
          online: 1,
          extraParams: { 'isBackStage': true } as Record<string, Object>
        } as textToSpeech.CreateEngineParams);
        this.engine.setListener({
          onStart: (requestId: string) => {
            this.fire(requestId, 'start', '');
          },
          onComplete: (requestId: string) => {
            this.fire(requestId, 'end', '');
          },
          onStop: (requestId: string) => {
            this.fire(requestId, 'end', 'stopped');
          },
          onError: (requestId: string, code: number, message: string) => {
            this.fire(requestId, 'error', `${code}: ${message}`);
          }
        } as textToSpeech.SpeakListener);
      }
      return this.engine !== null;
    } catch (e) {
      console.error(`[NativeTts] init failed: ${JSON.stringify(e)}`);
      return false;
    }
  }

  async speak(text: string, preload: boolean): Promise<string> {
    const utteranceId: string = `ohos-tts-${++this.utterSeq}`;
    if (!this.engine) {
      const ok: boolean = await this.init();
      if (!ok) {
        throw new Error('tts engine unavailable');
      }
    }
    if (preload) {
      // the engine has no pre-synthesis cache; report immediate completion
      this.fire(utteranceId, 'end', 'Dummy preload finished');
      return utteranceId;
    }
    this.engine!.speak(text, {
      requestId: utteranceId,
      extraParams: {
        'speed': Math.max(0.75, Math.min(2.0, this.rate)),
        'pitch': Math.max(0.5, Math.min(2.0, this.pitch))
      } as Record<string, Object>
    } as textToSpeech.SpeakParams);
    return utteranceId;
  }

  stop(): void {
    try {
      this.engine?.stop();
    } catch (e) {
      const err = e as BusinessError;
      console.error(`[NativeTts] stop failed: ${err.code}`);
    }
  }

  pause(): void {
    // no engine pause: stop matches the Android reference behavior
    this.stop();
  }

  setRate(rate: number): void {
    this.rate = rate;
  }

  setPitch(pitch: number): void {
    this.pitch = pitch;
  }

  setVoice(voiceId: string): void {
    const p: number = parseInt(voiceId, 10);
    if (!isNaN(p)) {
      this.person = p;
      this.engine = null; // recreated with the new timbre on next speak
    }
  }

  setLanguage(lang: string): void {
    const normalized: string = lang.replace('_', '-');
    if (normalized !== this.lang) {
      this.lang = normalized;
      this.engine = null; // recreated with the new language on next speak
    }
  }

  async voices(): Promise<TtsVoice[]> {
    try {
      if (!this.engine) {
        const ok: boolean = await this.init();
        if (!ok) {
          return [];
        }
      }
      const infos: Array<textToSpeech.VoiceInfo> =
        await this.engine!.listVoices({} as textToSpeech.VoiceQuery);
      const out: TtsVoice[] = [];
      for (let i = 0; i < infos.length; i++) {
        const v: textToSpeech.VoiceInfo = infos[i];
        const voice: TtsVoice = { id: '13', name: `OHOS ${v.language} #13`, lang: v.language };
        out.push(voice);
      }
      return out;
    } catch (e) {
      console.error(`[NativeTts] listVoices failed: ${JSON.stringify(e)}`);
      return [];
    }
  }

  private fire(utteranceId: string, code: string, message: string): void {
    if (this.onEvent !== null) {
      try {
        this.onEvent(utteranceId, code, message);
      } catch (e) {
        // listener errors must never take down synthesis
      }
    }
  }
}

export const nativeTts: NativeTts = new NativeTts();
