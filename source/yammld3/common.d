
module yammld3.common;

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
