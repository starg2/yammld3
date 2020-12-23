// Copyright (c) 2020 Starg.
// SPDX-License-Identifier: BSD-3-Clause

module yammld3.macros;

import std.algorithm.comparison : equal;
import std.algorithm.iteration : map;
import std.array;

import yammld3.ast;
import yammld3.common : AbsoluteOrRelative;
import yammld3.diagnostics : DiagnosticsHandler;
import yammld3.source : SourceLocation;

private struct NoteMacroDefinition
{
    string name;
    SourceLocation location;
    AbsoluteOrRelative!int[] keys;
}

package struct NoteMacroManagerContext
{
    NoteMacroDefinition[string] definedMacros;
}

package final class NoteMacroManager
{
    public this(DiagnosticsHandler handler)
    {
        _diagnosticsHandler = handler;
    }

    public void compileNoteMacroDefinitionCommand(NoteMacroDefinitionCommand c)
    {
        assert(c !is null);

        auto pPrevDef = c.name.value in _definedMacros;

        if (pPrevDef !is null)
        {
            _diagnosticsHandler.noteMacroRedefinition(
                c.location,
                c.name.value,
                pPrevDef.location
            );
        }

        NoteMacroDefinition def;
        def.name = c.name.value;
        def.location = c.location;
        def.keys = expandNoteMacros(c.definition);

        _definedMacros[c.name.value] = def;
    }

    public AbsoluteOrRelative!int[] expandNoteMacros(KeySpecifier[] kspArray)
    {
        auto keys = appender!(AbsoluteOrRelative!int[]);

        foreach (ksp; kspArray)
        {
            ksp.baseKey.visit!(
                (KeyLiteral kl)
                {
                    keys ~= AbsoluteOrRelative!int(ksp.octaveShift * 12 + cast(int)kl.keyName + ksp.accidental, true);
                },
                (AbsoluteKeyLiteral akl)
                {
                    keys ~= AbsoluteOrRelative!int(akl.key, false);
                },
                (NoteMacroReference nmr)
                {
                    auto pDef = nmr.name.value in _definedMacros;

                    if (pDef is null)
                    {
                        _diagnosticsHandler.undefinedNoteMacro(nmr.location, nmr.name.value);
                    }
                    else
                    {
                        keys ~= pDef.keys.map!(
                            x => AbsoluteOrRelative!int(
                                x.relative ? ksp.octaveShift * 12 + x.value + ksp.accidental : x.value,
                                x.relative
                            )
                        );
                    }
                }
            );
        }

        return keys[];
    }

    public NoteMacroManagerContext saveContext()
    {
        return NoteMacroManagerContext(_definedMacros.dup);
    }

    public void restoreContext(NoteMacroManagerContext c)
    {
        _definedMacros = c.definedMacros;
    }

    private DiagnosticsHandler _diagnosticsHandler;
    private NoteMacroDefinition[string] _definedMacros;
}

public struct ExpressionMacroParameter
{
    string name;
    SourceLocation location;
    Expression argument;
}

public struct ExpressionMacroDefinition
{
    string name;
    SourceLocation location;
    ExpressionMacroParameter[] parameters;
    Expression definition;
}

package struct ExpressionMacroManagerContext
{
    ExpressionMacroDefinition[string] definedMacros;
}

package final class ExpressionMacroManager
{
    public this(DiagnosticsHandler handler)
    {
        _diagnosticsHandler = handler;
    }

    public void defineExpressionMacro(ExpressionMacroDefinition def)
    {
        _definedMacros[def.name] = def;
    }

    public void compileExpressionMacroDefinitionCommand(ExpressionMacroDefinitionCommand c)
    {
        assert(c !is null);
        assert(c.definition !is null);

        auto pPrevDef = c.name.value in _definedMacros;

        if (pPrevDef !is null)
        {
            _diagnosticsHandler.expressionMacroRedefinition(
                c.location,
                c.name.value,
                pPrevDef.location
            );
        }

        ExpressionMacroDefinition def;
        def.name = c.name.value;
        def.location = c.location;
        def.definition = c.definition;

        if (c.parameters !is null && !c.parameters.items.empty)
        {
            auto items = c.parameters.items;
            auto paramAppender = appender(&def.parameters);
            paramAppender.reserve(items.length);
            bool foundDefArg = false;

            foreach (i; items)
            {
                auto nameNode = i.key !is null ? i.key : i.value;
                auto nameIdent = cast(Identifier)nameNode;

                if (nameIdent is null)
                {
                    _diagnosticsHandler.expectedIdentifier(nameNode.location, "expression macro parameter");
                }
                else
                {
                    if (i.key !is null)
                    {
                        foundDefArg = true;
                    }
                    else if (foundDefArg)
                    {
                        _diagnosticsHandler.expectedDefaultArgument(i.location, nameIdent.value);
                    }

                    paramAppender ~= ExpressionMacroParameter(
                        nameIdent.value,
                        i.location,
                        i.key !is null ? i.value : null
                    );
                }
            }
        }

        defineExpressionMacro(def);
    }

    // Call saveContext() beforehand!
    public Expression expandExpressionMacro(T)(T c)
        if (is(T : ExpressionMacroInvocationExpression) || is(T : ExpressionMacroInvocationCommand))
    {
        import std.algorithm.searching : count;

        assert(c !is null);

        auto pDef = c.name.value in _definedMacros;

        if (pDef is null)
        {
            _diagnosticsHandler.undefinedExpressionMacro(c.location, c.name.value);
            return null;
        }

        size_t minArgCount = pDef.parameters.count!(x => x.argument is null);
        ExpressionListItem[] args;

        if (c.arguments !is null)
        {
            args = c.arguments.items;

            if (pDef.parameters.length < args.length)
            {
                _diagnosticsHandler.wrongNumberOfArguments(
                    c.location,
                    "expression macro",
                    minArgCount,
                    pDef.parameters.length,
                    args.length
                );
            }

            foreach (i; args)
            {
                if (i.key !is null)
                {
                    _diagnosticsHandler.unexpectedArgument(i.location, "expression macro argument");
                }
            }
        }

        auto definition = pDef.definition;
        _definedMacros.remove(c.name.value);    // remove the current macro to avoid recursion

        auto actualArgs = appender!(ExpressionMacroDefinition[]);
        actualArgs.reserve(pDef.parameters.length);

        foreach (i, param; pDef.parameters)
        {
            if (i >= args.length && param.argument is null)
            {
                _diagnosticsHandler.expectedArgumentForExpressionMacro(
                    c.location,
                    pDef.name,
                    param.location,
                    param.name
                );
            }
            else
            {
                ExpressionMacroDefinition def;
                def.name = param.name;
                def.location = (i >= args.length ? param.location : args[i].location);
                def.definition = (i >= args.length ? param.argument : args[i].value);
                actualArgs ~= def;
            }
        }

        definition = expandMacroParameters(definition, actualArgs[]);

        foreach (def; actualArgs)
        {
            _definedMacros[def.name] = def;
        }

        return definition;
    }

    private Expression expandMacroParameters(T)(T expr, ExpressionMacroDefinition[] args)
        if (is(T == Expression))
    {
        assert(expr !is null);
        return expr.visit!(x => expandMacroParameters(x, args));
    }

    private Expression expandMacroParameters(T)(T expr, ExpressionMacroDefinition[] args)
        if (is(T : Expression) && !is(T == Expression))
    {
        return expr;
    }

    private CommandBlock expandMacroParameters(CommandBlock cb, ExpressionMacroDefinition[] args)
    {
        auto newCommands = cb.commands.map!(x => expandMacroParameters(x, args)).array;

        if (equal!((x, y) => x is y)(cb.commands, newCommands))
        {
            return cb;
        }
        else
        {
            return new CommandBlock(cb.location, newCommands);
        }
    }

    private Expression expandMacroParameters(ExpressionMacroInvocationExpression expr, ExpressionMacroDefinition[] args)
    {
        return doExpandMacroParametersForMacroInvocation!Expression(expr, args);
    }

    private Expression expandMacroParameters(UnaryExpression expr, ExpressionMacroDefinition[] args)
    {
        auto newOperand = expandMacroParameters(expr.operand, args);

        if (expr.operand is newOperand)
        {
            return expr;
        }
        else
        {
            return new UnaryExpression(expr.op, newOperand);
        }
    }

    private Expression expandMacroParameters(BinaryExpression expr, ExpressionMacroDefinition[] args)
    {
        auto newLeft = expandMacroParameters(expr.left, args);
        auto newRight = expandMacroParameters(expr.right, args);

        if (expr.left is newLeft && expr.right is newRight)
        {
            return expr;
        }
        else
        {
            return new BinaryExpression(expr.op, newLeft, newRight);
        }
    }

    private Expression expandMacroParameters(CallExpression expr, ExpressionMacroDefinition[] args)
    {
        auto newCallee = expandMacroParameters(expr.callee, args);
        auto newParameters = expandMacroParameters(expr.parameters, args);

        if (expr.callee is newCallee && expr.parameters is newParameters)
        {
            return expr;
        }
        else
        {
            return new CallExpression(newCallee, newParameters);
        }
    }

    private ExpressionList expandMacroParameters(ExpressionList exprList, ExpressionMacroDefinition[] args)
    {
        auto newItems = exprList.items.map!(x => expandMacroParameters(x, args)).array;

        if (equal!((x, y) => x is y)(exprList.items, newItems))
        {
            return exprList;
        }
        else
        {
            return new ExpressionList(exprList.location, newItems);
        }
    }

    private ExpressionListItem expandMacroParameters(ExpressionListItem item, ExpressionMacroDefinition[] args)
    {
        auto newKey = item.key !is null ? expandMacroParameters(item.key, args) : null;
        auto newValue = expandMacroParameters(item.value, args);

        if (item.key is newKey && item.value is newValue)
        {
            return item;
        }
        else
        {
            return new ExpressionListItem(newKey, newValue);
        }
    }

    private Command expandMacroParameters(T)(T c, ExpressionMacroDefinition[] args)
        if (is(T == Command))
    {
        assert(c !is null);
        return c.visit!(x => expandMacroParameters(x, args));
    }

    private Command expandMacroParameters(BasicCommand c, ExpressionMacroDefinition[] args)
    {
        auto newArg = c.argument !is null ? expandMacroParameters(c.argument, args) : null;

        if (c.argument is newArg)
        {
            return c;
        }
        else
        {
            return new BasicCommand(c.location, c.name, c.sign, newArg);
        }
    }

    private Command expandMacroParameters(NoteCommand c, ExpressionMacroDefinition[] args)
    {
        auto newDuration = c.duration !is null ? expandMacroParameters(c.duration, args) : null;

        if (c.duration is newDuration)
        {
            return c;
        }
        else
        {
            return new NoteCommand(c.location, c.keys, newDuration);
        }
    }

    private Command expandMacroParameters(ExtensionCommand c, ExpressionMacroDefinition[] args)
    {
        //auto newName = expandMacroParameters(c.name, args);
        auto newArgs = c.arguments !is null ? expandMacroParameters(c.arguments, args) : null;
        auto newBlock = c.block !is null ? expandMacroParameters(c.block, args) : null;

        if (c.arguments is newArgs && c.block is newBlock)
        {
            return c;
        }
        else
        {
            return new ExtensionCommand(c.location, c.name, newArgs, newBlock);
        }
    }

    private Command expandMacroParameters(T)(T c, ExpressionMacroDefinition[] args)
        if (is(T == ScopedCommand) || is(T == UnscopedCommand))
    {
        auto newCommands = c.commands.map!(x => x.visit!(y => expandMacroParameters(y, args))).array;

        if (equal!((x, y) => x is y)(c.commands, newCommands))
        {
            return c;
        }
        else
        {
            return new T(c.location, newCommands);
        }
    }

    private Command expandMacroParameters(ModifierCommand c, ExpressionMacroDefinition[] args)
    {
        auto newCommand = c.command.visit!(x => expandMacroParameters(x, args));
        //auto newName = expandMacroParameters(c.name, args);
        auto newArgs = c.arguments !is null ? expandMacroParameters(c.arguments, args) : null;

        if (c.command is newCommand && c.arguments is newArgs)
        {
            return c;
        }
        else
        {
            return new ModifierCommand(c.location, newCommand, c.name, newArgs);
        }
    }

    private Command expandMacroParameters(RepeatCommand c, ExpressionMacroDefinition[] args)
    {
        auto newCommand = c.command.visit!(x => expandMacroParameters(x, args));
        auto newRepeatCount = c.repeatCount.visit!(x => expandMacroParameters(x, args));

        if (c.command is newCommand && c.repeatCount is newRepeatCount)
        {
            return c;
        }
        else
        {
            return new RepeatCommand(c.location, newCommand, newRepeatCount);
        }
    }

    private Command expandMacroParameters(NoteMacroDefinitionCommand c, ExpressionMacroDefinition[] args)
    {
        return c;
    }

    private bool hasSameNames(ExpressionListItem item, ExpressionMacroDefinition def)
    {
        auto ident = cast(Identifier)(item.key !is null ? item.key : item.value);
        return ident !is null && ident.value == def.name;
    }

    private Command expandMacroParameters(ExpressionMacroDefinitionCommand c, ExpressionMacroDefinition[] args)
    {
        import std.algorithm.iteration : filter;
        import std.algorithm.searching : canFind;

        //auto newName = expandMacroParameters(c.name, args);
        auto newParameters = c.parameters !is null ? expandMacroParameters(c.parameters, args) : null;
        auto newDefinition = c.definition.visit!(
            x => expandMacroParameters(x, args.filter!(y => !(c.parameters !is null && c.parameters.items.canFind!(z => hasSameNames(z, y)))).array)
        );

        if (c.parameters is newParameters && c.definition is newDefinition)
        {
            return c;
        }
        else
        {
            return new ExpressionMacroDefinitionCommand(c.location, c.name, newParameters, newDefinition);
        }
    }

    private Command expandMacroParameters(ExpressionMacroInvocationCommand c, ExpressionMacroDefinition[] args)
    {
        return doExpandMacroParametersForMacroInvocation!Command(c, args);
    }

    private Base doExpandMacroParametersForMacroInvocation(Base, T)(T invocation, ExpressionMacroDefinition[] args)
        if (is(T : ExpressionMacroInvocationExpression) || is(T : ExpressionMacroInvocationCommand))
    {
        import std.algorithm.searching : find;

        //auto newName = expandMacroParameters(invocation.name, args);
        auto matched = args.find!(x => x.name == invocation.name.value);

        if (!matched.empty)
        {
            if (invocation.arguments is null)
            {
                static if (is(T : Command))
                {
                    auto cb = cast(CommandBlock)matched.front.definition;

                    if (cb is null)
                    {
                        _diagnosticsHandler.expressionMacroNotExpandedToCommandBlock(invocation.location, invocation.name.value);
                    }
                    else
                    {
                        return new UnscopedCommand(cb.location, cb.commands);
                    }
                }
                else
                {
                    return matched.front.definition;
                }
            }
            else
            {
                _diagnosticsHandler.wrongNumberOfArguments(
                    invocation.location,
                    "expression macro",
                    0,
                    invocation.arguments.items.length
                );
            }
        }

        auto newArgs = invocation.arguments !is null ? expandMacroParameters(invocation.arguments, args) : null;

        if (invocation.arguments is newArgs)
        {
            return invocation;
        }
        else
        {
            return new T(invocation.location, invocation.name, newArgs);
        }
    }

    public ExpressionMacroManagerContext saveContext()
    {
        return ExpressionMacroManagerContext(_definedMacros.dup);
    }

    public void restoreContext(ExpressionMacroManagerContext c)
    {
        _definedMacros = c.definedMacros;
    }

    private DiagnosticsHandler _diagnosticsHandler;
    private ExpressionMacroDefinition[string] _definedMacros;
}
