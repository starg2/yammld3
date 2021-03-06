// Copyright (c) 2020 Starg.
// SPDX-License-Identifier: BSD-3-Clause

module yammld3.ast;

import yammld3.source : SourceLocation;

public interface ASTNode
{
    @property SourceLocation location();
}

// ---------------------
// Expression

public enum OperatorKind
{
    plus,
    minus,
    star,
    slash,
    logicalNot,
    lessThan,
    greaterThan,
    lessThanOrEqual,
    greaterThanOrEqual,
    equal,
    notEqual,
    logicalAnd,
    logicalOr
}

public final class Operator : ASTNode
{
    public this(SourceLocation loc, OperatorKind kind)
    {
        _loc = loc;
        _kind = kind;
    }

    public override @property SourceLocation location()
    {
        return _loc;
    }

    public @property OperatorKind kind()
    {
        return _kind;
    }

    private SourceLocation _loc;
    private OperatorKind _kind;
}

public enum ExpressionKind
{
    identifier,
    integerLiteral,
    floatLiteral,
    stringLiteral,
    timeLiteral,
    durationLiteral,
    commandBlock,
    expressionMacroInvocation,
    unaryExpression,
    binaryExpression,
    callExpression
}

public interface Expression : ASTNode
{
    @property ExpressionKind kind();
}

public final class Identifier : Expression
{
    public this(SourceLocation loc, string value)
    {
        assert(value !is null);

        _loc = loc;
        _value = value;
    }

    public override @property SourceLocation location()
    {
        return _loc;
    }

    public override @property ExpressionKind kind()
    {
        return ExpressionKind.identifier;
    }

    public @property string value()
    {
        return _value;
    }

    private SourceLocation _loc;
    private string _value;
}

public final class IntegerLiteral : Expression
{
    public this(SourceLocation loc, int value)
    {
        _loc = loc;
        _value = value;
    }

    public override @property SourceLocation location()
    {
        return _loc;
    }

    public override @property ExpressionKind kind()
    {
        return ExpressionKind.integerLiteral;
    }

    public @property int value()
    {
        return _value;
    }

    private SourceLocation _loc;
    private int _value;
}

public final class FloatLiteral : Expression
{
    public this(SourceLocation loc, float value)
    {
        _loc = loc;
        _value = value;
    }

    public override @property SourceLocation location()
    {
        return _loc;
    }

    public override @property ExpressionKind kind()
    {
        return ExpressionKind.floatLiteral;
    }

    public @property float value()
    {
        return _value;
    }

    private SourceLocation _loc;
    private float _value;
}

public final class StringLiteral : Expression
{
    public this(SourceLocation loc, string value)
    {
        _loc = loc;
        _value = value;
    }

    public override @property SourceLocation location()
    {
        return _loc;
    }

    public override @property ExpressionKind kind()
    {
        return ExpressionKind.stringLiteral;
    }

    public @property string value()
    {
        return _value;
    }

    private SourceLocation _loc;
    private string _value;
}

public final class TimeLiteral : Expression
{
    import yammld3.common : Time;

    public this(SourceLocation loc, Time t)
    {
        _loc = loc;
        _time = t;
    }

    public this(SourceLocation loc, int m, int b, int t)
    {
        _loc = loc;
        _time.measures = m;
        _time.beats = b;
        _time.ticks = t;
    }

    public override @property SourceLocation location()
    {
        return _loc;
    }

    public override @property ExpressionKind kind()
    {
        return ExpressionKind.timeLiteral;
    }

    public @property Time time()
    {
        return _time;
    }

    public @property int measures()
    {
        return _time.measures;
    }

    public @property int beats()
    {
        return _time.beats;
    }

    public @property int ticks()
    {
        return _time.ticks;
    }

    private SourceLocation _loc;
    private Time _time;
}

public final class DurationLiteral : Expression
{
    public this(SourceLocation loc, int denom, int dot)
    {
        _loc = loc;
        _denominator = denom;
        _dot = dot;
    }

    public override @property SourceLocation location()
    {
        return _loc;
    }

    public override @property ExpressionKind kind()
    {
        return ExpressionKind.durationLiteral;
    }

    public @property int denominator()
    {
        return _denominator;
    }

    public @property int dot()
    {
        return _dot;
    }

    private SourceLocation _loc;
    private int _denominator;
    private int _dot;
}

public final class CommandBlock : Expression
{
    public this(SourceLocation loc, Command[] commands)
    {
        _loc = loc;
        _commands = commands;
    }

    public override @property SourceLocation location()
    {
        return _loc;
    }

    public override @property ExpressionKind kind()
    {
        return ExpressionKind.commandBlock;
    }

    public @property Command[] commands()
    {
        return _commands;
    }

    private SourceLocation _loc;
    private Command[] _commands;
}

private final class ExpressionMacroInvocationNode(Base, alias nodeKind) : Base
{
    public this(SourceLocation loc, ExpressionMacroName name, ExpressionList arguments)
    {
        assert(name !is null);

        _loc = loc;
        _name = name;
        _arguments = arguments;
    }

    public override @property SourceLocation location()
    {
        return _loc;
    }

    public override @property typeof(nodeKind) kind()
    {
        return nodeKind;
    }

    public @property ExpressionMacroName name()
    {
        return _name;
    }

    public @property ExpressionList arguments()
    {
        return _arguments;
    }

    private SourceLocation _loc;
    private ExpressionMacroName _name;
    private ExpressionList _arguments;
}

public alias ExpressionMacroInvocationExpression = ExpressionMacroInvocationNode!(Expression, ExpressionKind.expressionMacroInvocation);

// prefix expression only
public final class UnaryExpression : Expression
{
    public this(Operator op, Expression operand)
    {
        assert(op !is null);
        assert(operand !is null);

        this(SourceLocation(op.location, operand.location), op, operand);
    }

    public this(SourceLocation loc, Operator op, Expression operand)
    {
        assert(op !is null);
        assert(operand !is null);

        _loc = loc;
        _op = op;
        _operand = operand;
    }

    public override @property SourceLocation location()
    {
        return _loc;
    }

    public override @property ExpressionKind kind()
    {
        return ExpressionKind.unaryExpression;
    }

    public @property Operator op()
    {
        return _op;
    }

    public @property Expression operand()
    {
        return _operand;
    }

    private SourceLocation _loc;
    private Operator _op;
    private Expression _operand;
}

public final class BinaryExpression : Expression
{
    public this(Operator op, Expression left, Expression right)
    {
        assert(op !is null);
        assert(left !is null);
        assert(right !is null);

        this(SourceLocation(left.location, right.location), op, left, right);
    }

    public this(SourceLocation loc, Operator op, Expression left, Expression right)
    {
        assert(op !is null);
        assert(left !is null);
        assert(right !is null);

        _loc = loc;
        _op = op;
        _left = left;
        _right = right;
    }

    public override @property SourceLocation location()
    {
        return _loc;
    }

    public override @property ExpressionKind kind()
    {
        return ExpressionKind.binaryExpression;
    }

    public @property Operator op()
    {
        return _op;
    }

    public @property Expression left()
    {
        return _left;
    }

    public @property Expression right()
    {
        return _right;
    }

    private SourceLocation _loc;
    private Operator _op;
    private Expression _left;
    private Expression _right;
}

public final class CallExpression : Expression
{
    public this(Expression callee, ExpressionList parameters)
    {
        assert(callee !is null);
        assert(parameters !is null);

        this(SourceLocation(_callee.location, _parameters.location), callee, parameters);
    }

    public this(SourceLocation loc, Expression callee, ExpressionList parameters)
    {
        assert(callee !is null);
        assert(parameters !is null);

        _loc = loc;
        _callee = callee;
        _parameters = parameters;
    }

    public override @property SourceLocation location()
    {
        return _loc;
    }

    public override @property ExpressionKind kind()
    {
        return ExpressionKind.callExpression;
    }

    public @property Expression callee()
    {
        return _callee;
    }

    public @property ExpressionList parameters()
    {
        return _parameters;
    }

    private SourceLocation _loc;
    private Expression _callee;
    private ExpressionList _parameters;
}

public auto visit(Handlers...)(Expression expr)
{
    assert(expr !is null);

    static struct Overloaded
    {
        static foreach (h; Handlers)
        {
            alias opCall = h;
        }
    }

    final switch (expr.kind)
    {
    case ExpressionKind.identifier:
        return Overloaded(cast(Identifier)expr);

    case ExpressionKind.integerLiteral:
        return Overloaded(cast(IntegerLiteral)expr);

    case ExpressionKind.floatLiteral:
        return Overloaded(cast(FloatLiteral)expr);

    case ExpressionKind.stringLiteral:
        return Overloaded(cast(StringLiteral)expr);

    case ExpressionKind.timeLiteral:
        return Overloaded(cast(TimeLiteral)expr);

    case ExpressionKind.durationLiteral:
        return Overloaded(cast(DurationLiteral)expr);

    case ExpressionKind.commandBlock:
        return Overloaded(cast(CommandBlock)expr);

    case ExpressionKind.expressionMacroInvocation:
        return Overloaded(cast(ExpressionMacroInvocationExpression)expr);

    case ExpressionKind.unaryExpression:
        return Overloaded(cast(UnaryExpression)expr);

    case ExpressionKind.binaryExpression:
        return Overloaded(cast(BinaryExpression)expr);

    case ExpressionKind.callExpression:
        return Overloaded(cast(CallExpression)expr);
    }
}

public final class ExpressionListItem : ASTNode
{
    public this(Expression value)
    {
        assert(value !is null);

        _key = null;
        _value = value;
    }

    public this(Expression key, Expression value)
    {
        // key may be null
        assert(value !is null);

        _key = key;
        _value = value;
    }

    public override @property SourceLocation location()
    {
        return _key is null ? _value.location : SourceLocation(_key.location, _value.location);
    }

    public @property Expression key()
    {
        return _key;
    }

    public @property Expression value()
    {
        return _value;
    }

    private Expression _key;
    private Expression _value;
}

public final class ExpressionList : ASTNode
{
    public this(SourceLocation loc, ExpressionListItem[] items)
    {
        _loc = loc;
        _items = items;
    }

    public override @property SourceLocation location()
    {
        return _loc;
    }

    public @property ExpressionListItem[] items()
    {
        return _items;
    }

    private SourceLocation _loc;
    private ExpressionListItem[] _items;
}

// ---------------------
// BaseKeySpecifier

public final class NoteMacroName : ASTNode
{
    public this(SourceLocation loc, string value)
    {
        assert(value !is null);

        _loc = loc;
        _value = value;
    }

    public override @property SourceLocation location()
    {
        return _loc;
    }

    public @property string value()
    {
        return _value;
    }

    private SourceLocation _loc;
    private string _value;
}

public enum BaseKeySpecifierKind
{
    keyLiteral,
    absoluteKeyLiteral,
    noteMacroReference
}

public interface BaseKeySpecifier : ASTNode
{
    @property BaseKeySpecifierKind kind();
}

public final class KeyLiteral : BaseKeySpecifier
{
    import yammld3.common : KeyName;

    public this(SourceLocation loc, KeyName keyName)
    {
        _loc = loc;
        _keyName = keyName;
    }

    public override @property SourceLocation location()
    {
        return _loc;
    }

    public override @property BaseKeySpecifierKind kind()
    {
        return BaseKeySpecifierKind.keyLiteral;
    }

    public @property KeyName keyName()
    {
        return _keyName;
    }

    private SourceLocation _loc;
    private KeyName _keyName;
}

public final class AbsoluteKeyLiteral : BaseKeySpecifier
{
    public this(SourceLocation loc, int key)
    {
        _loc = loc;
        _key = key;
    }

    public override @property SourceLocation location()
    {
        return _loc;
    }

    public override @property BaseKeySpecifierKind kind()
    {
        return BaseKeySpecifierKind.absoluteKeyLiteral;
    }

    public @property int key()
    {
        return _key;
    }

    private SourceLocation _loc;
    private int _key;
}

public final class NoteMacroReference : BaseKeySpecifier
{
    public this(NoteMacroName name)
    {
        assert(name !is null);
        _name = name;
    }

    public override @property SourceLocation location()
    {
        return _name.location;
    }

    public override @property BaseKeySpecifierKind kind()
    {
        return BaseKeySpecifierKind.noteMacroReference;
    }

    public @property NoteMacroName name()
    {
        return _name;
    }

    private NoteMacroName _name;
}

public auto visit(Handlers...)(BaseKeySpecifier baseKey)
{
    assert(baseKey !is null);

    static struct Overloaded
    {
        static foreach (h; Handlers)
        {
            alias opCall = h;
        }
    }

    final switch (baseKey.kind)
    {
    case BaseKeySpecifierKind.keyLiteral:
        return Overloaded(cast(KeyLiteral)baseKey);

    case BaseKeySpecifierKind.absoluteKeyLiteral:
        return Overloaded(cast(AbsoluteKeyLiteral)baseKey);

    case BaseKeySpecifierKind.noteMacroReference:
        return Overloaded(cast(NoteMacroReference)baseKey);
    }
}

// ---------------------
// Command

public enum CommandKind
{
    basic,
    note,
    extension,
    scoped,
    unscoped,
    modifier,
    repeat,
    tableBlock,
    noteMacroDefinition,
    expressionMacroDefinition,
    expressionMacroInvocation
}

public interface Command : ASTNode
{
    @property CommandKind kind();
}

public final class BasicCommand : Command
{
    import yammld3.common : OptionalSign;

    public this(SourceLocation loc, string name, OptionalSign sign, Expression argument)
    {
        // argument may be null

        _loc = loc;
        _name = name;
        _sign = sign;
        _argument = argument;
    }

    public override @property SourceLocation location()
    {
        return _loc;
    }

    public override @property CommandKind kind()
    {
        return CommandKind.basic;
    }

    public @property string name()
    {
        return _name;
    }

    public @property OptionalSign sign()
    {
        return _sign;
    }

    public @property Expression argument()
    {
        return _argument;
    }

    private SourceLocation _loc;
    private string _name;
    private OptionalSign _sign;
    private Expression _argument;
}

public final class KeySpecifier : ASTNode
{
    public this(SourceLocation loc, int octaveShift, BaseKeySpecifier baseKey, int accidental)
    {
        _loc = loc;
        _octaveShift = octaveShift;
        _baseKey = baseKey;
        _accidental = accidental;
    }

    public override @property SourceLocation location()
    {
        return _loc;
    }

    public @property int octaveShift()
    {
        return _octaveShift;
    }

    public @property BaseKeySpecifier baseKey()
    {
        return _baseKey;
    }

    public @property int accidental()
    {
        return _accidental;
    }

    private SourceLocation _loc;
    private int _octaveShift;
    private BaseKeySpecifier _baseKey;
    private int _accidental;
}

public final class NoteCommand : Command
{
    public this(SourceLocation loc, KeySpecifier[] keys, Expression duration)
    {
        // duration may be null

        _loc = loc;
        _keys = keys;
        _duration = duration;
    }

    public override @property SourceLocation location()
    {
        return _loc;
    }

    public override @property CommandKind kind()
    {
        return CommandKind.note;
    }

    public @property KeySpecifier[] keys()
    {
        return _keys;
    }

    public @property Expression duration()
    {
        return _duration;
    }

    private SourceLocation _loc;
    private KeySpecifier[] _keys;
    private Expression _duration;
}

public final class ExtensionCommand : Command
{
    public this(SourceLocation loc, Identifier name, ExpressionList arguments, CommandBlock block)
    {
        assert(name !is null);
        // arguments may be null
        // block may be null

        _loc = loc;
        _name = name;
        _arguments = arguments;
        _block = block;
    }

    public override @property SourceLocation location()
    {
        return _loc;
    }

    public override @property CommandKind kind()
    {
        return CommandKind.extension;
    }

    public @property Identifier name()
    {
        return _name;
    }

    public @property ExpressionList arguments()
    {
        return _arguments;
    }

    public @property CommandBlock block()
    {
        return _block;
    }

    private SourceLocation _loc;
    private Identifier _name;
    private ExpressionList _arguments;
    private CommandBlock _block;
}

public final class ScopedCommand : Command
{
    public this(SourceLocation loc, Command[] commands)
    {
        _loc = loc;
        _commands = commands;
    }

    public override @property SourceLocation location()
    {
        return _loc;
    }

    public override @property CommandKind kind()
    {
        return CommandKind.scoped;
    }

    public @property Command[] commands()
    {
        return _commands;
    }

    private SourceLocation _loc;
    private Command[] _commands;
}

// Never generated by Parser
// Can only be generated by macro expansion
public final class UnscopedCommand : Command
{
    public this(SourceLocation loc, Command[] commands)
    {
        _loc = loc;
        _commands = commands;
    }

    public override @property SourceLocation location()
    {
        return _loc;
    }

    public override @property CommandKind kind()
    {
        return CommandKind.unscoped;
    }

    public @property Command[] commands()
    {
        return _commands;
    }

    private SourceLocation _loc;
    private Command[] _commands;
}

public final class ModifierCommand : Command
{
    public this(SourceLocation loc, Command c, Identifier name, ExpressionList arguments)
    {
        assert(c !is null);
        assert(name !is null);
        // arguments may be null

        _loc = loc;
        _command = c;
        _name = name;
        _arguments = arguments;
    }

    public override @property SourceLocation location()
    {
        return _loc;
    }

    public override @property CommandKind kind()
    {
        return CommandKind.modifier;
    }

    public @property Command command()
    {
        return _command;
    }

    public @property Identifier name()
    {
        return _name;
    }

    public @property ExpressionList arguments()
    {
        return _arguments;
    }

    private SourceLocation _loc;
    private Command _command;
    private Identifier _name;
    private ExpressionList _arguments;
}

public final class RepeatCommand : Command
{
    public this(SourceLocation loc, Command command, Expression repeatCount)
    {
        assert(command !is null);
        // repeatCount may be null

        _loc = loc;
        _command = command;
        _repeatCount = repeatCount;
    }

    public override @property SourceLocation location()
    {
        return _loc;
    }

    public override @property CommandKind kind()
    {
        return CommandKind.repeat;
    }

    public @property Command command()
    {
        return _command;
    }

    public @property Expression repeatCount()
    {
        return _repeatCount;
    }

    private SourceLocation _loc;
    private Command _command;
    private Expression _repeatCount;
}

public final class TableBlockRow : ASTNode
{
    public this(SourceLocation loc, Command[] commands)
    {
        _loc = loc;
        _commands = commands;
    }

    public override @property SourceLocation location()
    {
        return _loc;
    }

    public @property Command[] commands()
    {
        return _commands;
    }

    private SourceLocation _loc;
    private Command[] _commands;
}

public final class TableBlockCommand : Command
{
    public this(TableBlockRow[] rows)
    {
        assert(rows.length > 0);
        _rows = rows;
    }

    public override @property SourceLocation location()
    {
        return _rows[0].location;
    }

    public override @property CommandKind kind()
    {
        return CommandKind.tableBlock;
    }

    public @property TableBlockRow[] rows()
    {
        return _rows;
    }

    private TableBlockRow[] _rows;
}

public final class NoteMacroDefinitionCommand : Command
{
    public this(SourceLocation loc, NoteMacroName name, KeySpecifier[] definition)
    {
        assert(name !is null);
        assert(definition !is null);

        _loc = loc;
        _name = name;
        _definition = definition;
    }

    public override @property SourceLocation location()
    {
        return _loc;
    }

    public override @property CommandKind kind()
    {
        return CommandKind.noteMacroDefinition;
    }

    public @property NoteMacroName name()
    {
        return _name;
    }

    public @property KeySpecifier[] definition()
    {
        return _definition;
    }

    private SourceLocation _loc;
    private NoteMacroName _name;
    private KeySpecifier[] _definition;
}

public final class ExpressionMacroName : ASTNode
{
    public this(SourceLocation loc, string value)
    {
        assert(value !is null);

        _loc = loc;
        _value = value;
    }

    public override @property SourceLocation location()
    {
        return _loc;
    }

    public @property string value()
    {
        return _value;
    }

    private SourceLocation _loc;
    private string _value;
}

public final class ExpressionMacroDefinitionCommand : Command
{
    public this(SourceLocation loc, ExpressionMacroName name, ExpressionList parameters, Expression definition)
    {
        assert(name !is null);
        assert(definition !is null);

        _loc = loc;
        _name = name;
        _parameters = parameters;
        _definition = definition;
    }

    public override @property SourceLocation location()
    {
        return _loc;
    }

    public override @property CommandKind kind()
    {
        return CommandKind.expressionMacroDefinition;
    }

    public @property ExpressionMacroName name()
    {
        return _name;
    }

    public @property ExpressionList parameters()
    {
        return _parameters;
    }

    public @property Expression definition()
    {
        return _definition;
    }

    private SourceLocation _loc;
    private ExpressionMacroName _name;
    private ExpressionList _parameters;
    private Expression _definition;
}

public alias ExpressionMacroInvocationCommand = ExpressionMacroInvocationNode!(Command, CommandKind.expressionMacroInvocation);

public auto visit(Handlers...)(Command c)
{
    assert(c !is null);

    static struct Overloaded
    {
        static foreach (h; Handlers)
        {
            alias opCall = h;
        }
    }

    final switch (c.kind)
    {
    case CommandKind.basic:
        return Overloaded(cast(BasicCommand)c);

    case CommandKind.note:
        return Overloaded(cast(NoteCommand)c);

    case CommandKind.extension:
        return Overloaded(cast(ExtensionCommand)c);

    case CommandKind.scoped:
        return Overloaded(cast(ScopedCommand)c);

    case CommandKind.unscoped:
        return Overloaded(cast(UnscopedCommand)c);

    case CommandKind.modifier:
        return Overloaded(cast(ModifierCommand)c);

    case CommandKind.repeat:
        return Overloaded(cast(RepeatCommand)c);

    case CommandKind.tableBlock:
        return Overloaded(cast(TableBlockCommand)c);

    case CommandKind.noteMacroDefinition:
        return Overloaded(cast(NoteMacroDefinitionCommand)c);

    case CommandKind.expressionMacroDefinition:
        return Overloaded(cast(ExpressionMacroDefinitionCommand)c);

    case CommandKind.expressionMacroInvocation:
        return Overloaded(cast(ExpressionMacroInvocationCommand)c);
    }
}

// ---------------------
// Module

public final class Module
{
    public this(string name, Command[] commands)
    {
        _name = name;
        _commands = commands;
    }

    public @property string name()
    {
        return _name;
    }

    public @property Command[] commands()
    {
        return _commands;
    }

    private string _name;
    private Command[] _commands;
}
