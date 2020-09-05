
module yammld3.midiwriter;

import std.range.primitives;
import std.stdint;

import yammld3.midievent;

private bool isTextMetaEvent(MetaEventKind kind)
{
    switch (kind)
    {
    case MetaEventKind.textEvent:
    case MetaEventKind.copyright:
    case MetaEventKind.sequenceName:
    case MetaEventKind.instrumentName:
    case MetaEventKind.lyrics:
    case MetaEventKind.marker:
    case MetaEventKind.cuePoint:
        return true;

    default:
        return false;
    }
}

private ubyte[] transcodeText(ubyte[] text)
{
    version (Windows)
    {
        import std.string : fromStringz;
        import std.windows.charset : toMBSz;
        return cast(ubyte[])(cast(char[])text).toMBSz().fromStringz().dup;
    }
    else
    {
        return text;
    }
}

public final class MIDIWriter(Writer)
{
    import std.array : Appender;
    import std.bitmanip : nativeToBigEndian;
    import std.conv : to;

    import yammld3.common : ticksPerQuarterNote;
    import yammld3.diagnostics : DiagnosticsHandler;

    public this(DiagnosticsHandler diagnosticsHandler, Writer output)
    {
        _diagnosticsHandler = diagnosticsHandler;
        _output = output;
    }

    public void writeMIDI(string filePath, MIDITrack[] tracks)
    {
        _filePath = filePath;

        put(_output, "MThd");
        put(_output, 6.nativeToBigEndian!uint32_t[]);   // data length
        put(_output, 1.nativeToBigEndian!uint16_t[]);   // format

        if (tracks.length >= 1 << 16)
        {
            _diagnosticsHandler.tooManyTracks(filePath);
            assert(false);
        }

        put(_output, tracks.length.to!uint16_t.nativeToBigEndian!uint16_t[]);   // number of tracks
        put(_output, ticksPerQuarterNote.nativeToBigEndian!uint16_t[]); // time unit

        foreach (t; tracks)
        {
            writeTrack(t);
        }
    }

    private void writeTrack(MIDITrack track)
    {
        import std.variant : visit;

        _lastEventTime = 0;
        put(_output, "MTrk");
        _trackBuffer.clear();

        if (track.channel >= 16)
        {
            // set port
            _trackBuffer ~= [0, 0xFF, 0x21, 1, track.channel >> 4].to!(ubyte[]);
        }

        foreach (ev; track.events)
        {
            ev.data.visit!(d => writeEvent(track.channel, ev.time, d));
        }

        // write end of track
        writeTime(track.endOfTrackTime);
        _trackBuffer ~= [0xFF, 0x2F, 0].to!(ubyte[]);

        put(_output, _trackBuffer[].length.to!uint32_t.nativeToBigEndian!uint32_t[]);
        put(_output, _trackBuffer[]);
    }

    private void writeVLV(int value)
    {
        if (value < 0 || value >= (1 << 28))
        {
            _diagnosticsHandler.vlvIsOutOfRange(_filePath);
            assert(false);
        }

        ubyte[4] buf;
        buf[3] = (value & 0x7F).to!ubyte;
        size_t i = 1;

        for (uint n = value >> 7; n > 0; n >>= 7)
        {
            buf[$ - 1 - i] = (0x80 | (n & 0x7F)).to!ubyte;
            i++;
        }

        _trackBuffer ~= buf[($ - i)..$];
    }

    private void writeTime(int time)
    {
        assert(_lastEventTime <= time);
        writeVLV(time - _lastEventTime);
        _lastEventTime = time;
    }

    private void writeEvent(int channelNumber, int time, NoteOffEventData data)
    {
        writeTime(time);
        _trackBuffer ~= [0x80 | (channelNumber & 0xF), data.note, 0].to!(ubyte[]);
    }

    private void writeEvent(int channelNumber, int time, NoteOnEventData data)
    {
        writeTime(time);
        _trackBuffer ~= [0x90 | (channelNumber & 0xF), data.note, data.velocity].to!(ubyte[]);
    }

    private void writeEvent(int channelNumber, int time, PolyphonicAfterTouchEventData data)
    {
        writeTime(time);
        _trackBuffer ~= [0xA0 | (channelNumber & 0xF), data.note, data.pressure].to!(ubyte[]);
    }

    private void writeEvent(int channelNumber, int time, ControlChangeEventData data)
    {
        writeTime(time);
        _trackBuffer ~= [0xB0 | (channelNumber & 0xF), data.code, data.value].to!(ubyte[]);
    }

    private void writeEvent(int channelNumber, int time, ProgramChangeEventData data)
    {
        writeTime(time);
        _trackBuffer ~= [0xC0 | (channelNumber & 0xF), data.program].to!(ubyte[]);
    }

    private void writeEvent(int channelNumber, int time, ChannelAfterTouchEventData data)
    {
        writeTime(time);
        _trackBuffer ~= [0xD0 | (channelNumber & 0xF), data.pressure].to!(ubyte[]);
    }

    private void writeEvent(int channelNumber, int time, PitchBendEventData data)
    {
        writeTime(time);
        _trackBuffer ~= [0xE0 | (channelNumber & 0xF), data.bend & 0x7F, (data.bend >> 7) & 0x7F].to!(ubyte[]);
    }

    private void writeEvent(int /* channelNumber */, int time, SysExEventData data)
    {
        bool isF0 = !data.bytes.empty && data.bytes.front == 0xF0 && data.bytes.back == 0xF7;

        writeTime(time);

        if (isF0)
        {
            _trackBuffer ~= 0xF0.to!ubyte;
            writeVLV(data.bytes.length.to!int - 1);
            _trackBuffer ~= data.bytes[1..$];
        }
        else
        {
            _trackBuffer ~= 0xF7.to!ubyte;
            writeVLV(data.bytes.length.to!int);
            _trackBuffer ~= data.bytes;
        }
    }

    private void writeEvent(int /* channelNumber */, int time, MetaEventData data)
    {
        writeTime(time);
        _trackBuffer ~= 0xFF.to!ubyte;
        _trackBuffer ~= data.kind.to!ubyte;

        auto bytes = isTextMetaEvent(data.kind) ? transcodeText(data.bytes) : data.bytes;
        writeVLV(bytes.length.to!int);
        _trackBuffer ~= bytes;
    }

    private DiagnosticsHandler _diagnosticsHandler;
    private Writer _output;
    private string _filePath;
    private Appender!(ubyte[]) _trackBuffer;
    private int _lastEventTime;
}
