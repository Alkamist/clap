import ../binding

proc save*[T](plugin: ptr clap_plugin_t, stream: ptr clap_ostream_t): bool {.cdecl.} =
  mixin savePreset

  let plugin = cast[T](plugin.plugin_data)

  var preset = plugin.savePreset()
  if preset.len == 0:
    return false

  var writePtr = addr(preset[0])
  var bytesToWrite = int64(preset.len)
  while true:
    var bytesWritten = stream.write(stream, writePtr, uint64(bytesToWrite))

    # Success.
    if bytesWritten == bytesToWrite:
      break

    # An error happened.
    if bytesWritten <= 0 or bytesWritten > bytesToWrite:
      return false

    bytesToWrite -= bytesWritten
    writePtr = cast[ptr char](cast[uint](writePtr) + cast[uint](bytesWritten))

  return true

proc load*[T](plugin: ptr clap_plugin_t, stream: ptr clap_istream_t): bool {.cdecl.} =
  mixin loadPreset

  let plugin = cast[T](plugin.plugin_data)

  var preset: seq[byte]

  while true:
    var dataByte: byte
    var bytesRead = stream.read(stream, addr(dataByte), 1)

    # Hit the end of the stream.
    if bytesRead == 0:
      break

    # Possibly more to read so keep going.
    if bytesRead == 1:
      preset.add(dataByte)
      continue

    # An error happened.
    if bytesRead < 0:
      return false

  if preset.len == 0:
    return false

  plugin.loadPreset(preset)

  return true