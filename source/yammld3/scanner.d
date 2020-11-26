
module yammld3.scanner;

import std.range.primitives;

package struct Scanner
{
    import yammld3.source : SourceOffset;

    public this(string input, SourceOffset sourceOffset)
    {
        _input = input;
        _sourceOffset = sourceOffset;
    }

    public @property string view() const nothrow
    {
        return _input;
    }

    public @property bool empty() const nothrow
    {
        return _input.empty;
    }

    public @property dchar front() const
    {
        assert(!empty);
        return _input.front;
    }

    public void popFront()
    {
        import std.utf : stride;
        size_t n = stride(_input);

        if (front == '\n')
        {
            _sourceOffset.line++;
            _sourceOffset.column = 0;
        }
        else
        {
            _sourceOffset.column += n;
        }

        _input = _input[n..$];
    }

    public @property Scanner save()
    {
        return this;
    }

    public @property SourceOffset sourceOffset()
    {
        return _sourceOffset;
    }

    public bool scanString(string str)
    {
        import std.algorithm.searching : startsWith;

        if (_input.startsWith(str))
        {
            this.popFrontN(str.length);
            return true;
        }
        else
        {
            return false;
        }
    }

    private string _input;
    private SourceOffset _sourceOffset;
}

package bool scanCharIf(alias f)(ref Scanner s)
{
    if (!s.empty && f(s.front))
    {
        s.popFront();
        return true;
    }
    else
    {
        return false;
    }
}

package bool scanAnyChar(ref Scanner s)
{
    return s.scanCharIf!(x => true);
}

package bool scanAnyChar(ref Scanner s, ref dchar c)
{
    return s.scanCharIf!((x){ c = x; return true; });
}

package bool scanChar(ref Scanner s, dchar c)
{
    return s.scanCharIf!(x => x == c);
}

package bool scanCharSet(ref Scanner s, string charSet)
{
    import std.algorithm.searching : canFind;
    return s.scanCharIf!(x => charSet.canFind(x));
}

package bool scanCharRange(ref Scanner s, dchar from, dchar to)
{
    return s.scanCharIf!(x => from <= x && x <= to);
}

package bool scanWhiteSpace(ref Scanner s)
{
    return s.scanCharSet(" \t\r\n");
}

private bool isNameStartChar(dchar c)
{
    // from XML Standard
    return ('A' <= c && c <= 'Z')
        || (c == '_')
        || ('a' <= c && c <= 'z')
        || (0xC0 <= c && c <= 0xD6)
        || (0xD8 <= c && c <= 0xF6)
        || (0xF8 <= c && c <= 0x2FF)
        || (0x370 <= c && c <= 0x37D)
        || (0x37F <= c && c <= 0x1FFF)
        || (0x200C <= c && c <= 0x200D)
        || (0x2070 <= c && c <= 0x218F)
        || (0x2C00 <= c && c <= 0x2FEF)
        || (0x3001 <= c && c <= 0xD7FF)
        || (0xF900 <= c && c <= 0xFDCF)
        || (0xFDF0 <= c && c <= 0xFFFD)
        || (0x10000 <= c && c <= 0xEFFFF);
}

private bool isNameChar(dchar c)
{
    return isNameStartChar(c)
        //|| (c == '-')
        //|| (c == '.')
        || ('0' <= c && c <= '9')
        || (c == 0xB7)
        || (0x0300 <= c && c <= 0x036F)
        || (0x203F <= c && c <= 0x2040);
}

package bool scanNameStartChar(ref Scanner s)
{
    return s.scanCharIf!isNameStartChar;
}

package bool scanNameChar(ref Scanner s)
{
    return s.scanCharIf!isNameChar;
}
