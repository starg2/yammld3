
module yammld3.astprinter;

import std.range.primitives;

import yammld3.ast;

private string operatorKindToString(OperatorKind kind)
{
    final switch (kind)
    {
    case OperatorKind.plus:
        return "+";

    case OperatorKind.minus:
        return "-";

    case OperatorKind.star:
        return "*";

    case OperatorKind.slash:
        return "/";
    }
}

public final class ASTPrinter(Writer)
{
    import std.conv : text;
    import yammld3.xmlwriter : XMLAttribute, XMLWriter;

    public this(Writer output, string indent = "")
    {
        _writer = new XMLWriter!Writer(output, indent);
    }

    public void printModule(Module m)
    {
        assert(m !is null);

        _writer.startDocument();
        _writer.startElement("Module", [XMLAttribute("Name", m.name)]);

        foreach (c; m.commands)
        {
            printCommand(c);
        }

        _writer.endElement();
        _writer.endDocument();
    }

    private void printCommand(Command c)
    {
        assert(c !is null);

        final switch (c.kind)
        {
        case CommandKind.basic:
            printBasicCommand(cast(BasicCommand)c);
            break;

        case CommandKind.note:
            printNoteCommand(cast(NoteCommand)c);
            break;

        case CommandKind.extension:
            printExtensionCommand(cast(ExtensionCommand)c);
            break;

        case CommandKind.scoped:
            printScopedCommand(cast(ScopedCommand)c);
            break;

        case CommandKind.modifier:
            printModifierCommand(cast(ModifierCommand)c);
            break;

        case CommandKind.repeat:
            printRepeatCommand(cast(RepeatCommand)c);
            break;

        case CommandKind.tuplet:
            printTupletCommand(cast(TupletCommand)c);
            break;

        case CommandKind.chord:
            printChordCommand(cast(ChordCommand)c);
            break;
        }
    }

    private void printBasicCommand(BasicCommand c)
    {
        import yammld3.common : OptionalSign;
        assert(c !is null);

        auto attr = [XMLAttribute("Name", c.name)];

        final switch (c.sign)
        {
        case OptionalSign.none:
            break;

        case OptionalSign.plus:
            attr ~= XMLAttribute("Sign", "+");
            break;

        case OptionalSign.minus:
            attr ~= XMLAttribute("Sign", "-");
            break;
        }

        if (c.argument is null)
        {
            _writer.writeElement("BasicCommand", attr);
        }
        else
        {
            _writer.startElement("BasicCommand", attr);
            _writer.startElement("Argument");
            printExpression(c.argument);
            _writer.endElement();
            _writer.endElement();
        }
    }

    private void printNoteCommand(NoteCommand c)
    {
        import std.array : appender;
        import yammld3.common : KeyName;

        assert(c !is null);

        auto attr = appender!(XMLAttribute[]);

        if (c.octaveShift != 0)
        {
            attr.put(XMLAttribute("OctaveShift", c.octaveShift.text));
        }

        switch (c.baseKey)
        {
        case KeyName.c:
            attr.put(XMLAttribute("BaseKey", "C"));
            break;

        case KeyName.d:
            attr.put(XMLAttribute("BaseKey", "D"));
            break;

        case KeyName.e:
            attr.put(XMLAttribute("BaseKey", "E"));
            break;

        case KeyName.f:
            attr.put(XMLAttribute("BaseKey", "F"));
            break;

        case KeyName.g:
            attr.put(XMLAttribute("BaseKey", "G"));
            break;

        case KeyName.a:
            attr.put(XMLAttribute("BaseKey", "A"));
            break;

        case KeyName.b:
            attr.put(XMLAttribute("BaseKey", "B"));
            break;

        default:
            attr.put(XMLAttribute("BaseKey", (cast(int)c.baseKey).text));
            break;
        }

        if (c.accidental != 0)
        {
            attr.put(XMLAttribute("Accidental", c.accidental.text));
        }

        if (c.duration is null)
        {
            _writer.writeElement("NoteCommand", attr[]);
        }
        else
        {
            _writer.startElement("NoteCommand", attr[]);
            _writer.startElement("Duration");
            printExpression(c.duration);
            _writer.endElement();
            _writer.endElement();
        }
    }

    private void printExtensionCommand(ExtensionCommand c)
    {
        assert(c !is null);

        if (c.arguments is null && c.block is null)
        {
            _writer.writeElement("ExtensionCommand", [XMLAttribute("Name", c.name.value)]);
        }
        else
        {
            _writer.startElement("ExtensionCommand", [XMLAttribute("Name", c.name.value)]);

            if (c.arguments !is null)
            {
                printExpressionList(c.arguments);
            }

            if (c.block !is null)
            {
                printCommandBlock(c.block);
            }

            _writer.endElement();
        }
    }

    private void printScopedCommand(ScopedCommand c)
    {
        assert(c !is null);

        if (c.commands.empty)
        {
            _writer.writeElement("ScopedCommand");
        }
        else
        {
            _writer.startElement("ScopedCommand");

            foreach (i; c.commands)
            {
                printCommand(i);
            }

            _writer.endElement();
        }
    }

    private void printModifierCommand(ModifierCommand c)
    {
        assert(c !is null);

        _writer.startElement("ModifierCommand", [XMLAttribute("Name", c.name.value)]);
        printCommand(c.command);
        printExpressionList(c.arguments);
        _writer.endElement();
    }

    private void printRepeatCommand(RepeatCommand c)
    {
        assert(c !is null);

        _writer.startElement("RepeatCommand");
        printCommand(c.command);

        _writer.startElement("RepeatCount");
        printExpression(c.repeatCount);
        _writer.endElement();

        _writer.endElement();
    }

    private void printTupletCommand(TupletCommand c)
    {
        assert(c !is null);

        _writer.startElement("TupletCommand");
        printCommand(c.command);

        if (c.duration !is null)
        {
            _writer.startElement("Duration");
            printExpression(c.duration);
            _writer.endElement();
        }

        _writer.endElement();
    }

    private void printChordCommand(ChordCommand c)
    {
        assert(c !is null);

        if (c.children.empty)
        {
            _writer.writeElement("ChordCommand");
        }
        else
        {
            _writer.startElement("ChordCommand");

            foreach (i; c.children)
            {
                printCommand(i);
            }

            _writer.endElement();
        }
    }

    private void printCommandBlock(CommandBlock b)
    {
        assert(b !is null);

        if (b.commands.empty)
        {
            _writer.writeElement("CommandBlock");
        }
        else
        {
            _writer.startElement("CommandBlock");

            foreach (i; b.commands)
            {
                printCommand(i);
            }

            _writer.endElement();
        }
    }

    private void printExpressionList(ExpressionList elist)
    {
        assert(elist !is null);

        if (elist.items.empty)
        {
            _writer.writeElement("ExpressionList");
        }
        else
        {
            _writer.startElement("ExpressionList");

            foreach (i; elist.items)
            {
                _writer.startElement("ExpressionListItem");

                if (i.key !is null)
                {
                    _writer.startElement("Key");
                    printExpression(i.key);
                    _writer.endElement();
                }

                _writer.startElement("Value");
                printExpression(i.value);
                _writer.endElement();

                _writer.endElement();
            }

            _writer.endElement();
        }
    }

    private void printExpression(Expression expr)
    {
        assert(expr !is null);

        final switch (expr.kind)
        {
        case ExpressionKind.identifier:
            printIdentifier(cast(Identifier)expr);
            break;

        case ExpressionKind.integerLiteral:
            printIntegerLiteral(cast(IntegerLiteral)expr);
            break;

        case ExpressionKind.stringLiteral:
            printStringLiteral(cast(StringLiteral)expr);
            break;

        case ExpressionKind.timeLiteral:
            printTimeLiteral(cast(TimeLiteral)expr);
            break;

        case ExpressionKind.durationLiteral:
            printDurationLiteral(cast(DurationLiteral)expr);
            break;

        case ExpressionKind.unaryExpression:
            printUnaryExpression(cast(UnaryExpression)expr);
            break;

        case ExpressionKind.binaryExpression:
            printBinaryExpression(cast(BinaryExpression)expr);
            break;

        case ExpressionKind.callExpression:
            printCallExpression(cast(CallExpression)expr);
            break;
        }
    }

    private void printIdentifier(Identifier id)
    {
        assert(id !is null);
        _writer.writeElement("Identifier", [XMLAttribute("Value", id.value)]);
    }

    private void printIntegerLiteral(IntegerLiteral il)
    {
        assert(il !is null);
        _writer.writeElement("IntegerLiteral", [XMLAttribute("Value", il.value.text)]);
    }

    private void printStringLiteral(StringLiteral sl)
    {
        assert(sl !is null);
        _writer.writeElement("StringLiteral", [XMLAttribute("Value", sl.value)]);
    }

    private void printTimeLiteral(TimeLiteral tl)
    {
        assert(tl !is null);
        _writer.writeElement(
            "TimeLiteral",
            [
                XMLAttribute("Measures", tl.measures.text),
                XMLAttribute("Beats", tl.beats.text),
                XMLAttribute("Ticks", tl.ticks.text)
            ]
        );
    }

    private void printDurationLiteral(DurationLiteral dl)
    {
        assert(dl !is null);
        _writer.writeElement(
            "DurationLiteral",
            [
                XMLAttribute("Denominator", dl.denominator.text),
                XMLAttribute("Dot", dl.dot.text)
            ]
        );
    }

    private void printUnaryExpression(UnaryExpression expr)
    {
        assert(expr !is null);

        _writer.startElement("UnaryExpression", [XMLAttribute("Operator", operatorKindToString(expr.op.kind))]);

        _writer.startElement("Operand");
        printExpression(expr.operand);
        _writer.endElement();

        _writer.endElement();
    }

    private void printBinaryExpression(BinaryExpression expr)
    {
        assert(expr !is null);

        _writer.startElement("BinaryExpression", [XMLAttribute("Operator", operatorKindToString(expr.op.kind))]);

        _writer.startElement("Left");
        printExpression(expr.left);
        _writer.endElement();

        _writer.startElement("Right");
        printExpression(expr.right);
        _writer.endElement();

        _writer.endElement();
    }

    private void printCallExpression(CallExpression expr)
    {
        assert(expr !is null);

        _writer.startElement("CallExpression");

        _writer.startElement("Callee");
        printExpression(expr.callee);
        _writer.endElement();

        _writer.startElement("Parameters");
        printExpressionList(expr.parameters);
        _writer.endElement();

        _writer.endElement();
    }

    private XMLWriter!Writer _writer;
}