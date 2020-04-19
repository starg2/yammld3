
module yammld3.macros;

import yammld3.ast;
import yammld3.diagnostics : DiagnosticsHandler;
import yammld3.source : SourceLocation;

private struct NoteMacroDefinition
{
    string name;
    SourceLocation location;
    int[] keys;
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

    public int[] expandNoteMacros(KeySpecifier[] kspArray)
    {
        import std.algorithm.iteration : map;
        import std.array : appender;

        auto keys = appender!(int[]);

        foreach (ksp; kspArray)
        {
            ksp.baseKey.visit!(
                (KeyLiteral kl)
                {
                    keys.put(ksp.octaveShift * 12 + cast(int)kl.keyName + ksp.accidental);
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
                        keys.put(pDef.keys.map!(x => ksp.octaveShift * 12 + x + ksp.accidental));
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
