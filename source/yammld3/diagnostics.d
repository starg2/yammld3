
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
    void duplicatedOption(SourceLocation loc, string context);
    void unexpectedArgument(SourceLocation loc, string context);
    void unspecifiedOption(SourceLocation loc, string context);
    void cannotCountNoteLikeCommand(SourceLocation loc, SourceLocation requestLoc, string requestContext);
    void unexpectedExpressionKind(SourceLocation loc, string context);
    void expectedIdentifier(SourceLocation loc, string context);
    void expectedStringLiteral(SourceLocation loc, string context);
    void expectedArgument(SourceLocation loc, string context);
    void expectedArgumentKey(SourceLocation loc, string context);
    void expectedCommandBlock(SourceLocation loc, string context);
    void expectedTrackPropertyCommand(SourceLocation loc, string context);
    void unexpectedCommandBlock(SourceLocation loc, string context);
    void unexpectedSign(SourceLocation loc, string context);
    void divideBy0(SourceLocation loc);
    void maxIsLessThanMin(SourceLocation minLoc, SourceLocation maxLoc, string context);
    void negativeStdDev(SourceLocation loc, string context);
    void timeAssertionFailed(SourceLocation loc, string context, float expectedTime, float actualTime);
    void invalidFormatSpecifier(SourceLocation loc, string context);

    void templateRedefinition(SourceLocation loc, string name, SourceLocation prevLoc);
    void parameterRedefinition(SourceLocation loc, string name, SourceLocation prevLoc);
    void undefinedTemplate(SourceLocation loc, string name);
    void undefinedTemplateParameter(SourceLocation loc, string paramName, string templateName, SourceLocation defLoc);
    void unexpectedCommandInCommand(SourceLocation loc, string parentCommand, string expectedCommand);
    void unexpectedCommandOutsideCommand(SourceLocation loc, string childCommand, string parentCommand);

    void invalidChannel(SourceLocation loc, string context, int channel);
    void valueIsOutOfRange(SourceLocation loc, string context, int minValue, int maxValue, int actualValue);
    void undefinedKeySignature(SourceLocation loc, string context);
    void undefinedGSInsertionEffectType(SourceLocation loc, string context);

    void overflowInTrack(string filePath, string trackName);

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
        writeMessage(loc, "fatal error: support for '%s' is not implemented yet", featureName);
        incrementErrorCount();
        throw new FatalErrorException("not implemented");
    }

    public override void cannotOpenFile(string path)
    {
        _output.writefln("fatal error: cannot open file '%s'", path);
        incrementErrorCount();
        throw new FatalErrorException("cannot open file");
    }

    public override void unexpectedCharacter(SourceLocation loc, string context, dchar c)
    {
        writeMessage(loc, "error: '%s': unexpected character '%c'", context, c);
        incrementErrorCount();
    }

    public override void unterminatedBlockComment(SourceLocation loc)
    {
        writeMessage(loc, "error: unterminated block comment");
        incrementErrorCount();
    }

    public override void expectedAfter(SourceLocation loc, string context, string expected, string after)
    {
        writeMessage(loc, "error: '%s': expected '%s' after '%s'", context, expected, after);
        incrementErrorCount();
    }

    public override void noCloseCharacters(SourceLocation loc, SourceLocation openLoc, string openCharacters, string closeCharacters)
    {
        writeMessage(loc, "error: expected '%s'", closeCharacters);
        incrementErrorCount();

        writeMessage(openLoc, "note: no '%s' found matching '%s'", closeCharacters, openCharacters);
        incrementErrorCount();
    }

    public override void overflow(SourceLocation loc, string context)
    {
        writeMessage(loc, "error: '%s': overflow error has occurred", context);
        incrementErrorCount();
    }

    public override void unterminatedStringLiteral(SourceLocation loc)
    {
        writeMessage(loc, "error: unterminated string literal");
        incrementErrorCount();
    }

    public override void undefinedBasicCommand(SourceLocation loc, string name)
    {
        writeMessage(loc, "error: undefined command '%s'", name);
        incrementErrorCount();
    }

    public override void undefinedExtensionCommand(SourceLocation loc, string name)
    {
        writeMessage(loc, "error: undefined extension command '%%%s'", name);
        incrementErrorCount();
    }

    public override void undefinedModifierCommand(SourceLocation loc, string name)
    {
        writeMessage(loc, "error: undefined modifier command '!%s'", name);
        incrementErrorCount();
    }

    public override void negativeRepeatCount(SourceLocation loc)
    {
        writeMessage(loc, "error: repeat count may not be negative");
        incrementErrorCount();
    }

    public override void expectedArgumentList(SourceLocation loc, string context)
    {
        writeMessage(loc, "error: '%s': expected argument list", context);
        incrementErrorCount();
    }

    public override void wrongNumberOfArguments(SourceLocation loc, string context, size_t expectedCount, size_t actualCount)
    {
        writeMessage(loc, "error: '%s': wrong number of arguments; expected %d, got %d", context, expectedCount, actualCount);
        incrementErrorCount();
    }

    public override void wrongNumberOfArguments(SourceLocation loc, string context, size_t minCount, size_t maxCount, size_t actualCount)
    {
        writeMessage(
            loc, "error: '%s': wrong number of arguments; expected %d-%d, got %d", context, minCount, maxCount, actualCount
        );
        incrementErrorCount();
    }

    public override void duplicatedOption(SourceLocation loc, string context)
    {
        writeMessage(loc, "error: '%s': duplicated option", context);
        incrementErrorCount();
    }

    public override void unexpectedArgument(SourceLocation loc, string context)
    {
        writeMessage(loc, "error: '%s': unexpected argument", context);
        incrementErrorCount();
    }

    public override void unspecifiedOption(SourceLocation loc, string context)
    {
        writeMessage(loc, "error: '%s': not all options were specified", context);
        incrementErrorCount();
    }

    public override void cannotCountNoteLikeCommand(SourceLocation loc, SourceLocation requestLoc, string requestContext)
    {
        writeMessage(loc, "error: cannot count note-like commands");
        writeMessage(requestLoc, "note: note counting requested by '%s'", requestContext);
        incrementErrorCount();
    }

    public override void unexpectedExpressionKind(SourceLocation loc, string context)
    {
        writeMessage(loc, "error: '%s': unexpected kind of expression", context);
        incrementErrorCount();
    }

    public override void expectedIdentifier(SourceLocation loc, string context)
    {
        writeMessage(loc, "error: '%s': expected identifier", context);
        incrementErrorCount();
    }

    public override void expectedStringLiteral(SourceLocation loc, string context)
    {
        writeMessage(loc, "error: '%s': expected string literal", context);
        incrementErrorCount();
    }

    public override void expectedArgument(SourceLocation loc, string context)
    {
        writeMessage(loc, "error: '%s': expected argument", context);
        incrementErrorCount();
    }

    public override void expectedArgumentKey(SourceLocation loc, string context)
    {
        writeMessage(loc, "error: '%s': expected argument key", context);
        incrementErrorCount();
    }

    public override void expectedCommandBlock(SourceLocation loc, string context)
    {
        writeMessage(loc, "error: '%s': expected command block", context);
        incrementErrorCount();
    }

    public override void expectedTrackPropertyCommand(SourceLocation loc, string context)
    {
        writeMessage(loc, "error: '%s': expected track property command", context);
        incrementErrorCount();
    }

    public override void unexpectedCommandBlock(SourceLocation loc, string context)
    {
        writeMessage(loc, "error: '%s': unexpected command block", context);
        incrementErrorCount();
    }

    public override void unexpectedSign(SourceLocation loc, string context)
    {
        writeMessage(loc, "error: '%s': unexpected sign", context);
        incrementErrorCount();
    }

    public override void divideBy0(SourceLocation loc)
    {
        writeMessage(loc, "error: attempt to divide expression by 0");
        incrementErrorCount();
    }

    public override void maxIsLessThanMin(SourceLocation minLoc, SourceLocation maxLoc, string context)
    {
        writeMessage(maxLoc, "error: maximun value must be larger than or equal to minimum value");
        writeMessage(minLoc, "note: minimum value was defined here");
        incrementErrorCount();
    }

    public override void negativeStdDev(SourceLocation loc, string context)
    {
        writeMessage(loc, "error: '%s': standard deviation cannot be negative", context);
        incrementErrorCount();
    }

    public override void timeAssertionFailed(SourceLocation loc, string context, float expectedTime, float actualTime)
    {
        writeMessage(
            loc, "error: '%s': time assertion failed; current time '%.4f' is different from expectation '%.4f'", context, actualTime, expectedTime
        );
        incrementErrorCount();
    }

    public override void invalidFormatSpecifier(SourceLocation loc, string context)
    {
        writeMessage(loc, "error: '%s': invalid format specifier", context);
        incrementErrorCount();
    }

    public override void templateRedefinition(SourceLocation loc, string name, SourceLocation prevLoc)
    {
        writeMessage(loc, "error: '%s': template redefinition", name);
        writeMessage(prevLoc, "note: see previous definition of template '%s'", name);
        incrementErrorCount();
    }

    public override void parameterRedefinition(SourceLocation loc, string name, SourceLocation prevLoc)
    {
        writeMessage(loc, "error: '%s': parameter redefinition", name);
        writeMessage(prevLoc, "note: see previous definition of '%s'", name);
        incrementErrorCount();
    }

    public override void undefinedTemplate(SourceLocation loc, string name)
    {
        writeMessage(loc, "error: '%s': undefined template", name);
        incrementErrorCount();
    }

    public override void undefinedTemplateParameter(SourceLocation loc, string paramName, string templateName, SourceLocation defLoc)
    {
        writeMessage(loc, "error: template '%s' does not accept template parameter '%s'", templateName, paramName);
        writeMessage(defLoc, "note: see definition of template '%s'", templateName);
        incrementErrorCount();
    }

    public override void unexpectedCommandInCommand(SourceLocation loc, string parentCommand, string expectedCommand)
    {
        writeMessage(loc, "error: this command is not expected inside '%s'; expected '%s'", parentCommand, expectedCommand);
        incrementErrorCount();
    }

    public override void unexpectedCommandOutsideCommand(SourceLocation loc, string childCommand, string parentCommand)
    {
        writeMessage(loc, "error: command '%s' is not expected outside '%s'", childCommand, parentCommand);
        incrementErrorCount();
    }

    public override void invalidChannel(SourceLocation loc, string context, int channel)
    {
        writeMessage(loc, "error: '%s': channel number '%d' is out of range", context, channel);
        incrementErrorCount();
    }

    public override void valueIsOutOfRange(SourceLocation loc, string context, int minValue, int maxValue, int actualValue)
    {
        writeMessage(
            loc, "error: '%s': value '%d' is out of range; it must be between '%d' and '%d'", context, actualValue, minValue, maxValue
        );
        incrementErrorCount();
    }

    public override void undefinedKeySignature(SourceLocation loc, string context)
    {
        writeMessage(loc, "error: '%s': undefined key signature", context);
        incrementErrorCount();
    }

    public override void undefinedGSInsertionEffectType(SourceLocation loc, string context)
    {
        writeMessage(loc, "error: '%s': undefined GS insertion effect type", context);
        incrementErrorCount();
    }

    public override void overflowInTrack(string filePath, string trackName)
    {
        _output.writefln("%s: fatal error: overflow error occurred while compiling track '%s'", filePath, trackName);
        incrementErrorCount();
        throw new FatalErrorException("overflow");
    }

    public override void tooManyTracks(string filePath)
    {
        _output.writefln("%s: fatal error: more than %d tracks defined", filePath, (1 << 16) - 1);
        incrementErrorCount();
        throw new FatalErrorException("too many tracks defined");
    }

    public override void vlvIsOutOfRange(string filePath)
    {
        _output.writefln("%s: fatal error: variable length value is out of range", filePath);
        incrementErrorCount();
        throw new FatalErrorException("variable length value out of range");
    }

    private void writeMessage(T...)(SourceLocation loc, string msg, T args)
    {
        import std.algorithm.comparison : min;
        import std.algorithm.mutation : copy;
        import std.range : repeat;
        import std.utf : count;

        string lineStr = loc.getLine();
        size_t startColumn = lineStr[0..loc.column].count();
        _output.writef("%s(%d,%d): ", loc.source.path, loc.line, startColumn + 1);
        _output.writefln(msg, args);

        if (_printAnnotatedLine)
        {
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
