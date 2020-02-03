
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

        // table syntax (not implemented yet)
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

<Command> ::= <ChordCommand>

<ChordCommand> ::= <PostfixCommand> ('&' <PostfixCommand>)*

<PostfixCommand> ::= <PrimaryCommand> (<ModifierCommand> | <RepeatCommand> | <TupletCommand>)*

<PrimaryCommand> ::= ('(' <Command>* ')')
    | <ExtensionCommand>
    | <NoteCommand>
    | <BasicCommand>

<ModifierCommand> ::= '!' <Identifier> <ParenthesizedExpressionList>?

<RepeatCommand> ::= '*' <CommandArgumentExpression>?

<TupletCommand> ::= '/' <CommandArgumentExpression>?


<ExtensionCommand> ::= '%' <Identifier> <ParenthesizedExpressionList>? <CommandBlock>?

<NoteCommand> ::= ('>' | '<')* ('c' | 'd' | 'e' | 'f' | 'g' | 'a' | 'b') ('+' | '-')* <CommandArgumentExpression>?

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
        return parseChordCommand(s);
    }

    private Command parseChordCommand(ref Scanner s)
    {
        auto firstChild = parsePostfixCommand(s);

        if (firstChild is null)
        {
            return null;
        }

        Command[] restChildren;

        while (true)
        {
            skipSpaces(s);

            auto startOffset = s.sourceOffset;

            if (s.scanChar('&'))
            {
                skipSpaces(s);
                auto c = parsePostfixCommand(s);

                if (c is null)
                {
                    _diagnosticsHandler.expectedAfter(
                        SourceLocation(startOffset, 1),
                        "chord command",
                        "postfix command",
                        "&"
                    );
                    break;
                }
                else
                {
                    restChildren ~= c;
                }
            }
            else
            {
                break;
            }
        }

        if (restChildren.empty)
        {
            return firstChild;
        }
        else
        {
            return new ChordCommand(firstChild ~ restChildren);
        }
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
                c = new ModifierCommand(SourceLocation(startOffset, s.sourceOffset), c, name, elist);
            }
            else if (s.scanChar('*'))
            {
                //skipSpaces(s);
                auto arg = parseCommandArgumentExpression(s);
                c = new RepeatCommand(SourceLocation(startOffset, s.sourceOffset), c, arg);
            }
            else if (s.scanChar('/'))
            {
                //skipSpaces(s);
                auto arg = parseCommandArgumentExpression(s);
                c = new TupletCommand(SourceLocation(startOffset, s.sourceOffset), c, arg);
            }
            else
            {
                break;
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
            skipSpaces(s);
            auto block = parseCommandBlock(s);

            return new ExtensionCommand(
                SourceLocation(startOffset, s.sourceOffset),
                name,
                argList,
                block
            );
        }

        return null;
    }

    private NoteCommand parseNoteCommand(ref Scanner s)
    {
        import yammld3.common : KeyName;

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

        if (s.empty || !('a' <= s.front && s.front <= 'g'))
        {
            if (leftCount > 0 || rightCount > 0)
            {
                _diagnosticsHandler.expectedAfter(
                    SourceLocation(startOffset, s.sourceOffset),
                    "note command",
                    "note name",
                    startView[0..(s.view.ptr - startView.ptr)]
                );
            }

            return null;
        }

        KeyName baseKey;

        switch (s.front)
        {
        case 'c':
            baseKey = KeyName.c;
            break;

        case 'd':
            baseKey = KeyName.d;
            break;

        case 'e':
            baseKey = KeyName.e;
            break;

        case 'f':
            baseKey = KeyName.f;
            break;

        case 'g':
            baseKey = KeyName.g;
            break;

        case 'a':
            baseKey = KeyName.a;
            break;

        case 'b':
            baseKey = KeyName.b;
            break;

        default:
            assert(false);
        }

        s.popFront();

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

        auto dur = parseCommandArgumentExpression(s);
        return new NoteCommand(
            SourceLocation(startOffset, s.sourceOffset),
            rightCount - leftCount,
            baseKey,
            accidental,
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
        import std.conv : ConvException, parse;

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
            try
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
            catch (ConvException)
            {
                _diagnosticsHandler.overflow(SourceLocation(startOffset, s.sourceOffset), "literal");
                return null;
            }
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
        dchar quote = s.front;

        if (!(quote == '"' || quote == '\''))
        {
            return null;
        }

        s.popFront();
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
            else if (s.front == quote)
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
}
