
module yammld3.templates;

import std.range.primitives;

import yammld3.ast;
import yammld3.source : SourceLocation;

private struct TemplateParameter
{
    string name;
    SourceLocation location;
}

private struct TemplateDefinition
{
    string name;
    SourceLocation location;
    TemplateParameter[] parameters;
    Command[] definition;
}

package struct TemplateManagerContext
{
    TemplateDefinition[string] definedTemplates;
}

package final class TemplateManager
{
    import std.algorithm.searching : canFind, find;

    import yammld3.diagnostics : DiagnosticsHandler;

    public this(DiagnosticsHandler handler)
    {
        _diagnosticsHandler = handler;
    }

    public void compileDefineTemplateCommand(ExtensionCommand c)
    {
        assert(c !is null);
        assert(c.name.value == "template");

        if (c.block is null)
        {
            _diagnosticsHandler.expectedCommandBlock(c.location, "%" ~ c.name.value);
            return;
        }

        if (!hasSingleIdentifierInExpressionList(c))
        {
            return;
        }

        auto ident = cast(Identifier)c.arguments.items[0].value;
        assert(ident !is null);

        auto pPrevDefined = ident.value in _definedTemplates;

        if (pPrevDefined !is null)
        {
            _diagnosticsHandler.templateRedefinition(c.location, ident.value, pPrevDefined.location);
            return;
        }

        auto commands = c.block.commands;
        auto parameters = extractTemplateParameters(commands);
        _definedTemplates[ident.value] = TemplateDefinition(ident.value, c.location, parameters, commands);
    }

    // Call saveContext() beforehand!
    public Command[] compileExpandTemplateCommand(ExtensionCommand c)
    {
        assert(c !is null);
        assert(c.name.value == "expand");

        if (!hasSingleIdentifierInExpressionList(c))
        {
            return null;
        }

        auto ident = cast(Identifier)c.arguments.items[0].value;
        assert(ident !is null);

        auto pDefinition = ident.value in _definedTemplates;

        if (pDefinition is null)
        {
            _diagnosticsHandler.undefinedTemplate(c.location, ident.value);
            return null;
        }

        auto paramDefs = extractTemplateParameterDefinitions(c);

        if (!verifyParameters(pDefinition, paramDefs))
        {
            return null;
        }

        addDefaultParameterDefinitions(pDefinition, paramDefs);

        // Remove the definition of the current template to avoid recursion.
        _definedTemplates.remove(ident.value);

        foreach (pd; paramDefs)
        {
            _definedTemplates[pd.name] = pd;
        }

        return pDefinition.definition;
    }

    public TemplateManagerContext saveContext()
    {
        return TemplateManagerContext(_definedTemplates.dup);
    }

    public void restoreContext(TemplateManagerContext c)
    {
        _definedTemplates = c.definedTemplates;
    }

    private bool hasSingleIdentifierInExpressionList(ExtensionCommand c)
    {
        if (c.arguments is null)
        {
            _diagnosticsHandler.expectedArgumentList(c.location, "%" ~ c.name.value);
            return false;
        }

        if (c.arguments.items.length != 1)
        {
            _diagnosticsHandler.wrongNumberOfArguments(c.arguments.location, "%" ~ c.name.value, 1, c.arguments.items.length);
            return false;
        }

        if (c.arguments.items[0].key !is null)
        {
            _diagnosticsHandler.unexpectedArgument(c.arguments.items[0].key.location, "%" ~ c.name.value);
            return false;
        }

        if (c.arguments.items[0].value.kind != ExpressionKind.identifier)
        {
            _diagnosticsHandler.unexpectedExpressionKind(c.arguments.items[0].value.location, "%" ~ c.name.value);
            return false;
        }

        return true;
    }

    private TemplateParameter[] extractTemplateParameters(ref Command[] commands)
    {
        TemplateParameter[] params;

        while (!commands.empty)
        {
            auto ec = cast(ExtensionCommand)commands.front;

            if (ec is null || ec.name.value != "param")
            {
                break;
            }

            commands.popFront();

            if (hasSingleIdentifierInExpressionList(ec))
            {
                auto ident = cast(Identifier)ec.arguments.items[0].value;
                assert(ident !is null);

                auto paramWithSameName = params.find!(x => x.name == ident.value);

                if (!paramWithSameName.empty)
                {
                    _diagnosticsHandler.parameterRedefinition(ec.location, ident.value, paramWithSameName.front.location);
                }
                else
                {
                    if (ec.block !is null)
                    {
                        _diagnosticsHandler.unexpectedCommandBlock(ec.location, "%" ~ ec.name.value);
                    }

                    params ~= TemplateParameter(ident.value, ec.location);
                }
            }
        }

        return params;
    }

    private TemplateDefinition[] extractTemplateParameterDefinitions(ExtensionCommand c)
    {
        assert(c !is null);

        TemplateDefinition[] defs;

        if (c.block !is null)
        {
            foreach (child; c.block.commands)
            {
                auto ec = cast(ExtensionCommand)child;

                if (ec !is null && ec.name.value == "with_param")
                {
                    if (hasSingleIdentifierInExpressionList(ec))
                    {
                        auto ident = cast(Identifier)ec.arguments.items[0].value;
                        assert(ident !is null);

                        auto dupDef = defs.find!(x => x.name == ident.value);

                        if (!dupDef.empty)
                        {
                            _diagnosticsHandler.parameterRedefinition(ec.location, ident.value, dupDef.front.location);
                        }
                        else
                        {
                            defs ~= TemplateDefinition(ident.value, ec.location, null, ec.block is null ? null : ec.block.commands);
                        }
                    }
                }
                else
                {
                    _diagnosticsHandler.unexpectedCommandInCommand(child.location, "%" ~ c.name.value, "%with_param");
                }
            }
        }

        return defs;
    }

    private bool verifyParameters(TemplateDefinition* pDefinition, TemplateDefinition[] paramDefs)
    {
        assert(pDefinition !is null);
        bool valid = true;

        foreach (pd; paramDefs)
        {
            if (!pDefinition.parameters.canFind!(x => x.name == pd.name))
            {
                _diagnosticsHandler.undefinedTemplateParameter(pd.location, pd.name, pDefinition.name, pDefinition.location);
                valid = false;
            }
        }

        return valid;
    }

    private void addDefaultParameterDefinitions(TemplateDefinition* pDefinition, ref TemplateDefinition[] paramDefs)
    {
        assert(pDefinition !is null);

        foreach (pm; pDefinition.parameters)
        {
            if (!paramDefs.canFind!(x => x.name == pm.name))
            {
                // add empty definition
                paramDefs ~= TemplateDefinition(pm.name, pm.location, null, null);
            }
        }
    }

    private DiagnosticsHandler _diagnosticsHandler;
    private TemplateDefinition[string] _definedTemplates;
}
