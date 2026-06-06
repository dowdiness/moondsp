#!/usr/bin/env bash
set -euo pipefail

repo_root=$(cd "$(dirname "$0")/.." && pwd)
cc=${CC:-cc}
plugin="$repo_root/_build/native/release/clap/moondsp-synth.clap"
clap_include="$repo_root/third_party/clap/include"
expect_zero=0

if [[ ${1:-} == "--expect-zero" ]]; then
  expect_zero=1
elif [[ $# -gt 0 ]]; then
  echo "usage: $0 [--expect-zero]" >&2
  exit 2
fi

if [[ ! -f "$clap_include/clap/entry.h" ]]; then
  echo "Vendored CLAP headers not found under $clap_include" >&2
  exit 1
fi

"$repo_root/scripts/build-clap-prototype.sh" >/dev/null

tmp_dir=$(mktemp -d)
trap 'rm -rf "$tmp_dir"' EXIT

cat > "$tmp_dir/allocmon.c" <<'EOF'
#define _GNU_SOURCE
#include <dlfcn.h>
#include <stddef.h>
#include <stdatomic.h>
#include <stdlib.h>

static _Atomic unsigned long long alloc_count = 0;
static _Atomic unsigned long long alloc_bytes = 0;
static _Atomic unsigned long long realloc_count = 0;
static _Atomic unsigned long long calloc_count = 0;
static _Atomic int enabled = 0;
static __thread int in_hook = 0;

static void *(*real_malloc)(size_t) = 0;
static void *(*real_calloc)(size_t, size_t) = 0;
static void *(*real_realloc)(void *, size_t) = 0;
static void (*real_free)(void *) = 0;
static int (*real_posix_memalign)(void **, size_t, size_t) = 0;
static void *(*real_aligned_alloc)(size_t, size_t) = 0;

static void init_real(void) {
  if (real_malloc) {
    return;
  }
  in_hook = 1;
  real_malloc = (void *(*)(size_t))dlsym(RTLD_NEXT, "malloc");
  real_calloc = (void *(*)(size_t, size_t))dlsym(RTLD_NEXT, "calloc");
  real_realloc = (void *(*)(void *, size_t))dlsym(RTLD_NEXT, "realloc");
  real_free = (void (*)(void *))dlsym(RTLD_NEXT, "free");
  real_posix_memalign =
      (int (*)(void **, size_t, size_t))dlsym(RTLD_NEXT, "posix_memalign");
  real_aligned_alloc =
      (void *(*)(size_t, size_t))dlsym(RTLD_NEXT, "aligned_alloc");
  in_hook = 0;
}

void allocmon_reset(void) {
  atomic_store(&alloc_count, 0);
  atomic_store(&alloc_bytes, 0);
  atomic_store(&realloc_count, 0);
  atomic_store(&calloc_count, 0);
}

void allocmon_set_enabled(int on) { atomic_store(&enabled, on != 0); }
unsigned long long allocmon_count(void) { return atomic_load(&alloc_count); }
unsigned long long allocmon_bytes(void) { return atomic_load(&alloc_bytes); }
unsigned long long allocmon_realloc_count(void) {
  return atomic_load(&realloc_count);
}
unsigned long long allocmon_calloc_count(void) {
  return atomic_load(&calloc_count);
}

static void record(size_t size) {
  if (!in_hook && atomic_load(&enabled)) {
    atomic_fetch_add(&alloc_count, 1);
    atomic_fetch_add(&alloc_bytes, (unsigned long long)size);
  }
}

void *malloc(size_t size) {
  init_real();
  void *p = real_malloc(size);
  if (p) {
    record(size);
  }
  return p;
}

void *calloc(size_t nmemb, size_t size) {
  init_real();
  void *p = real_calloc(nmemb, size);
  if (p && !in_hook && atomic_load(&enabled)) {
    atomic_fetch_add(&calloc_count, 1);
    record(nmemb * size);
  }
  return p;
}

void *realloc(void *ptr, size_t size) {
  init_real();
  void *p = real_realloc(ptr, size);
  if (p && size > 0 && !in_hook && atomic_load(&enabled)) {
    atomic_fetch_add(&realloc_count, 1);
    record(size);
  }
  return p;
}

void free(void *ptr) {
  init_real();
  real_free(ptr);
}

int posix_memalign(void **memptr, size_t alignment, size_t size) {
  init_real();
  int rc = real_posix_memalign(memptr, alignment, size);
  if (rc == 0 && memptr && *memptr) {
    record(size);
  }
  return rc;
}

void *aligned_alloc(size_t alignment, size_t size) {
  init_real();
  void *p = real_aligned_alloc ? real_aligned_alloc(alignment, size) : 0;
  if (p) {
    record(size);
  }
  return p;
}
EOF

cat > "$tmp_dir/audit.c" <<'EOF'
#include <clap/entry.h>
#include <clap/events.h>
#include <clap/ext/params.h>
#include <clap/factory/plugin-factory.h>
#include <clap/process.h>

#include <dlfcn.h>
#include <math.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

typedef void (*set_enabled_fn)(int);
typedef void (*reset_fn)(void);
typedef unsigned long long (*count_fn)(void);

static set_enabled_fn allocmon_set_enabled_p;
static reset_fn allocmon_reset_p;
static count_fn allocmon_count_p;
static count_fn allocmon_bytes_p;
static count_fn allocmon_realloc_count_p;
static count_fn allocmon_calloc_count_p;
static int expect_zero;
static int failures;

typedef struct events_ctx {
  const clap_event_header_t *event;
  const clap_event_header_t *event2;
  uint32_t count;
} events_ctx_t;

static const void *host_get_extension(const clap_host_t *host, const char *id) {
  (void)host;
  (void)id;
  return NULL;
}

static void host_request(const clap_host_t *host) { (void)host; }

static uint32_t events_size(const clap_input_events_t *list) {
  const events_ctx_t *ctx = (const events_ctx_t *)list->ctx;
  return ctx->count;
}

static const clap_event_header_t *events_get(const clap_input_events_t *list,
                                             uint32_t index) {
  const events_ctx_t *ctx = (const events_ctx_t *)list->ctx;
  if (index == 0) {
    return ctx->event;
  }
  if (index == 1) {
    return ctx->event2;
  }
  return NULL;
}

static float peak(float *left, float *right, uint32_t frames) {
  float result = 0.0f;
  for (uint32_t i = 0; i < frames; i++) {
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

static void measured_process(const char *label, const clap_plugin_t *plugin,
                             clap_process_t *process) {
  allocmon_reset_p();
  allocmon_set_enabled_p(1);
  const int32_t status = plugin->process(plugin, process);
  allocmon_set_enabled_p(0);

  const unsigned long long allocs = allocmon_count_p();
  const unsigned long long bytes = allocmon_bytes_p();
  const unsigned long long reallocs = allocmon_realloc_count_p();
  const unsigned long long callocs = allocmon_calloc_count_p();
  printf("%-34s status=%d allocs=%llu bytes=%llu reallocs=%llu callocs=%llu\n",
         label, status, allocs, bytes, reallocs, callocs);

  if (status != CLAP_PROCESS_CONTINUE) {
    failures++;
  }
  if (expect_zero && allocs != 0) {
    failures++;
  }
}

static void init_allocmon(void) {
  allocmon_set_enabled_p =
      (set_enabled_fn)dlsym(RTLD_DEFAULT, "allocmon_set_enabled");
  allocmon_reset_p = (reset_fn)dlsym(RTLD_DEFAULT, "allocmon_reset");
  allocmon_count_p = (count_fn)dlsym(RTLD_DEFAULT, "allocmon_count");
  allocmon_bytes_p = (count_fn)dlsym(RTLD_DEFAULT, "allocmon_bytes");
  allocmon_realloc_count_p =
      (count_fn)dlsym(RTLD_DEFAULT, "allocmon_realloc_count");
  allocmon_calloc_count_p =
      (count_fn)dlsym(RTLD_DEFAULT, "allocmon_calloc_count");
  if (!allocmon_set_enabled_p || !allocmon_reset_p || !allocmon_count_p ||
      !allocmon_bytes_p || !allocmon_realloc_count_p || !allocmon_calloc_count_p) {
    fprintf(stderr, "allocmon symbols missing; run with LD_PRELOAD=allocmon.so\n");
    exit(2);
  }
  allocmon_set_enabled_p(0);
  allocmon_reset_p();
}

int main(int argc, char **argv) {
  if (argc != 3) {
    fprintf(stderr, "usage: audit <plugin.clap> <expect-zero-0-or-1>\n");
    return 2;
  }
  expect_zero = atoi(argv[2]) != 0;
  init_allocmon();

  void *lib = dlopen(argv[1], RTLD_NOW | RTLD_LOCAL);
  if (!lib) {
    fprintf(stderr, "dlopen failed: %s\n", dlerror());
    return 3;
  }
  const clap_plugin_entry_t *entry =
      (const clap_plugin_entry_t *)dlsym(lib, "clap_entry");
  if (!entry || !entry->init || !entry->deinit || !entry->get_factory) {
    fprintf(stderr, "clap_entry callbacks missing\n");
    return 4;
  }
  if (!entry->init(argv[1])) {
    fprintf(stderr, "clap_entry init failed\n");
    return 4;
  }
  const clap_plugin_factory_t *factory =
      (const clap_plugin_factory_t *)entry->get_factory(CLAP_PLUGIN_FACTORY_ID);
  if (!factory || !factory->create_plugin) {
    fprintf(stderr, "plugin factory missing\n");
    return 5;
  }

  clap_host_t host = {0};
  host.clap_version = (clap_version_t)CLAP_VERSION_INIT;
  host.name = "moondsp allocation audit";
  host.get_extension = host_get_extension;
  host.request_restart = host_request;
  host.request_process = host_request;
  host.request_callback = host_request;

  const clap_plugin_t *plugin =
      factory->create_plugin(factory, &host, "com.dowdiness.moondsp.synth");
  if (!plugin || !plugin->init || !plugin->activate || !plugin->start_processing ||
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
  clap_input_events_t events = {0};
  events.ctx = &event_ctx;
  events.size = events_size;
  events.get = events_get;

  clap_process_t process = {0};
  process.frames_count = 128;
  process.audio_outputs = &output;
  process.audio_outputs_count = 1;

  measured_process("steady idle no events", plugin, &process);

  clap_event_note_t note = {0};
  note.header.size = sizeof(note);
  note.header.time = 64;
  note.header.space_id = CLAP_CORE_EVENT_SPACE_ID;
  note.header.type = CLAP_EVENT_NOTE_ON;
  note.note_id = 101;
  note.key = 69;
  note.velocity = 1.0;
  event_ctx.event = &note.header;
  event_ctx.count = 1;
  process.in_events = &events;
  measured_process("note-on event @64", plugin, &process);
  printf("  peak after note-on block: %g\n", peak(left, right, 128));

  process.in_events = NULL;
  measured_process("steady active no events", plugin, &process);

  clap_event_param_value_t param = {0};
  param.header.size = sizeof(param);
  param.header.time = 0;
  param.header.space_id = CLAP_CORE_EVENT_SPACE_ID;
  param.header.type = CLAP_EVENT_PARAM_VALUE;
  param.param_id = 0;
  param.value = 0.7;
  event_ctx.event = &param.header;
  event_ctx.count = 1;
  process.in_events = &events;
  measured_process("param master gain active @0", plugin, &process);

  param.param_id = 2;
  param.value = 1200.0;
  measured_process("param cutoff active @0", plugin, &process);

  param.param_id = 1;
  param.value = 0.3;
  measured_process("param voice gain active @0", plugin, &process);

  param.param_id = 4;
  param.value = -0.25;
  measured_process("param pan active @0", plugin, &process);

  note.header.time = 0;
  note.header.type = CLAP_EVENT_NOTE_OFF;
  note.note_id = 101;
  note.key = 69;
  note.velocity = 0.0;
  event_ctx.event = &note.header;
  process.in_events = &events;
  measured_process("note-off active @0", plugin, &process);

  process.in_events = NULL;
  for (int i = 0; i < 32; i++) {
    plugin->process(plugin, &process);
  }

  note.header.type = CLAP_EVENT_NOTE_ON;
  note.note_id = 102;
  note.key = 67;
  note.velocity = 1.0;
  process.in_events = &events;
  plugin->process(plugin, &process);

  clap_event_transport_t transport = {0};
  transport.header.size = sizeof(transport);
  transport.header.time = 0;
  transport.header.space_id = CLAP_CORE_EVENT_SPACE_ID;
  transport.header.type = CLAP_EVENT_TRANSPORT;
  transport.flags = CLAP_TRANSPORT_IS_PLAYING;
  event_ctx.event = &transport.header;
  process.in_events = &events;
  measured_process("transport play active @0", plugin, &process);

  transport.flags = 0;
  measured_process("transport stop active @0", plugin, &process);

  process.in_events = NULL;
  for (int i = 0; i < 32; i++) {
    plugin->process(plugin, &process);
  }

  clap_event_midi_t midi = {0};
  midi.header.size = sizeof(midi);
  midi.header.time = 0;
  midi.header.space_id = CLAP_CORE_EVENT_SPACE_ID;
  midi.header.type = CLAP_EVENT_MIDI;
  midi.data[0] = 0x90;
  midi.data[1] = 72;
  midi.data[2] = 127;
  event_ctx.event = &midi.header;
  event_ctx.count = 1;
  process.in_events = &events;
  measured_process("MIDI note-on @0", plugin, &process);

  process.in_events = NULL;
  measured_process("steady MIDI active", plugin, &process);

  midi.data[0] = 0x80;
  midi.data[2] = 0;
  process.in_events = &events;
  measured_process("MIDI note-off active @0", plugin, &process);

  process.in_events = NULL;
  for (int i = 0; i < 32; i++) {
    plugin->process(plugin, &process);
  }

  midi.data[0] = 0x90;
  midi.data[1] = 74;
  midi.data[2] = 127;
  process.in_events = &events;
  plugin->process(plugin, &process);

  midi.data[0] = 0xB0;
  midi.data[1] = 123;
  midi.data[2] = 0;
  measured_process("MIDI all-notes-off CC active @0", plugin, &process);

  plugin->stop_processing(plugin);
  plugin->deactivate(plugin);
  plugin->destroy(plugin);
  entry->deinit();
  dlclose(lib);

  if (!expect_zero) {
    printf("Note: non-zero event-path allocations are expected until issue #173 is fully resolved.\n");
  }
  return failures == 0 ? 0 : 1;
}
EOF

"$cc" -shared -fPIC -O2 "$tmp_dir/allocmon.c" -ldl -o "$tmp_dir/allocmon.so"
"$cc" -std=gnu11 -O2 -I"$clap_include" "$tmp_dir/audit.c" -ldl -lm -o "$tmp_dir/audit"
LD_PRELOAD="$tmp_dir/allocmon.so" "$tmp_dir/audit" "$plugin" "$expect_zero"
