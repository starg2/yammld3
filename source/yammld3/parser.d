
module yammld3.parser;

import std.range.primitives;

import yammld3.ast;
import yammld3.scanner;
import yammld3.source;

/*

v10!on_note(+5, +3, +2)
v!on_time(0 = +5, :1 = +3)

(cd ef)*4
(cde)/4.
c&d&e

%time(1:0)
{
    %track(Foo, Bar)
    {
        (cd ef)*4
    }
}

*/

/*

%phrase(Foo)
{

}

%play(Foo)
%play(Bar, Bar2)
%play(Baz)

%section
{
    %track(A)
    {
        v100!on_time(0 = +0, :1 = +10)
        l4 c_d (cd)/   ef+g+b    (l8 >c__>e_>d>cb)   g+bg+_
    }

    %track(Foo, Bar)
    {
        %trackeffect(Bar) { n+3 }

        // table syntax
        %table
        {
            l8  l16                l8             l16
            v100     v110
            c_d cd   e_f+_g+_b_    >c__>e_>d>cb   g+_b_g+___
        }
    }
}

*/

/*

// Whether or not spaces are allowed in between is not expressed here.

<Module> ::= <Command>*

<Command> ::= <PostfixCommand>

<PostfixCommand> ::= <PrimaryCommand> (<ModifierCommand> | <RepeatCommand> | <TupletCommand>)*

<PrimaryCommand> ::= ('(' <Command>* ')')
    | <CommandMacroDefinitionCommand>
    | <CommandMacroInvocationCommand>
    | <NoteMacroDefinitionCommand>
    | <ExtensionCommand>
    | <NoteCommand>
    | <BasicCommand>

<ModifierCommand> ::= '!' <Identifier> <ParenthesizedExpressionList>?

<RepeatCommand> ::= '*' <CommandArgumentExpression>?

<TupletCommand> ::= '/' <CommandArgumentExpression>?


<CommandMacroDefinitionCommand> ::= <CommandMacroName> '=' <CommandBlock>

<CommandMacroInvocationCommand> ::= <CommandMacroName> <ParenthesizedExpressionList>?

<CommandMacroName> ::= '$' (IDCONT+ | '(' IDCONT+ ')')

<NoteMacroDefinitionCommand> ::= <NoteMacroName> '=' <ChordExpression>

<ExtensionCommand> ::= '%' <Identifier> <ParenthesizedExpressionList>? <CommandBlock>?

<NoteCommand> ::= <ChordExpression> <CommandArgumentExpression>?

<ChordExpression> ::= <KeySpecifier> ('&' <KeySpecifier>)*

<KeySpecifier> ::= ('>' | '<')* (<KeyLiteral> | <AbsoluteKeyLiteral> | <NoteMacroReference>) ('+' | '-')*

<KeyLiteral> ::= 'c' | 'd' | 'e' | 'f' | 'g' | 'a' | 'b'

<AbsoluteKeyLiteral> ::= '\' (('(' DIGIT+ ')') | DIGIT+)

<NoteMacroName> ::= '\' IDSTART+

<NoteMacroReference> ::= <NoteMacroName>

<BasicCommand> ::= IDSTART ('+' | '-')? <CommandArgumentExpression>?

<CommandBlock> ::= '{' <Command>* '}'


<Expression> ::= <AddSubExpression>

<AddSubExpression> ::= <MulDivExpression> (('+' | '-') <MulDivExpression>)*

<MulDivExpression> ::= <UnaryExpression> (('*' | '/') <UnaryExpression>)*

<UnaryExpression> ::= ('+' | '-')* <PostfixExpression>

<PostfixExpression> ::= <PrimaryExpression> <ParenthesizedExpressionList>*

<PrimaryExpression> ::= <Identifier>
    | <HexadecimalIntegerLiteral>
    | <DecimalIntegerLiteral>
    | <StringLiteral>
    | <TimeLiteral>
    | <DurationLiteral>
    | ('(' <Expression> ')')

<CommandArgumentExpression> ::= <DecimalIntegerLiteral>
    | <TimeLiteral>
    | <DurationLiteral>
    | ('(' <Expression> ')')

<ParenthesizedExpressionList> ::= '(' <NonEmptyExpressionList>? ')'

<NonEmptyExpressionList> ::= <ExpressionListItem> (',' <ExpressionListItem>)?

<ExpressionListItem> ::= (<Expression> '=')? <Expression>


<Identifier> ::= IDSTART IDCONT*

<HexadecimalIntegerLiteral> ::= '0' ('X' | 'x') XDIGIT+

<DecimalIntegerLiteral> ::= DIGIT+

<StringLiteral> ::= ...

<TimeLiteral> ::= (DIGIT+ ':' DIGIT* (':' DIGIT*)?)
    | (':' DIGIT+ (':' DIGIT*)?)
    | ('::' DIGIT+)

<DurationLiteral> ::= DIGIT+ ('.')*

*/

private immutable int recursionLimit = 50;

private struct ParseLiteralOptions
{
    bool allowHex;
    bool allowStringLiteral;
    bool allowDurationAndTimeLiteral;
}

public final class Parser
{
    import std.array : appender;

    import yammld3.diagnostics : DiagnosticsHandler;

    public this(DiagnosticsHandler diagnosticsHandler)
    {
        _diagnosticsHandler = diagnosticsHandler;
    }

    public Module parseModule(Source src)
    {
        assert(src !is null);

        auto s = Scanner(src.contents, SourceOffset(src, 1, 0));
        auto commands = parseCommands(s, null);
        return new Module(src.path, commands);
    }

    private Command[] parseCommands(ref Scanner s, string endString)
    {
        auto commands = appender!(Command[]);

        while (true)
        {
            auto c = parseCommand(s);

            if (c !is null)
            {
                commands.put(c);
                continue;
            }
            else if (!endString.empty)
            {
                auto s2 = s;

                if (s2.empty || s2.scanString(endString))
                {
                    break;
                }
            }
            else
            {
                if (s.empty)
                {
                    break;
                }
            }

            assert(!s.empty);

            auto charOffset = s.sourceOffset;
            dchar ch;
            s.scanAnyChar(ch);

            _diagnosticsHandler.unexpectedCharacter(
                SourceLocation(charOffset, s.sourceOffset),
                "command",
                ch
            );
        }

        return commands[];
    }

    private Command parseCommand(ref Scanner s)
    {
        _recursionDepth++;

        scope (exit)
        {
            _recursionDepth--;
        }

        if (_recursionDepth > recursionLimit)
        {
            _diagnosticsHandler.recursionLimitExceeded(SourceLocation(s.sourceOffset, 1));
            assert(false);
        }

        return parsePostfixCommand(s);
    }

    private Command parsePostfixCommand(ref Scanner s)
    {
        Command c = parsePrimaryCommand(s);

        if (c is null)
        {
            return null;
        }

        while (true)
        {
            //skipSpaces(s);

            auto startOffset = s.sourceOffset;

            if (s.scanChar('!'))
            {
                auto name = parseIdentifier(s);

                if (name is null)
                {
                    _diagnosticsHandler.expectedAfter(
                        SourceLocation(startOffset, 1),
                        "postfix command",
                        "identifier",
                        "!"
                    );
                    break;
                }

                //skipSpaces(s);
                auto elist = parseParenthesizedExpressionList(s);
                c = new ModifierCommand(SourceLocation(c.location.offset, s.sourceOffset), c, name, elist);
            }
            else if (s.scanChar('*'))
            {
                //skipSpaces(s);
                auto arg = parseCommandArgumentExpression(s);
                c = new RepeatCommand(SourceLocation(c.location.offset, s.sourceOffset), c, arg);
            }
            else
            {
                //skipSpaces(s);

                auto s2 = s.save;

                // don't parse comments as a tuplet command
                if (s2.scanString("//") || s2.scanString("/*"))
                {
                    break;
                }

                if (s.scanChar('/'))
                {
                    auto arg = parseCommandArgumentExpression(s);
                    c = new TupletCommand(SourceLocation(c.location.offset, s.sourceOffset), c, arg);
                }
                else
                {
                    break;
                }
            }
        }

        return c;
    }

    private Command parsePrimaryCommand(ref Scanner s)
    {
        skipSpaces(s);

        auto startOffset = s.sourceOffset;

        if (s.scanChar('('))
        {
            auto commands = parseCommands(s, ")");

            if (!s.scanChar(')'))
            {
                _diagnosticsHandler.noCloseCharacters(
                    SourceLocation(s.sourceOffset, 0),
                    SourceLocation(startOffset, 1),
                    "(",
                    ")"
                );
            }

            return new ScopedCommand(SourceLocation(startOffset, s.sourceOffset), commands);
        }

        auto cm = parseCommandMacro(s);

        if (cm !is null)
        {
            return cm;
        }

        auto nmd = parseNoteMacroDefinitionCommand(s);

        if (nmd !is null)
        {
            return nmd;
        }

        auto ec = parseExtensionCommand(s);

        if (ec !is null)
        {
            return ec;
        }

        auto nc = parseNoteCommand(s);

        if (nc !is null)
        {
            return nc;
        }

        return parseBasicCommand(s);
    }

    private Command parseCommandMacro(ref Scanner s)
    {
        auto startOffset = s.sourceOffset;
        auto name = parseCommandMacroName(s);

        if (name is null)
        {
            return null;
        }

        auto s2 = s.save;

        skipSpaces(s2);

        if (s2.scanChar('='))
        {
            s = s2;
            skipSpaces(s);
            auto block = parseCommandBlock(s);

            if (block is null)
            {
                _diagnosticsHandler.expectedAfter(
                    SourceLocation(startOffset, s.sourceOffset),
                    "command macro definition",
                    "command block",
                    "="
                );

                return null;
            }

            return new CommandMacroDefinitionCommand(
                SourceLocation(startOffset, s.sourceOffset),
                name,
                block
            );
        }

        auto argList = parseParenthesizedExpressionList(s);

        return new CommandMacroInvocationCommand(
            SourceLocation(startOffset, s.sourceOffset),
            name,
            argList
        );
    }

    private CommandMacroName parseCommandMacroName(ref Scanner s)
    {
        auto startOffset = s.sourceOffset;

        if (!s.scanChar('$'))
        {
            return null;
        }

        string name;

        if (s.scanChar('('))
        {
            name = parseCommandMacroNameString(s);

            if (!s.scanChar(')'))
            {
                _diagnosticsHandler.expectedAfter(
                    SourceLocation(startOffset, s.sourceOffset),
                    "command macro",
                    ")",
                    "$("
                );
            }

            if (name.empty)
            {
                _diagnosticsHandler.expectedAfter(
                    SourceLocation(startOffset, s.sourceOffset),
                    "command macro",
                    "command macro name",
                    "$("
                );
            }
        }
        else
        {
            name = parseCommandMacroNameString(s);

            if (name.empty)
            {
                _diagnosticsHandler.expectedAfter(
                    SourceLocation(startOffset, s.sourceOffset),
                    "command macro",
                    "command macro name",
                    "$"
                );
            }
        }

        return new CommandMacroName(SourceLocation(startOffset, s.sourceOffset), name);
    }

    private string parseCommandMacroNameString(ref Scanner s)
    {
        auto nameView = s.view;

        while (s.scanNameChar())
        {
        }

        return nameView[0..(s.view.ptr - nameView.ptr)];
    }

    private NoteMacroDefinitionCommand parseNoteMacroDefinitionCommand(ref Scanner s)
    {
        auto startOffset = s.sourceOffset;
        auto s2 = s.save;
        auto name = parseNoteMacroName(s2);

        if (name is null)
        {
            return null;
        }

        skipSpaces(s2);

        if (!s2.scanChar('='))
        {
            return null;
        }

        s = s2;
        skipSpaces(s);
        auto chord = parseChordExpression(s);

        if (chord is null)
        {
            _diagnosticsHandler.expectedAfter(
                SourceLocation(startOffset, s.sourceOffset),
                "note macro definition",
                "chord expression",
                "="
            );

            return null;
        }

        return new NoteMacroDefinitionCommand(
            SourceLocation(startOffset, s.sourceOffset),
            name,
            chord
        );
    }

    private ExtensionCommand parseExtensionCommand(ref Scanner s)
    {
        auto startOffset = s.sourceOffset;

        if (s.scanChar('%'))
        {
            auto name = parseIdentifier(s);

            if (name is null)
            {
                _diagnosticsHandler.expectedAfter(
                    SourceLocation(startOffset, 1),
                    "extension command",
                    "identifier",
                    "%"
                );

                return null;
            }

            // skipSpaces(s);
            auto argList = parseParenthesizedExpressionList(s);
            auto argListEndOffset = s.sourceOffset;
            skipSpaces(s);
            auto block = parseCommandBlock(s);

            return new ExtensionCommand(
                SourceLocation(startOffset, block is null ? argListEndOffset : s.sourceOffset),
                name,
                argList,
                block
            );
        }

        return null;
    }

    private KeyLiteral parseKeyLiteral(ref Scanner s)
    {
        import yammld3.common : KeyName;

        if (s.empty)
        {
            return null;
        }

        KeyName keyName;

        switch (s.front)
        {
        case 'c':
            keyName = KeyName.c;
            break;

        case 'd':
            keyName = KeyName.d;
            break;

        case 'e':
            keyName = KeyName.e;
            break;

        case 'f':
            keyName = KeyName.f;
            break;

        case 'g':
            keyName = KeyName.g;
            break;

        case 'a':
            keyName = KeyName.a;
            break;

        case 'b':
            keyName = KeyName.b;
            break;

        default:
            return null;
        }

        auto startOffset = s.sourceOffset;
        s.popFront();
        return new KeyLiteral(SourceLocation(startOffset, s.sourceOffset), keyName);
    }

    private AbsoluteKeyLiteral parseAbsoluteKeyLiteral(ref Scanner s)
    {
        import std.ascii : isDigit;
        import std.conv : ConvOverflowException, parse;

        auto s2 = s.save;
        auto startOffset = s.sourceOffset;

        if (!s2.scanChar('\\'))
        {
            return null;
        }

        bool paren = s2.scanChar('(');

        if (s2.empty || !isDigit(s2.front))
        {
            return null;
        }

        s = s2;

        try
        {
            int n = parse!int(s);

            if (paren && !s.scanChar(')'))
            {
                _diagnosticsHandler.noCloseCharacters(
                    SourceLocation(s.sourceOffset, 0),
                    SourceLocation(startOffset, 1),
                    "(",
                    ")"
                );
            }

            return new AbsoluteKeyLiteral(SourceLocation(startOffset, s.sourceOffset), n);
        }
        catch (ConvOverflowException e)
        {
            _diagnosticsHandler.overflow(SourceLocation(startOffset, s.sourceOffset), "absolute key literal");
            return null;
        }
    }

    private NoteMacroName parseNoteMacroName(ref Scanner s)
    {
        auto s2 = s.save;
        auto startOffset = s.sourceOffset;

        if (!s2.scanChar('\\'))
        {
            return null;
        }

        auto nameView = s2.view;

        if (!s2.scanNameStartChar())
        {
            return null;
        }

        s = s2;

        while (s.scanNameStartChar())
        {
        }

        return new NoteMacroName(
            SourceLocation(startOffset, s.sourceOffset),
            nameView[0..(s.view.ptr - nameView.ptr)]
        );
    }

    private NoteMacroReference parseNoteMacroReference(ref Scanner s)
    {
        auto name = parseNoteMacroName(s);

        if (name is null)
        {
            return null;
        }

        return new NoteMacroReference(name);
    }

    private KeySpecifier parseKeySpecifier(ref Scanner s)
    {
        auto startOffset = s.sourceOffset;
        auto startView = s.view;

        int rightCount = 0;
        int leftCount = 0;

        while (true)
        {
            if (s.scanChar('>'))
            {
                rightCount++;
            }
            else if (s.scanChar('<'))
            {
                leftCount++;
            }
            else
            {
                break;
            }
        }

        auto octaveShiftEndView = s.view;
        BaseKeySpecifier baseKey = parseKeyLiteral(s);

        if (baseKey is null)
        {
            baseKey = parseAbsoluteKeyLiteral(s);
        }

        if (baseKey is null)
        {
            baseKey = parseNoteMacroReference(s);
        }

        if (baseKey is null)
        {
            if (leftCount > 0 || rightCount > 0)
            {
                _diagnosticsHandler.expectedAfter(
                    SourceLocation(startOffset, s.sourceOffset),
                    "note command",
                    "base key specifier",
                    startView[0..(octaveShiftEndView.ptr - startView.ptr)]
                );
            }

            return null;
        }

        int accidental = 0;

        while (true)
        {
            if (s.scanChar('+'))
            {
                accidental++;
            }
            else if (s.scanChar('-'))
            {
                accidental--;
            }
            else
            {
                break;
            }
        }

        return new KeySpecifier(
            SourceLocation(startOffset, s.sourceOffset),
            rightCount - leftCount,
            baseKey,
            accidental
        );
    }

    private KeySpecifier[] parseChordExpression(ref Scanner s)
    {
        auto k = parseKeySpecifier(s);

        if (k is null)
        {
            return null;
        }

        auto keys = appender!(KeySpecifier[]);
        keys.put(k);

        while (true)
        {
            //skipSpaces(s);

            auto keyStartOffset = s.sourceOffset;

            if (s.scanChar('&'))
            {
                //skipSpaces(s);
                k = parseKeySpecifier(s);

                if (k is null)
                {
                    _diagnosticsHandler.expectedAfter(
                        SourceLocation(keyStartOffset, 1),
                        "chord expression",
                        "key specifier",
                        "&"
                    );
                    break;
                }
                else
                {
                    keys.put(k);
                }
            }
            else
            {
                break;
            }
        }

        return keys[];
    }

    private NoteCommand parseNoteCommand(ref Scanner s)
    {
        auto startOffset = s.sourceOffset;
        auto chord = parseChordExpression(s);

        if (chord is null)
        {
            return null;
        }

        auto dur = parseCommandArgumentExpression(s);

        return new NoteCommand(
            SourceLocation(startOffset, s.sourceOffset),
            chord,
            dur
        );
    }

    private BasicCommand parseBasicCommand(ref Scanner s)
    {
        import yammld3.common : OptionalSign;

        auto startOffset = s.sourceOffset;
        auto startView = s.view;

        if (!s.scanNameStartChar())
        {
            return null;
        }

        size_t len = s.view.ptr - startView.ptr;
        string name = startView[0..len];

        auto sign = OptionalSign.none;

        if (s.scanChar('+'))
        {
            sign = OptionalSign.plus;
        }
        else if (s.scanChar('-'))
        {
            sign = OptionalSign.minus;
        }

        auto arg = parseCommandArgumentExpression(s);
        return new BasicCommand(
            SourceLocation(startOffset, s.sourceOffset),
            name,
            sign,
            arg
        );
    }

    private CommandBlock parseCommandBlock(ref Scanner s)
    {
        auto startOffset = s.sourceOffset;

        if (s.scanChar('{'))
        {
            auto commands = parseCommands(s, "}");

            if (!s.scanChar('}'))
            {
                _diagnosticsHandler.noCloseCharacters(
                    SourceLocation(s.sourceOffset, 0),
                    SourceLocation(startOffset, 1),
                    "{",
                    "}"
                );
            }

            return new CommandBlock(SourceLocation(startOffset, s.sourceOffset), commands);
        }

        return null;
    }

    private ExpressionList parseParenthesizedExpressionList(ref Scanner s)
    {
        auto startOffset = s.sourceOffset;
        auto charOffset = startOffset;
        auto charView = s.view;

        if (s.scanChar('('))
        {
            skipSpaces(s);

            if (s.scanChar(')'))
            {
                return new ExpressionList(SourceLocation(startOffset, s.sourceOffset), null);
            }

            auto items = appender!(ExpressionListItem[]);

            while (true)
            {
                skipSpaces(s);
                auto item = parseExpressionListItem(s);

                if (item is null)
                {
                    _diagnosticsHandler.expectedAfter(
                        SourceLocation(charOffset, s.sourceOffset),
                        "parenthesized expression list",
                        "expression list item",
                        charView[0..1]
                    );

                    break;
                }

                items.put(item);
                skipSpaces(s);

                if (s.scanChar(','))
                {
                    charOffset = s.sourceOffset;
                    charView = s.view;
                }
                else if (s.scanChar(')'))
                {
                    break;
                }
                else
                {
                    _diagnosticsHandler.noCloseCharacters(
                        SourceLocation(s.sourceOffset, 0),
                        SourceLocation(startOffset, 1),
                        "(",
                        ")"
                    );
                    break;
                }
            }

            return new ExpressionList(SourceLocation(startOffset, s.sourceOffset), items[]);
        }

        return null;
    }

    private ExpressionListItem parseExpressionListItem(ref Scanner s)
    {
        // skipSpaces(s);
        auto ex0 = parseExpression(s);

        if (ex0 is null)
        {
            return null;
        }

        skipSpaces(s);

        auto eqOffset = s.sourceOffset;

        if (s.scanChar('='))
        {
            skipSpaces(s);
            auto ex1 = parseExpression(s);

            if (ex1 is null)
            {
                _diagnosticsHandler.expectedAfter(
                    SourceLocation(eqOffset, s.sourceOffset),
                    "expression list item",
                    "expression",
                    "="
                );

                return null;
            }
            else
            {
                return new ExpressionListItem(ex0, ex1);
            }
        }
        else
        {
            return new ExpressionListItem(ex0);
        }
    }

    private Expression parseExpression(ref Scanner s)
    {
        _recursionDepth++;

        scope (exit)
        {
            _recursionDepth--;
        }

        if (_recursionDepth > recursionLimit)
        {
            _diagnosticsHandler.recursionLimitExceeded(SourceLocation(s.sourceOffset, 1));
            assert(false);
        }

        return parseAddSubExpression(s);
    }

    private Expression parseAddSubExpression(ref Scanner s)
    {
        auto lhs = parseMulDivExpression(s);

        if (lhs is null)
        {
            return null;
        }

        while (true)
        {
            skipSpaces(s);

            auto opOffset = s.sourceOffset;
            auto opView = s.view;
            OperatorKind opKind;

            if (s.scanChar('+'))
            {
                opKind = OperatorKind.plus;
            }
            else if (s.scanChar('-'))
            {
                opKind = OperatorKind.minus;
            }
            else
            {
                break;
            }

            size_t opLen = s.view.ptr - opView.ptr;
            auto op = new Operator(SourceLocation(opOffset, s.sourceOffset), opKind);
            skipSpaces(s);
            auto rhs = parseMulDivExpression(s);

            if (rhs is null)
            {
                _diagnosticsHandler.expectedAfter(
                    op.location,
                    "expression",
                    "expression",
                    "operator '" ~ opView[0..opLen] ~ "'"
                );
                break;
            }

            lhs = new BinaryExpression(op, lhs, rhs);
        }

        return lhs;
    }

    private Expression parseMulDivExpression(ref Scanner s)
    {
        auto lhs = parseUnaryExpression(s);

        if (lhs is null)
        {
            return null;
        }

        while (true)
        {
            skipSpaces(s);

            auto opOffset = s.sourceOffset;
            auto opView = s.view;
            OperatorKind opKind;

            if (s.scanChar('*'))
            {
                opKind = OperatorKind.star;
            }
            else if (s.scanChar('/'))
            {
                opKind = OperatorKind.slash;
            }
            else
            {
                break;
            }

            size_t opLen = s.view.ptr - opView.ptr;
            auto op = new Operator(SourceLocation(opOffset, s.sourceOffset), opKind);
            skipSpaces(s);
            auto rhs = parseUnaryExpression(s);

            if (rhs is null)
            {
                _diagnosticsHandler.expectedAfter(
                    op.location,
                    "expression",
                    "expression",
                    "operator '" ~ opView[0..opLen] ~ "'"
                );
                break;
            }

            lhs = new BinaryExpression(op, lhs, rhs);
        }

        return lhs;
    }

    private Expression parseUnaryExpression(ref Scanner s)
    {
        Operator[] ops;

        while (true)
        {
            skipSpaces(s);
            auto opOffset = s.sourceOffset;

            if (s.scanChar('+'))
            {
                ops ~= new Operator(SourceLocation(opOffset, s.sourceOffset), OperatorKind.plus);
            }
            else if (s.scanChar('-'))
            {
                ops ~= new Operator(SourceLocation(opOffset, s.sourceOffset), OperatorKind.minus);
            }
            else
            {
                break;
            }
        }

        auto operand = parsePostfixExpression(s);

        if (operand is null)
        {
            if (!ops.empty)
            {
                _diagnosticsHandler.expectedAfter(
                    ops.back.location,
                    "expression",
                    "expression",
                    "operator '" ~ (ops.back.kind == OperatorKind.plus ? "+" : "-") ~ "'"
                );
            }

            return null;
        }

        while (!ops.empty)
        {
            operand = new UnaryExpression(ops.back, operand);
            ops.popBack();
        }

        return operand;
    }

    private Expression parsePostfixExpression(ref Scanner s)
    {
        auto operand = parsePrimaryExpression(s);

        if (operand is null)
        {
            return null;
        }

        while (true)
        {
            skipSpaces(s);

            auto elist = parseParenthesizedExpressionList(s);

            if (elist is null)
            {
                break;
            }

            operand = new CallExpression(operand, elist);
        }

        return operand;
    }

    private Expression parsePrimaryExpression(ref Scanner s)
    {
        return parsePrimaryExpressionEx(s, false);
    }

    private Expression parseCommandArgumentExpression(ref Scanner s)
    {
        return parsePrimaryExpressionEx(s, true);
    }

    private Expression parsePrimaryExpressionEx(ref Scanner s, bool isCommandArgument)
    {
        if (!isCommandArgument)
        {
            skipSpaces(s);
        }

        auto startOffset = s.sourceOffset;

        if (s.scanChar('('))
        {
            auto expr = parseExpression(s);

            if (expr is null)
            {
                _diagnosticsHandler.expectedAfter(
                    SourceLocation(startOffset, 1),
                    "expression",
                    "expression",
                    "("
                );

                return null;
            }

            while (true)
            {
                skipSpaces(s);

                if (s.scanChar(')'))
                {
                    break;
                }
                else
                {
                    dchar ch;
                    auto charOffset = s.sourceOffset;

                    if (s.scanAnyChar(ch))
                    {
                        _diagnosticsHandler.unexpectedCharacter(
                            SourceLocation(charOffset, s.sourceOffset),
                            "expression",
                            ch
                        );
                    }
                    else
                    {
                        _diagnosticsHandler.noCloseCharacters(
                            SourceLocation(s.sourceOffset, 0),
                            SourceLocation(startOffset, 1),
                            "(",
                            ")"
                        );

                        break;
                    }
                }
            }

            return expr;
        }

        if (!isCommandArgument)
        {
            auto ident = parseIdentifier(s);

            if (ident !is null)
            {
                return ident;
            }
        }

        ParseLiteralOptions options;
        options.allowHex = !isCommandArgument;
        options.allowStringLiteral = !isCommandArgument;
        options.allowDurationAndTimeLiteral = true;

        return parseLiteral(s, options);
    }

    private Identifier parseIdentifier(ref Scanner s)
    {
        // skipSpaces(s);

        auto startView = s.view;
        auto startOffset = s.sourceOffset;

        if (!s.scanNameStartChar())
        {
            return null;
        }

        while (s.scanNameChar())
        {
        }

        size_t len = s.view.ptr - startView.ptr;
        return new Identifier(SourceLocation(startOffset, len), startView[0..len]);
    }

    private Expression parseLiteral(ref Scanner s, ParseLiteralOptions options)
    {
        import std.ascii : isDigit, isHexDigit;
        import std.conv : ConvOverflowException, parse;

        // skipSpaces(s);

        if (s.empty)
        {
            return null;
        }

        if (options.allowStringLiteral)
        {
            auto sl = parseStringLiteral(s);

            if (sl !is null)
            {
                return sl;
            }
        }

        auto startOffset = s.sourceOffset;
        auto startView = s.view;

        try
        {
            if (options.allowHex && (s.scanString("0x") || s.scanString("0X")))
            {
                int value;

                if (!s.empty && isHexDigit(s.front))
                {
                    value = parse!int(s, 16);
                }
                else
                {
                    _diagnosticsHandler.expectedAfter(
                        SourceLocation(startOffset, 2),
                        "hexadecimal integer literal",
                        "xdigit",
                        startView[0..2]
                    );

                    value = 0;
                }

                return new IntegerLiteral(SourceLocation(startOffset, s.sourceOffset), value);
            }
            else
            {
                int[3] ints;

                if (isDigit(s.front))
                {
                    ints[0] = parse!int(s);

                    if (!options.allowDurationAndTimeLiteral)
                    {
                        return new IntegerLiteral(SourceLocation(startOffset, s.sourceOffset), ints[0]);
                    }

                    if (s.scanChar('.'))
                    {
                        int dots = 1;

                        while (s.scanChar('.'))
                        {
                            dots++;
                        }

                        return new DurationLiteral(SourceLocation(startOffset, s.sourceOffset), ints[0], dots);
                    }
                    else if (!s.scanChar(':'))
                    {
                        return new IntegerLiteral(SourceLocation(startOffset, s.sourceOffset), ints[0]);
                    }
                }
                else if (!(options.allowDurationAndTimeLiteral && s.scanChar(':')))
                {
                    return null;
                }

                if (!s.empty && isDigit(s.front))
                {
                    ints[1] = parse!int(s);
                }

                if (s.scanChar(':') && !s.empty && isDigit(s.front))
                {
                    ints[2] = parse!int(s);
                }

                return new TimeLiteral(SourceLocation(startOffset, s.sourceOffset), ints[0], ints[1], ints[2]);
            }
        }
        catch (ConvOverflowException e)
        {
            _diagnosticsHandler.overflow(SourceLocation(startOffset, s.sourceOffset), "literal");
            return null;
        }
    }

    private StringLiteral parseStringLiteral(ref Scanner s)
    {
        if (s.empty)
        {
            return null;
        }

        auto startOffset = s.sourceOffset;
        auto startView = s.view;

        if (!s.scanChar('"'))
        {
            return null;
        }

        auto str = appender!string();
        bool escaped = false;

        while (true)
        {
            if (s.empty || s.front == '\n')
            {
                _diagnosticsHandler.unterminatedStringLiteral(SourceLocation(startOffset, s.sourceOffset));
                break;
            }
            else if (escaped)
            {
                // TODO: handle more escape sequences

                switch (s.front)
                {
                case 'f':
                    str.put('\f');
                    break;

                case 'n':
                    str.put('\n');
                    break;

                case 'r':
                    str.put('\r');
                    break;

                case 't':
                    str.put('\t');
                    break;

                case 'v':
                    str.put('\v');
                    break;

                default:
                    str.put(s.front);
                    break;
                }

                s.popFront();
                escaped = false;
            }
            else if (s.front == '"')
            {
                s.popFront();
                break;
            }
            else if (s.front == '\\')
            {
                escaped = true;
                s.popFront();
            }
            else
            {
                str.put(s.front);
                s.popFront();
            }
        }

        return new StringLiteral(SourceLocation(startOffset, s.sourceOffset), str[]);
    }

    private void skipSpaces(ref Scanner s)
    {
        while (s.scanWhiteSpace() || skipLineComment(s) || skipBlockComment(s))
        {
        }
    }

    private bool skipLineComment(ref Scanner s)
    {
        if (s.scanString("//"))
        {
            while (!s.empty && s.front != '\n')
            {
                s.popFront();
            }

            return true;
        }
        else
        {
            return false;
        }
    }

    private bool skipBlockComment(ref Scanner s)
    {
        auto startOffset = s.sourceOffset;

        if (s.scanString("/*"))
        {
            auto startLoc = SourceLocation(startOffset, s.sourceOffset);

            while (true)
            {
                if (s.empty)
                {
                    _diagnosticsHandler.unterminatedBlockComment(startLoc);
                    break;
                }
                else if (s.scanString("*/"))
                {
                    break;
                }

                s.scanAnyChar();
            }

            return true;
        }
        else
        {
            return false;
        }
    }

    private DiagnosticsHandler _diagnosticsHandler;
    private int _recursionDepth = 0;
}
