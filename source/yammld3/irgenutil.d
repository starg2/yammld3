// Copyright (c) 2020 Starg.
// SPDX-License-Identifier: BSD-3-Clause

module yammld3.irgenutil;

import std.algorithm.iteration;
import std.array;
import std.conv;
import std.typecons : Nullable;
import std.variant;

import yammld3.common;
import yammld3.ir;
import yammld3.priorspec;


package bool isTimeApproximatelyEqual(float a, float b)
{
    import std.math : abs;
    return abs(a - b) < 1.0f / ticksPerQuarterNote / 2.0f;
}

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
    case TrackPropertyKind.timeShift:
        assert(false);

    case TrackPropertyKind.velocity:
        return n / 127.0f;

    case TrackPropertyKind.gateTime:
        return n / 100.0f;
    }
}

private struct TrackProperty(T)
{
    public void setBaseValue(T n)
    {
        _baseValue = n;
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
        import std.algorithm.searching : canFind;

        if (_priorSpecs.canFind!(x => x.expired(noteCount, time)))
        {
            _priorSpecs = _priorSpecs.filter!(x => !x.expired(noteCount, time)).array;
        }

        auto value = _baseValue;

        foreach (ps; _priorSpecs)
        {
            ps.apply(value, noteCount, time);
        }

        return value;
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

package struct NoteSetInfo
{
    float nominalTime;
    KeyInfo[] keys;
    float nominalDuration;
    float lastNominalDuration;
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

    public @property float trailingBlankTime()
    {
        return _trailingBlankTime;
    }

    public @property void trailingBlankTime(float t)
    {
        _trailingBlankTime = trailingBlankTime;
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
        return new Track(_name, _channel, _commands[], _trailingBlankTime);
    }

    public void putCommand(Command c)
    {
        flush();
        _commands ~= c;
    }

    public void putNote(int noteCount, NoteSetInfo noteSetInfo)
    {
        flush();

        int keyDelta = _context.octave.getValueFor(noteCount, noteSetInfo.nominalTime) * 12
            + _context.keyShift.getValueFor(noteCount, noteSetInfo.nominalTime);
        float velocity = _context.velocity.getValueFor(noteCount, noteSetInfo.nominalTime);
        float timeShift = _context.timeShift.getValueFor(noteCount, noteSetInfo.nominalTime);
        float gateTime = _context.gateTime.getValueFor(noteCount, noteSetInfo.nominalTime);

        noteSetInfo.keys = noteSetInfo.keys.map!((k){
            if (k.key.relative)
            {
                k.key.value += keyDelta;
            }

            k.velocity = velocity;
            k.timeShift = timeShift;
            k.gateTime = gateTime;

            return k;
        }).array;

        _queuedNote = noteSetInfo;
    }

    public bool extendPreviousNote(int noteCount, float time, float duration)
    {
        if (_queuedNote.isNull)
        {
            return false;
        }

        _queuedNote.get.nominalDuration += duration;
        _queuedNote.get.lastNominalDuration = duration;

        float gateTime = _context.gateTime.getValueFor(noteCount, time);

        foreach (ref k; _queuedNote.get.keys)
        {
            k.gateTime = gateTime;
        }

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
            foreach (k; _queuedNote.get.keys)
            {
                auto n = new Note(
                    _queuedNote.get.nominalTime,
                    _queuedNote.get.nominalDuration,
                    _queuedNote.get.lastNominalDuration,
                    k
                );

                _commands ~= n;
            }

            _queuedNote.nullify();
        }
    }

    private string _name;
    private int _channel = 0;
    private TrackBuilderContext _context;
    private Appender!(Command[]) _commands;
    private Nullable!NoteSetInfo _queuedNote;
    private float _trailingBlankTime = 4.0f;
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
                curTime = min(curTime + actualMeasures * tp[0].measureLength, tp[1].time);
            }

            if (curTime < tp[1].time && remainingTime.beats > 0)
            {
                int availableBeats = divUp(tp[1].time - curTime, tp[0].beatLength);
                int actualBeats = min(remainingTime.beats, availableBeats);
                remainingTime.beats -= actualBeats;
                curTime = min(curTime + actualBeats * tp[0].beatLength, tp[1].time);
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

    public Time toMeasures(float time) const
    {
        import std.algorithm.comparison : min;
        import std.math : floor;
        import std.range : slide;
        import std.typecons : No;

        auto r = getSorted();
        assert(!r.empty);

        Time ret;

        foreach (tp; r.slide!(No.withPartial)(2))
        {
            if (time <= tp[0].time)
            {
                return ret;
            }

            if (ret.beats > 0 || ret.ticks > 0)
            {
                ret.measures++;
                ret.beats = 0;
                ret.ticks = 0;
            }

            float dt = min(time, tp[1].time) - tp[0].time;
            int measures = floor(dt / tp[0].measureLength).to!int;
            dt -= tp[0].measureLength * measures;
            int beats = floor(dt / tp[0].beatLength).to!int;
            dt -= tp[0].beatLength * beats;
            ret.measures += measures;
            ret.beats += beats;
            ret.ticks += (dt * ticksPerQuarterNote).to!int;
        }

        if (ret.beats > 0 || ret.ticks > 0)
        {
            ret.measures++;
            ret.beats = 0;
            ret.ticks = 0;
        }

        float dt = time - r.back.time;
        int measures = floor(dt / r.back.measureLength).to!int;
        dt -= r.back.measureLength * measures;
        int beats = floor(dt / r.back.beatLength).to!int;
        dt -= r.back.beatLength * beats;
        ret.measures += measures;
        ret.beats += beats;
        ret.ticks += (dt * ticksPerQuarterNote).to!int;
        return ret;
    }

    public void setMeter(float time, Fraction!int meter)
    {
        auto r = getSorted();
        auto ts = r.trisect(MeterInfo(time));

        if (ts[1].empty)
        {
            size_t pos = r.length - ts[2].length;
            _timePoints.insertInPlace(pos, MeterInfo(time, meter));
        }
        else
        {
            assert(ts[1].length == 1);
            size_t pos = ts[0].length;
            _timePoints[pos].meter = meter;
        }
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

    public Time toMeasures(float time) const
    {
        return _meterMap.toMeasures(time);
    }

    public float getDurationFor(int noteCount, float time)
    {
        return _context.duration.getValueFor(noteCount, time);
    }

    public void resetSystem(float time, SystemKind kind)
    {
        _commands ~= new SystemReset(time, kind);
    }

    public void setTempo(float time, float tempo)
    {
        _commands ~= new SetTempoEvent(time, tempo);
    }

    public void setMeter(float time, Fraction!int meter)
    {
        _meterMap.setMeter(time, meter);
        _commands ~= new SetMeterEvent(time, meter);
    }

    public void setKeySig(SetKeySigEvent ks)
    {
        assert(ks !is null);
        _commands ~= ks;
    }

    public void addTextEvent(TextMetaEvent te)
    {
        assert(te !is null);
        _commands ~= te;
    }

    public void addCommand(Command c)
    {
        assert(c !is null);
        _commands ~= c;
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
        return new Track(".conductor", conductorChannel, _commands[], 0.0f);
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

    public void setTrailingBlankTime(float time)
    {
        foreach (t; _tracks)
        {
            t.trailingBlankTime = time;
        }
    }

    public MultiTrackContext saveContext()
    {
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

    public void putCommand(Command c)
    {
        foreach (t; _tracks)
        {
            t.putCommand(c);
        }
    }

    public void putNote(int noteCount, NoteSetInfo noteSetInfo)
    {
        foreach (t; _tracks)
        {
            t.putNote(noteCount, noteSetInfo);
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
        return track(".default");
    }

    public TrackBuilder track(string name)
    {
        return _tracks.require(name, new TrackBuilder(name));
    }

    public MultiTrackBuilder selectTracks(string[] names)
    {
        return new MultiTrackBuilder(this, names.map!(x => track(x)).array);
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

package Nullable!KeySig parseKeySig(string text)
{
    switch (text)
    {
    case "C":
        return typeof(return)(KeySig(KeyName.c, false));

    case "Cm":
        return typeof(return)(KeySig(KeyName.c, true));

    case "C#":
        return typeof(return)(KeySig(KeyName.cSharp, false));

    case "C#m":
        return typeof(return)(KeySig(KeyName.cSharp, true));

    case "D":
        return typeof(return)(KeySig(KeyName.d, false));

    case "Dm":
        return typeof(return)(KeySig(KeyName.d, true));

    case "D#":
        return typeof(return)(KeySig(KeyName.dSharp, false));

    case "D#m":
        return typeof(return)(KeySig(KeyName.dSharp, true));

    case "E":
        return typeof(return)(KeySig(KeyName.e, false));

    case "Em":
        return typeof(return)(KeySig(KeyName.e, true));

    case "F":
        return typeof(return)(KeySig(KeyName.f, false));

    case "Fm":
        return typeof(return)(KeySig(KeyName.f, true));

    case "F#":
        return typeof(return)(KeySig(KeyName.fSharp, false));

    case "F#m":
        return typeof(return)(KeySig(KeyName.fSharp, true));

    case "G":
        return typeof(return)(KeySig(KeyName.g, false));

    case "Gm":
        return typeof(return)(KeySig(KeyName.g, true));

    case "G#":
        return typeof(return)(KeySig(KeyName.gSharp, false));

    case "G#m":
        return typeof(return)(KeySig(KeyName.gSharp, true));

    case "A":
        return typeof(return)(KeySig(KeyName.a, false));

    case "Am":
        return typeof(return)(KeySig(KeyName.a, true));

    case "A#":
        return typeof(return)(KeySig(KeyName.aSharp, false));

    case "A#m":
        return typeof(return)(KeySig(KeyName.aSharp, true));

    case "B":
        return typeof(return)(KeySig(KeyName.b, false));

    case "Bm":
        return typeof(return)(KeySig(KeyName.b, true));

    default:
        return typeof(return).init;
    }
}

// https://rittor-music.jp/guitar/column/guitarchord/476
package int[] makeDiatonicTriad(KeySig keySig, int root)
{
    int i = root % 12 - cast(int)keySig.tonic;

    if (i < 0)
    {
        i += 12;
    }

    int[] triad = [root, root, root];

    // 0  1  2  3  4  5  6  7  8  9  10 11
    // c  c+ d  d+ e  f  f+ g  g+ a  a+ b
    // a  a+ b  c  c+ d  d+ e  f  f+ g  g+

    if (!keySig.isMinor)
    {
        switch (i)
        {
        case 0:
        case 5:
        case 7:
            triad[1] += 4;
            triad[2] += 7;
            break;

        case 2:
        case 4:
        case 9:
            triad[1] += 3;
            triad[2] += 7;
            break;

        case 11:
            triad[1] += 3;
            triad[2] += 6;
            break;

        default:
            return null;
        }
    }
    else
    {
        switch (i)
        {
        case 3:
        case 7:
        case 8:
        case 10:
            triad[1] += 4;
            triad[2] += 7;
            break;

        case 0:
        case 5:
            triad[1] += 3;
            triad[2] += 7;
            break;

        case 2:
            triad[1] += 3;
            triad[2] += 6;
            break;

        default:
            return null;
        }
    }

    /*
    final switch (scale)
    {
    case ScaleKind.major:
        switch (i)
        {
        case 0:
        case 5:
        case 7:
            triad[1] += 4;
            triad[2] += 7;
            break;

        case 2:
        case 4:
        case 9:
            triad[1] += 3;
            triad[2] += 7;
            break;

        case 11:
            triad[1] += 3;
            triad[2] += 6;
            break;

        default:
            return null;
        }

        break;

    case ScaleKind.naturalMinor:
        switch (i)
        {
        case 3:
        case 8:
        case 10:
            triad[1] += 4;
            triad[2] += 7;
            break;

        case 0:
        case 5:
        case 7:
            triad[1] += 3;
            triad[2] += 7;
            break;

        case 2:
            triad[1] += 3;
            triad[2] += 6;
            break;

        default:
            return null;
        }

        break;

    case ScaleKind.harmonicMinor:
        switch (i)
        {
        case 7:
        case 8:
            triad[1] += 4;
            triad[2] += 7;
            break;

        case 0:
        case 5:
            triad[1] += 3;
            triad[2] += 7;
            break;

        case 3:
            triad[1] += 4;
            triad[2] += 8;
            break;

        case 2:
        case 11:
            triad[1] += 3;
            triad[2] += 6;
            break;

        default:
            return null;
        }

        break;

    case ScaleKind.melodicMinor:
        switch (i)
        {
        case 5:
        case 7:
            triad[1] += 4;
            triad[2] += 7;
            break;

        case 0:
        case 2:
            triad[1] += 3;
            triad[2] += 7;
            break;

        case 3:
            triad[1] += 4;
            triad[2] += 8;
            break;

        case 9:
        case 11:
            triad[1] += 3;
            triad[2] += 6;
            break;

        default:
            return null;
        }

        break;
    }
    */

    return triad;
}

package Nullable!GSInsertionEffectType getGSInsertionEffectTypeFromString(string str)
{
    switch (str)
    {
    case "Thru":
        return typeof(return)(GSInsertionEffectType.thru);

    case "Stereo-EQ":
        return typeof(return)(GSInsertionEffectType.stereoEQ);

    case "Spectrum":
        return typeof(return)(GSInsertionEffectType.spectrum);

    case "Enhancer":
        return typeof(return)(GSInsertionEffectType.enhancer);

    case "Humanizer":
        return typeof(return)(GSInsertionEffectType.humanizer);

    case "Overdrive":
        return typeof(return)(GSInsertionEffectType.overdrive);

    case "Distortion":
        return typeof(return)(GSInsertionEffectType.distortion);

    case "Phaser":
        return typeof(return)(GSInsertionEffectType.phaser);

    case "Auto Wah":
        return typeof(return)(GSInsertionEffectType.autoWah);

    case "Rotary":
        return typeof(return)(GSInsertionEffectType.rotary);

    case "Stereo Flanger":
        return typeof(return)(GSInsertionEffectType.stereoFlanger);

    case "Step Flanger":
        return typeof(return)(GSInsertionEffectType.stepFlanger);

    case "Tremolo":
        return typeof(return)(GSInsertionEffectType.tremolo);

    case "Auto Pan":
        return typeof(return)(GSInsertionEffectType.autoPan);

    case "Compressor":
        return typeof(return)(GSInsertionEffectType.compressor);

    case "Limiter":
        return typeof(return)(GSInsertionEffectType.limiter);

    case "Hexa Chorus":
        return typeof(return)(GSInsertionEffectType.hexaChorus);

    case "Tremolo Chorus":
        return typeof(return)(GSInsertionEffectType.tremoloChorus);

    case "Stereo Chorus":
        return typeof(return)(GSInsertionEffectType.stereoChorus);

    case "Space D":
        return typeof(return)(GSInsertionEffectType.spaceD);

    case "3D Chorus":
        return typeof(return)(GSInsertionEffectType._3dChorus);

    case "Stereo Delay":
        return typeof(return)(GSInsertionEffectType.stereoDelay);

    case "Mod Delay":
        return typeof(return)(GSInsertionEffectType.modDelay);

    case "3 Tap Delay":
        return typeof(return)(GSInsertionEffectType._3TapDelay);

    case "4 Tap Delay":
        return typeof(return)(GSInsertionEffectType._4TapDelay);

    case "Tm Ctrl Delay":
        return typeof(return)(GSInsertionEffectType.tmCtrlDelay);

    case "Reverb":
        return typeof(return)(GSInsertionEffectType.reverb);

    case "Gate Reverb":
        return typeof(return)(GSInsertionEffectType.gateReverb);

    case "3D Delay":
        return typeof(return)(GSInsertionEffectType._3dDelay);

    case "2 Pitch Shifter":
        return typeof(return)(GSInsertionEffectType._2PitchShifter);

    case "Fb P.Shifter":
        return typeof(return)(GSInsertionEffectType.fbPShifter);

    case "3D Auto":
        return typeof(return)(GSInsertionEffectType._3dAuto);

    case "3D Manual":
        return typeof(return)(GSInsertionEffectType._3dManual);

    case "Lo-Fi 1":
        return typeof(return)(GSInsertionEffectType.loFi1);

    case "Lo-Fi 2":
        return typeof(return)(GSInsertionEffectType.loFi2);

    case "OD->Chorus":
        return typeof(return)(GSInsertionEffectType.odChorus);

    case "OD->Flanger":
        return typeof(return)(GSInsertionEffectType.odFlanger);

    case "OD->Delay":
        return typeof(return)(GSInsertionEffectType.odDelay);

    case "DS->Chorus":
        return typeof(return)(GSInsertionEffectType.dsChorus);

    case "DS->Flanger":
        return typeof(return)(GSInsertionEffectType.dsFlanger);

    case "DS->Delay":
        return typeof(return)(GSInsertionEffectType.dsDelay);

    case "EH->Chorus":
        return typeof(return)(GSInsertionEffectType.ehChorus);

    case "EH->Flanger":
        return typeof(return)(GSInsertionEffectType.ehFlanger);

    case "EH->Delay":
        return typeof(return)(GSInsertionEffectType.ehDelay);

    case "Cho->Delay":
        return typeof(return)(GSInsertionEffectType.choDelay);

    case "FL->Delay":
        return typeof(return)(GSInsertionEffectType.flDelay);

    case "Cho->Flanger":
        return typeof(return)(GSInsertionEffectType.choFlanger);

    case "Rotary Multi":
        return typeof(return)(GSInsertionEffectType.rotaryMulti);

    case "GTR Multi 1":
        return typeof(return)(GSInsertionEffectType.gtrMulti1);

    case "GTR Multi 2":
        return typeof(return)(GSInsertionEffectType.gtrMulti2);

    case "GTR Multi 3":
        return typeof(return)(GSInsertionEffectType.gtrMulti3);

    case "Clean Gt Multi 1":
        return typeof(return)(GSInsertionEffectType.cleanGtMulti1);

    case "Clean Gt Multi 2":
        return typeof(return)(GSInsertionEffectType.cleanGtMulti2);

    case "Bass Multi":
        return typeof(return)(GSInsertionEffectType.bassMulti);

    case "Rhodes Multi":
        return typeof(return)(GSInsertionEffectType.rhodesMulti);

    case "Keyboard Multi":
        return typeof(return)(GSInsertionEffectType.keyboardMulti);

    case "Cho/Delay":
        return typeof(return)(GSInsertionEffectType.choPlusDelay);

    case "FL/Delay":
        return typeof(return)(GSInsertionEffectType.flPlusDelay);

    case "Cho/Flanger":
        return typeof(return)(GSInsertionEffectType.choPlusFlanger);

    case "OD1/Od2":
        return typeof(return)(GSInsertionEffectType.od1PlusOd2);

    case "OD/Rotary":
        return typeof(return)(GSInsertionEffectType.odPlusRotary);

    case "OD/Phaser":
        return typeof(return)(GSInsertionEffectType.odPlusPhaser);

    case "OD/AutoWah":
        return typeof(return)(GSInsertionEffectType.odPlusAutoWah);

    case "PH/Rotary":
        return typeof(return)(GSInsertionEffectType.phPlusRotary);

    case "PH/AutoWah":
        return typeof(return)(GSInsertionEffectType.phPlusAutoWah);

    default:
        return typeof(return).init;
    }
}
