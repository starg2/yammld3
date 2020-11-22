
module yammld3.common;

import std.stdint;

public enum int ticksPerQuarterNote = 960;
public enum int maxChannelCount = 64;
//public enum int maxDrumChannelCount = maxChannelCount / 16;
//public enum int maxMelodicChannelCount = maxChannelCount - 1 - maxDrumChannelCount;

public class FatalErrorException : Exception
{
    public this(string msg, string file = __FILE__, size_t line = __LINE__) @nogc @safe pure nothrow
    {
        super(msg, file, line);
    }
}

public enum KeyName : byte
{
    c = 0,
    cSharp = 1,
    d = 2,
    dSharp = 3,
    e = 4,
    f = 5,
    fSharp = 6,
    g = 7,
    gSharp = 8,
    a = 9,
    aSharp = 10,
    b = 11
}

public struct KeySig
{
    int countSharp()
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

    KeyName tonic;
    bool isMinor;
}

public struct Time
{
    int measures;
    int beats;
    int ticks;
}

public struct Fraction(T)
{
    T numerator;
    T denominator;
}

public enum OptionalSign
{
    none,
    plus,
    minus
}

public struct AbsoluteOrRelative(T)
{
    T value;
    bool relative;
}

private struct SplitMix64
{
    this(uint64_t seed)
    {
        _s = seed;
    }

    enum bool empty = false;

    @property uint64_t front() const
    {
        uint64_t result = _s;
        result = (result ^ (result >> 30)) * 0xBF58476D1CE4E5B9;
        result = (result ^ (result >> 27)) * 0x94D049BB133111EB;
        return result ^ (result >> 31);
    }

    void popFront()
    {
        _s += 0x9E3779B97f4A7C15;
    }

    private uint64_t _s;
}

package struct XorShift128Plus
{
    enum bool empty = false;

    void seed(uint64_t n)
    {
        auto sm = SplitMix64(n);
        _s0 = sm.front;
        sm.popFront();
        _s1 = sm.front;
    }

    @property double front() const
    {
        import std.bitmanip : DoubleRep;

        DoubleRep rep;
        rep.fraction = (_s0 + _s1) >> 12;

        if (rep.fraction == 0)
        {
            rep.fraction = 1;
        }

        rep.exponent = 1023;
        rep.sign = false;

        return rep.value - 1.0;
    }

    void popFront()
    {
        uint64_t t = _s0;
        uint64_t s = _s1;
        _s0 = s;
        t ^= t << 23;
        t ^= t >> 17;
        t ^= s ^ (s >> 26);
        _s1 = t;
    }

    private uint64_t _s0 = 0x95F6E804A9B45D75;
    private uint64_t _s1 = 0x8E78B2850738A063;
}
