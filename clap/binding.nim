import std/strutils

proc currentSourceDir(): string {.compileTime.} =
  result = currentSourcePath().replace("\\", "/")
  result = result[0 ..< result.rfind("/")]

const clapHeader = currentSourceDir() & "/clap/clap.h"

{.emit: """/*INCLUDESECTION*/
#include "`clapHeader`"
""".}

const CLAP_NAME_SIZE* = 256

type
  clap_version_t* {.importc, header: clapHeader.} = object
    major*: uint32
    minor*: uint32
    revision*: uint32

  clap_plugin_descriptor_t* {.importc, header: clapHeader.} = object
    clap_version*: clap_version_t
    id*: cstring
    name*: cstring
    vendor*: cstring
    url*: cstring
    manual_url*: cstring
    support_url*: cstring
    version*: cstring
    description*: cstring
    features*: ptr cstring

  clap_id* = uint32

  clap_note_dialect* {.size: sizeof(cint).} = enum
    CLAP_NOTE_DIALECT_CLAP = 1 shl 0,
    CLAP_NOTE_DIALECT_MIDI = 1 shl 1,
    CLAP_NOTE_DIALECT_MIDI_MPE = 1 shl 2,
    CLAP_NOTE_DIALECT_MIDI2 = 1 shl 3,

  clap_note_port_info_t* {.importc, header: clapHeader.} = object
    id*: clap_id
    supported_dialects*: uint32
    preferred_dialect*: uint32
    name*: array[CLAP_NAME_SIZE, char]

  clap_plugin_note_ports_t* {.importc, header: clapHeader.} = object
    count*: proc(plugin: ptr clap_plugin_t, is_input: bool): uint32 {.cdecl.}
    get*: proc(plugin: ptr clap_plugin_t, index: uint32, is_input: bool, info: ptr clap_note_port_info_t): bool {.cdecl.}

  clap_audio_port_info_t* {.importc, header: clapHeader.} = object
    id*: clap_id
    name*: array[CLAP_NAME_SIZE, char]
    flags*: uint32
    channel_count*: uint32
    port_type*: cstring
    in_place_pair*: clap_id

  clap_plugin_audio_ports_t* {.importc, header: clapHeader.} = object
    count*: proc(plugin: ptr clap_plugin_t, is_input: bool): uint32 {.cdecl.}
    get*: proc(plugin: ptr clap_plugin_t, index: uint32, is_input: bool, info: ptr clap_audio_port_info_t): bool {.cdecl.}

  clap_plugin_latency_t* {.importc, header: clapHeader.} = object
    get*: proc(plugin: ptr clap_plugin_t): uint32 {.cdecl.}

  clap_istream_t* {.importc, header: clapHeader.} = object
    ctx*: pointer
    read*: proc(stream: ptr clap_istream_t, buffer: pointer, size: uint64): int64 {.cdecl.}

  clap_ostream_t* {.importc, header: clapHeader.} = object
    ctx*: pointer
    write*: proc(stream: ptr clap_ostream_t, buffer: pointer, size: uint64): int64 {.cdecl.}

  clap_plugin_state_t* {.importc, header: clapHeader.} = object
    save*: proc(plugin: ptr clap_plugin_t, stream: ptr clap_ostream_t): bool {.cdecl.}
    load*: proc(plugin: ptr clap_plugin_t, stream: ptr clap_istream_t): bool {.cdecl.}

  clap_process_status* {.size: sizeof(int32).} = enum
    CLAP_PROCESS_ERROR = 0,
    CLAP_PROCESS_CONTINUE = 1,
    CLAP_PROCESS_CONTINUE_IF_NOT_QUIET = 2,
    CLAP_PROCESS_TAIL = 3,
    CLAP_PROCESS_SLEEP = 4,

  clap_event_header_t* {.importc, header: clapHeader.} = object
   size*: uint32
   time*: uint32
   space_id*: uint16
   `type`*: uint16
   flags*: uint32

  clap_event_param_value_t* {.importc, header: clapHeader.} = object
    header*: clap_event_header_t
    param_id*: clap_id
    cookie*: pointer
    note_id*: int32
    port_index*: int16
    channel*: int16
    key*: int16
    value*: cdouble

  clap_beattime* = int64
  clap_sectime* = int64

  clap_event_transport_t* {.importc, header: clapHeader.} = object
    header*: clap_event_header_t
    flags*: uint32
    song_pos_beats*: clap_beattime
    song_pos_seconds*: clap_sectime
    tempo*: cdouble
    tempo_inc*: cdouble
    loop_start_beats*: clap_beattime
    loop_end_beats*: clap_beattime
    loop_start_seconds*: clap_sectime
    loop_end_seconds*: clap_sectime
    bar_start*: clap_beattime
    bar_number*: int32
    tsig_num*: uint16
    tsig_denom*: uint16

  clap_audio_buffer_t* {.importc, header: clapHeader.} = object
    data32*: UncheckedArray[UncheckedArray[cfloat]]
    data64*: UncheckedArray[UncheckedArray[cdouble]]
    channel_count*: uint32
    latency*: uint32
    constant_mask*: uint64

  clap_input_events_t* {.importc, header: clapHeader.} = object
    ctx*: pointer
    size*: proc(list: ptr clap_input_events_t): uint32 {.cdecl.}
    get*: proc(list: ptr clap_input_events_t, index: uint32): ptr clap_event_header_t {.cdecl.}

  clap_output_events_t* {.importc, header: clapHeader.} = object
    ctx*: pointer
    try_push*: proc(list: ptr clap_output_events_t, event: ptr clap_event_header_t): bool {.cdecl.}

  clap_process_t* {.importc, header: clapHeader.} = object
    steady_time*: int64
    frames_count*: uint32
    transport*: ptr clap_event_transport_t
    audio_inputs*: UncheckedArray[clap_audio_buffer_t]
    audio_outputs*: UncheckedArray[clap_audio_buffer_t]
    audio_inputs_count*: uint32
    audio_outputs_count*: uint32
    in_events*: ptr clap_input_events_t
    out_events*: ptr clap_output_events_t

  clap_plugin_t* {.importc, header: clapHeader.} = object
    desc*: ptr clap_plugin_descriptor_t
    plugin_data*: pointer
    init*: proc(plugin: ptr clap_plugin_t): bool {.cdecl.}
    destroy*: proc(plugin: ptr clap_plugin_t) {.cdecl.}
    activate*: proc(plugin: ptr clap_plugin_t, sample_rate: cdouble, min_frames_count, max_frames_count: uint32): bool {.cdecl.}
    deactivate*: proc(plugin: ptr clap_plugin_t) {.cdecl.}
    start_processing*: proc(plugin: ptr clap_plugin_t): bool {.cdecl.}
    stop_processing*: proc(plugin: ptr clap_plugin_t) {.cdecl.}
    reset*: proc(plugin: ptr clap_plugin_t) {.cdecl.}
    process*: proc(plugin: ptr clap_plugin_t, process: ptr clap_process_t): clap_process_status {.cdecl.}
    get_extension*: proc(plugin: ptr clap_plugin_t, id: cstring): pointer {.cdecl.}
    on_main_thread*: proc(plugin: ptr clap_plugin_t) {.cdecl.}

  clap_host_latency_t* {.importc, header: clapHeader.} = object
    changed*: proc(host: ptr clap_host_t) {.cdecl.}

  clap_log_severity* = int32

  clap_host_log_t* {.importc, header: clapHeader.} = object
    log*: proc(host: ptr clap_host_t, severity: clap_log_severity, msg: cstring) {.cdecl.}

  clap_host_thread_check_t* {.importc, header: clapHeader.} = object
    is_main_thread*: proc(host: ptr clap_host_t): bool {.cdecl.}
    is_audio_thread*: proc(host: ptr clap_host_t): bool {.cdecl.}

  clap_host_state_t* {.importc, header: clapHeader.} = object
    mark_dirty*: proc(host: ptr clap_host_t)

  clap_host_t* {.importc, header: clapHeader.} = object
    clap_version*: clap_version_t
    host_data*: pointer
    name*: cstring
    vendor*: cstring
    url*: cstring
    version*: cstring
    get_extension*: proc(host: ptr clap_host_t, extension_id: cstring): pointer {.cdecl.}
    request_restart*: proc(host: ptr clap_host_t) {.cdecl.}
    request_process*: proc(host: ptr clap_host_t) {.cdecl.}
    request_callback*: proc(host: ptr clap_host_t) {.cdecl.}

  clap_plugin_factory_t* {.importc, header: clapHeader.} = object
    get_plugin_count*: proc(factory: ptr clap_plugin_factory_t): uint32 {.cdecl.}
    get_plugin_descriptor*: proc(factory: ptr clap_plugin_factory_t, index: uint32): ptr clap_plugin_descriptor_t {.cdecl.}
    create_plugin*: proc(factory: ptr clap_plugin_factory_t, host: ptr clap_host_t, plugin_id: cstring): ptr clap_plugin_t {.cdecl.}

const CLAP_VERSION_INIT* = clap_version_t(major: 1, minor: 1, revision: 7)

const CLAP_EVENT_NOTE_ON* = 0
const CLAP_EVENT_NOTE_OFF* = 1
const CLAP_EVENT_NOTE_CHOKE* = 2
const CLAP_EVENT_NOTE_END* = 3
const CLAP_EVENT_NOTE_EXPRESSION* = 4
const CLAP_EVENT_PARAM_VALUE* = 5
const CLAP_EVENT_PARAM_MOD* = 6
const CLAP_EVENT_PARAM_GESTURE_BEGIN* = 7
const CLAP_EVENT_PARAM_GESTURE_END* = 8
const CLAP_EVENT_TRANSPORT* = 9
const CLAP_EVENT_MIDI* = 10
const CLAP_EVENT_MIDI_SYSEX* = 11
const CLAP_EVENT_MIDI2* = 12

const CLAP_AUDIO_PORT_IS_MAIN* = 1 shl 0
const CLAP_AUDIO_PORT_SUPPORTS_64BITS* = 1 shl 1
const CLAP_AUDIO_PORT_PREFERS_64BITS* = 1 shl 2
const CLAP_AUDIO_PORT_REQUIRES_COMMON_SAMPLE_SIZE* = 1 shl 3

const CLAP_EXT_AUDIO_PORTS* = cstring"clap.audio-ports"
const CLAP_PORT_MONO* = cstring"mono"
const CLAP_PORT_STEREO* = cstring"stereo"

const CLAP_EXT_TRACK_INFO* = cstring"clap.track-info.draft/1"

const CLAP_INVALID_ID* = high(uint32).clap_id

const CLAP_PLUGIN_FACTORY_ID* = cstring"clap.plugin-factory"

template clap_version_is_compatible*(v: clap_version_t): bool = v.major >= 1