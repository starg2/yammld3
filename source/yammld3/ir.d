
module yammld3.ir;

import std.variant;

import yammld3.common;
public import yammld3.midievent : ControlChangeCode, MetaEventKind;

public struct NoteInfo
{
    int key;
    float velocity;
    float timeShift;
    float lastNominalDuration;
    float gateTime;
}

public struct Note
{
    import std.typecons : Nullable;

    @property bool isRest()
    {
        return noteInfo.isNull;
    }

    float nominalTime;
    Nullable!NoteInfo noteInfo;
    float nominalDuration;  // 1.0 == quarter note
}

public struct ControlChange
{
    float nominalTime;
    ControlChangeCode code;
    int value;
}

public struct ProgramChange
{
    float nominalTime;
    byte bankLSB;
    byte bankMSB;
    byte program;
}

public struct SetTempoEvent
{
    float nominalTime;
    float tempo;
}

public struct SetMeterEvent
{
    float nominalTime;
    Fraction!int meter;
}

public struct SetKeySigEvent
{
    float nominalTime;
    KeyName tonic;
    bool isMinor;
}

public struct TextMetaEvent
{
    float nominalTime;
    MetaEventKind kind;
    string text;
}

public enum SystemKind
{
    gm,
    gs,
    xg
}

public struct SystemReset
{
    float nominalTime;
    SystemKind kind;
}

public alias Command = Algebraic!(
    Note,
    ControlChange,
    ProgramChange,
    SetTempoEvent,
    SetMeterEvent,
    SetKeySigEvent,
    TextMetaEvent,
    SystemReset
);

public enum int conductorChannel = -1;
public enum int virtualChannel = -2;

public final class Track
{
    public this(string name, int channel, Command[] commands)
    {
        _name = name;
        _channel = channel;
        _commands = commands;
    }

    public @property string name()
    {
        return _name;
    }

    public @property int channel()
    {
        return _channel;
    }

    public @property Command[] commands()
    {
        return _commands;
    }

    private string _name;
    private int _channel;
    private Command[] _commands;
}

public final class Composition
{
    public this(string name, Track[] tracks)
    {
        _name = name;
        _tracks = tracks;
    }

    public @property string name()
    {
        return _name;
    }

    public @property Track[] tracks()
    {
        return _tracks;
    }

    private string _name;
    private Track[] _tracks;
}
