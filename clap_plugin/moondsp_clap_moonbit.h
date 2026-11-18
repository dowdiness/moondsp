#ifndef MOONDSP_CLAP_MOONBIT_H
#define MOONDSP_CLAP_MOONBIT_H

/*
 * Stable C ABI exported by the MoonBit payload in clap_plugin/clap_payload.mbt
 * through `#export_name`. Keep these declarations in sync with that file; the
 * CLAP build scripts compile the payload C with this header included, so a
 * mismatched signature fails the build.
 */

#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

// MoonBit runtime entrypoints emitted/linked by the native backend.
void moonbit_init(void);

// MoonBit Bool results cross this boundary as int32_t 1 or 0.
int32_t mb_engine_create(double sample_rate, int32_t max_block_size, int32_t max_voices);
int32_t mb_engine_destroy(int32_t handle);
int32_t mb_engine_note_on(int32_t handle, int32_t note_id, int32_t key, double velocity);
int32_t mb_engine_note_off(int32_t handle, int32_t note_id, int32_t key);
int32_t mb_engine_all_notes_off(int32_t handle);
int32_t mb_engine_set_param(int32_t handle, int32_t param_id, double value);
int32_t mb_engine_process(int32_t handle, int32_t frame_count);
double mb_engine_left_sample(int32_t handle, int32_t index);
double mb_engine_right_sample(int32_t handle, int32_t index);
double mb_engine_master_gain(int32_t handle);
double mb_engine_voice_gain(int32_t handle);
double mb_engine_cutoff_hz(int32_t handle);
double mb_engine_resonance(int32_t handle);
double mb_engine_pan(int32_t handle);

#ifdef __cplusplus
}
#endif

#endif
