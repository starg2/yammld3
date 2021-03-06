// Copyright (c) 2020 Starg.
// SPDX-License-Identifier: BSD-3-Clause

module yammld3.midigen;

import std.algorithm.comparison : clamp, max;
import std.conv : ConvOverflowException, to;
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
        return !isMinor ? 5 : 2;
    }
}

private ubyte[] makeGSSysex(ubyte[] data)
{
    import std.algorithm.iteration : sum;
    ubyte checksum = ((128 - data.sum(0) % 128) & 127).to!ubyte;
    return [0xF0, 0x41, 0x10, 0x42, 0x12].to!(ubyte[]) ~ data ~ checksum ~ 0xF7;
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
            tracks ~= compileTrack(composition.name, conductorTrack.front);
        }

        foreach (t; composition.tracks.filter!(a => a.channel >= 0))
        {
            tracks ~= compileTrack(composition.name, t);
        }

        return tracks[];
    }

    private MIDITrack compileTrack(string fileName, Track track)
    {
        import std.algorithm.mutation : SwapStrategy;
        import std.algorithm.sorting : sort;

        MIDITrack mt;
        mt.channel = max(track.channel, 0);

        auto events = appender(&mt.events);
        events.reserve(track.commands.length * 2);

        try
        {
            foreach (c; track.commands)
            {
                assert(c !is null);
                c.visit!(x => compileCommand(events, track.channel, x));
            }
        }
        catch (ConvOverflowException e)
        {
            _diagnosticsHandler.overflowInTrack(fileName, track.name);
        }

        mt.events.sort!((a, b) => a.time < b.time, SwapStrategy.stable);
        mt.endOfTrackTime = (mt.events.empty ? 0 : mt.events.back.time) + convertTime(track.trailingBlankTime);
        return mt;
    }

    private void compileCommand(RefAppender!(MIDIEvent[]) events, int channel, Note note)
    {
        byte velocity = (note.keyInfo.velocity * 127.0f).to!int.clamp(0, 127).to!byte;

        if (velocity > 0)
        {
            int onTime = convertTime(note.nominalTime + note.keyInfo.timeShift);
            int offTime = convertTime(
                note.nominalTime
                    + note.nominalDuration - note.lastNominalDuration
                    + note.lastNominalDuration * note.keyInfo.gateTime
            );

            if (onTime < offTime)
            {
                byte key = note.keyInfo.key.value.clamp(0, 127).to!byte;

                NoteOnEventData onev;
                onev.note = key;
                onev.velocity = velocity;

                MIDIEvent ev;
                ev.time = onTime;
                ev.data = MIDIEventData(onev);
                events ~= ev;

                NoteOffEventData offev;
                offev.note = key;

                ev.time = offTime;
                ev.data = MIDIEventData(offev);
                events ~= ev;
            }
        }
    }

    private void compileCommand(RefAppender!(MIDIEvent[]) events, int channel, ControlChange cc)
    {
        ControlChangeEventData cev;
        cev.code = cc.code;
        cev.value = cc.value.clamp(0, 127).to!byte;

        MIDIEvent ev;
        ev.time = convertTime(cc.nominalTime);
        ev.data = MIDIEventData(cev);
        events ~= ev;
    }

    private void compileCommand(RefAppender!(MIDIEvent[]) events, int channel, ProgramChange pc)
    {
        MIDIEvent ev;
        ev.time = convertTime(pc.nominalTime);

        ControlChangeEventData cev;
        cev.code = ControlChangeCode.bankSelectMSB;
        cev.value = pc.bankMSB;
        ev.data = MIDIEventData(cev);
        events ~= ev;

        cev.code = ControlChangeCode.bankSelectLSB;
        cev.value = pc.bankLSB;
        ev.data = MIDIEventData(cev);
        events ~= ev;

        ProgramChangeEventData pcev;
        pcev.program = pc.program;
        ev.data = MIDIEventData(pcev);
        events ~= ev;
    }

    private void compileCommand(RefAppender!(MIDIEvent[]) events, int channel, PitchBendEvent pb)
    {
        PitchBendEventData pbev;
        pbev.bend = (pb.bend * (pb.bend <= 0.0f ? 8192.0f : 8191.0f) + 8192.0f).clamp(0, 16383).to!short;

        MIDIEvent ev;
        ev.time = convertTime(pb.nominalTime);
        ev.data = MIDIEventData(pbev);
        events ~= ev;
    }

    private void compileCommand(RefAppender!(MIDIEvent[]) events, int channel, SetTempoEvent te)
    {
        uint usecPerQuarter = (60.0f * 1_000_000.0f / te.tempo).to!uint;

        MetaEventData mev;
        mev.kind = MetaEventKind.setTempo;
        mev.bytes = [(usecPerQuarter >> 16) & 0xFF, (usecPerQuarter >> 8) & 0xFF, usecPerQuarter & 0xFF].to!(ubyte[]);

        MIDIEvent ev;
        ev.time = convertTime(te.nominalTime);
        ev.data = MIDIEventData(mev);
        events ~= ev;
    }

    private void compileCommand(RefAppender!(MIDIEvent[]) events, int channel, SetMeterEvent me)
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
        events ~= ev;
    }

    private void compileCommand(RefAppender!(MIDIEvent[]) events, int channel, SetKeySigEvent ks)
    {
        MetaEventData mev;
        mev.kind = MetaEventKind.keySignature;
        mev.bytes = [cast(ubyte)(countSharp(ks.tonic, ks.isMinor).to!byte), ks.isMinor.to!ubyte];

        MIDIEvent ev;
        ev.time = convertTime(ks.nominalTime);
        ev.data = MIDIEventData(mev);
        events ~= ev;
    }

    private void compileCommand(RefAppender!(MIDIEvent[]) events, int channel, NRPNEvent nrpnEvent)
    {
        ControlChangeEventData cc;
        cc.code = ControlChangeCode.nonRegisteredParameterNumberMSB;
        cc.value = nrpnEvent.nrpnMSB;

        MIDIEvent ev;
        ev.time = convertTime(nrpnEvent.nominalTime);
        ev.data = MIDIEventData(cc);
        events ~= ev;

        cc.code = ControlChangeCode.nonRegisteredParameterNumberLSB;
        cc.value = nrpnEvent.nrpnLSB;
        ev.data = MIDIEventData(cc);
        events ~= ev;

        cc.code = ControlChangeCode.dataEntryMSB;
        cc.value = nrpnEvent.dataMSB;
        ev.data = MIDIEventData(cc);
        events ~= ev;

        if (nrpnEvent.dataLSB != 0)
        {
            cc.code = ControlChangeCode.dataEntryLSB;
            cc.value = nrpnEvent.dataLSB;
            ev.data = MIDIEventData(cc);
            events ~= ev;
        }
    }

    private void compileCommand(RefAppender!(MIDIEvent[]) events, int channel, RPNEvent rpnEvent)
    {
        ControlChangeEventData cc;
        cc.code = ControlChangeCode.registeredParameterNumberMSB;
        cc.value = rpnEvent.rpnMSB;

        MIDIEvent ev;
        ev.time = convertTime(rpnEvent.nominalTime);
        ev.data = MIDIEventData(cc);
        events ~= ev;

        cc.code = ControlChangeCode.registeredParameterNumberLSB;
        cc.value = rpnEvent.rpnLSB;
        ev.data = MIDIEventData(cc);
        events ~= ev;

        cc.code = ControlChangeCode.dataEntryMSB;
        cc.value = rpnEvent.dataMSB;
        ev.data = MIDIEventData(cc);
        events ~= ev;

        if (rpnEvent.dataLSB != 0)
        {
            cc.code = ControlChangeCode.dataEntryLSB;
            cc.value = rpnEvent.dataLSB;
            ev.data = MIDIEventData(cc);
            events ~= ev;
        }
    }

    private void compileCommand(RefAppender!(MIDIEvent[]) events, int channel, TextMetaEvent tm)
    {
        MetaEventData mev;
        mev.kind = tm.metaEventKind;
        mev.bytes = cast(ubyte[])tm.text.dup;

        MIDIEvent ev;
        ev.time = convertTime(tm.nominalTime);
        ev.data = MIDIEventData(mev);
        events ~= ev;
    }

    private void compileCommand(RefAppender!(MIDIEvent[]) events, int channel, SysExEvent se)
    {
        SysExEventData sysex;
        sysex.bytes = se.bytes;

        MIDIEvent ev;
        ev.time = convertTime(se.nominalTime);
        ev.data = MIDIEventData(sysex);
        events ~= ev;
    }

    private void compileCommand(RefAppender!(MIDIEvent[]) events, int channel, SystemReset sr)
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
        events ~= ev;
    }

    private void compileCommand(RefAppender!(MIDIEvent[]) events, int channel, MTSNoteTuning mnt)
    {
        bool withBank = mnt.bank != 0 || !mnt.realtime;
        auto bytes = appender!(ubyte[]);

        bytes ~= 0xF0.to!ubyte;
        bytes ~= (mnt.realtime ? 0x7F : 0x7E).to!ubyte;
        bytes ~= mnt.deviceID;
        bytes ~= 0x08.to!ubyte;
        bytes ~= (withBank ? 0x07 : 0x02).to!ubyte;

        if (withBank)
        {
            bytes ~= mnt.bank;
        }

        bytes ~= mnt.program;

        assert(1 <= mnt.tune.length && mnt.tune.length <= 0x7F);
        bytes ~= mnt.tune.length.to!ubyte;

        foreach (i; mnt.tune)
        {
            bytes ~= i.noteName;

            int n = (i.semitones * 128 * 128).to!int.clamp(0, (1 << 21) - 1);
            bytes ~= ((n >> 14) & 0x7F).to!ubyte;
            bytes ~= ((n >> 7) & 0x7F).to!ubyte;
            bytes ~= (n & 0x7F).to!ubyte;
        }

        bytes ~= 0xF7.to!ubyte;

        SysExEventData sysex;
        sysex.bytes = bytes[];

        MIDIEvent ev;
        ev.time = convertTime(mnt.nominalTime);
        ev.data = MIDIEventData(sysex);
        events ~= ev;
    }

    private void compileCommand(RefAppender!(MIDIEvent[]) events, int channel, MTSOctaveTuning mot)
    {
        auto bytes = appender!(ubyte[]);
        bytes.reserve(mot.dataSize > 1 ? 33 : 21);

        bytes ~= 0xF0.to!ubyte;
        bytes ~= (mot.realtime ? 0x7F : 0x7E).to!ubyte;
        bytes ~= mot.deviceID;
        bytes ~= 0x08.to!ubyte;
        bytes ~= (mot.dataSize > 1 ? 0x09 : 0x08).to!ubyte;

        bytes ~= ((mot.channelMask >> 14) & 3).to!ubyte;
        bytes ~= ((mot.channelMask >> 7) & 0x7F).to!ubyte;
        bytes ~= (mot.channelMask & 0x7F).to!ubyte;

        foreach (i; mot.offsets[])
        {
            if (mot.dataSize > 1)
            {
                // (offset - 8192) * 100 / 8192 [cent]
                int n = (i * 8192.0f / 100.0f + 8192.0f).to!int.clamp(0, 16383);
                bytes ~= ((n >> 7) & 0x7F).to!ubyte;
                bytes ~= (n & 0x7F).to!ubyte;
            }
            else
            {
                // offset - 64 [cent]
                bytes ~= (i + 64.0f).to!int.clamp(0, 127).to!ubyte;
            }
        }

        bytes ~= 0xF7.to!ubyte;

        SysExEventData sysex;
        sysex.bytes = bytes[];

        MIDIEvent ev;
        ev.time = convertTime(mot.nominalTime);
        ev.data = MIDIEventData(sysex);
        events ~= ev;
    }

    private void compileCommand(RefAppender!(MIDIEvent[]) events, int channel, GSInsertionEffectOn ie)
    {
        SysExEventData sysex;
        sysex.bytes = makeGSSysex(
            [0x40, channel == 9 ? 0x40 : channel < 9 ? 0x41 + channel : 0x40 + channel, 0x22, ie.on ? 0x01 : 0x00].to!(ubyte[])
        );

        MIDIEvent ev;
        ev.time = convertTime(ie.nominalTime);
        ev.data = MIDIEventData(sysex);
        events ~= ev;
    }

    private void compileCommand(RefAppender!(MIDIEvent[]) events, int channel, GSInsertionEffectSetType ie)
    {
        ushort type = cast(ushort)ie.type;

        SysExEventData sysex;
        sysex.bytes = makeGSSysex([0x40, 0x03, 0x00, type >> 8, type & 0xFF].to!(ubyte[]));

        MIDIEvent ev;
        ev.time = convertTime(ie.nominalTime);
        ev.data = MIDIEventData(sysex);
        events ~= ev;
    }

    private void compileCommand(RefAppender!(MIDIEvent[]) events, int channel, GSInsertionEffectSetParam ie)
    {
        assert(0 <= ie.index && ie.index <= 19);

        SysExEventData sysex;
        sysex.bytes = makeGSSysex([0x40, 0x03, ie.index + 0x03, ie.value].to!(ubyte[]));

        MIDIEvent ev;
        ev.time = convertTime(ie.nominalTime);
        ev.data = MIDIEventData(sysex);
        events ~= ev;
    }

    private DiagnosticsHandler _diagnosticsHandler;
}
