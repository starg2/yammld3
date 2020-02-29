
module yammld3.midiwriter;

import std.range.primitives;
import std.stdint;

import yammld3.midievent;

private struct NoteOffEvent
{
    int time;
    byte note;
}

private struct PriorityQueue(T, alias comp = (a, b) => a < b)
{
    import std.algorithm.mutation : swap;

    public @property bool empty() const
    {
        return _buffer.empty;
    }

    public @property T front() const
    {
        assert(!empty);
        return _buffer.front;
    }

    public void popFront()
    {
        assert(!empty);

        swap(_buffer[0], _buffer[$ - 1]);
        _buffer.popBack();

        size_t i = 0;

        while (true)
        {
            // n => 2n + 1, 2n + 2
            size_t left = (i << 1) + 1;
            size_t right = (i << 1) + 2;

            if (right < _buffer.length)
            {
                size_t target = comp(_buffer[left], _buffer[right]) ? right : left;

                if (comp(_buffer[i], _buffer[target]))
                {
                    swap(_buffer[i], _buffer[target]);
                    i = target;
                }
                else
                {
                    break;
                }
            }
            else if (left < _buffer.length)
            {
                if (comp(_buffer[i], _buffer[left]))
                {
                    swap(_buffer[i], _buffer[left]);
                    //i = left;
                }

                break;
            }
            else
            {
                break;
            }
        }
    }

    public void insert(T value)
    {
        _buffer.assumeSafeAppend() ~= value;
        size_t i = _buffer.length - 1;

        while (i >= 1)
        {
            // (n - 1)/2 <= n
            size_t parent = (i - 1) >> 1;

            if (comp(_buffer[parent], _buffer[i]))
            {
                swap(_buffer[parent], _buffer[i]);
                i = parent;
            }
            else
            {
                break;
            }
        }
    }

    private T[] _buffer;
}

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
            writeTrack(t.channel, t.events);
        }
    }

    private void writeTrack(int channelNumber, MIDIEvent[] events)
    {
        import std.variant : visit;

        _lastEventTime = 0;
        put(_output, "MTrk");
        _trackBuffer.clear();

        if (channelNumber >= 16)
        {
            // set port
            put(_trackBuffer, [0, 0xFF, 0x21, 1, channelNumber >> 4].to!(ubyte[]));
        }

        foreach (ev; events)
        {
            while (!_noteOffEventQueue.empty && _noteOffEventQueue.front.time < ev.time)
            {
                writeNoteOffEvent(channelNumber, _noteOffEventQueue.front);
                _noteOffEventQueue.popFront();
            }

            ev.data.visit!(d => writeEvent(channelNumber, ev.time, d));
        }

        while (!_noteOffEventQueue.empty)
        {
            writeNoteOffEvent(channelNumber, _noteOffEventQueue.front);
            _noteOffEventQueue.popFront();
        }

        // write end of track
        writeTime(_lastEventTime);
        put(_trackBuffer, [0xFF, 0x2F, 0].to!(ubyte[]));

        put(_output, _trackBuffer[].length.to!uint32_t.nativeToBigEndian!uint32_t[]);
        put(_output, _trackBuffer[]);
        _trackBuffer.clear();
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

        put(_trackBuffer, buf[($ - i)..$]);
    }

    private void writeTime(int time)
    {
        assert(_lastEventTime <= time);
        writeVLV(time - _lastEventTime);
        _lastEventTime = time;
    }

    private void writeNoteOffEvent(int channelNumber, NoteOffEvent ev)
    {
        writeTime(ev.time);
        put(_trackBuffer, [0x80 | (channelNumber & 0xF), ev.note, 0].to!(ubyte[]));
    }

    private void writeEvent(int channelNumber, int time, NoteEventData data)
    {
        _noteOffEventQueue.insert(NoteOffEvent(time + data.duration, data.note));

        writeTime(time);
        put(
            _trackBuffer,
            [0x90 | (channelNumber & 0xF), data.note, data.velocity].to!(ubyte[])
        );
    }

    private void writeEvent(int channelNumber, int time, PolyphonicAfterTouchEventData data)
    {
        writeTime(time);
        put(
            _trackBuffer,
            [0xA0 | (channelNumber & 0xF), data.note, data.pressure].to!(ubyte[])
        );
    }

    private void writeEvent(int channelNumber, int time, ControlChangeEventData data)
    {
        writeTime(time);
        put(
            _trackBuffer,
            [0xB0 | (channelNumber & 0xF), data.code, data.value].to!(ubyte[])
        );
    }

    private void writeEvent(int channelNumber, int time, ProgramChangeEventData data)
    {
        writeTime(time);
        put(
            _trackBuffer,
            [0xC0 | (channelNumber & 0xF), data.program].to!(ubyte[])
        );
    }

    private void writeEvent(int channelNumber, int time, ChannelAfterTouchEventData data)
    {
        writeTime(time);
        put(
            _trackBuffer,
            [0xD0 | (channelNumber & 0xF), data.pressure].to!(ubyte[])
        );
    }

    private void writeEvent(int channelNumber, int time, PitchBendEventData data)
    {
        writeTime(time);
        put(
            _trackBuffer,
            [0xE0 | (channelNumber & 0xF), data.bend & 0x7F, (data.bend >> 7) & 0x7F].to!(ubyte[])
        );
    }

    private void writeEvent(int /* channelNumber */, int time, SysExEventData data)
    {
        bool isF0 = !data.bytes.empty && data.bytes.front == 0xF0 && data.bytes.back == 0xF7;

        writeTime(time);

        if (isF0)
        {
            put(_trackBuffer, 0xF0.to!ubyte);
            writeVLV(data.bytes.length.to!int - 1);
            put(_trackBuffer, data.bytes[1..$]);
        }
        else
        {
            put(_trackBuffer, 0xF7.to!ubyte);
            writeVLV(data.bytes.length.to!int);
            put(_trackBuffer, data.bytes);
        }
    }

    private void writeEvent(int /* channelNumber */, int time, MetaEventData data)
    {
        writeTime(time);
        put(_trackBuffer, 0xFF.to!ubyte);
        put(_trackBuffer, data.kind.to!ubyte);

        auto bytes = isTextMetaEvent(data.kind) ? transcodeText(data.bytes) : data.bytes;
        writeVLV(bytes.length.to!int);
        put(_trackBuffer, bytes);
    }

    private DiagnosticsHandler _diagnosticsHandler;
    private Writer _output;
    private string _filePath;
    private Appender!(ubyte[]) _trackBuffer;
    private int _lastEventTime;

    private PriorityQueue!(NoteOffEvent, (a, b) => a.time > b.time) _noteOffEventQueue;
}
