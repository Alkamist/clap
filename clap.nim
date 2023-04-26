{.experimental: "overloadableEnums".}

const nameSize* = 256
const pathSize* = 1024
const coreEventSpaceId* = 0
const pluginFactoryId* = cstring"clap.plugin-factory"
const extNotePorts* = cstring"clap.note-ports"
const extLatency* = cstring"clap.latency"
const extParams* = cstring"clap.params"
const extTimerSupport* = cstring"clap.timer-support"

type
  Id* = uint32
  BeatTime* = int64
  SecTime* = int64

  NoteDialect* = enum
    Clap
    Midi
    MidiMpe
    Midi2

  EventType* = enum
    NoteOn
    NoteOff
    NoteChoke
    NoteEnd
    NoteExpression
    ParamValue
    ParamMod
    ParamGestureBegin
    ParamGestureEnd
    Transport
    Midi
    MidiSysex
    Midi2

  EventFlags* = enum
    IsLive
    DontRecord

  EventHeader* {.bycopy.} = object
    size*: uint32
    time*: uint32
    spaceId*: uint16
    `type`*: uint16
    flags*: uint32

  EventParamValue* {.bycopy.} = object
    header*: EventHeader
    paramId*: Id
    cookie*: pointer
    noteId*: int32
    portIndex*: int16
    channel*: int16
    key*: int16
    value*: float64

  EventMidi* {.bycopy.} = object
    header*: EventHeader
    portIndex*: uint16
    data*: array[3, uint8]

  EventTransport* {.bycopy.} = object
    header*: EventHeader
    flags*: uint32
    songPosBeats*: BeatTime
    songPosSeconds*: SecTime
    tempo*: float64
    tempoInc*: float64
    loopStartBeats*: BeatTime
    loopEndBeats*: BeatTime
    loopStartSeconds*: SecTime
    loopEndSeconds*: SecTime
    barStart*: BeatTime
    barNumber*: int32
    tsigNum*: uint16
    tsigDenom*: uint16

  AudioBuffer* {.bycopy.} = object
    data32*: ptr ptr float32
    data64*: ptr ptr float64
    channelCount*: uint32
    latency*: uint32
    constantMask*: uint64

  InputEvents* {.bycopy.} = object
    ctx*: pointer
    size*: proc(list: ptr InputEvents): uint32 {.cdecl.}
    get*: proc(list: ptr InputEvents, index: uint32): ptr EventHeader {.cdecl.}

  OutputEvents* {.bycopy.} = object
    ctx*: pointer
    tryPush*: proc(list: ptr OutputEvents, event: ptr EventHeader): bool {.cdecl.}

  ProcessStatus* {.size: sizeof(int32).} = enum
    Error
    Continue
    ContinueIfNotQuiet
    Tail
    Sleep

  PluginLatency* {.bycopy.} = object
    get*: proc(plugin: ptr Plugin): uint32 {.cdecl.}

  Process* {.bycopy.} = object
    steadyTime*: int64
    framesCount*: uint32
    transport*: ptr EventTransport
    audioInputs*: ptr AudioBuffer
    audioOutputs*: ptr AudioBuffer
    audioInputsCount*: uint32
    audioOutputsCount*: uint32
    inEvents*: ptr InputEvents
    outEvents*: ptr OutputEvents

  NotePortInfo* {.bycopy.} = object
    id*: Id
    supportedDialects*: uint32
    preferredDialect*: uint32
    name*: array[nameSize, uint8]

  PluginNotePorts* {.bycopy.} = object
    count*: proc(plugin: ptr Plugin, isInput: bool): uint32 {.cdecl.}
    get*: proc(plugin: ptr Plugin, index: uint32, isInput: bool, info: ptr NotePortInfo): bool {.cdecl.}

  ParamInfoFlags* = enum
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

  ParamInfo* {.bycopy.} = object
    id*: Id
    flags*: uint32
    cookie*: pointer
    name*: array[nameSize, uint8]
    module*: array[pathSize, uint8]
    minValue*: float64
    maxValue*: float64
    defaultValue*: float64

  PluginParams* {.bycopy.} = object
    count*: proc(plugin: ptr Plugin): uint32 {.cdecl.}
    getInfo*: proc(plugin: ptr Plugin, paramIndex: uint32, paramInfo: ptr ParamInfo): bool {.cdecl.}
    getValue*: proc(plugin: ptr Plugin, paramId: Id, outValue: ptr float64): bool {.cdecl.}
    valueToText*: proc(plugin: ptr Plugin, paramId: Id, value: float64, outBuffer: ptr UncheckedArray[uint8], outBufferCapacity: uint32): bool {.cdecl.}
    textToValue*: proc(plugin: ptr Plugin, paramId: Id, paramValueText: cstring, outValue: ptr float64): bool {.cdecl.}
    flush*: proc(plugin: ptr Plugin, input: ptr InputEvents, output: ptr OutputEvents) {.cdecl.}

  PluginDescriptor* {.bycopy.} = object
    clapVersion*: Version
    id*: cstring
    name*: cstring
    vendor*: cstring
    url*: cstring
    manualUrl*: cstring
    supportUrl*: cstring
    version*: cstring
    description*: cstring
    features*: ptr UncheckedArray[cstring]

  Plugin* {.bycopy.} = object
    desc*: ptr PluginDescriptor
    pluginData*: pointer
    init*: proc(plugin: ptr Plugin): bool {.cdecl.}
    destroy*: proc(plugin: ptr Plugin) {.cdecl.}
    activate*: proc(plugin: ptr Plugin, sampleRate: float64, minFramesCount, maxFramesCount: uint32): bool {.cdecl.}
    deactivate*: proc(plugin: ptr Plugin) {.cdecl.}
    startProcessing*: proc(plugin: ptr Plugin): bool {.cdecl.}
    stopProcessing*: proc(plugin: ptr Plugin) {.cdecl.}
    reset*: proc(plugin: ptr Plugin) {.cdecl.}
    process*: proc(plugin: ptr Plugin, process: ptr Process): ProcessStatus {.cdecl.}
    getExtension*: proc(plugin: ptr Plugin, id: cstring): pointer {.cdecl.}
    onMainThread*: proc(plugin: ptr Plugin) {.cdecl.}

  Version* {.bycopy.} = object
    major*: uint32
    minor*: uint32
    revision*: uint32

  PluginTimerSupport* {.bycopy.} = object
    onTimer*: proc(plugin: ptr Plugin, timerId: Id) {.cdecl.}

  HostTimerSupport* {.bycopy.} = object
    registerTimer*: proc(host: ptr Host, periodMs: uint32, timerId: ptr Id): bool {.cdecl.}
    unregisterTimer*: proc(host: ptr Host, timerId: Id): bool {.cdecl.}

  Host* {.bycopy.} = object
    clapVersion*: Version
    hostData*: pointer
    name*: cstring
    vendor*: cstring
    url*: cstring
    version*: cstring
    getExtension*: proc(host: ptr Host, extensionId: cstring): pointer {.cdecl.}
    requestRestart*: proc(host: ptr Host) {.cdecl.}
    requestProcess*: proc(host: ptr Host) {.cdecl.}
    requestCallback*: proc(host: ptr Host) {.cdecl.}

  PluginFactory* {.bycopy.} = object
    getPluginCount*: proc(factory: ptr PluginFactory): uint32 {.cdecl.}
    getPluginDescriptor*: proc(factory: ptr PluginFactory, index: uint32): ptr PluginDescriptor {.cdecl.}
    createPlugin*: proc(factory: ptr PluginFactory, host: ptr Host, pluginId: cstring): ptr Plugin {.cdecl.}

  PluginEntry* {.bycopy.} = object
    clapVersion*: Version
    init*: proc(pluginPath: cstring): bool {.cdecl.}
    deinit*: proc() {.cdecl.}
    getFactory*: proc(factoryId: cstring): pointer {.cdecl.}

proc versionIsCompatible*(v: Version): bool =
  v.major >= 1

converter toUint16*(eventType: EventType): uint16 = uint16(eventType)
converter toUint32*(noteDialectSet: set[NoteDialect]): uint32 = cast[uint32](noteDialectSet)