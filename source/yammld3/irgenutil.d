
module yammld3.irgenutil;

import std.array;
import std.conv : to;
import std.typecons : Nullable;
import std.variant;

import yammld3.common;
import yammld3.ir;
import yammld3.priorspec;


package enum TrackPropertyKind
{
    duration,   // l
    octave,     // o
    keyShift,   // n
    velocity,   // v
    timeShift,  // t
    gateTime    // q
}

package bool isIntegerProperty(TrackPropertyKind kind)
{
    return kind == TrackPropertyKind.octave || kind == TrackPropertyKind.keyShift;
}

package float toPercentage(TrackPropertyKind kind, float n)
{
    final switch (kind)
    {
    case TrackPropertyKind.duration:
    case TrackPropertyKind.octave:
    case TrackPropertyKind.keyShift:
        assert(false);

    case TrackPropertyKind.velocity:
        return n / 127.0f;

    case TrackPropertyKind.timeShift:
        return n;

    case TrackPropertyKind.gateTime:
        return n / 100.0f;
    }
}

private struct TrackProperty(T)
{
    public void setBaseValue(T n)
    {
        _baseValue = n;
        _priorSpecs = null;
    }

    public void incrementBaseValue(T n)
    {
        _baseValue += n;
    }

    public void modifyBaseValue(OptionalSign sign, T n)
    {
        final switch (sign)
        {
        case OptionalSign.none:
            setBaseValue(n);
            break;

        case OptionalSign.plus:
            incrementBaseValue(n);
            break;

        case OptionalSign.minus:
            incrementBaseValue(-n);
            break;
        }
    }

    public void addPriorSpec(PriorSpec!T ps)
    {
        _priorSpecs ~= ps;
    }
    
    public void clearPriorSpecs()
    {
        _priorSpecs = null;
    }

    public T getValueFor(int noteCount, float time)
    {
        import std.algorithm.iteration : filter, map, sum;
        import std.algorithm.searching : canFind;

        if (_priorSpecs.canFind!(x => x.expired(noteCount, time)))
        {
            _priorSpecs = _priorSpecs.filter!(x => !x.expired(noteCount, time)).array;
        }

        return _priorSpecs.map!(x => x.getValueFor(noteCount, time)).sum(_baseValue);
    }

    private T _baseValue = 0;
    private PriorSpec!T[] _priorSpecs;
}

private struct TrackBuilderContext
{
    TrackProperty!int octave;
    TrackProperty!int keyShift;
    TrackProperty!float velocity;     // [0, 1]
    TrackProperty!float timeShift;    // 1.0 == quarter note
    TrackProperty!float gateTime;     // [0, 1]
}

private final class TrackBuilder
{
    public this(string name)
    {
        _name = name;
        _context.octave.setBaseValue(5);
        _context.velocity.setBaseValue(0.7f);
        _context.gateTime.setBaseValue(0.7f);
    }

    public @property string name()
    {
        return _name;
    }

    public @property int channel()
    {
        return _channel;
    }

    public @property void channel(int ch)
    {
        _channel = ch;
    }

    public TrackBuilderContext saveContext()
    {
        return _context;
    }

    public void restoreContext(TrackBuilderContext context)
    {
        _context = context;
    }

    public Track build()
    {
        flush();
        return new Track(_name, _channel, _commands[]);
    }

    public void setProgram(ProgramChange pc)
    {
        flush();
        _commands.put(Command(pc));
    }

    public void setControlChange(ControlChange cc)
    {
        flush();
        _commands.put(Command(cc));
    }

    public void putNote(int noteCount, float time, Note note)
    {
        flush();

        if (!note.noteInfo.isNull)
        {
            note.noteInfo.get.key += _context.octave.getValueFor(noteCount, time) * 12;
            note.noteInfo.get.key += _context.keyShift.getValueFor(noteCount, time);
            note.noteInfo.get.velocity += _context.velocity.getValueFor(noteCount, time);
            note.noteInfo.get.timeShift += _context.timeShift.getValueFor(noteCount, time);
            note.noteInfo.get.gateTime += _context.gateTime.getValueFor(noteCount, time);
        }

        _queuedNote = note;
    }

    public bool extendPreviousNote(int noteCount, float time, float duration)
    {
        if (_queuedNote.isNull)
        {
            return false;
        }

        if (!_queuedNote.get.noteInfo.isNull)
        {
            _queuedNote.get.noteInfo.get.lastNominalDuration = duration;
            _queuedNote.get.noteInfo.get.gateTime = _context.gateTime.getValueFor(noteCount, time);
        }

        _queuedNote.get.nominalDuration += duration;
        return true;
    }

    public void setTrackProperty(TrackPropertyKind kind, OptionalSign sign, Algebraic!(int, float) value)
    {
        final switch (kind)
        {
        case TrackPropertyKind.duration:
            assert(false);

        case TrackPropertyKind.octave:
            assert(value.peek!int !is null);
            _context.octave.modifyBaseValue(sign, value.get!int);
            break;

        case TrackPropertyKind.keyShift:
            assert(value.peek!int !is null);
            _context.keyShift.modifyBaseValue(sign, value.get!int);
            break;

        case TrackPropertyKind.velocity:
            assert(value.peek!float !is null);
            _context.velocity.modifyBaseValue(sign, value.get!float);
            break;

        case TrackPropertyKind.timeShift:
            assert(value.peek!float !is null);
            _context.timeShift.modifyBaseValue(sign, value.get!float);
            break;

        case TrackPropertyKind.gateTime:
            assert(value.peek!float !is null);
            _context.gateTime.modifyBaseValue(sign, value.get!float);
            break;
        }
    }
    
    public void clearPriorSpecs(TrackPropertyKind kind)
    {
        final switch (kind)
        {
        case TrackPropertyKind.duration:
            assert(false);

        case TrackPropertyKind.octave:
            _context.octave.clearPriorSpecs();
            break;

        case TrackPropertyKind.keyShift:
            _context.keyShift.clearPriorSpecs();
            break;

        case TrackPropertyKind.velocity:
            _context.velocity.clearPriorSpecs();
            break;

        case TrackPropertyKind.timeShift:
            _context.timeShift.clearPriorSpecs();
            break;

        case TrackPropertyKind.gateTime:
            _context.gateTime.clearPriorSpecs();
            break;
        }
    }

    public void addPriorSpec(TrackPropertyKind kind, Algebraic!(PriorSpec!int, PriorSpec!float) priorSpec)
    {
        final switch (kind)
        {
        case TrackPropertyKind.duration:
            assert(false);

        case TrackPropertyKind.octave:
            assert(priorSpec.peek!(PriorSpec!int) !is null);
            _context.octave.addPriorSpec(priorSpec.get!(PriorSpec!int));
            break;

        case TrackPropertyKind.keyShift:
            assert(priorSpec.peek!(PriorSpec!int) !is null);
            _context.keyShift.addPriorSpec(priorSpec.get!(PriorSpec!int));
            break;

        case TrackPropertyKind.velocity:
            assert(priorSpec.peek!(PriorSpec!float) !is null);
            _context.velocity.addPriorSpec(priorSpec.get!(PriorSpec!float));
            break;

        case TrackPropertyKind.timeShift:
            assert(priorSpec.peek!(PriorSpec!float) !is null);
            _context.timeShift.addPriorSpec(priorSpec.get!(PriorSpec!float));
            break;

        case TrackPropertyKind.gateTime:
            assert(priorSpec.peek!(PriorSpec!float) !is null);
            _context.gateTime.addPriorSpec(priorSpec.get!(PriorSpec!float));
            break;
        }
    }
    
    private void flush()
    {
        if (!_queuedNote.isNull)
        {
            _commands.put(Command(_queuedNote.get));
            _queuedNote.nullify();
        }
    }

    private string _name;
    private int _channel;
    private TrackBuilderContext _context;
    private Appender!(Command[]) _commands;
    private Nullable!Note _queuedNote;
}

private struct MeterInfo
{
    @property float measureLength() const
    {
        return 4.0f * meter.numerator.to!float / meter.denominator.to!float;
    }

    @property float beatLength() const
    {
        return 4.0f / meter.denominator.to!float;
    }

    float time;
    Fraction!int meter;
}

private int divUp(float numerator, float denominator)
{
    import std.math : floor;
    assert(numerator >= 0);
    assert(denominator > 0);
    return (floor(numerator).to!int + floor(denominator).to!int - 1) / floor(denominator).to!int;
}

private struct MeterMap
{
    public float toTime(float startTime, Time time) const
    {
        import std.algorithm.comparison : min;
        import std.range : slide;
        import std.typecons : No;

        auto r = getSorted();
        assert(!r.empty);
        auto low = r.lowerBound(MeterInfo(startTime));

        size_t i = low.length == 0 ? 0 : low.length - 1;
        float curTime = startTime;
        Time remainingTime = time;

        foreach (tp; r[i..$].slide!(No.withPartial)(2))
        {
            if (remainingTime == Time(0, 0, 0))
            {
                return curTime - startTime;
            }

            if (curTime < tp[1].time && remainingTime.measures > 0)
            {
                int availableMeasures = divUp(tp[1].time - curTime, tp[0].measureLength);
                int actualMeasures = min(remainingTime.measures, availableMeasures);
                remainingTime.measures -= actualMeasures;
                curTime += actualMeasures * tp[0].measureLength;
            }

            if (curTime < tp[1].time && remainingTime.beats > 0)
            {
                int availableBeats = divUp(tp[1].time - curTime, tp[0].beatLength);
                int actualBeats = min(remainingTime.beats, availableBeats);
                remainingTime.beats -= actualBeats;
                curTime += actualBeats * tp[0].beatLength;
            }

            if (curTime < tp[1].time && remainingTime.ticks > 0)
            {
                curTime += remainingTime.ticks.to!float / ticksPerQuarterNote;
                remainingTime.ticks = 0;
                return curTime - startTime;
            }
        }

        curTime += remainingTime.measures * r.back.measureLength;
        curTime += remainingTime.beats * r.back.beatLength;
        curTime += remainingTime.ticks.to!float / ticksPerQuarterNote;

        return curTime - startTime;
    }

    public void setMeter(float time, Fraction!int meter)
    {
        auto r = getSorted();
        size_t pos = r.length - r.upperBound(MeterInfo(time)).length;
        _timePoints.insertInPlace(pos, MeterInfo(time, meter));
    }

    private auto getSorted() const
    {
        import std.algorithm.sorting : isSorted;
        import std.math : cmp;
        import std.range : assumeSorted;

        assert(!_timePoints.empty);
        assert(_timePoints.isSorted!((a, b) => cmp(a.time, b.time) < 0));
        return _timePoints.assumeSorted!((a, b) => cmp(a.time, b.time) < 0);
    }

    // must be sorted!
    private auto _timePoints = [MeterInfo(0.0f, Fraction!int(4, 4))];
}

private struct ConductorTrackContext
{
    TrackProperty!float duration;     // time
}

package final class ConductorTrackBuilder
{
    public this()
    {
        _context.duration.setBaseValue(1.0f);
    }

    public float toTime(float startTime, Time time) const
    {
        return _meterMap.toTime(startTime, time);
    }

    public float getDurationFor(int noteCount, float time)
    {
        return _context.duration.getValueFor(noteCount, time);
    }

    public void resetSystem(float time, SystemKind kind)
    {
        SystemReset sr;
        sr.nominalTime = time;
        sr.kind = kind;
        _commands.put(Command(sr));
    }

    public void setTempo(float time, float tempo)
    {
        SetTempoEvent c;
        c.nominalTime = time;
        c.tempo = tempo;
        _commands.put(Command(c));
    }

    public void setMeter(float time, Fraction!int meter)
    {
        _meterMap.setMeter(time, meter);

        SetMeterEvent c;
        c.nominalTime = time;
        c.meter = meter;
        _commands.put(Command(c));
    }

    public void setKeySig(SetKeySigEvent ks)
    {
        _commands.put(Command(ks));
    }

    public void addTextEvent(TextMetaEvent te)
    {
        _commands.put(Command(te));
    }

    public ConductorTrackContext saveContext()
    {
        return _context;
    }

    public void restoreContext(ConductorTrackContext context)
    {
        _context = context;
    }

    public void setDuration(OptionalSign sign, float value)
    {
        _context.duration.modifyBaseValue(sign, value);
    }

    public void clearDurationPriorSpecs()
    {
        _context.duration.clearPriorSpecs();
    }
    
    public void addDurationPriorSpec(PriorSpec!float priorSpec)
    {
        _context.duration.addPriorSpec(priorSpec);
    }

    public Track build()
    {
        return new Track(".conductor", conductorChannel, _commands[]);
    }

    private MeterMap _meterMap;
    private ConductorTrackContext _context;
    private Appender!(Command[]) _commands;
}

package struct MultiTrackContext
{
    ConductorTrackContext conductor;
    TrackBuilderContext[] tracks;
}

package final class MultiTrackBuilder
{
    public this(CompositionBuilder composition, TrackBuilder[] tracks)
    {
        _composition = composition;
        _tracks = tracks;
    }

    public @property CompositionBuilder compositionBuilder()
    {
        return _composition;
    }

    public void setChannel(int ch)
    {
        foreach (t; _tracks)
        {
            t.channel = ch;
        }
    }

    public MultiTrackContext saveContext()
    {
        import std.algorithm.iteration : map;

        return MultiTrackContext(
            _composition.conductorTrackBuilder.saveContext(),
            _tracks.map!(t => t.saveContext()).array
        );
    }

    public void restoreContext(MultiTrackContext c)
    {
        import std.range : lockstep;

        _composition.conductorTrackBuilder.restoreContext(c.conductor);

        foreach (tb, tc; lockstep(_tracks, c.tracks))
        {
            tb.restoreContext(tc);
        }
    }

    public void setProgram(ProgramChange pc)
    {
        foreach (t; _tracks)
        {
            t.setProgram(pc);
        }
    }

    public void setControlChange(ControlChange cc)
    {
        foreach (t; _tracks)
        {
            t.setControlChange(cc);
        }
    }

    public void putNote(int noteCount, float time, Note note)
    {
        foreach (t; _tracks)
        {
            t.putNote(noteCount, time, note);
        }
    }

    public bool extendPreviousNote(int noteCount, float time, float duration)
    {
        bool ret = false;

        foreach (t; _tracks)
        {
            if (t.extendPreviousNote(noteCount, time, duration))
            {
                ret = true;
            }
        }

        return ret;
    }

    public void setTrackProperty(TrackPropertyKind kind, OptionalSign sign, Algebraic!(int, float) value)
    {
        foreach (t; _tracks)
        {
            t.setTrackProperty(kind, sign, value);
        }
    }

    public void clearPriorSpecs(TrackPropertyKind kind)
    {
        foreach (t; _tracks)
        {
            t.clearPriorSpecs(kind);
        }
    }

    public void addPriorSpec(TrackPropertyKind kind, Algebraic!(PriorSpec!int, PriorSpec!float) priorSpec)
    {
        foreach (t; _tracks)
        {
            t.addPriorSpec(kind, priorSpec);
        }
    }
    
    private CompositionBuilder _composition;
    private TrackBuilder[] _tracks;
}

package final class CompositionBuilder
{
    import std.algorithm.iteration : map;

    public this(string name)
    {
        _name = name;
        _conductor = new ConductorTrackBuilder();
    }

    public @property ConductorTrackBuilder conductorTrackBuilder()
    {
        return _conductor;
    }

    public @property float currentTime()
    {
        return _currentTime;
    }

    public @property void currentTime(float t)
    {
        _currentTime = t;
    }

    public @property int currentNoteCount()
    {
        return _noteCount;
    }

    public int nextNoteCount()
    {
        return _noteCount++;
    }

    public @property TrackBuilder defaultTrack()
    {
        return _tracks.require(".default", new TrackBuilder(".default"));
    }

    public TrackBuilder track(string name)
    {
        return _tracks.require(name, new TrackBuilder(name));
    }

    public MultiTrackBuilder selectTracks(string[] names)
    {
        return new MultiTrackBuilder(this, names.map!(x => _tracks.require(x, new TrackBuilder(x))).array);
    }

    public MultiTrackBuilder selectDefaultTrack()
    {
        return new MultiTrackBuilder(this, [defaultTrack]);
    }

    public Composition build()
    {
        import std.range : chain, only;
        return new Composition(_name, chain(only(_conductor.build()), _tracks.byValue.map!(x => x.build())).array);
    }

    private string _name;
    private ConductorTrackBuilder _conductor;
    private TrackBuilder[string] _tracks;
    private float _currentTime = 0.0f;
    private int _noteCount = 0;
}

package Nullable!SetKeySigEvent makeKeySigEvent(float time, string text)
{
    SetKeySigEvent ks;
    ks.nominalTime = time;

    switch (text)
    {
    case "C":
        ks.tonic = KeyName.c;
        ks.isMinor = false;
        break;

    case "Cm":
        ks.tonic = KeyName.c;
        ks.isMinor = true;
        break;

    case "C#":
        ks.tonic = KeyName.cSharp;
        ks.isMinor = false;
        break;

    case "C#m":
        ks.tonic = KeyName.cSharp;
        ks.isMinor = true;
        break;

    case "D":
        ks.tonic = KeyName.d;
        ks.isMinor = false;
        break;

    case "Dm":
        ks.tonic = KeyName.d;
        ks.isMinor = true;
        break;

    case "D#":
        ks.tonic = KeyName.dSharp;
        ks.isMinor = false;
        break;

    case "D#m":
        ks.tonic = KeyName.dSharp;
        ks.isMinor = true;
        break;

    case "E":
        ks.tonic = KeyName.e;
        ks.isMinor = false;
        break;

    case "Em":
        ks.tonic = KeyName.e;
        ks.isMinor = true;
        break;

    case "F":
        ks.tonic = KeyName.f;
        ks.isMinor = false;
        break;

    case "Fm":
        ks.tonic = KeyName.f;
        ks.isMinor = true;
        break;

    case "F#":
        ks.tonic = KeyName.fSharp;
        ks.isMinor = false;
        break;

    case "F#m":
        ks.tonic = KeyName.fSharp;
        ks.isMinor = true;
        break;

    case "G":
        ks.tonic = KeyName.g;
        ks.isMinor = false;
        break;

    case "Gm":
        ks.tonic = KeyName.g;
        ks.isMinor = true;
        break;

    case "G#":
        ks.tonic = KeyName.gSharp;
        ks.isMinor = false;
        break;

    case "G#m":
        ks.tonic = KeyName.gSharp;
        ks.isMinor = true;
        break;

    case "A":
        ks.tonic = KeyName.a;
        ks.isMinor = false;
        break;

    case "Am":
        ks.tonic = KeyName.a;
        ks.isMinor = true;
        break;

    case "A#":
        ks.tonic = KeyName.aSharp;
        ks.isMinor = false;
        break;

    case "A#m":
        ks.tonic = KeyName.aSharp;
        ks.isMinor = true;
        break;

    case "B":
        ks.tonic = KeyName.b;
        ks.isMinor = false;
        break;

    case "Bm":
        ks.tonic = KeyName.b;
        ks.isMinor = true;
        break;

    default:
        return typeof(return).init;
    }

    return typeof(return)(ks);
}
