
module yammld3.midievent;

import std.variant;

public struct NoteEventData
{
    byte note;
    byte velocity;   // [0, 127]
    int duration;   // in ticks
}

public struct PolyphonicAfterTouchEventData
{
    byte note;
    byte pressure;
}

// http://quelque.sakura.ne.jp/midi_cc.html
public enum ControlChangeCode : byte
{
    bankSelectMSB = 0,
    modulation = 1,
    breathController = 2,
    footController = 4,
    portamentoTime = 5,
    dataEntry = 6,
    channelVolume = 7,
    balance = 8,
    pan = 10,
    expression = 11,
    effectControl1 = 12,
    effectControl2 = 13,
    generalPurposeController1 = 16,
    generalPurposeController2 = 17,
    generalPurposeController3 = 18,
    generalPurposeController4 = 19,
    bankSelectLSB = 32,
    hold1 = 64,
    portamento = 65,
    sostenuto = 66,
    softPedal = 67,
    legatoFootswitch = 68,
    hold2 = 69,
    soundVariation = 70,
    harmonicIntensity = 71,
    releaseTime = 72,
    attackTime = 73,
    brightness = 74,
    decayTime = 75,
    vibratoRate = 76,
    vibratoDepth = 77,
    vibratoDelay = 78,
    generalPurposeController5 = 80,
    generalPurposeController6 = 81,
    generalPurposeController7 = 82,
    generalPurposeController8 = 83,
    portamentoControl = 84,
    effect1Depth = 91,  // reverb
    effect2Depth = 92,  // tremolo
    effect3Depth = 93,  // chorus
    effect4Depth = 94,  // celeste
    effect5Depth = 95,  // phaser
    dataIncrement = 96,
    dataDecrement = 97,
    nonRegisteredParameterNumberMSB = 99,
    nonRegisteredParameterNumberLSB = 98,
    registeredParameterNumberLSB = 100,
    registeredParameterNumberMSB = 101
}

public struct ControlChangeEventData
{
    ControlChangeCode code;
    byte value;
}

public struct ProgramChangeEventData
{
    byte program;
}

public struct ChannelAfterTouchEventData
{
    byte pressure;
}

public struct PitchBendEventData
{
    short bend;
}

public struct SysExEventData
{
    ubyte[] bytes;
}

public enum MetaEventKind : byte
{
    sequenceNumber = 0x0,
    textEvent = 0x1,
    copyright = 0x2,
    sequenceName = 0x3,
    instrumentName = 0x4,
    lyrics = 0x5,
    marker = 0x6,
    cuePoint = 0x7,
    channelPrefix = 0x20,
    endOfTrack = 0x2F,
    setTempo = 0x51,
    smpteOffset = 0x54,
    timeSignature = 0x58,
    keySignature = 0x59,
    sequencerSpecific = 0x7F
}

public struct MetaEventData
{
    MetaEventKind kind;
    ubyte[] bytes;
}

public alias MIDIEventData = Algebraic!(
    NoteEventData,
    PolyphonicAfterTouchEventData,
    ControlChangeEventData,
    ProgramChangeEventData,
    ChannelAfterTouchEventData,
    PitchBendEventData,
    SysExEventData,
    MetaEventData
);

public struct MIDIEvent
{
    int time;   // absolute time in ticks
    MIDIEventData data;
}

public struct MIDITrack
{
    int channel;
    MIDIEvent[] events;
}
