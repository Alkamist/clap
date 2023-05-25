import std/options; export options
import std/tables; export tables
import std/atomics; export atomics
import ./binding

type
  MidiEvent* = object
    time*: int
    port*: int
    data*: array[3, uint8]

  ParameterEventKind* = enum
    Value
    Modulation

  ParameterEvent* = object
    id*: int
    kind*: ParameterEventKind
    noteId*: int
    port*: int
    channel*: int
    key*: int
    value*: float

  TimeSignature* = object
    numerator*: int
    denominator*: int

  TransportFlag* = enum
    IsPlaying
    IsRecording
    LoopIsActive
    IsWithinPreRoll

  TransportEvent* = object
    flags*: set[TransportFlag]
    songPositionSeconds*: Option[float]
    loopStartSeconds*: Option[float]
    loopEndSeconds*: Option[float]
    songPositionBeats*: Option[float]
    loopStartBeats*: Option[float]
    loopEndBeats*: Option[float]
    tempo*: Option[float]
    tempoIncrement*: Option[float]
    barStartBeats*: Option[float]
    barNumber*: Option[int]
    timeSignature*: Option[TimeSignature]

  ParameterFlag* = enum
    IsStepped
    IsPeriodic
    IsHidden
    IsReadOnly
    IsBypass
    IsAutomatable
    IsAutomatablePerNoteId
    IsAutomatablePerKey
    IsAutomatablePerChannel
    IsAutomatablePerPort
    IsModulatable
    IsModulatablePerNoteId
    IsModulatablePerKey
    IsModulatablePerChannel
    IsModulatablePerPort
    RequiresProcess

  ParameterInfo* = object
    id*: int
    name*: string
    minValue*: float
    maxValue*: float
    defaultValue*: float
    flags*: set[ParameterFlag]
    module*: string

  AudioPlugin*[P] = ref object of RootObj
    sampleRate*: float
    minFrameCount*: int
    maxFrameCount*: int
    latency*: int
    isActive*: bool
    clapPlugin*: clap_plugin_t
    clapHost*: ptr clap_host_t
    clapHostLog*: ptr clap_host_log_t
    clapHostLatency*: ptr clap_host_latency_t
    clapHostTimerSupport*: ptr clap_host_timer_support_t
    timerNameToId*: Table[string, clap_id]
    timerIdToProc*: Table[clap_id, proc(plugin: AudioPlugin[P])]
    parameterValues*: array[P, Atomic[float]]
    outputEvents*: seq[clap_event_midi_t]