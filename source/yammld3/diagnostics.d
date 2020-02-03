
module yammld3.diagnostics;

import yammld3.source : SourceLocation;

public interface DiagnosticsHandler
{
    @property bool hasErrors() const;

    void notImplemented(SourceLocation loc, string featureName);

    void cannotOpenFile(string path);

    void unexpectedCharacter(SourceLocation loc, string context, dchar c);
    void unterminatedBlockComment(SourceLocation loc);
    void expectedAfter(SourceLocation loc, string context, string expected, string after);
    void noCloseCharacters(SourceLocation loc, SourceLocation openLoc, string openCharacters, string closeCharacters);
    void overflow(SourceLocation loc, string context);
    void unterminatedStringLiteral(SourceLocation loc);

    void undefinedBasicCommand(SourceLocation loc, string name);
    void undefinedExtensionCommand(SourceLocation loc, string name);
    void undefinedModifierCommand(SourceLocation loc, string name);
    void negativeRepeatCount(SourceLocation loc);
    void expectedArgumentList(SourceLocation loc, string context);
    void wrongNumberOfArguments(SourceLocation loc, string context, size_t expectedCount, size_t actualCount);
    void wrongNumberOfArguments(SourceLocation loc, string context, size_t minCount, size_t maxCount, size_t actualCount);
    void unexpectedArgumentKey(SourceLocation loc, string context);
    void cannotCountNoteLikeCommand(SourceLocation loc, SourceLocation requestLoc, string requestContext);
    void unexpectedExpressionKind(SourceLocation loc, string context);
    void expectedArgument(SourceLocation loc, string context);
    void expectedCommandBlock(SourceLocation loc, string context);
    void expectedTrackPropertyCommand(SourceLocation loc, string context);
    void unexpectedCommandBlock(SourceLocation loc, string context);
    void unexpectedSign(SourceLocation loc, string context);
    void divideBy0(SourceLocation loc);
    
    void invalidChannel(SourceLocation loc, string context, int channel);
    void valueIsOutOfRange(SourceLocation loc, string context, int minValue, int maxValue, int actualValue);
    void undefinedKeySignature(SourceLocation loc, string context);

    void tooManyTracks(string filePath);
    void vlvIsOutOfRange(string filePath);
}

public final class SimpleDiagnosticsHandler : DiagnosticsHandler
{
    import std.stdio : File;
    import yammld3.common : FatalErrorException;

    public this(File output, bool printAnnotatedLine = true)
    {
        _output = output;
        _printAnnotatedLine = printAnnotatedLine;
    }

    public override @property bool hasErrors() const
    {
        return _errorCount > 0;
    }

    public override void notImplemented(SourceLocation loc, string featureName)
    {
        writeMessage(loc, "fatal error: support for '", featureName, "' is not implemented yet");
        incrementErrorCount();
        throw new FatalErrorException("not implemented");
    }

    public override void cannotOpenFile(string path)
    {
        _output.writeln("fatal error: cannot open file '", path, "'");
        incrementErrorCount();
        throw new FatalErrorException("cannot open file");
    }

    public override void unexpectedCharacter(SourceLocation loc, string context, dchar c)
    {
        writeMessage(loc, "error: '", context, "': unexpected character '", c, "'");
        incrementErrorCount();
    }

    public override void unterminatedBlockComment(SourceLocation loc)
    {
        writeMessage(loc, "error: unterminated block comment");
        incrementErrorCount();
    }

    public override void expectedAfter(SourceLocation loc, string context, string expected, string after)
    {
        writeMessage(loc, "error: '", context, "': expected '", expected, "' after '", after, "'");
        incrementErrorCount();
    }

    public override void noCloseCharacters(SourceLocation loc, SourceLocation openLoc, string openCharacters, string closeCharacters)
    {
        writeMessage(loc, "error: expected '", closeCharacters, "'");
        incrementErrorCount();

        writeMessage(openLoc, "note: no '", closeCharacters, "' found matching '", openCharacters, "'");
        incrementErrorCount();
    }

    public override void overflow(SourceLocation loc, string context)
    {
        writeMessage(loc, "error: '", context, "': overflow error has occurred");
        incrementErrorCount();
    }

    public override void unterminatedStringLiteral(SourceLocation loc)
    {
        writeMessage(loc, "error: unterminated string literal");
        incrementErrorCount();
    }

    public override void undefinedBasicCommand(SourceLocation loc, string name)
    {
        writeMessage(loc, "error: undefined command '", name, "'");
        incrementErrorCount();
    }

    public override void undefinedExtensionCommand(SourceLocation loc, string name)
    {
        writeMessage(loc, "error: undefined extension command '%", name, "'");
        incrementErrorCount();
    }

    public override void undefinedModifierCommand(SourceLocation loc, string name)
    {
        writeMessage(loc, "error: undefined modifier command '!", name, "'");
        incrementErrorCount();
    }

    public override void negativeRepeatCount(SourceLocation loc)
    {
        writeMessage(loc, "error: repeat count may not be negative");
        incrementErrorCount();
    }
    
    public override void expectedArgumentList(SourceLocation loc, string context)
    {
        writeMessage(loc, "error: '", context, "': expected argument list");
        incrementErrorCount();
    }

    public override void wrongNumberOfArguments(SourceLocation loc, string context, size_t expectedCount, size_t actualCount)
    {
        writeMessage(loc, "error: '", context, "': wrong number of arguments; expected ", expectedCount, ", got ", actualCount);
        incrementErrorCount();
    }

    public override void wrongNumberOfArguments(SourceLocation loc, string context, size_t minCount, size_t maxCount, size_t actualCount)
    {
        writeMessage(
            loc, "error: '", context, "': wrong number of arguments; expected ", minCount, "-", maxCount, ", got ", actualCount
        );
        incrementErrorCount();
    }
    
    public override void unexpectedArgumentKey(SourceLocation loc, string context)
    {
        writeMessage(loc, "error: '", context, "': unexpected argument key");
        incrementErrorCount();
    }

    public override void cannotCountNoteLikeCommand(SourceLocation loc, SourceLocation requestLoc, string requestContext)
    {
        writeMessage(loc, "error: cannot count note-like commands");
        writeMessage(requestLoc, "note: note counting requested by '", requestContext, "'");
        incrementErrorCount();
    }

    public override void unexpectedExpressionKind(SourceLocation loc, string context)
    {
        writeMessage(loc, "error: '", context, "': unexpected kind of expression");
        incrementErrorCount();
    }

    public override void expectedArgument(SourceLocation loc, string context)
    {
        writeMessage(loc, "error: '", context, "': expected argument");
        incrementErrorCount();
    }

    public override void expectedCommandBlock(SourceLocation loc, string context)
    {
        writeMessage(loc, "error: '", context, "': expected command block");
        incrementErrorCount();
    }
    
    public override void expectedTrackPropertyCommand(SourceLocation loc, string context)
    {
        writeMessage(loc, "error: '", context, "': expected track property command");
        incrementErrorCount();
    }

    public override void unexpectedCommandBlock(SourceLocation loc, string context)
    {
        writeMessage(loc, "error: '", context, "': unexpected command block");
        incrementErrorCount();
    }

    public override void unexpectedSign(SourceLocation loc, string context)
    {
        writeMessage(loc, "error: '", context, "': unexpected sign");
        incrementErrorCount();
    }

    public override void divideBy0(SourceLocation loc)
    {
        writeMessage(loc, "error: attempt to divide expression by 0");
        incrementErrorCount();
    }

    public override void invalidChannel(SourceLocation loc, string context, int channel)
    {
        writeMessage(loc, "error: '", context, "': channel number ", channel, " is out of range");
        incrementErrorCount();
    }
    
    public override void valueIsOutOfRange(SourceLocation loc, string context, int minValue, int maxValue, int actualValue)
    {
        writeMessage(
            loc, "error: '", context, "': value ", actualValue, " is out of range; it must be between ", minValue, " and ", maxValue
        );
        incrementErrorCount();
    }

    public override void undefinedKeySignature(SourceLocation loc, string context)
    {
        writeMessage(loc, "error: '", context, "': undefined key signature");
        incrementErrorCount();
    }

    public override void tooManyTracks(string filePath)
    {
        _output.writeln(
            filePath, ": fatal error: more than ", (1 << 16) - 1, " tracks defined"
        );
        incrementErrorCount();
        throw new FatalErrorException("too many tracks defined");
    }

    public override void vlvIsOutOfRange(string filePath)
    {
        _output.writefln(
            filePath, ": fatal error: variable length value is out of range"
        );
        incrementErrorCount();
        throw new FatalErrorException("variable length value out of range");
    }

    private void writeMessage(T...)(SourceLocation loc, T args)
    {
        import std.utf : count;

        string lineStr = loc.getLine();
        size_t startColumn = lineStr[0..loc.column].count();
        _output.write(loc.source.path, "(", loc.line, ",", startColumn + 1, "): ");
        _output.writeln(args);

        if (_printAnnotatedLine)
        {
            import std.algorithm.comparison : min;
            import std.algorithm.mutation : copy;
            import std.range : repeat;

            _output.writeln(lineStr);
            ' '.repeat(startColumn).copy(_output.lockingTextWriter());
            _output.write('^');

            size_t cpCount = lineStr[loc.column..min(loc.column + loc.length, $)].count();

            if (cpCount > 1)
            {
                '~'.repeat(cpCount - 1).copy(_output.lockingTextWriter());
            }

            _output.writeln();
        }
    }

    private void incrementErrorCount()
    {
        _errorCount++;

        if (_errorCount >= 10)
        {
            _output.writeln("fatal error: too many errors detected; compilation terminated");
            _errorCount++;
            throw new FatalErrorException("too many errors");
        }
    }

    private File _output;
    private bool _printAnnotatedLine;
    private int _errorCount = 0;
}
