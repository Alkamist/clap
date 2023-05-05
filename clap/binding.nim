const CLAP_NAME_SIZE* = 256
const CLAP_PATH_SIZE* = 1024

type
  clap_version_t* {.bycopy.} = object
    major*: uint32
    minor*: uint32
    revision*: uint32

  clap_plugin_descriptor_t* {.bycopy.} = object
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

  clap_note_port_info_t* {.bycopy.} = object
    id*: clap_id
    supported_dialects*: uint32
    preferred_dialect*: uint32
    name*: array[CLAP_NAME_SIZE, char]

  clap_plugin_note_ports_t* {.bycopy.} = object
    count*: proc(plugin: ptr clap_plugin_t, is_input: bool): uint32 {.cdecl.}
    get*: proc(plugin: ptr clap_plugin_t, index: uint32, is_input: bool, info: ptr clap_note_port_info_t): bool {.cdecl.}

  clap_audio_port_info_t* {.bycopy.} = object
    id*: clap_id
    name*: array[CLAP_NAME_SIZE, char]
    flags*: uint32
    channel_count*: uint32
    port_type*: cstring
    in_place_pair*: clap_id

  clap_plugin_audio_ports_t* {.bycopy.} = object
    count*: proc(plugin: ptr clap_plugin_t, is_input: bool): uint32 {.cdecl.}
    get*: proc(plugin: ptr clap_plugin_t, index: uint32, is_input: bool, info: ptr clap_audio_port_info_t): bool {.cdecl.}

  clap_plugin_latency_t* {.bycopy.} = object
    get*: proc(plugin: ptr clap_plugin_t): uint32 {.cdecl.}

  clap_istream_t* {.bycopy.} = object
    ctx*: pointer
    read*: proc(stream: ptr clap_istream_t, buffer: pointer, size: uint64): int64 {.cdecl.}

  clap_ostream_t* {.bycopy.} = object
    ctx*: pointer
    write*: proc(stream: ptr clap_ostream_t, buffer: pointer, size: uint64): int64 {.cdecl.}

  clap_plugin_state_t* {.bycopy.} = object
    save*: proc(plugin: ptr clap_plugin_t, stream: ptr clap_ostream_t): bool {.cdecl.}
    load*: proc(plugin: ptr clap_plugin_t, stream: ptr clap_istream_t): bool {.cdecl.}

  clap_plugin_timer_support_t* {.bycopy.} = object
    on_timer*: proc(plugin: ptr clap_plugin_t, timer_id: clap_id) {.cdecl.}

  clap_host_timer_support_t* {.bycopy.} = object
    register_timer*: proc(host: ptr clap_host_t, period_ms: uint32, timer_id: ptr clap_id): bool {.cdecl.}
    unregister_timer*: proc(host: ptr clap_host_t, timer_id: clap_id): bool {.cdecl.}

  clap_gui_resize_hints_t* {.bycopy.} = object
    can_resize_horizontally*: bool
    can_resize_vertically*: bool
    preserve_aspect_ratio*: bool
    aspect_ratio_width*: uint32
    aspect_ratio_height*: uint32

  clap_hwnd* = pointer
  clap_nsview* = pointer
  clap_xwnd* = culong

  clap_window_union* {.bycopy, union.} = object
    cocoa*: clap_nsview
    x11*: clap_xwnd
    win32*: clap_hwnd
    `ptr`*: pointer

  clap_window_t* {.bycopy.} = object
    api*: cstring
    union*: clap_window_union

  clap_plugin_gui_t* {.bycopy.} = object
    is_api_supported*: proc(plugin: ptr clap_plugin_t, api: cstring, is_floating: bool): bool {.cdecl.}
    get_preferred_api*: proc(plugin: ptr clap_plugin_t, api: ptr cstring, is_floating: ptr bool): bool {.cdecl.}
    create*: proc(plugin: ptr clap_plugin_t, api: cstring, is_floating: bool): bool {.cdecl.}
    destroy*: proc(plugin: ptr clap_plugin_t) {.cdecl.}
    set_scale*: proc(plugin: ptr clap_plugin_t, scale: cdouble): bool {.cdecl.}
    get_size*: proc(plugin: ptr clap_plugin_t, width, height: ptr uint32): bool {.cdecl.}
    can_resize*: proc(plugin: ptr clap_plugin_t): bool {.cdecl.}
    get_resize_hints*: proc(plugin: ptr clap_plugin_t, hints: ptr clap_gui_resize_hints_t): bool {.cdecl.}
    adjust_size*: proc(plugin: ptr clap_plugin_t, width, height: ptr uint32): bool {.cdecl.}
    set_size*: proc(plugin: ptr clap_plugin_t, width, height: uint32): bool {.cdecl.}
    set_parent*: proc(plugin: ptr clap_plugin_t, window: ptr clap_window_t): bool {.cdecl.}
    set_transient*: proc(plugin: ptr clap_plugin_t, window: ptr clap_window_t): bool {.cdecl.}
    suggest_title*: proc(plugin: ptr clap_plugin_t, title: cstring) {.cdecl.}
    show*: proc(plugin: ptr clap_plugin_t): bool {.cdecl.}
    hide*: proc(plugin: ptr clap_plugin_t): bool {.cdecl.}

  clap_event_header_t* {.bycopy.} = object
   size*: uint32
   time*: uint32
   space_id*: uint16
   `type`*: uint16
   flags*: uint32

  clap_event_param_value_t* {.bycopy.} = object
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

  clap_event_transport_t* {.bycopy.} = object
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

  clap_event_note_t* {.bycopy.} = object
    header*: clap_event_header_t
    note_id*: int32
    port_index*: int16
    channel*: int16
    key*: int16
    velocity*: cdouble

  clap_event_midi_t* {.bycopy.} = object
   header*: clap_event_header_t
   port_index*: uint16
   data*: array[3, uint8]

  clap_audio_buffer_t* {.bycopy.} = object
    data32*: ptr ptr cfloat
    data64*: ptr ptr cdouble
    channel_count*: uint32
    latency*: uint32
    constant_mask*: uint64

  clap_input_events_t* {.bycopy.} = object
    ctx*: pointer
    size*: proc(list: ptr clap_input_events_t): uint32 {.cdecl.}
    get*: proc(list: ptr clap_input_events_t, index: uint32): ptr clap_event_header_t {.cdecl.}

  clap_output_events_t* {.bycopy.} = object
    ctx*: pointer
    try_push*: proc(list: ptr clap_output_events_t, event: ptr clap_event_header_t): bool {.cdecl.}

  clap_param_info_flags* = uint32

  clap_param_info_t* {.bycopy.} = object
    id*: clap_id
    flags*: clap_param_info_flags
    cookie*: pointer
    name*: array[CLAP_NAME_SIZE, char]
    module*: array[CLAP_PATH_SIZE, char]
    min_value*: cdouble
    max_value*: cdouble
    default_value*: cdouble

  clap_plugin_params_t* {.bycopy.} = object
    count*: proc(plugin: ptr clap_plugin_t): uint32 {.cdecl.}
    get_info*: proc(plugin: ptr clap_plugin_t, param_index: uint32, param_info: ptr clap_param_info_t): bool {.cdecl.}
    get_value*: proc(plugin: ptr clap_plugin_t, param_id: clap_id, out_value: ptr cdouble): bool {.cdecl.}
    value_to_text*: proc(plugin: ptr clap_plugin_t, param_id: clap_id, value: cdouble, out_buffer: ptr UncheckedArray[char], out_buffer_capacity: uint32): bool {.cdecl.}
    text_to_value*: proc(plugin: ptr clap_plugin_t, param_id: clap_id, param_value_text: cstring, out_value: ptr cdouble): bool {.cdecl.}
    flush*: proc(plugin: ptr clap_plugin_t, `in`: ptr clap_input_events_t, `out`: ptr clap_output_events_t) {.cdecl.}

  clap_process_status* = int32

  clap_process_t* {.bycopy.} = object
    steady_time*: int64
    frames_count*: uint32
    transport*: ptr clap_event_transport_t
    audio_inputs*: ptr clap_audio_buffer_t
    audio_outputs*: ptr clap_audio_buffer_t
    audio_inputs_count*: uint32
    audio_outputs_count*: uint32
    in_events*: ptr clap_input_events_t
    out_events*: ptr clap_output_events_t

  clap_plugin_t* {.bycopy.} = object
    desc*: ptr clap_plugin_descriptor_t
    plugin_data*: pointer
    init*: proc(plugin: ptr clap_plugin_t): bool {.cdecl.}
    destroy*: proc(plugin: ptr clap_plugin_t) {.cdecl.}
    activate*: proc(plugin: ptr clap_plugin_t, sample_rate: cdouble, min_frames_count, max_frames_count: uint32): bool {.cdecl.}
    deactivate*: proc(plugin: ptr clap_plugin_t) {.cdecl.}
    start_processing*: proc(plugin: ptr clap_plugin_t): bool {.cdecl.}
    stop_processing*: proc(plugin: ptr clap_plugin_t) {.cdecl.}
    reset*: proc(plugin: ptr clap_plugin_t) {.cdecl.}
    process*: proc(plugin: ptr clap_plugin_t, process: ptr clap_process_t): int32 {.cdecl.}
    get_extension*: proc(plugin: ptr clap_plugin_t, id: cstring): pointer {.cdecl.}
    on_main_thread*: proc(plugin: ptr clap_plugin_t) {.cdecl.}

  clap_host_latency_t* {.bycopy.} = object
    changed*: proc(host: ptr clap_host_t) {.cdecl.}

  clap_log_severity* = int32

  clap_host_log_t* {.bycopy.} = object
    log*: proc(host: ptr clap_host_t, severity: clap_log_severity, msg: cstring) {.cdecl.}

  clap_host_thread_check_t* {.bycopy.} = object
    is_main_thread*: proc(host: ptr clap_host_t): bool {.cdecl.}
    is_audio_thread*: proc(host: ptr clap_host_t): bool {.cdecl.}

  clap_host_state_t* {.bycopy.} = object
    mark_dirty*: proc(host: ptr clap_host_t)

  clap_host_t* {.bycopy.} = object
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

  clap_plugin_factory_t* {.bycopy.} = object
    get_plugin_count*: proc(factory: ptr clap_plugin_factory_t): uint32 {.cdecl.}
    get_plugin_descriptor*: proc(factory: ptr clap_plugin_factory_t, index: uint32): ptr clap_plugin_descriptor_t {.cdecl.}
    create_plugin*: proc(factory: ptr clap_plugin_factory_t, host: ptr clap_host_t, plugin_id: cstring): ptr clap_plugin_t {.cdecl.}

  clap_plugin_entry_t* {.bycopy.} = object
    clap_version*: clap_version_t
    init*: proc(plugin_path: cstring): bool {.cdecl.}
    deinit*: proc() {.cdecl.}
    get_factory*: proc(factory_id: cstring): pointer {.cdecl.}

const CLAP_VERSION_INIT* = clap_version_t(major: 1, minor: 1, revision: 7)
template clap_version_is_compatible*(v: clap_version_t): bool = v.major >= 1

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
const CLAP_CORE_EVENT_SPACE_ID* = 0
const CLAP_AUDIO_PORT_IS_MAIN* = 1 shl 0
const CLAP_AUDIO_PORT_SUPPORTS_64BITS* = 1 shl 1
const CLAP_AUDIO_PORT_PREFERS_64BITS* = 1 shl 2
const CLAP_AUDIO_PORT_REQUIRES_COMMON_SAMPLE_SIZE* = 1 shl 3
const CLAP_PARAM_IS_STEPPED* = 1 shl 0
const CLAP_PARAM_IS_PERIODIC* = 1 shl 1
const CLAP_PARAM_IS_HIDDEN* = 1 shl 2
const CLAP_PARAM_IS_READONLY* = 1 shl 3
const CLAP_PARAM_IS_BYPASS* = 1 shl 4
const CLAP_PARAM_IS_AUTOMATABLE* = 1 shl 5
const CLAP_PARAM_IS_AUTOMATABLE_PER_NOTE_ID* = 1 shl 6
const CLAP_PARAM_IS_AUTOMATABLE_PER_KEY* = 1 shl 7
const CLAP_PARAM_IS_AUTOMATABLE_PER_CHANNEL* = 1 shl 8
const CLAP_PARAM_IS_AUTOMATABLE_PER_PORT* = 1 shl 9
const CLAP_PARAM_IS_MODULATABLE* = 1 shl 10
const CLAP_PARAM_IS_MODULATABLE_PER_NOTE_ID* = 1 shl 11
const CLAP_PARAM_IS_MODULATABLE_PER_KEY* = 1 shl 12
const CLAP_PARAM_IS_MODULATABLE_PER_CHANNEL* = 1 shl 13
const CLAP_PARAM_IS_MODULATABLE_PER_PORT* = 1 shl 14
const CLAP_PARAM_REQUIRES_PROCESS* = 1 shl 15
const CLAP_NOTE_DIALECT_CLAP* = 1 shl 0
const CLAP_NOTE_DIALECT_MIDI* = 1 shl 1
const CLAP_NOTE_DIALECT_MIDI_MPE* = 1 shl 2
const CLAP_NOTE_DIALECT_MIDI2* = 1 shl 3
const CLAP_PROCESS_ERROR* = 0
const CLAP_PROCESS_CONTINUE* = 1
const CLAP_PROCESS_CONTINUE_IF_NOT_QUIET* = 2
const CLAP_PROCESS_TAIL* = 3
const CLAP_PROCESS_SLEEP* = 4
const CLAP_PORT_MONO* = cstring"mono"
const CLAP_PORT_STEREO* = cstring"stereo"
const CLAP_INVALID_ID* = high(uint32).clap_id
const CLAP_PLUGIN_FACTORY_ID* = cstring"clap.plugin-factory"
const CLAP_EXT_PARAMS* = cstring"clap.params"
const CLAP_EXT_STATE* = cstring"clap.state"
const CLAP_EXT_TRACK_INFO* = cstring"clap.track-info.draft/1"
const CLAP_EXT_NOTE_PORTS* = cstring"clap.note-ports"
const CLAP_EXT_AUDIO_PORTS* = cstring"clap.audio-ports"
const CLAP_EXT_TIMER_SUPPORT* = cstring"clap.timer-support"
const CLAP_EXT_LATENCY* = cstring"clap.latency"
const CLAP_EXT_GUI* = cstring"clap.gui"

const CLAP_WINDOW_API_WIN32* = cstring"win32"
const CLAP_WINDOW_API_COCOA* = cstring"cocoa"
const CLAP_WINDOW_API_X11* = cstring"x11"
const CLAP_WINDOW_API_WAYLAND* = cstring"wayland"