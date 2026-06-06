#!/usr/bin/env bash
set -euo pipefail

repo_root=$(cd "$(dirname "$0")/.." && pwd)
cc=${CC:-cc}
clap_include="$repo_root/third_party/clap/include"
plugin="$repo_root/_build/native/release/clap/moondsp-synth.clap"
tmp_dir=$(mktemp -d)
trap 'rm -rf "$tmp_dir"' EXIT

if [[ ! -f "$clap_include/clap/entry.h" ]]; then
  echo "Vendored CLAP headers not found under $clap_include" >&2
  exit 1
fi

"$repo_root/scripts/build-clap-prototype.sh" >/dev/null

cat > "$tmp_dir/smoke.c" <<'EOF'
#include <clap/entry.h>
#include <clap/events.h>
#include <clap/factory/plugin-factory.h>
#include <clap/process.h>

#include <dlfcn.h>
#include <math.h>
#include <stdio.h>
#include <string.h>

typedef struct events_ctx {
  clap_event_note_t note;
  clap_event_midi_t midi;
  const clap_event_header_t *event;
} events_ctx_t;

static const void *host_get_extension(const clap_host_t *host, const char *id) {
  (void)host;
  (void)id;
  return NULL;
}

static void host_request(const clap_host_t *host) { (void)host; }

static uint32_t events_size(const clap_input_events_t *list) {
  (void)list;
  return 1;
}

static const clap_event_header_t *events_get(
    const clap_input_events_t *list,
    uint32_t index) {
  if (index != 0) {
    return NULL;
  }
  const events_ctx_t *ctx = (const events_ctx_t *)list->ctx;
  return ctx->event;
}

static float peak(float *left, float *right, uint32_t start, uint32_t end) {
  float result = 0.0f;
  for (uint32_t i = start; i < end; i++) {
    const float l = fabsf(left[i]);
    const float r = fabsf(right[i]);
    if (l > result) {
      result = l;
    }
    if (r > result) {
      result = r;
    }
  }
  return result;
}

int main(int argc, char **argv) {
  if (argc != 2) {
    fprintf(stderr, "usage: smoke <plugin.clap>\n");
    return 2;
  }
  void *lib = dlopen(argv[1], RTLD_NOW | RTLD_LOCAL);
  if (!lib) {
    fprintf(stderr, "dlopen failed: %s\n", dlerror());
    return 3;
  }
  const clap_plugin_entry_t *entry =
      (const clap_plugin_entry_t *)dlsym(lib, "clap_entry");
  if (!entry) {
    fprintf(stderr, "clap_entry missing\n");
    return 4;
  }
  if (!entry->init || !entry->deinit || !entry->get_factory) {
    fprintf(stderr, "clap_entry callbacks missing\n");
    return 4;
  }
  if (!entry->init(argv[1])) {
    fprintf(stderr, "clap_entry init failed\n");
    return 4;
  }
  const clap_plugin_factory_t *factory =
      (const clap_plugin_factory_t *)entry->get_factory(CLAP_PLUGIN_FACTORY_ID);
  if (!factory) {
    fprintf(stderr, "plugin factory missing\n");
    return 5;
  }
  if (!factory->get_plugin_count || !factory->create_plugin) {
    fprintf(stderr, "plugin factory callbacks missing\n");
    return 5;
  }
  if (factory->get_plugin_count(factory) != 1) {
    fprintf(stderr, "unexpected plugin count\n");
    return 5;
  }
  clap_host_t host = {0};
  host.clap_version = (clap_version_t)CLAP_VERSION_INIT;
  host.name = "moondsp smoke";
  host.get_extension = host_get_extension;
  host.request_restart = host_request;
  host.request_process = host_request;
  host.request_callback = host_request;
  const clap_plugin_t *plugin = factory->create_plugin(
      factory,
      &host,
      "com.dowdiness.moondsp.synth");
  if (!plugin) {
    fprintf(stderr, "plugin create failed\n");
    return 6;
  }
  if (!plugin->init || !plugin->activate || !plugin->start_processing ||
      !plugin->process || !plugin->stop_processing || !plugin->deactivate ||
      !plugin->destroy) {
    fprintf(stderr, "plugin lifecycle callbacks missing\n");
    return 6;
  }
  if (!plugin->init(plugin)) {
    fprintf(stderr, "plugin init failed\n");
    return 6;
  }
  if (!plugin->activate(plugin, 48000.0, 1, 128)) {
    fprintf(stderr, "plugin activate failed\n");
    return 6;
  }
  if (!plugin->start_processing(plugin)) {
    fprintf(stderr, "plugin start_processing failed\n");
    return 6;
  }

  float left[128] = {0};
  float right[128] = {0};
  float *channels[2] = {left, right};
  clap_audio_buffer_t output = {0};
  output.data32 = channels;
  output.channel_count = 2;

  events_ctx_t event_ctx = {0};
  event_ctx.note.header.size = sizeof(clap_event_note_t);
  event_ctx.note.header.time = 64;
  event_ctx.note.header.space_id = CLAP_CORE_EVENT_SPACE_ID;
  event_ctx.note.header.type = CLAP_EVENT_NOTE_ON;
  event_ctx.note.note_id = 100;
  event_ctx.note.key = 69;
  event_ctx.note.velocity = 1.0;
  event_ctx.event = &event_ctx.note.header;
  clap_input_events_t events = {0};
  events.ctx = &event_ctx;
  events.size = events_size;
  events.get = events_get;

  clap_process_t process = {0};
  process.frames_count = 128;
  process.audio_outputs = &output;
  process.audio_outputs_count = 1;
  process.in_events = &events;

  const int32_t status = plugin->process(plugin, &process);
  const float before = peak(left, right, 0, 64);
  const float after = peak(left, right, 64, 128);

  event_ctx.note.header.time = 0;
  event_ctx.note.header.type = CLAP_EVENT_NOTE_OFF;
  event_ctx.note.note_id = -1;
  event_ctx.note.key = 69;
  event_ctx.note.velocity = 0.0;
  const int32_t off_status = plugin->process(plugin, &process);

  process.in_events = NULL;
  int32_t tail_status = CLAP_PROCESS_CONTINUE;
  float tail_peak = 0.0f;
  for (uint32_t block = 0; block < 128; block++) {
    tail_status = plugin->process(plugin, &process);
    tail_peak = peak(left, right, 0, 128);
  }

  event_ctx.midi.header.size = sizeof(clap_event_midi_t);
  event_ctx.midi.header.time = 0;
  event_ctx.midi.header.space_id = CLAP_CORE_EVENT_SPACE_ID;
  event_ctx.midi.header.type = CLAP_EVENT_MIDI;
  event_ctx.midi.data[0] = 0x90;
  event_ctx.midi.data[1] = 72;
  event_ctx.midi.data[2] = 127;
  event_ctx.event = &event_ctx.midi.header;
  process.in_events = &events;
  const int32_t midi_on_status = plugin->process(plugin, &process);
  const float midi_peak = peak(left, right, 0, 128);

  event_ctx.midi.data[0] = 0x80;
  event_ctx.midi.data[2] = 0;
  const int32_t midi_off_status = plugin->process(plugin, &process);

  process.in_events = NULL;
  int32_t midi_tail_status = CLAP_PROCESS_CONTINUE;
  float midi_tail_peak = 0.0f;
  for (uint32_t block = 0; block < 128; block++) {
    midi_tail_status = plugin->process(plugin, &process);
    midi_tail_peak = peak(left, right, 0, 128);
  }

  plugin->stop_processing(plugin);
  plugin->deactivate(plugin);
  plugin->destroy(plugin);
  entry->deinit();
  dlclose(lib);

  if (status != CLAP_PROCESS_CONTINUE) {
    fprintf(stderr, "unexpected process status %d\n", status);
    return 7;
  }
  if (off_status != CLAP_PROCESS_CONTINUE || tail_status != CLAP_PROCESS_CONTINUE) {
    fprintf(stderr,
            "unexpected note-off/tail status %d/%d\n",
            off_status,
            tail_status);
    return 7;
  }
  if (midi_on_status != CLAP_PROCESS_CONTINUE ||
      midi_off_status != CLAP_PROCESS_CONTINUE ||
      midi_tail_status != CLAP_PROCESS_CONTINUE) {
    fprintf(stderr,
            "unexpected MIDI status %d/%d/%d\n",
            midi_on_status,
            midi_off_status,
            midi_tail_status);
    return 7;
  }
  if (before > 0.0000001f) {
    fprintf(stderr, "event timestamp ignored: pre-event peak %g\n", before);
    return 8;
  }
  if (after <= 0.000001f) {
    fprintf(stderr, "no post-event audio: peak %g\n", after);
    return 9;
  }
  if (tail_peak > 0.000001f) {
    fprintf(stderr, "wildcard note-off did not release audio: peak %g\n", tail_peak);
    return 10;
  }
  if (midi_peak <= 0.000001f) {
    fprintf(stderr, "MIDI note-on produced no audio: peak %g\n", midi_peak);
    return 11;
  }
  if (midi_tail_peak > 0.000001f) {
    fprintf(stderr, "MIDI note-off did not release audio: peak %g\n", midi_tail_peak);
    return 12;
  }
  printf(
      "CLAP smoke passed: pre-event peak=%g post-event peak=%g tail peak=%g MIDI tail peak=%g\n",
      before,
      after,
      tail_peak,
      midi_tail_peak);
  return 0;
}
EOF

"$cc" -std=gnu11 -I"$clap_include" "$tmp_dir/smoke.c" -ldl -lm -o "$tmp_dir/smoke"
"$tmp_dir/smoke" "$plugin"
