
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
        c.visit!(x => doPrintCommand(x));
    }

    private void doPrintCommand(BasicCommand c)
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

    private void doPrintCommand(NoteCommand c)
    {
        assert(c !is null);
        assert(!c.keys.empty);

        _writer.startElement("NoteCommand");
        printKeySpecifiers(c.keys);

        if (c.duration !is null)
        {
            _writer.startElement("Duration");
            printExpression(c.duration);
            _writer.endElement();
        }

        _writer.endElement();
    }

    private void printKeySpecifiers(KeySpecifier[] keys)
    {
        import std.array : appender;
        import yammld3.common : KeyName;

        auto attr = appender!(XMLAttribute[]);

        foreach (k; keys)
        {
            if (k.octaveShift != 0)
            {
                attr ~= XMLAttribute("OctaveShift", k.octaveShift.text);
            }

            k.baseKey.visit!(
                (KeyLiteral kl)
                {
                    switch (kl.keyName)
                    {
                    case KeyName.c:
                        attr ~= XMLAttribute("KeyName", "C");
                        break;

                    case KeyName.d:
                        attr ~= XMLAttribute("KeyName", "D");
                        break;

                    case KeyName.e:
                        attr ~= XMLAttribute("KeyName", "E");
                        break;

                    case KeyName.f:
                        attr ~= XMLAttribute("KeyName", "F");
                        break;

                    case KeyName.g:
                        attr ~= XMLAttribute("KeyName", "G");
                        break;

                    case KeyName.a:
                        attr ~= XMLAttribute("KeyName", "A");
                        break;

                    case KeyName.b:
                        attr ~= XMLAttribute("KeyName", "B");
                        break;

                    default:
                        attr ~= XMLAttribute("KeyName", (cast(int)kl.keyName).text);
                        break;
                    }
                },
                (AbsoluteKeyLiteral akl)
                {
                    attr ~= XMLAttribute("Key", akl.key.text);
                },
                (NoteMacroReference nmr)
                {
                    attr ~= XMLAttribute("Name", nmr.name.value);
                }
            );

            if (k.accidental != 0)
            {
                attr ~= XMLAttribute("Accidental", k.accidental.text);
            }

            _writer.writeElement(
                k.baseKey.visit!(
                    (KeyLiteral kl) => "KeyLiteral",
                    (AbsoluteKeyLiteral akl) => "AbsoluteKeyLiteral",
                    (NoteMacroReference nmr) => "NoteMacroReference"
                ),
                attr[]
            );

            attr.clear();
        }
    }

    private void doPrintCommand(ExtensionCommand c)
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

    private void doPrintCommand(ScopedCommand c)
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

    private void doPrintCommand(ModifierCommand c)
    {
        assert(c !is null);

        _writer.startElement("ModifierCommand", [XMLAttribute("Name", c.name.value)]);
        printCommand(c.command);
        printExpressionList(c.arguments);
        _writer.endElement();
    }

    private void doPrintCommand(RepeatCommand c)
    {
        assert(c !is null);

        _writer.startElement("RepeatCommand");
        printCommand(c.command);

        _writer.startElement("RepeatCount");
        printExpression(c.repeatCount);
        _writer.endElement();

        _writer.endElement();
    }

    private void doPrintCommand(NoteMacroDefinitionCommand c)
    {
        assert(c !is null);

        _writer.startElement("NoteMacroDefinitionCommand", [XMLAttribute("Name", c.name.value)]);
        printKeySpecifiers(c.definition);
        _writer.endElement();
    }

    private void doPrintCommand(ExpressionMacroDefinitionCommand c)
    {
        assert(c !is null);

        _writer.startElement("ExpressionMacroDefinitionCommand", [XMLAttribute("Name", c.name.value)]);
        printExpression(c.definition);
        _writer.endElement();
    }

    private void doPrintCommand(ExpressionMacroInvocationCommand c)
    {
        assert(c !is null);

        if (c.arguments is null)
        {
            _writer.writeElement("ExpressionMacroInvocationCommand", [XMLAttribute("Name", c.name.value)]);
        }
        else
        {
            _writer.startElement("ExpressionMacroInvocationCommand", [XMLAttribute("Name", c.name.value)]);
            printExpressionList(c.arguments);
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
        expr.visit!(x => doPrintExpression(x));
    }

    private void doPrintExpression(Identifier id)
    {
        assert(id !is null);
        _writer.writeElement("Identifier", [XMLAttribute("Value", id.value)]);
    }

    private void doPrintExpression(IntegerLiteral il)
    {
        assert(il !is null);
        _writer.writeElement("IntegerLiteral", [XMLAttribute("Value", il.value.text)]);
    }

    private void doPrintExpression(StringLiteral sl)
    {
        assert(sl !is null);
        _writer.writeElement("StringLiteral", [XMLAttribute("Value", sl.value)]);
    }

    private void doPrintExpression(TimeLiteral tl)
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

    private void doPrintExpression(DurationLiteral dl)
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

    private void doPrintExpression(CommandBlock b)
    {
        printCommandBlock(b);
    }

    private void doPrintExpression(UnaryExpression expr)
    {
        assert(expr !is null);

        _writer.startElement("UnaryExpression", [XMLAttribute("Operator", operatorKindToString(expr.op.kind))]);

        _writer.startElement("Operand");
        printExpression(expr.operand);
        _writer.endElement();

        _writer.endElement();
    }

    private void doPrintExpression(BinaryExpression expr)
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

    private void doPrintExpression(CallExpression expr)
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
