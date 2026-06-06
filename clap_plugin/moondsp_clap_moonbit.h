#ifndef MOONDSP_CLAP_MOONBIT_H
#define MOONDSP_CLAP_MOONBIT_H

#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

// MoonBit runtime entrypoints emitted/linked by the native backend.
void moonbit_runtime_init(int argc, char **argv);
void moonbit_init(void);

// Primitive bridge symbols emitted by `moon build --target native clap_plugin`.
// These names are currently MoonBit-mangled. The custom CLAP build should
// compile the generated `clap_plugin.c` payload and this C shim together.
int32_t _M0FP39dowdiness7moondsp10clap__host14engine__create(
    double sample_rate, int32_t max_block_size, int32_t max_voices);
int32_t _M0FP39dowdiness7moondsp10clap__host15engine__destroy(int32_t handle);
int32_t _M0FP39dowdiness7moondsp10clap__host16engine__note__on(
    int32_t handle, int32_t note_id, int32_t key, double velocity);
int32_t _M0FP39dowdiness7moondsp10clap__host17engine__note__off(
    int32_t handle, int32_t note_id, int32_t key);
int32_t _M0FP39dowdiness7moondsp10clap__host23engine__all__notes__off(
    int32_t handle);
int32_t _M0FP39dowdiness7moondsp10clap__host18engine__set__param(
    int32_t handle, int32_t param_id, double value);
int32_t _M0FP39dowdiness7moondsp10clap__host15engine__process(
    int32_t handle, int32_t frame_count);
double _M0FP39dowdiness7moondsp10clap__host20engine__left__sample(
    int32_t handle, int32_t index);
double _M0FP39dowdiness7moondsp10clap__host21engine__right__sample(
    int32_t handle, int32_t index);
double _M0FP39dowdiness7moondsp10clap__host20engine__master__gain(
    int32_t handle);
double _M0FP39dowdiness7moondsp10clap__host19engine__voice__gain(
    int32_t handle);
double _M0FP39dowdiness7moondsp10clap__host18engine__cutoff__hz(
    int32_t handle);
double _M0FP39dowdiness7moondsp10clap__host17engine__resonance(
    int32_t handle);
double _M0FP39dowdiness7moondsp10clap__host11engine__pan(int32_t handle);

#define mb_engine_create _M0FP39dowdiness7moondsp10clap__host14engine__create
#define mb_engine_destroy _M0FP39dowdiness7moondsp10clap__host15engine__destroy
#define mb_engine_note_on _M0FP39dowdiness7moondsp10clap__host16engine__note__on
#define mb_engine_note_off _M0FP39dowdiness7moondsp10clap__host17engine__note__off
#define mb_engine_all_notes_off _M0FP39dowdiness7moondsp10clap__host23engine__all__notes__off
#define mb_engine_set_param _M0FP39dowdiness7moondsp10clap__host18engine__set__param
#define mb_engine_process _M0FP39dowdiness7moondsp10clap__host15engine__process
#define mb_engine_left_sample _M0FP39dowdiness7moondsp10clap__host20engine__left__sample
#define mb_engine_right_sample _M0FP39dowdiness7moondsp10clap__host21engine__right__sample
#define mb_engine_master_gain _M0FP39dowdiness7moondsp10clap__host20engine__master__gain
#define mb_engine_voice_gain _M0FP39dowdiness7moondsp10clap__host19engine__voice__gain
#define mb_engine_cutoff_hz _M0FP39dowdiness7moondsp10clap__host18engine__cutoff__hz
#define mb_engine_resonance _M0FP39dowdiness7moondsp10clap__host17engine__resonance
#define mb_engine_pan _M0FP39dowdiness7moondsp10clap__host11engine__pan

#ifdef __cplusplus
}
#endif

#endif
