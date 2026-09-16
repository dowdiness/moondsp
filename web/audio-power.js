import { GraphEngine } from './graph-engine.js';
import {
  audio_power_new,
  audio_power_turn_on,
  powered_audio_resume,
  powered_audio_turn_off,
} from './audio-power-core.js';

/** Own a sequence of realtime audio power cycles. Construction allocates no audio resources. */
export function AudioPower(options) {
  const owner = audio_power_new(options, GraphEngine);
  return Object.freeze({
    turnOn(setupAudio) {
      const started = audio_power_turn_on(owner, setupAudio);
      if (!started.ok) throw started.error;
      const generation = started.generation;
      return Object.freeze({
        context: started.context,
        ready: started.ready,
        ended: started.ended,
        resume: () => powered_audio_resume(generation),
        turnOff: () => powered_audio_turn_off(generation),
      });
    },
  });
}
