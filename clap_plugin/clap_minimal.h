#ifndef MOONDSP_CLAP_MINIMAL_H
#define MOONDSP_CLAP_MINIMAL_H

#include <stdbool.h>
#include <stdint.h>

#if defined(_WIN32)
#define CLAP_EXPORT __declspec(dllexport)
#else
#define CLAP_EXPORT __attribute__((visibility("default")))
#endif

#define CLAP_NAME_SIZE 256
#define CLAP_PATH_SIZE 1024
#define CLAP_INVALID_ID UINT32_MAX

#define CLAP_PLUGIN_FACTORY_ID "clap.plugin-factory"
#define CLAP_EXT_AUDIO_PORTS "clap.audio-ports"
#define CLAP_EXT_NOTE_PORTS "clap.note-ports"
#define CLAP_EXT_PARAMS "clap.params"

#define CLAP_PORT_STEREO "stereo"
#define CLAP_AUDIO_PORT_IS_MAIN (1u << 0u)

#define CLAP_NOTE_DIALECT_CLAP (1u << 0u)

#define CLAP_PARAM_IS_AUTOMATABLE (1u << 5u)

#define CLAP_PLUGIN_FEATURE_INSTRUMENT "instrument"
#define CLAP_PLUGIN_FEATURE_SYNTHESIZER "synthesizer"
#define CLAP_PLUGIN_FEATURE_STEREO "stereo"

#define CLAP_CORE_EVENT_SPACE_ID 0u
#define CLAP_EVENT_NOTE_ON 0u
#define CLAP_EVENT_NOTE_OFF 1u
#define CLAP_EVENT_PARAM_VALUE 5u

#define CLAP_PROCESS_ERROR 0
#define CLAP_PROCESS_CONTINUE 1

#ifdef __cplusplus
extern "C" {
#endif

typedef uint32_t clap_id;

typedef struct clap_version {
  uint32_t major;
  uint32_t minor;
  uint32_t revision;
} clap_version_t;

#define CLAP_VERSION_INIT { 1, 2, 8 }

typedef struct clap_host clap_host_t;
typedef struct clap_plugin clap_plugin_t;
typedef struct clap_plugin_descriptor clap_plugin_descriptor_t;
typedef struct clap_process clap_process_t;

typedef struct clap_plugin_descriptor {
  clap_version_t clap_version;
  const char *id;
  const char *name;
  const char *vendor;
  const char *url;
  const char *manual_url;
  const char *support_url;
  const char *version;
  const char *description;
  const char *const *features;
} clap_plugin_descriptor_t;

typedef struct clap_host {
  clap_version_t clap_version;
  void *host_data;
  const char *name;
  const char *vendor;
  const char *url;
  const char *version;
  const void *(*get_extension)(const clap_host_t *host, const char *extension_id);
  void (*request_restart)(const clap_host_t *host);
  void (*request_process)(const clap_host_t *host);
  void (*request_callback)(const clap_host_t *host);
} clap_host_t;

typedef struct clap_plugin {
  const clap_plugin_descriptor_t *desc;
  void *plugin_data;
  bool (*init)(const clap_plugin_t *plugin);
  void (*destroy)(const clap_plugin_t *plugin);
  bool (*activate)(const clap_plugin_t *plugin, double sample_rate,
                   uint32_t min_frames_count, uint32_t max_frames_count);
  void (*deactivate)(const clap_plugin_t *plugin);
  bool (*start_processing)(const clap_plugin_t *plugin);
  void (*stop_processing)(const clap_plugin_t *plugin);
  void (*reset)(const clap_plugin_t *plugin);
  int32_t (*process)(const clap_plugin_t *plugin, const clap_process_t *process);
  const void *(*get_extension)(const clap_plugin_t *plugin, const char *id);
  void (*on_main_thread)(const clap_plugin_t *plugin);
} clap_plugin_t;

typedef struct clap_audio_buffer {
  float **data32;
  double **data64;
  uint32_t channel_count;
  uint32_t latency;
  uint64_t constant_mask;
} clap_audio_buffer_t;

typedef struct clap_event_header {
  uint32_t size;
  uint32_t time;
  uint16_t space_id;
  uint16_t type;
  uint32_t flags;
} clap_event_header_t;

typedef struct clap_event_note {
  clap_event_header_t header;
  int32_t note_id;
  int16_t port_index;
  int16_t channel;
  int16_t key;
  double velocity;
} clap_event_note_t;

typedef struct clap_event_param_value {
  clap_event_header_t header;
  clap_id param_id;
  void *cookie;
  int32_t note_id;
  int16_t port_index;
  int16_t channel;
  int16_t key;
  double value;
} clap_event_param_value_t;

typedef struct clap_input_events {
  void *ctx;
  uint32_t (*size)(const struct clap_input_events *list);
  const clap_event_header_t *(*get)(const struct clap_input_events *list,
                                    uint32_t index);
} clap_input_events_t;

typedef struct clap_output_events {
  void *ctx;
  bool (*try_push)(const struct clap_output_events *list,
                   const clap_event_header_t *event);
} clap_output_events_t;

typedef struct clap_process {
  int64_t steady_time;
  uint32_t frames_count;
  void *transport;
  const clap_audio_buffer_t *audio_inputs;
  clap_audio_buffer_t *audio_outputs;
  uint32_t audio_inputs_count;
  uint32_t audio_outputs_count;
  const clap_input_events_t *in_events;
  const clap_output_events_t *out_events;
} clap_process_t;

typedef struct clap_plugin_factory {
  uint32_t (*get_plugin_count)(const struct clap_plugin_factory *factory);
  const clap_plugin_descriptor_t *(*get_plugin_descriptor)(
      const struct clap_plugin_factory *factory, uint32_t index);
  const clap_plugin_t *(*create_plugin)(const struct clap_plugin_factory *factory,
                                        const clap_host_t *host,
                                        const char *plugin_id);
} clap_plugin_factory_t;

typedef struct clap_plugin_entry {
  clap_version_t clap_version;
  bool (*init)(const char *plugin_path);
  void (*deinit)(void);
  const void *(*get_factory)(const char *factory_id);
} clap_plugin_entry_t;

typedef struct clap_audio_port_info {
  clap_id id;
  char name[CLAP_NAME_SIZE];
  uint32_t flags;
  uint32_t channel_count;
  const char *port_type;
  clap_id in_place_pair;
} clap_audio_port_info_t;

typedef struct clap_plugin_audio_ports {
  uint32_t (*count)(const clap_plugin_t *plugin, bool is_input);
  bool (*get)(const clap_plugin_t *plugin, uint32_t index, bool is_input,
              clap_audio_port_info_t *info);
} clap_plugin_audio_ports_t;

typedef struct clap_note_port_info {
  clap_id id;
  uint32_t supported_dialects;
  uint32_t preferred_dialect;
  char name[CLAP_NAME_SIZE];
} clap_note_port_info_t;

typedef struct clap_plugin_note_ports {
  uint32_t (*count)(const clap_plugin_t *plugin, bool is_input);
  bool (*get)(const clap_plugin_t *plugin, uint32_t index, bool is_input,
              clap_note_port_info_t *info);
} clap_plugin_note_ports_t;

typedef struct clap_param_info {
  clap_id id;
  uint32_t flags;
  void *cookie;
  char name[CLAP_NAME_SIZE];
  char module[CLAP_PATH_SIZE];
  double min_value;
  double max_value;
  double default_value;
} clap_param_info_t;

typedef struct clap_plugin_params {
  uint32_t (*count)(const clap_plugin_t *plugin);
  bool (*get_info)(const clap_plugin_t *plugin, uint32_t param_index,
                   clap_param_info_t *param_info);
  bool (*get_value)(const clap_plugin_t *plugin, clap_id param_id,
                    double *value);
  bool (*value_to_text)(const clap_plugin_t *plugin, clap_id param_id,
                        double value, char *display, uint32_t size);
  bool (*text_to_value)(const clap_plugin_t *plugin, clap_id param_id,
                        const char *display, double *value);
  void (*flush)(const clap_plugin_t *plugin,
                const clap_input_events_t *in_events,
                const clap_output_events_t *out_events);
} clap_plugin_params_t;

#ifdef __cplusplus
}
#endif

#endif
