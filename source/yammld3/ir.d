
module yammld3.ir;

import yammld3.common;
public import yammld3.midievent : ControlChangeCode, MetaEventKind;

public enum IRKind
{
    note,
    controlChange,
    programChange,
    pitchBend,
    setTempo,
    setMeter,
    setKeySig,
    textMetaEvent,
    systemReset
}

public interface Command
{
    @property IRKind kind();
    @property float nominalTime();
}

public struct NoteInfo
{
    int key;
    float velocity;
    float timeShift;
    float lastNominalDuration;
    float gateTime;
}

public final class Note : Command
{
    import std.typecons : Nullable;

    public this(float nominalTime, float nominalDuration)
    {
        _nominalTime = nominalTime;
        _nominalDuration = nominalDuration;
    }

    public this(float nominalTime, NoteInfo noteInfo, float nominalDuration)
    {
        _nominalTime = nominalTime;
        _noteInfo = noteInfo;
        _nominalDuration = nominalDuration;
    }

    public override @property IRKind kind()
    {
        return IRKind.note;
    }

    public override @property float nominalTime()
    {
        return _nominalTime;
    }

    public @property bool isRest()
    {
        return _noteInfo.isNull;
    }

    public @property NoteInfo noteInfo()
    {
        return _noteInfo.get;
    }

    package @property void noteInfo(NoteInfo ni)
    {
        _noteInfo = ni;
    }

    public @property float nominalDuration()
    {
        return _nominalDuration;
    }

    package @property void nominalDuration(float d)
    {
        _nominalDuration = d;
    }

    private float _nominalTime;
    private Nullable!NoteInfo _noteInfo;
    private float _nominalDuration;
}

public final class ControlChange : Command
{
    public this(float nominalTime, ControlChangeCode code, int value)
    {
        _nominalTime = nominalTime;
        _code = code;
        _value = value;
    }

    public override @property IRKind kind()
    {
        return IRKind.controlChange;
    }

    public override @property float nominalTime()
    {
        return _nominalTime;
    }

    public @property ControlChangeCode code()
    {
        return _code;
    }

    public @property int value()
    {
        return _value;
    }

    private float _nominalTime;
    private ControlChangeCode _code;
    private int _value;
}

public final class ProgramChange : Command
{
    public this(float nominalTime, byte bankLSB, byte bankMSB, byte program)
    {
        _nominalTime = nominalTime;
        _bankLSB = bankLSB;
        _bankMSB = bankMSB;
        _program = program;
    }

    public override @property IRKind kind()
    {
        return IRKind.programChange;
    }

    public override @property float nominalTime()
    {
        return _nominalTime;
    }

    public @property byte bankLSB()
    {
        return _bankLSB;
    }

    public @property byte bankMSB()
    {
        return _bankMSB;
    }

    public @property byte program()
    {
        return _program;
    }

    private float _nominalTime;
    private byte _bankLSB;
    private byte _bankMSB;
    private byte _program;
}

public final class PitchBendEvent : Command
{
    public this(float nominalTime, float bend)
    {
        _nominalTime = nominalTime;
        _bend = bend;
    }

    public override @property IRKind kind()
    {
        return IRKind.pitchBend;
    }

    public override @property float nominalTime()
    {
        return _nominalTime;
    }

    public @property float bend()
    {
        return _bend;
    }

    private float _nominalTime;
    private float _bend;
}

public final class SetTempoEvent : Command
{
    public this(float nominalTime, float tempo)
    {
        _nominalTime = nominalTime;
        _tempo = tempo;
    }

    public override @property IRKind kind()
    {
        return IRKind.setTempo;
    }

    public override @property float nominalTime()
    {
        return _nominalTime;
    }

    public @property float tempo()
    {
        return _tempo;
    }

    private float _nominalTime;
    private float _tempo;
}

public final class SetMeterEvent : Command
{
    public this(float nominalTime, Fraction!int meter)
    {
        _nominalTime = nominalTime;
        _meter = meter;
    }

    public override @property IRKind kind()
    {
        return IRKind.setMeter;
    }

    public override @property float nominalTime()
    {
        return _nominalTime;
    }

    public @property Fraction!int meter()
    {
        return _meter;
    }

    private float _nominalTime;
    private Fraction!int _meter;
}

public final class SetKeySigEvent : Command
{
    public this(float nominalTime, KeyName tonic, bool isMinor)
    {
        _nominalTime = nominalTime;
        _tonic = tonic;
        _isMinor = isMinor;
    }

    public override @property IRKind kind()
    {
        return IRKind.setKeySig;
    }

    public override @property float nominalTime()
    {
        return _nominalTime;
    }

    public @property KeyName tonic()
    {
        return _tonic;
    }

    public @property bool isMinor()
    {
        return _isMinor;
    }

    public int countSharp()
    {
        final switch (_tonic)
        {
        case KeyName.c:
            return !_isMinor ? 0 : -3;

        case KeyName.cSharp:
            return !_isMinor ? -5 : 4;

        case KeyName.d:
            return !_isMinor ? 2 : -1;

        case KeyName.dSharp:
            return !_isMinor ? -3 : 6;

        case KeyName.e:
            return !_isMinor ? 4 : 1;

        case KeyName.f:
            return !_isMinor ? -1 : -4;

        case KeyName.fSharp:
            return !_isMinor ? 6 : 3;

        case KeyName.g:
            return !_isMinor ? 1 : -2;

        case KeyName.gSharp:
            return !_isMinor ? -4 : 5;

        case KeyName.a:
            return !_isMinor ? 3 : 0;

        case KeyName.aSharp:
            return !_isMinor ? -2 : -5;

        case KeyName.b:
            return !_isMinor ? 5 : -2;
        }
    }

    private float _nominalTime;
    private KeyName _tonic;
    private bool _isMinor;
}

public final class TextMetaEvent : Command
{
    public this(float nominalTime, MetaEventKind metaEventKind, string text)
    {
        _nominalTime = nominalTime;
        _metaEventKind = metaEventKind;
        _text = text;
    }

    public override @property IRKind kind()
    {
        return IRKind.textMetaEvent;
    }

    public override @property float nominalTime()
    {
        return _nominalTime;
    }

    public @property MetaEventKind metaEventKind()
    {
        return _metaEventKind;
    }

    public @property string text()
    {
        return _text;
    }

    private float _nominalTime;
    private MetaEventKind _metaEventKind;
    private string _text;
}

public enum SystemKind
{
    gm,
    gs,
    xg
}

public final class SystemReset : Command
{
    public this(float nominalTime, SystemKind systemKind)
    {
        _nominalTime = nominalTime;
        _systemKind = systemKind;
    }

    public override @property IRKind kind()
    {
        return IRKind.systemReset;
    }

    public override @property float nominalTime()
    {
        return _nominalTime;
    }

    public @property SystemKind systemKind()
    {
        return _systemKind;
    }

    private float _nominalTime;
    private SystemKind _systemKind;
}

public auto visit(Handlers...)(Command c)
{
    assert(c !is null);

    static struct Overloaded
    {
        static foreach (h; Handlers)
        {
            alias opCall = h;
        }
    }

    final switch (c.kind)
    {
    case IRKind.note:
        return Overloaded(cast(Note)c);

    case IRKind.controlChange:
        return Overloaded(cast(ControlChange)c);

    case IRKind.programChange:
        return Overloaded(cast(ProgramChange)c);

    case IRKind.pitchBend:
        return Overloaded(cast(PitchBendEvent)c);

    case IRKind.setTempo:
        return Overloaded(cast(SetTempoEvent)c);

    case IRKind.setMeter:
        return Overloaded(cast(SetMeterEvent)c);

    case IRKind.setKeySig:
        return Overloaded(cast(SetKeySigEvent)c);

    case IRKind.textMetaEvent:
        return Overloaded(cast(TextMetaEvent)c);

    case IRKind.systemReset:
        return Overloaded(cast(SystemReset)c);
    }
}

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
