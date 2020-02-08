
module yammld3.irgenutil;

import std.array;
import std.conv : to;
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
        _context.gateTime.setBaseValue(0.8f);
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
        _commands.put(pc);
    }

    public void setControlChange(ControlChange cc)
    {
        flush();
        _commands.put(cc);
    }

    public void putNote(int noteCount, float time, Note note)
    {
        flush();

        if (!note.isRest)
        {
            auto noteInfo = note.noteInfo;

            noteInfo.key += _context.octave.getValueFor(noteCount, time) * 12;
            noteInfo.key += _context.keyShift.getValueFor(noteCount, time);
            noteInfo.velocity += _context.velocity.getValueFor(noteCount, time);
            noteInfo.timeShift += _context.timeShift.getValueFor(noteCount, time);
            noteInfo.gateTime += _context.gateTime.getValueFor(noteCount, time);

            note.noteInfo = noteInfo;
        }

        _queuedNote = note;
    }

    public bool extendPreviousNote(int noteCount, float time, float duration)
    {
        if (_queuedNote is null)
        {
            return false;
        }

        if (!_queuedNote.isRest)
        {
            auto noteInfo = _queuedNote.noteInfo;

            noteInfo.lastNominalDuration = duration;
            noteInfo.gateTime = _context.gateTime.getValueFor(noteCount, time);

            _queuedNote.noteInfo = noteInfo;
        }

        _queuedNote.nominalDuration = _queuedNote.nominalDuration + duration;
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
        if (_queuedNote !is null)
        {
            _commands.put(_queuedNote);
            _queuedNote = null;
        }
    }

    private string _name;
    private int _channel;
    private TrackBuilderContext _context;
    private Appender!(Command[]) _commands;
    private Note _queuedNote;
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
        _commands.put(new SystemReset(time, kind));
    }

    public void setTempo(float time, float tempo)
    {
        _commands.put(new SetTempoEvent(time, tempo));
    }

    public void setMeter(float time, Fraction!int meter)
    {
        _meterMap.setMeter(time, meter);
        _commands.put(new SetMeterEvent(time, meter));
    }

    public void setKeySig(SetKeySigEvent ks)
    {
        assert(ks !is null);
        _commands.put(ks);
    }

    public void addTextEvent(TextMetaEvent te)
    {
        assert(te !is null);
        _commands.put(te);
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

package SetKeySigEvent makeKeySigEvent(float time, string text)
{
    switch (text)
    {
    case "C":
        return new SetKeySigEvent(time, KeyName.c, false);

    case "Cm":
        return new SetKeySigEvent(time, KeyName.c, true);

    case "C#":
        return new SetKeySigEvent(time, KeyName.cSharp, false);

    case "C#m":
        return new SetKeySigEvent(time, KeyName.cSharp, true);

    case "D":
        return new SetKeySigEvent(time, KeyName.d, false);

    case "Dm":
        return new SetKeySigEvent(time, KeyName.d, true);

    case "D#":
        return new SetKeySigEvent(time, KeyName.dSharp, false);

    case "D#m":
        return new SetKeySigEvent(time, KeyName.dSharp, true);

    case "E":
        return new SetKeySigEvent(time, KeyName.e, false);

    case "Em":
        return new SetKeySigEvent(time, KeyName.e, true);

    case "F":
        return new SetKeySigEvent(time, KeyName.f, false);

    case "Fm":
        return new SetKeySigEvent(time, KeyName.f, true);

    case "F#":
        return new SetKeySigEvent(time, KeyName.fSharp, false);

    case "F#m":
        return new SetKeySigEvent(time, KeyName.fSharp, true);

    case "G":
        return new SetKeySigEvent(time, KeyName.g, false);

    case "Gm":
        return new SetKeySigEvent(time, KeyName.g, true);

    case "G#":
        return new SetKeySigEvent(time, KeyName.gSharp, false);

    case "G#m":
        return new SetKeySigEvent(time, KeyName.gSharp, true);

    case "A":
        return new SetKeySigEvent(time, KeyName.a, false);

    case "Am":
        return new SetKeySigEvent(time, KeyName.a, true);

    case "A#":
        return new SetKeySigEvent(time, KeyName.aSharp, false);

    case "A#m":
        return new SetKeySigEvent(time, KeyName.aSharp, true);

    case "B":
        return new SetKeySigEvent(time, KeyName.b, false);

    case "Bm":
        return new SetKeySigEvent(time, KeyName.b, true);

    default:
        return null;
    }
}
