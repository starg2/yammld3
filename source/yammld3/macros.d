
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

private struct ExpressionMacroDefinition
{
    string name;
    SourceLocation location;
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

        _definedMacros[c.name.value] = def;
    }

    // Call saveContext() beforehand!
    public Expression expandExpressionMacro(ExpressionMacroInvocationCommand c)
    {
        assert(c !is null);

        auto pDef = c.name.value in _definedMacros;

        if (pDef is null)
        {
            _diagnosticsHandler.undefinedExpressionMacro(c.location, c.name.value);
            return null;
        }

        if (c.arguments !is null)
        {
            _diagnosticsHandler.notImplemented(c.location, "expression macro with arguments");
            assert(false);
        }

        auto definition = pDef.definition;
        _definedMacros.remove(c.name.value);    // remove the current macro to avoid recursion
        return definition;
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
