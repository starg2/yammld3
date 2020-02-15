
module yammld3.midigen;

import std.algorithm.comparison : clamp, max;
import std.conv : to;
import std.range.primitives;

import yammld3.common;
import yammld3.ir;
import yammld3.midievent;

private int convertTime(float t)
{
    return max((t * ticksPerQuarterNote).to!int, 0);
}

private int countSharp(KeyName tonic, bool isMinor)
{
    final switch (tonic)
    {
    case KeyName.c:
        return !isMinor ? 0 : -3;

    case KeyName.cSharp:
        return !isMinor ? -5 : 4;

    case KeyName.d:
        return !isMinor ? 2 : -1;

    case KeyName.dSharp:
        return !isMinor ? -3 : 6;

    case KeyName.e:
        return !isMinor ? 4 : 1;

    case KeyName.f:
        return !isMinor ? -1 : -4;

    case KeyName.fSharp:
        return !isMinor ? 6 : 3;

    case KeyName.g:
        return !isMinor ? 1 : -2;

    case KeyName.gSharp:
        return !isMinor ? -4 : 5;

    case KeyName.a:
        return !isMinor ? 3 : 0;

    case KeyName.aSharp:
        return !isMinor ? -2 : -5;

    case KeyName.b:
        return !isMinor ? 5 : -2;
    }
}

public final class MIDIGenerator
{
    import std.array : appender, RefAppender;

    import yammld3.diagnostics : DiagnosticsHandler;

    public this(DiagnosticsHandler handler)
    {
        _diagnosticsHandler = handler;
    }

    public MIDITrack[] generateMIDI(Composition composition)
    {
        import std.algorithm.iteration : filter;
        import std.algorithm.searching : find;

        assert(composition !is null);

        if (composition.tracks.length >= 1 << 16)
        {
            _diagnosticsHandler.tooManyTracks(composition.name);
            assert(false);
        }

        auto tracks = appender!(MIDITrack[]);
        tracks.reserve(composition.tracks.length);

        auto conductorTrack = composition.tracks.find!(a => a.channel == conductorChannel);

        if (!conductorTrack.empty)
        {
            tracks.put(compileTrack(conductorTrack.front));
        }

        foreach (t; composition.tracks.filter!(a => a.channel >= 0))
        {
            tracks.put(compileTrack(t));
        }

        return tracks[];
    }

    private MIDITrack compileTrack(Track track)
    {
        import std.algorithm.mutation : SwapStrategy;
        import std.algorithm.sorting : sort;

        MIDITrack mt;
        mt.channel = max(track.channel, 0);

        auto events = appender(&mt.events);

        foreach (c; track.commands)
        {
            assert(c !is null);
            c.visit!(x => compileCommand(events, x));
        }

        mt.events.sort!((a, b) => a.time < b.time, SwapStrategy.stable);
        return mt;
    }

    private void compileCommand(RefAppender!(MIDIEvent[]) events, Note note)
    {
        if (!note.isRest)
        {
            NoteEventData nev;
            nev.note = note.noteInfo.key.clamp(0, 127).to!byte;
            nev.velocity = (note.noteInfo.velocity * 127.0f).to!int.clamp(0, 127).to!byte;
            nev.duration = convertTime(
                note.noteInfo.timeShift + note.nominalDuration - note.noteInfo.lastNominalDuration
                    + note.noteInfo.lastNominalDuration * note.noteInfo.gateTime
            );

            MIDIEvent ev;
            ev.time = convertTime(note.nominalTime + note.noteInfo.timeShift);
            ev.data = MIDIEventData(nev);
            events.put(ev);
        }
    }

    private void compileCommand(RefAppender!(MIDIEvent[]) events, ControlChange cc)
    {
        ControlChangeEventData cev;
        cev.code = cc.code;
        cev.value = cc.value.clamp(0, 127).to!byte;

        MIDIEvent ev;
        ev.time = convertTime(cc.nominalTime);
        ev.data = MIDIEventData(cev);
        events.put(ev);
    }

    private void compileCommand(RefAppender!(MIDIEvent[]) events, ProgramChange pc)
    {
        MIDIEvent ev;
        ev.time = convertTime(pc.nominalTime);

        ControlChangeEventData cev;
        cev.code = ControlChangeCode.bankSelectMSB;
        cev.value = pc.bankMSB;
        ev.data = MIDIEventData(cev);
        events.put(ev);

        cev.code = ControlChangeCode.bankSelectLSB;
        cev.value = pc.bankLSB;
        ev.data = MIDIEventData(cev);
        events.put(ev);

        ProgramChangeEventData pcev;
        pcev.program = pc.program;
        ev.data = MIDIEventData(pcev);
        events.put(ev);
    }

    private void compileCommand(RefAppender!(MIDIEvent[]) events, SetTempoEvent te)
    {
        uint usecPerQuarter = (60.0f * 1_000_000.0f / te.tempo).to!uint;

        MetaEventData mev;
        mev.kind = MetaEventKind.setTempo;
        mev.bytes = [usecPerQuarter >> 16, (usecPerQuarter >> 8) & 0xFF, usecPerQuarter & 0xFF].to!(ubyte[]);

        MIDIEvent ev;
        ev.time = convertTime(te.nominalTime);
        ev.data = MIDIEventData(mev);
        events.put(ev);
    }

    private void compileCommand(RefAppender!(MIDIEvent[]) events, SetMeterEvent me)
    {
        import core.bitop : bsr;

        assert(me.meter.numerator > 0);
        assert(me.meter.denominator > 0);

        MetaEventData mev;
        mev.kind = MetaEventKind.timeSignature;
        mev.bytes = [me.meter.numerator, bsr(me.meter.denominator), 24, 8].to!(ubyte[]);

        MIDIEvent ev;
        ev.time = convertTime(me.nominalTime);
        ev.data = MIDIEventData(mev);
        events.put(ev);
    }

    private void compileCommand(RefAppender!(MIDIEvent[]) events, SetKeySigEvent ks)
    {
        MetaEventData mev;
        mev.kind = MetaEventKind.keySignature;
        mev.bytes = [cast(ubyte)(countSharp(ks.tonic, ks.isMinor).to!byte), ks.isMinor.to!ubyte];

        MIDIEvent ev;
        ev.time = convertTime(ks.nominalTime);
        ev.data = MIDIEventData(mev);
        events.put(ev);
    }

    private void compileCommand(RefAppender!(MIDIEvent[]) events, TextMetaEvent tm)
    {
        MetaEventData mev;
        mev.kind = tm.metaEventKind;
        mev.bytes = cast(ubyte[])tm.text.dup;

        MIDIEvent ev;
        ev.time = convertTime(tm.nominalTime);
        ev.data = MIDIEventData(mev);
        events.put(ev);
    }

    private void compileCommand(RefAppender!(MIDIEvent[]) events, SystemReset sr)
    {
        SysExEventData sysex;

        final switch (sr.systemKind)
        {
        case SystemKind.gm:
            sysex.bytes = [0xF0, 0x7E, 0x7F, 0x09, 0x01, 0xF7].to!(ubyte[]);
            break;

        case SystemKind.gs:
            sysex.bytes = [0xF0, 0x41, 0x10, 0x42, 0x12, 0x40, 0x00, 0x7F, 0x00, 0x41, 0xF7].to!(ubyte[]);
            break;

        case SystemKind.xg:
            sysex.bytes = [0xF0, 0x43, 0x10, 0x4C, 0x00, 0x00, 0x7E, 0x00, 0xF7].to!(ubyte[]);
            break;
        }

        MIDIEvent ev;
        ev.time = convertTime(sr.nominalTime);
        ev.data = MIDIEventData(sysex);
        events.put(ev);
    }

    private DiagnosticsHandler _diagnosticsHandler;
}
