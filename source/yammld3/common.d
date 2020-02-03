
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
