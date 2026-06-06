#include <clap/entry.h>
#include <clap/events.h>
#include <clap/ext/audio-ports.h>
#include <clap/ext/note-ports.h>
#include <clap/ext/params.h>
#include <clap/factory/plugin-factory.h>
#include <clap/plugin-features.h>
#include <clap/process.h>

#include "moondsp_clap_moonbit.h"

#include <limits.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#define MOONDSP_PLUGIN_ID "com.dowdiness.moondsp.synth"
#define MOONDSP_PLUGIN_NAME "moondsp Synth"
#define MOONDSP_VENDOR "dowdiness"
#define MOONDSP_VERSION "0.1.0"

#define PARAM_MASTER_GAIN 0u
#define PARAM_VOICE_GAIN 1u
#define PARAM_CUTOFF_HZ 2u
#define PARAM_RESONANCE 3u
#define PARAM_PAN 4u
#define PARAM_COUNT 5u

typedef struct moondsp_plugin_state {
  const clap_host_t *host;
  clap_plugin_t plugin;
  int32_t engine_handle;
  double sample_rate;
  uint32_t max_frames_count;
  bool processing;
  bool transport_known;
  bool transport_playing;
} moondsp_plugin_state_t;

static bool moonbit_ready = false;

static void ensure_moonbit_runtime(void) {
  if (!moonbit_ready) {
    moonbit_runtime_init(0, NULL);
    moonbit_init();
    moonbit_ready = true;
  }
}

static moondsp_plugin_state_t *state_from_plugin(const clap_plugin_t *plugin) {
  return plugin ? (moondsp_plugin_state_t *)plugin->plugin_data : NULL;
}

static const char *const moondsp_features[] = {
    CLAP_PLUGIN_FEATURE_INSTRUMENT,
    CLAP_PLUGIN_FEATURE_SYNTHESIZER,
    CLAP_PLUGIN_FEATURE_STEREO,
    NULL,
};

static const clap_plugin_descriptor_t moondsp_descriptor = {
    .clap_version = CLAP_VERSION_INIT,
    .id = MOONDSP_PLUGIN_ID,
    .name = MOONDSP_PLUGIN_NAME,
    .vendor = MOONDSP_VENDOR,
    .url = "https://github.com/dowdiness/moondsp",
    .manual_url = "https://github.com/dowdiness/moondsp",
    .support_url = "https://github.com/dowdiness/moondsp/issues",
    .version = MOONDSP_VERSION,
    .description = "MoonBit moondsp CLAP instrument prototype",
    .features = moondsp_features,
};

static bool moondsp_plugin_init(const clap_plugin_t *plugin) {
  (void)plugin;
  ensure_moonbit_runtime();
  return true;
}

static void destroy_engine_if_needed(moondsp_plugin_state_t *state) {
  if (state && state->engine_handle > 0) {
    mb_engine_destroy(state->engine_handle);
    state->engine_handle = 0;
  }
}

static void moondsp_plugin_destroy(const clap_plugin_t *plugin) {
  moondsp_plugin_state_t *state = state_from_plugin(plugin);
  destroy_engine_if_needed(state);
  free(state);
}

static bool moondsp_plugin_activate(const clap_plugin_t *plugin,
                                    double sample_rate,
                                    uint32_t min_frames_count,
                                    uint32_t max_frames_count) {
  moondsp_plugin_state_t *state = state_from_plugin(plugin);
  if (!state || !(sample_rate > 0.0) || min_frames_count == 0 ||
      max_frames_count == 0 || min_frames_count > max_frames_count ||
      max_frames_count > (uint32_t)INT32_MAX) {
    return false;
  }
  ensure_moonbit_runtime();
  destroy_engine_if_needed(state);
  state->sample_rate = sample_rate;
  state->max_frames_count = max_frames_count;
  state->engine_handle = mb_engine_create(sample_rate, (int32_t)max_frames_count, 32);
  return state->engine_handle > 0;
}

static void moondsp_plugin_deactivate(const clap_plugin_t *plugin) {
  moondsp_plugin_state_t *state = state_from_plugin(plugin);
  destroy_engine_if_needed(state);
}

static bool moondsp_plugin_start_processing(const clap_plugin_t *plugin) {
  moondsp_plugin_state_t *state = state_from_plugin(plugin);
  if (!state || state->engine_handle <= 0) {
    return false;
  }
  state->processing = true;
  return true;
}

static void moondsp_plugin_stop_processing(const clap_plugin_t *plugin) {
  moondsp_plugin_state_t *state = state_from_plugin(plugin);
  if (state) {
    if (state->engine_handle > 0) {
      mb_engine_all_notes_off(state->engine_handle);
    }
    state->processing = false;
  }
}

static void moondsp_plugin_reset(const clap_plugin_t *plugin) {
  moondsp_plugin_state_t *state = state_from_plugin(plugin);
  if (state && state->engine_handle > 0) {
    mb_engine_all_notes_off(state->engine_handle);
  }
}

static bool event_has_size(const clap_event_header_t *header,
                           uint32_t expected_size) {
  return header && header->size >= expected_size;
}

static void update_transport_playing(moondsp_plugin_state_t *state,
                                     bool is_playing) {
  if (!state) {
    return;
  }
  if (state->transport_known && state->transport_playing && !is_playing &&
      state->engine_handle > 0) {
    mb_engine_all_notes_off(state->engine_handle);
  }
  state->transport_known = true;
  state->transport_playing = is_playing;
}

static void handle_transport_event(moondsp_plugin_state_t *state,
                                   const clap_event_transport_t *event) {
  if (!event) {
    return;
  }
  update_transport_playing(
      state,
      (event->flags & CLAP_TRANSPORT_IS_PLAYING) == CLAP_TRANSPORT_IS_PLAYING);
}

static void handle_midi_data(moondsp_plugin_state_t *state,
                             const uint8_t data[3]) {
  if (!state || state->engine_handle <= 0 || !data) {
    return;
  }
  const uint8_t status = data[0] & 0xF0u;
  const int32_t key = (int32_t)(data[1] & 0x7Fu);
  const uint8_t value = data[2] & 0x7Fu;
  switch (status) {
  case 0x80u:
    mb_engine_note_off(state->engine_handle, -1, key);
    break;
  case 0x90u:
    if (value == 0) {
      mb_engine_note_off(state->engine_handle, -1, key);
    } else {
      mb_engine_note_on(state->engine_handle, -1, key, (double)value / 127.0);
    }
    break;
  case 0xB0u:
    if (data[1] == 120u || data[1] == 123u) {
      mb_engine_all_notes_off(state->engine_handle);
    }
    break;
  default:
    break;
  }
}

static void handle_input_event(moondsp_plugin_state_t *state,
                               const clap_event_header_t *header) {
  if (!state || state->engine_handle <= 0 || !header ||
      header->space_id != CLAP_CORE_EVENT_SPACE_ID) {
    return;
  }
  switch (header->type) {
  case CLAP_EVENT_NOTE_ON: {
    if (!event_has_size(header, sizeof(clap_event_note_t))) {
      return;
    }
    const clap_event_note_t *event = (const clap_event_note_t *)header;
    if (event->key < 0) {
      return;
    }
    mb_engine_note_on(state->engine_handle, event->note_id, (int32_t)event->key,
                      event->velocity);
    break;
  }
  case CLAP_EVENT_NOTE_OFF:
  case CLAP_EVENT_NOTE_CHOKE: {
    if (!event_has_size(header, sizeof(clap_event_note_t))) {
      return;
    }
    const clap_event_note_t *event = (const clap_event_note_t *)header;
    if (event->note_id < 0 && event->key < 0) {
      mb_engine_all_notes_off(state->engine_handle);
    } else {
      mb_engine_note_off(state->engine_handle, event->note_id,
                         (int32_t)event->key);
    }
    break;
  }
  case CLAP_EVENT_PARAM_VALUE: {
    if (!event_has_size(header, sizeof(clap_event_param_value_t))) {
      return;
    }
    const clap_event_param_value_t *event =
        (const clap_event_param_value_t *)header;
    mb_engine_set_param(state->engine_handle, (int32_t)event->param_id,
                        event->value);
    break;
  }
  case CLAP_EVENT_TRANSPORT: {
    if (!event_has_size(header, sizeof(clap_event_transport_t))) {
      return;
    }
    handle_transport_event(state, (const clap_event_transport_t *)header);
    break;
  }
  case CLAP_EVENT_MIDI: {
    if (!event_has_size(header, sizeof(clap_event_midi_t))) {
      return;
    }
    const clap_event_midi_t *event = (const clap_event_midi_t *)header;
    handle_midi_data(state, event->data);
    break;
  }
  default:
    break;
  }
}

static void handle_input_events(moondsp_plugin_state_t *state,
                                const clap_input_events_t *events) {
  if (!events || !events->size || !events->get) {
    return;
  }
  const uint32_t count = events->size(events);
  for (uint32_t i = 0; i < count; i++) {
    handle_input_event(state, events->get(events, i));
  }
}

static void clear_output(clap_audio_buffer_t *output, uint32_t frames_count) {
  if (!output || output->channel_count == 0) {
    return;
  }
  for (uint32_t ch = 0; ch < output->channel_count; ch++) {
    if (output->data32 && output->data32[ch]) {
      memset(output->data32[ch], 0, sizeof(float) * frames_count);
    }
    if (output->data64 && output->data64[ch]) {
      memset(output->data64[ch], 0, sizeof(double) * frames_count);
    }
  }
}

static void copy_engine_output(moondsp_plugin_state_t *state,
                               clap_audio_buffer_t *output,
                               uint32_t output_offset,
                               uint32_t frames_count) {
  if (!state || state->engine_handle <= 0 || !output || output->channel_count < 2) {
    return;
  }
  if (output->data64 && output->data64[0] && output->data64[1]) {
    for (uint32_t i = 0; i < frames_count; i++) {
      output->data64[0][output_offset + i] =
          mb_engine_left_sample(state->engine_handle, (int32_t)i);
      output->data64[1][output_offset + i] =
          mb_engine_right_sample(state->engine_handle, (int32_t)i);
    }
  } else if (output->data32 && output->data32[0] && output->data32[1]) {
    for (uint32_t i = 0; i < frames_count; i++) {
      output->data32[0][output_offset + i] =
          (float)mb_engine_left_sample(state->engine_handle, (int32_t)i);
      output->data32[1][output_offset + i] =
          (float)mb_engine_right_sample(state->engine_handle, (int32_t)i);
    }
  }
}

static void render_span(moondsp_plugin_state_t *state,
                        clap_audio_buffer_t *output,
                        uint32_t start_frame,
                        uint32_t end_frame) {
  if (end_frame <= start_frame) {
    return;
  }
  const uint32_t span = end_frame - start_frame;
  if (span > (uint32_t)INT32_MAX) {
    return;
  }
  const int32_t rendered = mb_engine_process(state->engine_handle, (int32_t)span);
  if (rendered > 0) {
    copy_engine_output(state, output, start_frame, (uint32_t)rendered);
  }
}

static int32_t moondsp_plugin_process(const clap_plugin_t *plugin,
                                      const clap_process_t *process) {
  moondsp_plugin_state_t *state = state_from_plugin(plugin);
  if (!state || !process || state->engine_handle <= 0) {
    return CLAP_PROCESS_ERROR;
  }
  if (process->audio_outputs_count == 0 || !process->audio_outputs) {
    return CLAP_PROCESS_CONTINUE;
  }
  clap_audio_buffer_t *output = &process->audio_outputs[0];
  const uint32_t frames_count = process->frames_count;
  clear_output(output, frames_count);
  if (process->transport) {
    handle_transport_event(state, process->transport);
  }
  uint32_t cursor = 0;
  const clap_input_events_t *events = process->in_events;
  if (events && events->size && events->get) {
    const uint32_t event_count = events->size(events);
    for (uint32_t i = 0; i < event_count; i++) {
      const clap_event_header_t *event = events->get(events, i);
      if (!event) {
        continue;
      }
      uint32_t event_time = event->time;
      if (event_time > frames_count) {
        event_time = frames_count;
      }
      if (event_time < cursor) {
        event_time = cursor;
      }
      render_span(state, output, cursor, event_time);
      cursor = event_time;
      handle_input_event(state, event);
    }
  }
  render_span(state, output, cursor, frames_count);
  return CLAP_PROCESS_CONTINUE;
}

static uint32_t audio_ports_count(const clap_plugin_t *plugin, bool is_input) {
  (void)plugin;
  return is_input ? 0u : 1u;
}

static bool audio_ports_get(const clap_plugin_t *plugin, uint32_t index,
                            bool is_input, clap_audio_port_info_t *info) {
  (void)plugin;
  if (is_input || index != 0 || !info) {
    return false;
  }
  memset(info, 0, sizeof(*info));
  info->id = 0;
  snprintf(info->name, sizeof(info->name), "Main Out");
  info->flags = CLAP_AUDIO_PORT_IS_MAIN;
  info->channel_count = 2;
  info->port_type = CLAP_PORT_STEREO;
  info->in_place_pair = CLAP_INVALID_ID;
  return true;
}

static const clap_plugin_audio_ports_t audio_ports_extension = {
    .count = audio_ports_count,
    .get = audio_ports_get,
};

static uint32_t note_ports_count(const clap_plugin_t *plugin, bool is_input) {
  (void)plugin;
  return is_input ? 1u : 0u;
}

static bool note_ports_get(const clap_plugin_t *plugin, uint32_t index,
                           bool is_input, clap_note_port_info_t *info) {
  (void)plugin;
  if (!is_input || index != 0 || !info) {
    return false;
  }
  memset(info, 0, sizeof(*info));
  info->id = 0;
  info->supported_dialects = CLAP_NOTE_DIALECT_CLAP;
  info->preferred_dialect = CLAP_NOTE_DIALECT_CLAP;
  snprintf(info->name, sizeof(info->name), "Note In");
  return true;
}

static const clap_plugin_note_ports_t note_ports_extension = {
    .count = note_ports_count,
    .get = note_ports_get,
};

typedef struct param_defaults {
  clap_id id;
  const char *name;
  double min_value;
  double max_value;
  double default_value;
} param_defaults_t;

static const param_defaults_t params[PARAM_COUNT] = {
    {PARAM_MASTER_GAIN, "Master Gain", 0.0, 4.0, 0.8},
    {PARAM_VOICE_GAIN, "Voice Gain", 0.0, 4.0, 0.25},
    {PARAM_CUTOFF_HZ, "Cutoff", 20.0, 20000.0, 1600.0},
    {PARAM_RESONANCE, "Resonance", 0.05, 32.0, 0.707},
    {PARAM_PAN, "Pan", -1.0, 1.0, 0.0},
};

static const param_defaults_t *param_by_id(clap_id id) {
  for (uint32_t i = 0; i < PARAM_COUNT; i++) {
    if (params[i].id == id) {
      return &params[i];
    }
  }
  return NULL;
}

static uint32_t params_count(const clap_plugin_t *plugin) {
  (void)plugin;
  return PARAM_COUNT;
}

static bool params_get_info(const clap_plugin_t *plugin, uint32_t param_index,
                            clap_param_info_t *param_info) {
  (void)plugin;
  if (!param_info || param_index >= PARAM_COUNT) {
    return false;
  }
  const param_defaults_t *p = &params[param_index];
  memset(param_info, 0, sizeof(*param_info));
  param_info->id = p->id;
  param_info->flags = CLAP_PARAM_IS_AUTOMATABLE;
  snprintf(param_info->name, sizeof(param_info->name), "%s", p->name);
  param_info->min_value = p->min_value;
  param_info->max_value = p->max_value;
  param_info->default_value = p->default_value;
  return true;
}

static bool params_get_value(const clap_plugin_t *plugin, clap_id param_id,
                             double *value) {
  if (!value) {
    return false;
  }
  const param_defaults_t *p = param_by_id(param_id);
  if (!p) {
    return false;
  }
  moondsp_plugin_state_t *state = state_from_plugin(plugin);
  if (!state || state->engine_handle <= 0) {
    *value = p->default_value;
    return true;
  }
  switch (param_id) {
  case PARAM_MASTER_GAIN:
    *value = mb_engine_master_gain(state->engine_handle);
    return true;
  case PARAM_VOICE_GAIN:
    *value = mb_engine_voice_gain(state->engine_handle);
    return true;
  case PARAM_CUTOFF_HZ:
    *value = mb_engine_cutoff_hz(state->engine_handle);
    return true;
  case PARAM_RESONANCE:
    *value = mb_engine_resonance(state->engine_handle);
    return true;
  case PARAM_PAN:
    *value = mb_engine_pan(state->engine_handle);
    return true;
  default:
    return false;
  }
}

static bool params_value_to_text(const clap_plugin_t *plugin, clap_id param_id,
                                 double value, char *display, uint32_t size) {
  (void)plugin;
  if (!display || size == 0 || !param_by_id(param_id)) {
    return false;
  }
  snprintf(display, size, "%.6g", value);
  return true;
}

static bool is_ascii_space(char c) {
  return c == ' ' || c == '\t' || c == '\n' || c == '\r' || c == '\f' ||
         c == '\v';
}

static bool params_text_to_value(const clap_plugin_t *plugin, clap_id param_id,
                                 const char *display, double *value) {
  (void)plugin;
  if (!display || !value || !param_by_id(param_id)) {
    return false;
  }
  char *end = NULL;
  const double parsed = strtod(display, &end);
  if (end == display) {
    return false;
  }
  while (is_ascii_space(*end)) {
    end++;
  }
  if (*end != '\0') {
    return false;
  }
  *value = parsed;
  return true;
}

static void params_flush(const clap_plugin_t *plugin,
                         const clap_input_events_t *in_events,
                         const clap_output_events_t *out_events) {
  (void)out_events;
  moondsp_plugin_state_t *state = state_from_plugin(plugin);
  handle_input_events(state, in_events);
}

static const clap_plugin_params_t params_extension = {
    .count = params_count,
    .get_info = params_get_info,
    .get_value = params_get_value,
    .value_to_text = params_value_to_text,
    .text_to_value = params_text_to_value,
    .flush = params_flush,
};

static const void *moondsp_plugin_get_extension(const clap_plugin_t *plugin,
                                                const char *id) {
  (void)plugin;
  if (!id) {
    return NULL;
  }
  if (strcmp(id, CLAP_EXT_AUDIO_PORTS) == 0) {
    return &audio_ports_extension;
  }
  if (strcmp(id, CLAP_EXT_NOTE_PORTS) == 0) {
    return &note_ports_extension;
  }
  if (strcmp(id, CLAP_EXT_PARAMS) == 0) {
    return &params_extension;
  }
  return NULL;
}

static void moondsp_plugin_on_main_thread(const clap_plugin_t *plugin) {
  (void)plugin;
}

static uint32_t factory_get_plugin_count(const clap_plugin_factory_t *factory) {
  (void)factory;
  return 1;
}

static const clap_plugin_descriptor_t *factory_get_plugin_descriptor(
    const clap_plugin_factory_t *factory, uint32_t index) {
  (void)factory;
  return index == 0 ? &moondsp_descriptor : NULL;
}

static const clap_plugin_t *factory_create_plugin(const clap_plugin_factory_t *factory,
                                                  const clap_host_t *host,
                                                  const char *plugin_id) {
  (void)factory;
  if (!plugin_id || strcmp(plugin_id, MOONDSP_PLUGIN_ID) != 0) {
    return NULL;
  }
  moondsp_plugin_state_t *state =
      (moondsp_plugin_state_t *)calloc(1, sizeof(moondsp_plugin_state_t));
  if (!state) {
    return NULL;
  }
  state->host = host;
  state->engine_handle = 0;
  state->plugin.desc = &moondsp_descriptor;
  state->plugin.plugin_data = state;
  state->plugin.init = moondsp_plugin_init;
  state->plugin.destroy = moondsp_plugin_destroy;
  state->plugin.activate = moondsp_plugin_activate;
  state->plugin.deactivate = moondsp_plugin_deactivate;
  state->plugin.start_processing = moondsp_plugin_start_processing;
  state->plugin.stop_processing = moondsp_plugin_stop_processing;
  state->plugin.reset = moondsp_plugin_reset;
  state->plugin.process = moondsp_plugin_process;
  state->plugin.get_extension = moondsp_plugin_get_extension;
  state->plugin.on_main_thread = moondsp_plugin_on_main_thread;
  return &state->plugin;
}

static const clap_plugin_factory_t plugin_factory = {
    .get_plugin_count = factory_get_plugin_count,
    .get_plugin_descriptor = factory_get_plugin_descriptor,
    .create_plugin = factory_create_plugin,
};

static bool entry_init(const char *plugin_path) {
  (void)plugin_path;
  ensure_moonbit_runtime();
  return true;
}

static void entry_deinit(void) {}

static const void *entry_get_factory(const char *factory_id) {
  if (factory_id && strcmp(factory_id, CLAP_PLUGIN_FACTORY_ID) == 0) {
    return &plugin_factory;
  }
  return NULL;
}

CLAP_EXPORT const clap_plugin_entry_t clap_entry = {
    .clap_version = CLAP_VERSION_INIT,
    .init = entry_init,
    .deinit = entry_deinit,
    .get_factory = entry_get_factory,
};
