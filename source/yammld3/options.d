// Copyright (c) 2020 Starg.
// SPDX-License-Identifier: BSD-3-Clause

module yammld3.options;

import std.array;
import std.typecons : Nullable;
import std.variant;

import yammld3.ast;
import yammld3.source : SourceLocation;

package enum OptionType
{
    flag,
    identifier,
    int7b,
    integer,
    floatingPoint,
    duration,
    floatRatio100,
    floatRatio127,
    text,
    commandBlock
}

package alias OptionValueData = Algebraic!(bool, byte, int, float, string, CommandBlock);

package struct OptionValue
{
    OptionValueData data;
    SourceLocation location;
}

package struct Option
{
    bool optional;
    bool multi;

    Algebraic!(string, OptionType) key;
    Nullable!(size_t, -1) position;
    OptionType valueType;

    // If `key` contains `OptionType`, `values` contains a key-value pair or an array thereof;
    // otherwise `values` contains zero or more items;
    Algebraic!(OptionValue*, RefAppender!(OptionValue[])) values;

    size_t actualCount;
}

package final class OptionProcessor
{
    import yammld3.diagnostics : DiagnosticsHandler;
    import yammld3.eval : CommandBlockExpressionEvaluator, DurationExpressionEvaluator, NumericExpressionEvaluator, StringExpressionEvaluator;

    public this(
        DiagnosticsHandler handler,
        DurationExpressionEvaluator durationEval,
        NumericExpressionEvaluator!int intEval,
        NumericExpressionEvaluator!float floatEval,
        StringExpressionEvaluator strEval,
        CommandBlockExpressionEvaluator commandEval
    )
    {
        _diagnosticsHandler = handler;
        _durationEvaluator = durationEval;
        _intEvaluator = intEval;
        _floatEvaluator = floatEval;
        _strEval = strEval;
        _commandEval = commandEval;
    }

    public bool processOptions(
        Option[] options,
        ExpressionList args,
        string context,
        SourceLocation loc,
        float startTime
    )
    {
        bool err = false;

        if (args !is null)
        {
            size_t currentPosition = 0;

            foreach (arg; args.items)
            {
                auto pOption = findOption(options, arg, currentPosition);

                if (pOption is null)
                {
                    err = true;
                    _diagnosticsHandler.unexpectedArgument(arg.location, context);
                    continue;
                }

                if (!pOption.multi && pOption.actualCount > 0)
                {
                    err = true;
                    _diagnosticsHandler.duplicatedOption(arg.location, context);
                    continue;
                }

                pOption.actualCount++;

                SourceLocation keyLoc = arg.key !is null ? arg.key.location : arg.location;

                if (pOption.key.peek!OptionType !is null)
                {
                    auto keyVal = evaluateAs(pOption.key.get!OptionType, arg.key, context, keyLoc, startTime, true);

                    if (keyVal.isNull)
                    {
                        err = true;
                        continue;
                    }

                    assert(pOption.values.peek!(RefAppender!(OptionValue[])) !is null);
                    pOption.values.get!(RefAppender!(OptionValue[])) ~= OptionValue(keyVal.get, keyLoc);
                }

                assert(arg.value !is null);
                auto val = evaluateAs(pOption.valueType, arg.value, context, arg.value.location, startTime, false);

                if (val.isNull)
                {
                    err = true;
                    continue;
                }

                if (pOption.values.peek!(RefAppender!(OptionValue[])) !is null)
                {
                    pOption.values.get!(RefAppender!(OptionValue[])) ~= OptionValue(val.get, arg.value.location);
                }
                else
                {
                    assert(!pOption.multi);
                    *pOption.values.get!(OptionValue*) = OptionValue(val.get, arg.value.location);
                }
            }
        }

        foreach (ref opt; options)
        {
            if (!opt.optional && opt.valueType != OptionType.flag && opt.actualCount == 0)
            {
                err = true;

                if (args is null)
                {
                    _diagnosticsHandler.expectedArgumentList(loc, context);
                }
                else if (opt.key.peek!string !is null)
                {
                    _diagnosticsHandler.expectedArgument(loc, context, opt.key.get!string);
                }
                else if (!opt.position.isNull)
                {
                    _diagnosticsHandler.expectedArgument(loc, context, opt.position.get);
                }
                else
                {
                    _diagnosticsHandler.expectedArgument(loc, context);
                }

                break;
            }
        }

        return !err;
    }

    private Option* findOption(Option[] options, ExpressionListItem arg, ref size_t currentPosition)
    {
        import std.algorithm.searching : find;

        assert(arg !is null);

        if (arg.key is null)
        {
            if (arg.value.kind == ExpressionKind.identifier)
            {
                string flagName = (cast(Identifier)arg.value).value;

                // flag option
                auto flagOpt = options.find!(
                    x => x.key.peek!string !is null && x.valueType == OptionType.flag && x.key.get!string == flagName
                );

                if (!flagOpt.empty)
                {
                    return flagOpt.ptr;
                }
            }

            // no key, find option by exact position
            auto posOpt = options.find!(
                x => !x.position.isNull && x.position.get == currentPosition
            );

            if (!posOpt.empty)
            {
                currentPosition++;
                return posOpt.ptr;
            }

            // no key, find array option
            auto arrPosOpt = options.find!(
                x => x.multi && !x.position.isNull && x.position.get <= currentPosition
            );

            if (!arrPosOpt.empty)
            {
                currentPosition++;
                return arrPosOpt.ptr;
            }
        }
        else
        {
            if (arg.key.kind == ExpressionKind.identifier)
            {
                string keyName = (cast(Identifier)arg.key).value;

                // find option by key name
                auto keyNameOpt = options.find!(
                    x => x.key.peek!string !is null && x.key.get!string == keyName && x.valueType != OptionType.flag
                );

                if (!keyNameOpt.empty)
                {
                    return keyNameOpt.ptr;
                }
            }

            // find option by key and exact position
            auto keyPosOpt = options.find!(
                x => x.key.peek!OptionType !is null && !x.position.isNull && x.position.get == currentPosition && x.valueType != OptionType.flag
            );

            if (!keyPosOpt.empty)
            {
                currentPosition++;
                return keyPosOpt.ptr;
            }

            // find array option by key and position
            auto arrKeyPosOpt = options.find!(
                x => x.key.peek!OptionType !is null && x.multi && !x.position.isNull && x.position.get <= currentPosition && x.valueType != OptionType.flag
            );

            if (!arrKeyPosOpt.empty)
            {
                currentPosition++;
                return arrKeyPosOpt.ptr;
            }
        }

        return null;
    }

    private Nullable!OptionValueData evaluateAs(
        OptionType type,
        Expression expr,
        string context,
        SourceLocation loc,
        float startTime,
        bool isKey
    )
    {
        import std.conv : to;

        if (expr is null)
        {
            if (isKey)
            {
                _diagnosticsHandler.expectedArgumentKey(loc, context);
            }
            else
            {
                _diagnosticsHandler.expectedArgument(loc, context);
            }

            return typeof(return).init;
        }

        final switch (type)
        {
        case OptionType.flag:
            return typeof(return)(OptionValueData(true));

        case OptionType.identifier:
            auto id = cast(Identifier)expr;

            if (id is null)
            {
                _diagnosticsHandler.expectedIdentifier(expr.location, context);
                return typeof(return).init;
            }

            return typeof(return)(OptionValueData(id.value));

        case OptionType.int7b:
            int v = _intEvaluator.evaluate(expr);

            if (!(0 <= v && v <= 127))
            {
                _diagnosticsHandler.valueIsOutOfRange(expr.location, context, 0, 127, v);
                return typeof(return).init;
            }

            return typeof(return)(OptionValueData(v.to!byte));

        case OptionType.integer:
            int n = _intEvaluator.evaluate(expr);
            return typeof(return)(OptionValueData(n));

        case OptionType.floatingPoint:
            float n = _floatEvaluator.evaluate(expr);
            return typeof(return)(OptionValueData(n));

        case OptionType.duration:
            float dur = _durationEvaluator.evaluate(startTime, expr);
            return typeof(return)(OptionValueData(dur));

        case OptionType.floatRatio100:
            float n = _floatEvaluator.evaluate(expr);
            return typeof(return)(OptionValueData(n / 100.0f));

        case OptionType.floatRatio127:
            float n = _floatEvaluator.evaluate(expr);
            return typeof(return)(OptionValueData(n / 127.0f));

        case OptionType.text:
            string str = _strEval.evaluate(expr);
            return typeof(return)(OptionValueData(str));

        case OptionType.commandBlock:
            auto block = _commandEval.evaluate(expr);

            if (block is null)
            {
                _diagnosticsHandler.expectedCommandBlock(expr.location, context);
                return typeof(return).init;
            }

            return typeof(return)(OptionValueData(block));
        }
    }

    private DiagnosticsHandler _diagnosticsHandler;
    private DurationExpressionEvaluator _durationEvaluator;
    private NumericExpressionEvaluator!int _intEvaluator;
    private NumericExpressionEvaluator!float _floatEvaluator;
    private StringExpressionEvaluator _strEval;
    private CommandBlockExpressionEvaluator _commandEval;
}
