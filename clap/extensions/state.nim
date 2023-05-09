import ../binding
import ../shared

var stateExtension* = clap_plugin_state_t(
  save: proc(plugin: ptr clap_plugin_t, stream: ptr clap_ostream_t): bool {.cdecl.} =
    let instance = getInstance(plugin)
    if instance.dispatcher.savePreset == nil:
      return false

    instance.syncParametersAudioThreadToMainThread()
    var preset = instance.dispatcher.savePreset(instance)

    var writePtr = addr(preset[0])
    var bytesToWrite = int64(preset.len)
    while true:
      var bytesWritten = stream.write(stream, writePtr, uint64(bytesToWrite))

      # Success
      if bytesWritten == bytesToWrite:
        break

      # An error happened
      if bytesWritten <= 0 or bytesWritten > bytesToWrite:
        return false

      bytesToWrite -= bytesWritten
      writePtr = cast[ptr byte](cast[uint](writePtr) + cast[uint](bytesWritten))

    return true
  ,
  load: proc(plugin: ptr clap_plugin_t, stream: ptr clap_istream_t): bool {.cdecl.} =
    let instance = getInstance(plugin)

    var preset: seq[byte]

    while true:
      var dataByte: byte
      var bytesRead = stream.read(stream, addr(dataByte), 1)

      # Hit the end of the stream
      if bytesRead == 0:
        break

      # Possibly more to read so keep going
      if bytesRead == 1:
        preset.add(dataByte)
        continue

      # An error happened
      if bytesRead < 0:
        return false

    instance.parameterLock.acquire()
    instance.dispatcher.loadPreset(instance, preset)
    instance.parameterLock.release()

    return true
  ,
)