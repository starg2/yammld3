
module yammld3.macros;

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
        import std.algorithm.iteration : map;
        import std.array : appender;

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

private struct ExpressionMacroParameter
{
    string name;
    SourceLocation location;
    Expression argument;
}

private struct ExpressionMacroDefinition
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

    public void compileExpressionMacroDefinitionCommand(ExpressionMacroDefinitionCommand c)
    {
        import std.array : appender, empty;

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

        _definedMacros[c.name.value] = def;
    }

    // Call saveContext() beforehand!
    public Expression expandExpressionMacro(T)(T c)
        if (is(T : ExpressionMacroInvocationExpression) || is(T : ExpressionMacroInvocationCommand))
    {
        import std.algorithm.searching : count;
        import std.range : lockstep;

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
                _definedMacros[param.name] = def;
            }
        }

        return definition;
    }

    public Expression expandExpressionMacroAndRestoreContext(T)(T c)
        if (is(T : ExpressionMacroInvocationExpression) || is(T : ExpressionMacroInvocationCommand))
    {
        auto context = saveContext();

        scope (exit)
        {
            restoreContext(context);
        }

        return expandExpressionMacro(c);
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
