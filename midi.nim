type
  Message* = array[3, uint8]

  MessageKind* = enum
    Unknown
    NoteOff
    NoteOn
    Aftertouch
    Cc
    PatchChange
    ChannelPressure
    PitchBend
    NonMusical

proc kind*(msg: Message): MessageKind =
  let statusCode = msg[0] and 0xF0
  return case statusCode:
    of 0x80: NoteOff
    of 0x90: NoteOn
    of 0xA0: Aftertouch
    of 0xB0: Cc
    of 0xC0: PatchChange
    of 0xD0: ChannelPressure
    of 0xE0: PitchBend
    of 0xF0: NonMusical
    else: Unknown

proc channel*(msg: Message): uint8 = return min(msg[0] and 0x0F, 15)
proc key*(msg: Message): uint8 = return min(msg[1], 127)
proc velocity*(msg: Message): uint8 = return min(msg[2], 127)
proc ccNumber*(msg: Message): uint8 = return min(msg[1], 127)
proc ccValue*(msg: Message): uint8 = return min(msg[2], 127)