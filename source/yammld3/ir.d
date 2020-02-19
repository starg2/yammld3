
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
    systemReset,
    gsInsertionEffectOn,
    gsInsertionEffectSetType,
    gsInsertionEffectSetParam
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

    public @property float nominalDuration()
    {
        return _nominalDuration;
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

public final class GSInsertionEffectOn : Command
{
    public this(float nominalTime, bool on)
    {
        _nominalTime = nominalTime;
        _on = on;
    }

    public override @property IRKind kind()
    {
        return IRKind.gsInsertionEffectOn;
    }

    public override @property float nominalTime()
    {
        return _nominalTime;
    }

    public @property bool on()
    {
        return _on;
    }

    private float _nominalTime;
    private bool _on;
}

// http://www.eiji-s.info/88proie.html
public enum GSInsertionEffectType : ushort
{
    thru = 0x0000,
    stereoEQ = 0x0100,
    spectrum = 0x0101,
    enhancer = 0x0102,
    humanizer = 0x0103,
    overdrive = 0x0110,
    distortion = 0x0111,
    phaser = 0x0120,
    autoWah = 0x0121,
    rotary = 0x0122,
    stereoFlanger = 0x0123,
    stepFlanger = 0x0124,
    tremolo = 0x0125,
    autoPan = 0x0126,
    compressor = 0x0130,
    limiter = 0x0131,
    hexaChorus = 0x0140,
    tremoloChorus = 0x0141,
    stereoChorus = 0x0142,
    spaceD = 0x0143,
    _3dChorus = 0x0144,
    stereoDelay = 0x0150,
    modDelay = 0x0151,
    _3TapDelay = 0x0152,
    _4TapDelay = 0x0153,
    tmCtrlDelay = 0x0154,
    reverb = 0x0155,
    gateReverb = 0x0156,
    _3dDelay = 0x0157,
    _2PitchShifter = 0x0160,
    fbPShifter = 0x0161,
    _3dAuto = 0x0170,
    _3dManual = 0x0171,
    loFi1 = 0x0172,
    loFi2 = 0x0173,
    odChorus = 0x0200,
    odFlanger = 0x0201,
    odDelay = 0x0202,
    dsChorus = 0x0203,
    dsFlanger = 0x0204,
    dsDelay = 0x0205,
    ehChorus = 0x0206,
    ehFlanger = 0x0207,
    ehDelay = 0x0208,
    choDelay = 0x0209,
    flDelay = 0x020A,
    choFlanger = 0x020B,
    rotaryMulti = 0x0300,
    gtrMulti1 = 0x0400,
    gtrMulti2 = 0x0401,
    gtrMulti3 = 0x0402,
    cleanGtMulti1 = 0x0403,
    cleanGtMulti2 = 0x0404,
    bassMulti = 0x0405,
    rhodesMulti = 0x0406,
    keyboardMulti = 0x0500,
    choPlusDelay = 0x1100,
    flPlusDelay = 0x1101,
    choPlusFlanger = 0x1102,
    od1PlusOd2 = 0x1103,
    odPlusRotary = 0x1104,
    odPlusPhaser = 0x1105,
    odPlusAutoWah = 0x1106,
    phPlusRotary = 0x1107,
    phPlusAutoWah = 0x1108
}

public final class GSInsertionEffectSetType : Command
{
    public this(float nominalTime, GSInsertionEffectType type)
    {
        _nominalTime = nominalTime;
        _type = type;
    }

    public override @property IRKind kind()
    {
        return IRKind.gsInsertionEffectSetType;
    }

    public override @property float nominalTime()
    {
        return _nominalTime;
    }

    public @property GSInsertionEffectType type()
    {
        return _type;
    }

    private float _nominalTime;
    private GSInsertionEffectType _type;
}

public final class GSInsertionEffectSetParam : Command
{
    public this(float nominalTime, byte index, byte value)
    {
        assert(0 <= index && index < 20);

        _nominalTime = nominalTime;
        _index = index;
        _value = value;
    }

    public override @property IRKind kind()
    {
        return IRKind.gsInsertionEffectSetParam;
    }

    public override @property float nominalTime()
    {
        return _nominalTime;
    }

    public @property byte index()
    {
        return _index;
    }

    public @property byte value()
    {
        return _value;
    }

    private float _nominalTime;
    private byte _index;    // 0-based
    private byte _value;
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

    case IRKind.gsInsertionEffectOn:
        return Overloaded(cast(GSInsertionEffectOn)c);

    case IRKind.gsInsertionEffectSetType:
        return Overloaded(cast(GSInsertionEffectSetType)c);

    case IRKind.gsInsertionEffectSetParam:
        return Overloaded(cast(GSInsertionEffectSetParam)c);
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
