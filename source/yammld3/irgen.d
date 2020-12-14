
module yammld3.irgen;

import yammld3.macros;

private struct BlockScopeContext
{
    NoteMacroManagerContext noteMacroManagerContext;
    ExpressionMacroManagerContext expressionMacroManagerContext;
}

private immutable int recursionLimit = 20;

public final class IRGenerator
{
    import std.algorithm.comparison : cmp, max, min;
    import std.algorithm.iteration : map, sum;
    import std.array;
    import std.conv : to;
    import std.typecons : Nullable, tuple;
    import std.variant : Algebraic;

    import ast = yammld3.ast;
    import yammld3.common;
    import yammld3.diagnostics : DiagnosticsHandler;
    import yammld3.eval;
    import ir = yammld3.ir;
    import yammld3.irgenutil;
    import yammld3.options;
    import yammld3.parser : Parser;
    import yammld3.priorspec;
    import yammld3.source;

    public this(DiagnosticsHandler handler, SourceManager sourceManager, Parser parser)
    {
        _diagnosticsHandler = handler;
        _sourceManager = sourceManager;
        _parser = parser;
        _noteMacroManager = new NoteMacroManager(handler);
        _expressionMacroManager = new ExpressionMacroManager(handler);

        _intEvaluator = new NumericExpressionEvaluator!int(handler, _expressionMacroManager);
        _floatEvaluator = new NumericExpressionEvaluator!float(handler, _expressionMacroManager);
        _strEval = new StringExpressionEvaluator(handler, _expressionMacroManager);
        _commandEval = new CommandBlockExpressionEvaluator(handler, _expressionMacroManager);
    }

    public ir.Composition compileModule(ast.Module am)
    {
        assert(am !is null);
        auto cb = new CompositionBuilder(am.name);

        _durationEvaluator = new DurationExpressionEvaluator(
            _diagnosticsHandler,
            (startTime, t) => cb.conductorTrackBuilder.toTime(startTime, t.time),
            _expressionMacroManager
        );

        _optionProc = new OptionProcessor(
            _diagnosticsHandler,
            _durationEvaluator,
            _intEvaluator,
            _floatEvaluator,
            _strEval,
            _commandEval
        );

        auto tb = cb.selectDefaultTrack();
        compileCommands(tb, am.commands);
        return cb.build();
    }

    private void compileCommands(MultiTrackBuilder tb, ast.Command[] commands)
    {
        auto context = saveContext();

        scope (exit)
        {
            restoreContext(context);
        }

        foreach (c; commands)
        {
            assert(c !is null);
            compileCommand(tb, c);
        }
    }

    private void compileCommand(MultiTrackBuilder tb, ast.Command c)
    {
        import yammld3.ast : visit;
        assert(c !is null);
        c.visit!(x => doCompileCommand(tb, x));
    }

    private void doCompileCommand(MultiTrackBuilder tb, ast.BasicCommand c)
    {
        assert(c !is null);

        switch (c.name)
        {
        case "a":
        case "b":
        case "c":
        case "d":
        case "e":
        case "f":
        case "g":
            assert(false);

        case "h":
            compileControlChangeCommand(tb, ir.ControlChangeCode.hold1, c, true);
            break;

        case "i":
            compilePitchBendCommand(tb, c);
            break;

        case "l":
            setDuration(tb, c.location, c.sign, c.argument);
            break;

        case "m":
            compileControlChangeCommand(tb, ir.ControlChangeCode.modulation, c, false);
            break;

        case "n":
            setTrackProperty(tb, TrackPropertyKind.keyShift, c.location, c.sign, c.argument);
            break;

        case "o":
            setTrackProperty(tb, TrackPropertyKind.octave, c.location, c.sign, c.argument);
            break;

        case "p":
            compileControlChangeCommand(tb, ir.ControlChangeCode.pan, c, false);
            break;

        case "q":
            setTrackProperty(tb, TrackPropertyKind.gateTime, c.location, c.sign, c.argument);
            break;

        case "r":
            if (c.sign == OptionalSign.none)
            {
                compileRestCommand(tb, c);
            }
            else
            {
                moveTime(tb.compositionBuilder, c);
            }
            break;

        case "t":
            setTrackProperty(tb, TrackPropertyKind.timeShift, c.location, c.sign, c.argument);
            break;

        case "v":
            setTrackProperty(tb, TrackPropertyKind.velocity, c.location, c.sign, c.argument);
            break;

        case "x":
            compileControlChangeCommand(tb, ir.ControlChangeCode.expression, c, false);
            break;

        case "_":
            extendPreviousNote(tb, c);
            break;

        default:
            _diagnosticsHandler.undefinedBasicCommand(c.location, c.name);
            break;
        }
    }

    private void compileNoteComandWithKeys(MultiTrackBuilder tb, ast.NoteCommand c, ir.KeyInfo[] keys)
    {
        auto cb = tb.compositionBuilder;
        auto cdb = cb.conductorTrackBuilder;
        int noteCount = cb.nextNoteCount();
        float curTime = cb.currentTime;

        float duration;

        if (c.duration is null)
        {
            duration = cdb.getDurationFor(noteCount, curTime);
        }
        else
        {
            duration = _durationEvaluator.evaluate(curTime, c.duration);
        }

        NoteSetInfo noteSetInfo;
        noteSetInfo.nominalTime = curTime;
        noteSetInfo.nominalDuration = duration;
        noteSetInfo.lastNominalDuration = duration;
        noteSetInfo.keys = keys;

        tb.putNote(noteCount, noteSetInfo);
        cb.currentTime = curTime + duration;
    }

    private void doCompileCommand(MultiTrackBuilder tb, ast.NoteCommand c)
    {
        assert(c !is null);

        auto keys = _noteMacroManager.expandNoteMacros(c.keys).map!(
            (x)
            {
                ir.KeyInfo k;
                k.key = x;
                k.velocity = 0.0f;
                k.timeShift = 0.0f;
                k.gateTime = 0.0f;
                return k;
            }
        );

        compileNoteComandWithKeys(tb, c, keys.array);
    }

    private void compileRestCommand(MultiTrackBuilder tb, ast.BasicCommand c)
    {
        assert(c !is null);
        assert(c.sign == OptionalSign.none);

        auto cb = tb.compositionBuilder;
        auto cdb = cb.conductorTrackBuilder;
        int noteCount = cb.nextNoteCount();
        float curTime = cb.currentTime;

        float duration;

        if (c.argument is null)
        {
            duration = cdb.getDurationFor(noteCount, curTime);
        }
        else
        {
            duration = _durationEvaluator.evaluate(curTime, c.argument);
        }

        NoteSetInfo noteSetInfo;
        noteSetInfo.nominalTime = curTime;
        noteSetInfo.nominalDuration = duration;
        noteSetInfo.lastNominalDuration = duration;
        noteSetInfo.keys = [];

        tb.putNote(noteCount, noteSetInfo);
        cb.currentTime = curTime + duration;
    }

    private void moveTime(CompositionBuilder cb, ast.BasicCommand c)
    {
        assert(c !is null);
        assert(c.sign != OptionalSign.none);

        if (c.argument is null)
        {
            _diagnosticsHandler.expectedArgument(c.location, c.sign == OptionalSign.minus ? "r-" : "r+");
            return;
        }

        float curTime = cb.currentTime;
        float duration = _durationEvaluator.evaluate(curTime, c.argument);

        if (c.sign == OptionalSign.minus)
        {
            cb.currentTime = curTime - duration;
        }
        else
        {
            cb.currentTime = curTime + duration;
        }
    }

    private void extendPreviousNote(MultiTrackBuilder tb, ast.BasicCommand c)
    {
        assert(c !is null);

        if (c.sign != OptionalSign.none)
        {
            _diagnosticsHandler.unexpectedSign(c.location, "_");
            return;
        }

        auto cb = tb.compositionBuilder;
        auto cdb = cb.conductorTrackBuilder;
        int noteCount = cb.nextNoteCount();
        float curTime = cb.currentTime;

        float duration;

        if (c.argument is null)
        {
            duration = cdb.getDurationFor(noteCount, curTime);
        }
        else
        {
            duration = _durationEvaluator.evaluate(curTime, c.argument);
        }

        tb.extendPreviousNote(noteCount, curTime, duration);
        cb.currentTime = curTime + duration;
    }

    private void compilePitchBendCommand(MultiTrackBuilder tb, ast.BasicCommand c)
    {
        assert(c !is null);

        if (c.argument is null)
        {
            _diagnosticsHandler.expectedArgument(c.location, c.name);
            return;
        }

        auto pb = new ir.PitchBendEvent(
            tb.compositionBuilder.currentTime,
            _floatEvaluator.evaluate(c.argument) * (c.sign == OptionalSign.minus ? -1.0f : 1.0f) / 8192.0f
        );

        tb.putCommand(pb);
    }

    private void setDuration(MultiTrackBuilder tb, SourceLocation loc, OptionalSign sign, ast.Expression arg)
    {
        auto cb = tb.compositionBuilder;
        auto cdb = cb.conductorTrackBuilder;
        float curTime = cb.currentTime;

        if (arg is null)
        {
            _diagnosticsHandler.expectedArgument(loc, "basic command");
            return;
        }

        cdb.setDuration(sign, _durationEvaluator.evaluate(curTime, arg));
    }

    private void setTrackProperty(
        MultiTrackBuilder tb,
        TrackPropertyKind kind,
        SourceLocation loc,
        OptionalSign sign,
        ast.Expression arg
    )
    {
        if (sign == OptionalSign.none && arg is null)
        {
            _diagnosticsHandler.expectedArgument(loc, "basic command");
            return;
        }

        Algebraic!(int, float) value;

        if (isIntegerProperty(kind))
        {
            if (arg is null)
            {
                value = 1;
            }
            else
            {
                value = _intEvaluator.evaluate(arg);
            }
        }
        else if (kind == TrackPropertyKind.timeShift)
        {
            if (arg is null)
            {
                _diagnosticsHandler.expectedArgument(loc, "basic command");
                return;
            }
            else
            {
                value = _durationEvaluator.evaluate(tb.compositionBuilder.currentTime, arg);
            }
        }
        else
        {
            if (arg is null)
            {
                _diagnosticsHandler.expectedArgument(loc, "basic command");
                return;
            }
            else
            {
                value = toPercentage(kind, _floatEvaluator.evaluate(arg));
            }
        }

        tb.setTrackProperty(kind, sign, value);
    }

    private void doCompileCommand(MultiTrackBuilder tb, ast.ExtensionCommand c)
    {
        assert(c !is null);

        switch (c.name.value)
        {
        case "all_notes_off":
            compileChannelModeCommand(tb, ir.ControlChangeCode.allNotesOff, c);
            break;

        case "all_sound_off":
            compileChannelModeCommand(tb, ir.ControlChangeCode.allSoundOff, c);
            break;

        case "auto_chord":
            compileAutoChordCommand(tb, c);
            break;

        case "arp":
        case "arpeggio":
            compileArpeggioCommand(tb, c);
            break;

        case "assert_time":
            assertTime(tb.compositionBuilder, c);
            break;

        case "attack_time":
            compileControlChangeCommand(tb, ir.ControlChangeCode.attackTime, c);
            break;

        case "brightness":
            compileControlChangeCommand(tb, ir.ControlChangeCode.brightness, c);
            break;

        case "celeste":
            compileControlChangeCommand(tb, ir.ControlChangeCode.effect4Depth, c);
            break;

        case "channel":
            setChannel(tb, c);
            break;

        case "choose":
            compileChooseCommand(tb, c);
            break;

        case "chorus":
            compileControlChangeCommand(tb, ir.ControlChangeCode.effect3Depth, c);
            break;

        case "copyright":
            addTextEventToConductorTrack(tb.compositionBuilder, ir.MetaEventKind.copyright, c);
            break;

        case "control":
            compileControlChangeCommand(tb, c);
            break;

        case "cutoff":
            compileControlChangeCommand(tb, ir.ControlChangeCode.brightness, c);
            break;

        case "decay_time":
            compileControlChangeCommand(tb, ir.ControlChangeCode.decayTime, c);
            break;

        case "expression":
            compileControlChangeCommand(tb, ir.ControlChangeCode.expression, c);
            break;

        case "for":
            compileForCommand(tb, c);
            break;

        case "fork":
            compileForkCommand(tb, c);
            break;

        case "gm_reset":
            resetSystem(tb.compositionBuilder, ir.SystemKind.gm, c);
            break;

        case "gs_ieffect_on":
            setGSInsertionEffectOn(tb, c);
            break;

        case "gs_ieffect_param":
            setGSInsertionEffectParam(tb, c);
            break;

        case "gs_ieffect_type":
            setGSInsertionEffectType(tb, c);
            break;

        case "gs_reset":
            resetSystem(tb.compositionBuilder, ir.SystemKind.gs, c);
            break;

        case "harmonic":
            compileControlChangeCommand(tb, ir.ControlChangeCode.harmonicIntensity, c);
            break;

        case "if":
            compileIfCommand(tb, c);
            break;

        case "include":
            includeFile(tb, c);
            break;

        case "key":
            setKeySignature(tb.compositionBuilder, c);
            break;

        case "lyrics":
            addTextEventToConductorTrack(tb.compositionBuilder, ir.MetaEventKind.lyrics, c);
            break;

        case "marker":
            addTextEventToConductorTrack(tb.compositionBuilder, ir.MetaEventKind.marker, c);
            break;

        case "meter":
            setMeter(tb.compositionBuilder, c);
            break;

        case "otherwise":
            _diagnosticsHandler.commandValidOnlyWithin(c.name.location, c.name.value, "choose");
            break;

        case "pan":
            compileControlChangeCommand(tb, ir.ControlChangeCode.pan, c);
            break;

        case "phaser":
            compileControlChangeCommand(tb, ir.ControlChangeCode.effect5Depth, c);
            break;

        case "print_time":
            printTime(tb.compositionBuilder, c);
            break;

        case "print_value":
            printValue(c);
            break;

        case "program":
            setProgram(tb, c);
            break;

        case "release_time":
            compileControlChangeCommand(tb, ir.ControlChangeCode.releaseTime, c);
            break;

        case "reset_all_controllers":
            compileChannelModeCommand(tb, ir.ControlChangeCode.resetAllControllers, c);
            break;

        case "resonance":
            compileControlChangeCommand(tb, ir.ControlChangeCode.harmonicIntensity, c);
            break;

        case "reverb":
            compileControlChangeCommand(tb, ir.ControlChangeCode.effect1Depth, c);
            break;

        case "section":
            compileSectionCommand(tb, c);
            break;

        case "seqname":
            addTextEventToConductorTrack(tb.compositionBuilder, ir.MetaEventKind.sequenceName, c);
            break;

        case "set_trailing_blank":
            setTrailingBlankCommand(tb, c);
            break;

        case "srand":
            seedRNG(c);
            break;

        case "table":
            compileTableCommand(tb, c);
            break;

        case "tempo":
            setTempo(tb.compositionBuilder, c);
            break;

        case "track":
            compileTrackCommand(tb, c);
            break;

        case "tremolo":
            compileControlChangeCommand(tb, ir.ControlChangeCode.effect2Depth, c);
            break;

        case "vibrato_delay":
            compileControlChangeCommand(tb, ir.ControlChangeCode.vibratoDelay, c);
            break;

        case "vibrato_depth":
            compileControlChangeCommand(tb, ir.ControlChangeCode.vibratoDepth, c);
            break;

        case "vibrato_rate":
            compileControlChangeCommand(tb, ir.ControlChangeCode.vibratoRate, c);
            break;

        case "volume":
            compileControlChangeCommand(tb, ir.ControlChangeCode.channelVolume, c);
            break;

        case "when":
            _diagnosticsHandler.commandValidOnlyWithin(c.name.location, c.name.value, "choose");
            break;

        case "xg_reset":
            resetSystem(tb.compositionBuilder, ir.SystemKind.xg, c);
            break;

        default:
            _diagnosticsHandler.undefinedExtensionCommand(c.name.location, c.name.value);
            break;
        }
    }

    private void doCompileCommand(MultiTrackBuilder tb, ast.ScopedCommand c)
    {
        assert(c !is null);

        auto context = tb.saveContext();

        scope (exit)
        {
            tb.restoreContext(context);
        }

        compileCommands(tb, c.commands);
    }

    private void doCompileCommand(MultiTrackBuilder tb, ast.ModifierCommand c)
    {
        // Currently, modifier commands are available exclusively for note-specific track property commands
        // (e.g. `l` and `v`).
        // While it is possible to define modifier commands that accept control change commands like `m` and `x`,
        // it may be confusing to do so.
        assert(c !is null);

        switch (c.name.value)
        {
        //case "animate":
        //    _diagnosticsHandler.notImplemented(c.location, "!" ~ c.name.value);
        //    break;

        case "clamp":
            addClampPriorSpecs(tb, c);
            break;

        case "clear":
            clearPriorSpecs(tb, c);
            break;

        case "const":
            addConstPriorSpec(tb, c);
            break;

        case "nrand":
            addNormalRandomPriorSpec(tb, c);
            break;

        case "on_note":
            addOnNotePriorSpec(tb, c);
            break;

        case "on_time":
            addOnTimePriorSpec(tb, c, false);
            break;

        case "on_time_l":
            addOnTimePriorSpec(tb, c, true);
            break;

        case "persist":
            addPersistentOffset(tb, c);
            break;

        case "rand":
            addUniformRandomPriorSpec(tb, c);
            break;

        case "transition":
            addTransition(tb, c);
            break;

        default:
            _diagnosticsHandler.undefinedModifierCommand(c.name.location, c.name.value);
            break;
        }
    }

    private void doCompileCommand(MultiTrackBuilder tb, ast.RepeatCommand c)
    {
        assert(c !is null);

        int repeatCount = 2;

        if (c.repeatCount !is null)
        {
            repeatCount = _intEvaluator.evaluate(c.repeatCount);

            if (repeatCount < 0)
            {
                _diagnosticsHandler.negativeRepeatCount(c.repeatCount.location);
                repeatCount = 0;
            }
        }

        foreach (i; 0..repeatCount)
        {
            auto context = tb.saveContext();

            scope (exit)
            {
                tb.restoreContext(context);
            }

            compileCommand(tb, c.command);
        }
    }

    private void doCompileCommand(MultiTrackBuilder tb, ast.NoteMacroDefinitionCommand c)
    {
        _noteMacroManager.compileNoteMacroDefinitionCommand(c);
    }

    private void doCompileCommand(MultiTrackBuilder tb, ast.ExpressionMacroDefinitionCommand c)
    {
        _expressionMacroManager.compileExpressionMacroDefinitionCommand(c);
    }

    private void doCompileCommand(MultiTrackBuilder tb, ast.ExpressionMacroInvocationCommand c)
    {
        auto context = _expressionMacroManager.saveContext();

        scope (exit)
        {
            _expressionMacroManager.restoreContext(context);
        }

        auto block = cast(ast.CommandBlock)_expressionMacroManager.expandExpressionMacro(c);

        if (block is null)
        {
            _diagnosticsHandler.expressionMacroNotExpandedToCommandBlock(c.location, c.name.value);
            return;
        }

        foreach (child; block.commands)
        {
            compileCommand(tb, child);
        }
    }

    private void compileAutoChordCommand(MultiTrackBuilder tb, ast.ExtensionCommand c)
    {
        assert(c !is null);
        assert(c.name.value == "auto_chord");

        if (c.block is null)
        {
            _diagnosticsHandler.expectedCommandBlock(c.location, "%" ~ c.name.value);
            return;
        }

        OptionValue keySig;
        Option keySigOpt;
        keySigOpt.key = "key";
        keySigOpt.valueType = OptionType.text;
        keySigOpt.values = &keySig;

        if (!_optionProc.processOptions([keySigOpt], c.arguments, "%" ~ c.name.value, c.location, 0.0f))
        {
            return;
        }

        auto ks = parseKeySig(keySig.data.get!string);

        if (ks.isNull)
        {
            _diagnosticsHandler.undefinedKeySignature(keySig.location, "%" ~ c.name.value);
            return;
        }

        auto context = saveContext();

        scope (exit)
        {
            restoreContext(context);
        }

        foreach (child; c.block.commands)
        {
            auto nc = cast(ast.NoteCommand)child;

            if (nc !is null && nc.keys.length == 1)
            {
                auto ksp = nc.keys[0];
                auto kl = cast(ast.KeyLiteral)ksp.baseKey;

                if (kl !is null)
                {
                    int root = ksp.octaveShift * 12 + cast(int)kl.keyName + ksp.accidental;
                    int[] chord = makeDiatonicTriad(ks.get, root);

                    if (chord is null)
                    {
                        chord = [root];
                    }

                    assert(!chord.empty);

                    auto keys = appender!(ir.KeyInfo[]);
                    keys.reserve(chord.length);

                    foreach (t; chord)
                    {
                        ir.KeyInfo k;
                        k.key = AbsoluteOrRelative!int(t, true);

                        if (k.key.value >= chord[0] / 12 * 12 + 10)
                        {
                            k.key.value -= 12;
                        }

                        k.velocity = 0.0f;
                        k.timeShift = 0.0f;
                        k.gateTime = 0.0f;

                        keys ~= k;
                    }

                    compileNoteComandWithKeys(tb, nc, keys[]);
                    continue;
                }
            }

            compileCommand(tb, child);
        }
    }

    private void compileArpeggioCommand(MultiTrackBuilder tb, ast.ExtensionCommand c)
    {
        import std.range : iota;

        assert(c !is null);
        assert(c.name.value == "arp" || c.name.value == "arpeggio");

        if (c.block is null)
        {
            _diagnosticsHandler.expectedCommandBlock(c.location, "%" ~ c.name.value);
            return;
        }

        auto cb = tb.compositionBuilder;
        auto cdb = cb.conductorTrackBuilder;
        int noteCount = cb.currentNoteCount;
        float curTime = cb.currentTime;

        OptionValue ahead;
        Option aheadOpt;
        aheadOpt.key = "ahead";
        aheadOpt.valueType = OptionType.flag;
        aheadOpt.values = &ahead;

        OptionValue behind;
        Option behindOpt;
        behindOpt.key = "behind";
        behindOpt.valueType = OptionType.flag;
        behindOpt.values = &behind;

        OptionValue stepVal;
        Option stepOpt;
        stepOpt.optional = true;
        stepOpt.key = "step";
        stepOpt.position = 0;
        stepOpt.valueType = OptionType.duration;
        stepOpt.values = &stepVal;

        OptionValue durationVal;
        Option durationOpt;
        durationOpt.optional = true;
        durationOpt.key = "duration";
        durationOpt.position = 1;
        durationOpt.valueType = OptionType.duration;
        durationOpt.values = &durationVal;

        if (!_optionProc.processOptions([aheadOpt, behindOpt, stepOpt, durationOpt], c.arguments, "%" ~ c.name.value, c.location, curTime))
        {
            return;
        }

        float duration = durationVal.data.hasValue ? durationVal.data.get!float : cdb.getDurationFor(noteCount, curTime);
        int noteLikeCommandCount = c.block.commands.map!(x => countNoteLikeCommands(x, c.location, "%" ~ c.name.value)).sum(0);

        if (noteLikeCommandCount > 0)
        {
            float step = stepVal.data.hasValue ? stepVal.data.get!float : min(duration / 4.0f / noteLikeCommandCount, 4.0f / 64.0f);
            bool isBehind = behind.data.hasValue;

            auto values = iota(0, noteLikeCommandCount).map!(x => tuple(x, isBehind ? x * step : (noteLikeCommandCount - 1 - x) * -step));
            Algebraic!(PriorSpec!int, PriorSpec!float) priorSpec = cast(PriorSpec!float)new OnNotePriorSpec!float(noteCount, values.array);
            tb.addPriorSpec(TrackPropertyKind.timeShift, priorSpec);
        }

        float startTime = curTime;
        float endTime = startTime;

        auto context = saveContext();

        scope (exit)
        {
            restoreContext(context);
        }

        foreach (child; c.block.commands)
        {
            cb.currentTime = startTime;
            compileCommand(tb, child);
            endTime = max(endTime, cb.currentTime);
        }

        cb.currentTime = endTime;
    }

    private void assertTime(CompositionBuilder cb, ast.ExtensionCommand c)
    {
        assert(c !is null);
        assert(c.name.value == "assert_time");

        if (c.block !is null)
        {
            _diagnosticsHandler.unexpectedCommandBlock(c.location, "%" ~ c.name.value);
        }

        OptionValue time;
        Option timeOpt;
        timeOpt.position = 0;
        timeOpt.valueType = OptionType.duration;
        timeOpt.values = &time;

        if (!_optionProc.processOptions([timeOpt], c.arguments, "%" ~ c.name.value, c.location, 0.0f))
        {
            return;
        }

        if (!isTimeApproximatelyEqual(time.data.get!float, cb.currentTime))
        {
            _diagnosticsHandler.timeAssertionFailed(
                time.location,
                "%" ~ c.name.value,
                cb.conductorTrackBuilder.toMeasures(time.data.get!float),
                time.data.get!float,
                cb.conductorTrackBuilder.toMeasures(cb.currentTime),
                cb.currentTime
            );
        }
    }

    private void setChannel(MultiTrackBuilder tb, ast.ExtensionCommand c)
    {
        assert(c !is null);
        assert(c.name.value == "channel");

        if (c.block !is null)
        {
            _diagnosticsHandler.unexpectedCommandBlock(c.location, "%" ~ c.name.value);
        }

        OptionValue ch;
        Option chOpt;
        chOpt.position = 0;
        chOpt.valueType = OptionType.integer;
        chOpt.values = &ch;

        if (!_optionProc.processOptions([chOpt], c.arguments, "%" ~ c.name.value, c.location, 0.0f))
        {
            return;
        }

        if (!(0 <= ch.data.get!int && ch.data.get!int < maxChannelCount))
        {
            _diagnosticsHandler.invalidChannel(ch.location, "%" ~ c.name.value, ch.data.get!int);
            return;
        }

        tb.setChannel(ch.data.get!int);
    }

    private void compileControlChangeCommand(MultiTrackBuilder tb, ast.ExtensionCommand c)
    {
        assert(c !is null);
        assert(c.name.value == "control");

        if (c.block !is null)
        {
            _diagnosticsHandler.unexpectedCommandBlock(c.location, "%" ~ c.name.value);
        }

        OptionValue code;
        Option codeOpt;
        codeOpt.key = "code";
        codeOpt.position = 0;
        codeOpt.valueType = OptionType.int7b;
        codeOpt.values = &code;

        OptionValue value;
        Option valueOpt;
        valueOpt.key = "value";
        valueOpt.position = 1;
        valueOpt.valueType = OptionType.int7b;
        valueOpt.values = &value;

        if (!_optionProc.processOptions([codeOpt, valueOpt], c.arguments, "%" ~ c.name.value, c.location, 0.0f))
        {
            return;
        }

        auto cc = new ir.ControlChange(
            tb.compositionBuilder.currentTime,
            cast(ir.ControlChangeCode)code.data.get!byte,
            value.data.get!byte
        );

        tb.putCommand(cc);
    }

    private void compileControlChangeCommand(MultiTrackBuilder tb, ir.ControlChangeCode code, ast.ExtensionCommand c)
    {
        assert(c !is null);

        if (c.block !is null)
        {
            _diagnosticsHandler.unexpectedCommandBlock(c.location, "%" ~ c.name.value);
        }

        OptionValue value;
        Option valueOpt;
        valueOpt.position = 0;
        valueOpt.valueType = OptionType.int7b;
        valueOpt.values = &value;

        if (!_optionProc.processOptions([valueOpt], c.arguments, "%" ~ c.name.value, c.location, 0.0f))
        {
            return;
        }

        auto cc = new ir.ControlChange(
            tb.compositionBuilder.currentTime,
            code,
            value.data.get!byte
        );

        tb.putCommand(cc);
    }

    private void compileControlChangeCommand(MultiTrackBuilder tb, ir.ControlChangeCode code, ast.BasicCommand c, bool isBinary)
    {
        assert(c !is null);

        if (c.sign != OptionalSign.none)
        {
            _diagnosticsHandler.unexpectedSign(c.location, c.name);
            return;
        }

        if (c.argument is null)
        {
            _diagnosticsHandler.expectedArgument(c.location, c.name);
            return;
        }

        auto value = evaluateAsByte(c.name, c.argument);

        if (value.isNull)
        {
            return;
        }

        auto cc = new ir.ControlChange(
            tb.compositionBuilder.currentTime,
            code,
            isBinary && value.get > 0 ? 127 : value.get
        );

        tb.putCommand(cc);
    }

    private void compileChannelModeCommand(MultiTrackBuilder tb, ir.ControlChangeCode code, ast.ExtensionCommand c)
    {
        assert(c !is null);

        if (c.block !is null)
        {
            _diagnosticsHandler.unexpectedCommandBlock(c.location, "%" ~ c.name.value);
        }

        if (!_optionProc.processOptions([], c.arguments, "%" ~ c.name.value, c.location, 0.0f))
        {
            return;
        }

        auto cc = new ir.ControlChange(
            tb.compositionBuilder.currentTime,
            code,
            0
        );

        tb.putCommand(cc);
    }

    private void resetSystem(CompositionBuilder cb, ir.SystemKind kind, ast.ExtensionCommand c)
    {
        assert(c !is null);

        if (c.block !is null)
        {
            _diagnosticsHandler.unexpectedCommandBlock(c.location, "%" ~ c.name.value);
        }

        if (!_optionProc.processOptions([], c.arguments, "%" ~ c.name.value, c.location, 0.0f))
        {
            return;
        }

        cb.conductorTrackBuilder.resetSystem(cb.currentTime, kind);
    }

    private void setGSInsertionEffectOn(MultiTrackBuilder tb, ast.ExtensionCommand c)
    {
        assert(c !is null);
        assert(c.name.value == "gs_ieffect_on");

        if (c.block !is null)
        {
            _diagnosticsHandler.unexpectedCommandBlock(c.location, "%" ~ c.name.value);
        }

        OptionValue onFlag;
        Option onFlagOpt;
        onFlagOpt.key = "on";
        onFlagOpt.valueType = OptionType.flag;
        onFlagOpt.values = &onFlag;

        OptionValue offFlag;
        Option offFlagOpt;
        offFlagOpt.key = "off";
        offFlagOpt.valueType = OptionType.flag;
        offFlagOpt.values = &offFlag;

        if (!_optionProc.processOptions([onFlagOpt, offFlagOpt], c.arguments, "%" ~ c.name.value, c.location, 0.0f))
        {
            return;
        }

        tb.putCommand(new ir.GSInsertionEffectOn(tb.compositionBuilder.currentTime, !offFlag.data.hasValue));
    }

    private void setGSInsertionEffectParam(MultiTrackBuilder tb, ast.ExtensionCommand c)
    {
        assert(c !is null);
        assert(c.name.value == "gs_ieffect_param");

        if (c.block !is null)
        {
            _diagnosticsHandler.unexpectedCommandBlock(c.location, "%" ~ c.name.value);
        }

        OptionValue indexValue;
        Option indexValueOpt;
        indexValueOpt.key = "index";
        indexValueOpt.position = 0;
        indexValueOpt.valueType = OptionType.int7b;
        indexValueOpt.values = &indexValue;

        OptionValue value;
        Option valueOpt;
        valueOpt.key = "value";
        valueOpt.position = 1;
        valueOpt.valueType = OptionType.int7b;
        valueOpt.values = &value;

        if (!_optionProc.processOptions([indexValueOpt, valueOpt], c.arguments, "%" ~ c.name.value, c.location, 0.0f))
        {
            return;
        }

        if (!(1 <= indexValue.data.get!byte && indexValue.data.get!byte <= 20))
        {
            _diagnosticsHandler.valueIsOutOfRange(indexValue.location, "%" ~ c.name.value, 1, 20, indexValue.data.get!byte);
            return;
        }

        tb.putCommand(
            new ir.GSInsertionEffectSetParam(
                tb.compositionBuilder.currentTime,
                (indexValue.data.get!byte - 1).to!byte,
                value.data.get!byte
            )
        );
    }

    private void setGSInsertionEffectType(MultiTrackBuilder tb, ast.ExtensionCommand c)
    {
        assert(c !is null);
        assert(c.name.value == "gs_ieffect_type");

        if (c.block !is null)
        {
            _diagnosticsHandler.unexpectedCommandBlock(c.location, "%" ~ c.name.value);
        }

        OptionValue typeValue;
        Option typeValueOpt;
        typeValueOpt.position = 0;
        typeValueOpt.valueType = OptionType.text;
        typeValueOpt.values = &typeValue;

        if (!_optionProc.processOptions([typeValueOpt], c.arguments, "%" ~ c.name.value, c.location, 0.0f))
        {
            return;
        }

        auto type = getGSInsertionEffectTypeFromString(typeValue.data.get!string);

        if (type.isNull)
        {
            _diagnosticsHandler.undefinedGSInsertionEffectType(typeValue.location, "%" ~ c.name.value);
            return;
        }

        tb.putCommand(new ir.GSInsertionEffectSetType(tb.compositionBuilder.currentTime, type.get));
    }

    private void setTempo(CompositionBuilder cb, ast.ExtensionCommand c)
    {
        assert(c !is null);
        assert(c.name.value == "tempo");

        if (c.block !is null)
        {
            _diagnosticsHandler.unexpectedCommandBlock(c.location, "%" ~ c.name.value);
        }

        OptionValue value;
        Option valueOpt;
        valueOpt.position = 0;
        valueOpt.valueType = OptionType.floatingPoint;
        valueOpt.values = &value;

        if (!_optionProc.processOptions([valueOpt], c.arguments, "%" ~ c.name.value, c.location, 0.0f))
        {
            return;
        }

        float tempo = value.data.get!float;

        // TODO: clamp value
        cb.conductorTrackBuilder.setTempo(cb.currentTime, tempo);
    }

    private void setMeter(CompositionBuilder cb, ast.ExtensionCommand c)
    {
        assert(c !is null);
        assert(c.name.value == "meter");

        if (c.block !is null)
        {
            _diagnosticsHandler.unexpectedCommandBlock(c.location, "%" ~ c.name.value);
        }

        if (c.arguments is null)
        {
            _diagnosticsHandler.expectedArgumentList(c.location, "%" ~ c.name.value);
            return;
        }

        if (c.arguments.items.length != 1)
        {
            _diagnosticsHandler.wrongNumberOfArguments(c.arguments.location, "%" ~ c.name.value, 1, c.arguments.items.length);
            return;
        }

        if (c.arguments.items[0].key !is null)
        {
            _diagnosticsHandler.unexpectedArgument(c.arguments.items[0].key.location, "%" ~ c.name.value);
            return;
        }

        auto be = cast(ast.BinaryExpression)c.arguments.items[0].value;

        if (be is null || be.op.kind != ast.OperatorKind.slash)
        {
            _diagnosticsHandler.unexpectedExpressionKind(c.arguments.items[0].value.location, "%" ~ c.name.value);
            return;
        }

        Fraction!int m;
        m.numerator = _intEvaluator.evaluate(be.left);
        m.denominator = _intEvaluator.evaluate(be.right);

        if (!(1 <= m.denominator && m.denominator <= 64))
        {
            _diagnosticsHandler.valueIsOutOfRange(be.right.location, "%" ~ c.name.value, 1, 64, m.denominator);
            return;
        }

        if (!(1 <= m.numerator && m.numerator <= 64))
        {
            _diagnosticsHandler.valueIsOutOfRange(be.right.location, "%" ~ c.name.value, 1, 64, m.numerator);
            return;
        }

        cb.conductorTrackBuilder.setMeter(cb.currentTime, m);
    }

    private void setKeySignature(CompositionBuilder cb, ast.ExtensionCommand c)
    {
        assert(c !is null);
        assert(c.name.value == "key");

        if (c.block !is null)
        {
            _diagnosticsHandler.unexpectedCommandBlock(c.location, "%" ~ c.name.value);
        }

        OptionValue value;
        Option valueOpt;
        valueOpt.position = 0;
        valueOpt.valueType = OptionType.text;
        valueOpt.values = &value;

        if (!_optionProc.processOptions([valueOpt], c.arguments, "%" ~ c.name.value, c.location, 0.0f))
        {
            return;
        }

        auto ks = parseKeySig(value.data.get!string);

        if (ks.isNull)
        {
            _diagnosticsHandler.undefinedKeySignature(value.location, "%" ~ c.name.value);
            return;
        }

        cb.conductorTrackBuilder.setKeySig(new ir.SetKeySigEvent(cb.currentTime, ks.get));
    }

    private void addTextEventToConductorTrack(CompositionBuilder cb, ir.MetaEventKind kind, ast.ExtensionCommand c)
    {
        assert(c !is null);

        if (c.block !is null)
        {
            _diagnosticsHandler.unexpectedCommandBlock(c.location, "%" ~ c.name.value);
        }

        OptionValue value;
        Option valueOpt;
        valueOpt.position = 0;
        valueOpt.valueType = OptionType.text;
        valueOpt.values = &value;

        if (!_optionProc.processOptions([valueOpt], c.arguments, "%" ~ c.name.value, c.location, 0.0f))
        {
            return;
        }

        auto te = new ir.TextMetaEvent(
            cb.currentTime,
            kind,
            value.data.get!string
        );

        cb.conductorTrackBuilder.addTextEvent(te);
    }

    private void includeFile(MultiTrackBuilder tb, ast.ExtensionCommand c)
    {
        assert(c !is null);
        assert(c.name.value == "include");

        _includeDepth++;

        scope (exit)
        {
            _includeDepth--;
        }

        if (_includeDepth > recursionLimit)
        {
            _diagnosticsHandler.includeRecursionLimitExceeded(c.location, "%" ~ c.name.value);
            assert(false);
        }

        if (c.block !is null)
        {
            _diagnosticsHandler.unexpectedCommandBlock(c.location, "%" ~ c.name.value);
        }

        OptionValue value;
        Option valueOpt;
        valueOpt.position = 0;
        valueOpt.valueType = OptionType.text;
        valueOpt.values = &value;

        if (!_optionProc.processOptions([valueOpt], c.arguments, "%" ~ c.name.value, c.location, 0.0f))
        {
            return;
        }

        assert(c.location.source !is null);
        auto newSource = _sourceManager.getOrLoadSource(value.data.get!string, c.location.source.path);

        if (newSource is null)
        {
            _diagnosticsHandler.cannotOpenFile(value.location, "%" ~ c.name.value, value.data.get!string);
            return;
        }

        auto newModule = _parser.parseModule(newSource);

        if (newModule !is null)
        {
            compileCommands(tb, newModule.commands);
        }
    }

    private void compileIfCommand(MultiTrackBuilder tb, ast.ExtensionCommand c)
    {
        assert(c !is null);
        assert(c.name.value == "if");

        if (c.block is null)
        {
            _diagnosticsHandler.expectedCommandBlock(c.location, "%" ~ c.name.value);
            return;
        }

        OptionValue value;
        Option valueOpt;
        valueOpt.position = 0;
        valueOpt.valueType = OptionType.floatingPoint;
        valueOpt.values = &value;

        if (!_optionProc.processOptions([valueOpt], c.arguments, "%" ~ c.name.value, c.location, 0.0f))
        {
            return;
        }

        if (value.data.get!float)
        {
            compileCommands(tb, c.block.commands);
        }
    }

    private void compileChooseCommand(MultiTrackBuilder tb, ast.ExtensionCommand c)
    {
        assert(c !is null);
        assert(c.name.value == "choose");

        if (c.block is null)
        {
            _diagnosticsHandler.expectedCommandBlock(c.location, "%" ~ c.name.value);
            return;
        }

        if (!_optionProc.processOptions([], c.arguments, "%" ~ c.name.value, c.location, 0.0f))
        {
            return;
        }

        foreach (i, childCommand; c.block.commands)
        {
            auto childExt = cast(ast.ExtensionCommand)childCommand;

            if (childExt is null)
            {
                _diagnosticsHandler.expectedCommand2(childCommand.location, "%" ~ c.name.value, "when", "otherwise");
                continue;
            }

            switch (childExt.name.value)
            {
            case "when":
                {
                    if (childExt.block is null)
                    {
                        _diagnosticsHandler.expectedCommandBlock(childExt.location, "%" ~ childExt.name.value);
                        continue;
                    }

                    OptionValue value;
                    Option valueOpt;
                    valueOpt.position = 0;
                    valueOpt.valueType = OptionType.floatingPoint;
                    valueOpt.values = &value;

                    if (!_optionProc.processOptions([valueOpt], childExt.arguments, "%" ~ childExt.name.value, childExt.location, 0.0f))
                    {
                        continue;
                    }

                    if (value.data.get!float)
                    {
                        compileCommands(tb, childExt.block.commands);
                        return; // stop processing
                    }
                }

                break;

            case "otherwise":
                if (i != c.block.commands.length - 1)
                {
                    _diagnosticsHandler.mustBeLastCommandWithin(childCommand.location, "otherwise", "choose");
                }

                if (childExt.block is null)
                {
                    _diagnosticsHandler.expectedCommandBlock(childExt.location, "%" ~ childExt.name.value);
                    continue;
                }

                if (!_optionProc.processOptions([], childExt.arguments, "%" ~ childExt.name.value, childExt.location, 0.0f))
                {
                    continue;
                }

                compileCommands(tb, childExt.block.commands);
                return; // stop processing

            default:
                _diagnosticsHandler.expectedCommand2(childCommand.location, "%" ~ c.name.value, "when", "otherwise");
                break;
            }
        }
    }

    private void compileForCommand(MultiTrackBuilder tb, ast.ExtensionCommand c)
    {
        assert(c !is null);
        assert(c.name.value == "for");

        if (c.block is null)
        {
            _diagnosticsHandler.expectedCommandBlock(c.location, "%" ~ c.name.value);
            return;
        }

        OptionValue[] varAndStart;
        Option varAndStartOpt;
        varAndStartOpt.position = 0;
        varAndStartOpt.key = OptionType.identifier;
        varAndStartOpt.valueType = OptionType.integer;
        varAndStartOpt.values = appender(&varAndStart);

        OptionValue limitVal;
        Option limitValOpt;
        limitValOpt.position = 1;
        limitValOpt.valueType = OptionType.integer;
        limitValOpt.values = &limitVal;

        OptionValue stepVal;
        Option stepValOpt;
        stepValOpt.optional = true;
        stepValOpt.position = 2;
        stepValOpt.valueType = OptionType.integer;
        stepValOpt.values = &stepVal;

        if (!_optionProc.processOptions([varAndStartOpt, limitValOpt, stepValOpt], c.arguments, "%" ~ c.name.value, c.location, 0.0f))
        {
            return;
        }

        string macroName = varAndStart[0].data.get!string;
        int start = varAndStart[1].data.get!int;
        int limit = limitVal.data.get!int;
        int step = stepVal.data.hasValue ? stepVal.data.get!int : 1;

        if (start > limit)
        {
            _diagnosticsHandler.limitLessThanStart(c.location, "%" ~ c.name.value, start, limit);
            return;
        }

        if (step <= 0)
        {
            _diagnosticsHandler.stepMustBePositive(stepVal.data.hasValue ? stepVal.location : c.location, "%" ~ c.name.value, step);
            return;
        }

        for (int i = start; i <= limit; i += step)
        {
            auto context = saveContext();
    
            scope (exit)
            {
                restoreContext(context);
            }
    
            ExpressionMacroDefinition def;
            def.name = macroName;
            def.location = varAndStart[0].location;
            def.definition = new ast.IntegerLiteral(varAndStart[0].location, i);

            _expressionMacroManager.defineExpressionMacro(def);
    
            foreach (childCommand; c.block.commands)
            {
                assert(childCommand !is null);
                compileCommand(tb, childCommand);
            }
        }
    }

    private void printTime(CompositionBuilder cb, ast.ExtensionCommand c)
    {
        assert(c !is null);
        assert(c.name.value == "print_time");

        if (c.block !is null)
        {
            _diagnosticsHandler.unexpectedCommandBlock(c.location, "%" ~ c.name.value);
        }

        if (!_optionProc.processOptions([], c.arguments, "%" ~ c.name.value, c.location, 0.0f))
        {
            return;
        }

        _diagnosticsHandler.printTime(
            c.location,
            '%' ~ c.name.value,
            cb.conductorTrackBuilder.toMeasures(cb.currentTime),
            cb.currentTime
        );
    }

    private void printValue(ast.ExtensionCommand c)
    {
        import std.conv : text;

        assert(c !is null);
        assert(c.name.value == "print_value");

        if (c.block !is null)
        {
            _diagnosticsHandler.unexpectedCommandBlock(c.location, "%" ~ c.name.value);
        }

        OptionValue value;
        Option valueOpt;
        valueOpt.position = 0;
        valueOpt.valueType = OptionType.floatingPoint;
        valueOpt.values = &value;

        if (!_optionProc.processOptions([valueOpt], c.arguments, "%" ~ c.name.value, c.location, 0.0f))
        {
            return;
        }

        _diagnosticsHandler.print(value.location, '%' ~ c.name.value, value.data.get!float.text);
    }

    private void setProgram(MultiTrackBuilder tb, ast.ExtensionCommand c)
    {
        assert(c !is null);
        assert(c.name.value == "program");

        if (c.block !is null)
        {
            _diagnosticsHandler.unexpectedCommandBlock(c.location, "%" ~ c.name.value);
        }

        OptionValue prog;
        Option progOpt;
        progOpt.key = "program";
        progOpt.position = 0;
        progOpt.valueType = OptionType.int7b;
        progOpt.values = &prog;

        OptionValue bm;
        Option bmOpt;
        bmOpt.optional = true;
        bmOpt.key = "bank_msb";
        bmOpt.position = 1;
        bmOpt.valueType = OptionType.int7b;
        bmOpt.values = &bm;

        OptionValue bl;
        Option blOpt;
        blOpt.optional = true;
        blOpt.key = "bank_lsb";
        blOpt.position = 2;
        blOpt.valueType = OptionType.int7b;
        blOpt.values = &bl;

        if (!_optionProc.processOptions([progOpt, bmOpt, blOpt], c.arguments, "%" ~ c.name.value, c.location, 0.0f))
        {
            return;
        }

        auto pc = new ir.ProgramChange(
            tb.compositionBuilder.currentTime,
            bl.data.hasValue ? bl.data.get!byte : 0,
            bm.data.hasValue ? bm.data.get!byte : 0,
            prog.data.get!byte
        );

        tb.putCommand(pc);
    }

    private void compileForkCommand(MultiTrackBuilder tb, ast.ExtensionCommand c)
    {
        assert(c !is null);
        assert(c.name.value == "fork");

        if (c.block is null)
        {
            _diagnosticsHandler.expectedCommandBlock(c.location, "%" ~ c.name.value);
            return;
        }

        auto cb = tb.compositionBuilder;
        float prevTime = cb.currentTime;

        OptionValue value;
        Option valueOpt;
        valueOpt.optional = true;
        valueOpt.key = "time";
        valueOpt.position = 0;
        valueOpt.valueType = OptionType.duration;
        valueOpt.values = &value;

        if (!_optionProc.processOptions([valueOpt], c.arguments, "%" ~ c.name.value, c.location, 0.0f))
        {
            return;
        }

        if (value.data.hasValue)
        {
            cb.currentTime = value.data.get!float;
        }

        compileCommands(tb, c.block.commands);
        cb.currentTime = prevTime;
    }

    private void compileSectionCommand(MultiTrackBuilder tb, ast.ExtensionCommand c)
    {
        assert(c !is null);
        assert(c.name.value == "section");

        if (c.block is null)
        {
            _diagnosticsHandler.expectedCommandBlock(c.location, "%" ~ c.name.value);
            return;
        }

        auto cb = tb.compositionBuilder;
        float startTime = cb.currentTime;

        OptionValue reqStartTime;
        Option reqStartTimeOpt;
        reqStartTimeOpt.optional = true;
        reqStartTimeOpt.key = "start";
        reqStartTimeOpt.position = 0;
        reqStartTimeOpt.valueType = OptionType.duration;
        reqStartTimeOpt.values = &reqStartTime;

        OptionValue reqEndTime;
        Option reqEndTimeOpt;
        reqEndTimeOpt.optional = true;
        reqEndTimeOpt.key = "end";
        reqEndTimeOpt.position = 1;
        reqEndTimeOpt.valueType = OptionType.duration;
        reqEndTimeOpt.values = &reqEndTime;

        if (!_optionProc.processOptions([reqStartTimeOpt, reqEndTimeOpt], c.arguments, "%" ~ c.name.value, c.location, 0.0f))
        {
            return;
        }

        if (reqStartTime.data.hasValue)
        {
            startTime = reqStartTime.data.get!float;
        }

        float endTime = startTime;

        auto context = saveContext();

        scope (exit)
        {
            restoreContext(context);
        }

        foreach (command; c.block.commands)
        {
            cb.currentTime = startTime;
            compileCommand(tb, command);

            if (reqEndTime.data.hasValue)
            {
                if (!isTimeApproximatelyEqual(cb.currentTime, startTime) && !isTimeApproximatelyEqual(cb.currentTime, reqEndTime.data.get!float))
                {
                    _diagnosticsHandler.endTimeAssertionFailed(
                        command.location,
                        reqEndTime.location,
                        "%" ~ c.name.value,
                        cb.conductorTrackBuilder.toMeasures(reqEndTime.data.get!float),
                        reqEndTime.data.get!float,
                        cb.conductorTrackBuilder.toMeasures(cb.currentTime),
                        cb.currentTime
                    );
                }
            }
            else
            {
                endTime = max(endTime, cb.currentTime);
            }
        }

        cb.currentTime = reqEndTime.data.hasValue ? reqEndTime.data.get!float : endTime;
    }

    private void seedRNG(ast.ExtensionCommand c)
    {
        assert(c !is null);
        assert(c.name.value == "srand");

        if (c.block !is null)
        {
            _diagnosticsHandler.unexpectedCommandBlock(c.location, "%" ~ c.name.value);
        }

        OptionValue value;
        Option valueOpt;
        valueOpt.position = 0;
        valueOpt.valueType = OptionType.integer;
        valueOpt.values = &value;

        if (!_optionProc.processOptions([valueOpt], c.arguments, "%" ~ c.name.value, c.location, 0.0f))
        {
            return;
        }

        _rng.seed(value.data.get!int);
    }

    private void setTrailingBlankCommand(MultiTrackBuilder tb, ast.ExtensionCommand c)
    {
        assert(c !is null);
        assert(c.name.value == "set_trailing_blank");

        if (c.block !is null)
        {
            _diagnosticsHandler.unexpectedCommandBlock(c.location, "%" ~ c.name.value);
        }

        OptionValue value;
        Option valueOpt;
        valueOpt.position = 0;
        valueOpt.valueType = OptionType.duration;
        valueOpt.values = &value;

        if (!_optionProc.processOptions([valueOpt], c.arguments, "%" ~ c.name.value, c.location, tb.compositionBuilder.currentTime))
        {
            return;
        }

        tb.setTrailingBlankTime(value.data.get!float);
    }

    private void compileTableCommand(MultiTrackBuilder tb, ast.ExtensionCommand c)
    {
        import std.algorithm.iteration : chunkBy;
        //import std.algorithm.mutation : SwapStrategy;
        import std.algorithm.sorting : sort;

        assert(c !is null);
        assert(c.name.value == "table");

        if (c.block is null)
        {
            _diagnosticsHandler.expectedCommandBlock(c.location, "%" ~ c.name.value);
            return;
        }

        if (!_optionProc.processOptions([], c.arguments, "%" ~ c.name.value, c.location, 0.0f))
        {
            return;
        }

        //auto sortedByColumn = c.block.commands.dup.sort!((a, b) => a.location.column < b.location.column, SwapStrategy.stable);
        auto sortedByColumn = c.block.commands.dup.sort!(
            (a, b) => cmp([a.location.column, a.location.line], [b.location.column, b.location.line]) < 0
        );

        auto cb = tb.compositionBuilder;
        auto context = saveContext();

        scope (exit)
        {
            restoreContext(context);
        }

        foreach (column; sortedByColumn.chunkBy!((a, b) => a.location.column == b.location.column))
        {
            float startTime = cb.currentTime;
            float endTime = startTime;

            foreach (child; column)
            {
                cb.currentTime = startTime;
                compileCommand(tb, child);
                endTime = max(endTime, cb.currentTime);
            }

            cb.currentTime = endTime;
        }
    }

    private void compileTrackCommand(MultiTrackBuilder tb, ast.ExtensionCommand c)
    {
        assert(c !is null);
        assert(c.name.value == "track");

        if (c.block is null)
        {
            _diagnosticsHandler.expectedCommandBlock(c.location, "%" ~ c.name.value);
            return;
        }

        OptionValue[] tracks;
        Option trackOpt;
        trackOpt.multi = true;
        trackOpt.position = 0;
        trackOpt.valueType = OptionType.identifier;
        trackOpt.values = appender(&tracks);

        if (!_optionProc.processOptions([trackOpt], c.arguments, "%" ~ c.name.value, c.location, 0.0f))
        {
            return;
        }

        compileCommands(tb.compositionBuilder.selectTracks(tracks.map!(x => x.data.get!string).array), c.block.commands);
    }

    private void clearPriorSpecs(MultiTrackBuilder tb, ast.ModifierCommand c)
    {
        assert(c !is null);
        assert(c.name.value == "clear");

        if (!_optionProc.processOptions([], c.arguments, "!" ~ c.name.value, c.location, 0.0f))
        {
            return;
        }

        auto kind = trackPropertyKindFromCommand(c.command, "!" ~ c.name.value);

        if (kind.isNull)
        {
            return;
        }

        compileBasicCommandIfItHasArgument(tb, c);

        if (kind.get == TrackPropertyKind.duration)
        {
            tb.compositionBuilder.conductorTrackBuilder.clearDurationPriorSpecs();
        }
        else
        {
            tb.clearPriorSpecs(kind.get);
        }
    }

    private void addConstPriorSpec(MultiTrackBuilder tb, ast.ModifierCommand c)
    {
        assert(c !is null);
        assert(c.name.value == "const");

        auto kind = trackPropertyKindFromCommand(c.command, "!" ~ c.name.value);

        if (kind.isNull)
        {
            return;
        }

        compileBasicCommandIfItHasArgument(tb, c);

        OptionValue value;
        Option valueOpt;
        valueOpt.position = 0;
        valueOpt.valueType = optionTypeFromTrackPropertyKind(kind.get);
        valueOpt.values = &value;

        if (!_optionProc.processOptions([valueOpt], c.arguments, "!" ~ c.name.value, c.location, tb.compositionBuilder.currentTime))
        {
            return;
        }

        if (kind.get == TrackPropertyKind.duration)
        {
            float t = value.data.get!float;
            tb.compositionBuilder.conductorTrackBuilder.addDurationPriorSpec(new ConstantPriorSpec!float(t));
        }
        else
        {
            Algebraic!(PriorSpec!int, PriorSpec!float) priorSpec;

            if (isIntegerProperty(kind.get))
            {
                priorSpec = cast(PriorSpec!int)new ConstantPriorSpec!int(value.data.get!int);
            }
            else
            {
                priorSpec = cast(PriorSpec!float)new ConstantPriorSpec!float(value.data.get!float);
            }

            tb.addPriorSpec(kind.get, priorSpec);
        }
    }

    private void addClampPriorSpecs(MultiTrackBuilder tb, ast.ModifierCommand c)
    {
        assert(c !is null);
        assert(c.name.value == "clamp");

        auto kind = trackPropertyKindFromCommand(c.command, "!" ~ c.name.value);

        if (kind.isNull)
        {
            return;
        }

        compileBasicCommandIfItHasArgument(tb, c);

        OptionValue minValue;
        Option minValueOpt;
        minValueOpt.key = "min";
        minValueOpt.position = 0;
        minValueOpt.valueType = optionTypeFromTrackPropertyKind(kind.get);
        minValueOpt.values = &minValue;

        OptionValue maxValue;
        Option maxValueOpt;
        maxValueOpt.key = "max";
        maxValueOpt.position = 1;
        maxValueOpt.valueType = optionTypeFromTrackPropertyKind(kind.get);
        maxValueOpt.values = &maxValue;

        if (!_optionProc.processOptions([minValueOpt, maxValueOpt], c.arguments, "!" ~ c.name.value, c.location, tb.compositionBuilder.currentTime))
        {
            return;
        }

        if (kind.get == TrackPropertyKind.duration)
        {
            if (maxValue.data.get!float < minValue.data.get!float)
            {
                _diagnosticsHandler.maxIsLessThanMin(minValue.location, maxValue.location, "!" ~ c.name.value);
                return;
            }

            tb.compositionBuilder.conductorTrackBuilder.addDurationPriorSpec(
                new ClampPriorSpec!float(minValue.data.get!float, maxValue.data.get!float)
            );
        }
        else
        {
            Algebraic!(PriorSpec!int, PriorSpec!float) priorSpec;

            if (isIntegerProperty(kind.get))
            {
                if (maxValue.data.get!int < minValue.data.get!int)
                {
                    _diagnosticsHandler.maxIsLessThanMin(minValue.location, maxValue.location, "!" ~ c.name.value);
                    return;
                }

                priorSpec = cast(PriorSpec!int)new ClampPriorSpec!int(
                    minValue.data.get!int, maxValue.data.get!int
                );
            }
            else
            {
                if (maxValue.data.get!float < minValue.data.get!float)
                {
                    _diagnosticsHandler.maxIsLessThanMin(minValue.location, maxValue.location, "!" ~ c.name.value);
                    return;
                }

                priorSpec = cast(PriorSpec!float)new ClampPriorSpec!float(
                    minValue.data.get!float, maxValue.data.get!float
                );
            }

            tb.addPriorSpec(kind.get, priorSpec);
        }
    }

    private void addPersistentOffset(MultiTrackBuilder tb, ast.ModifierCommand c)
    {
        assert(c !is null);
        assert(c.name.value == "persist");

        auto kind = trackPropertyKindFromCommand(c.command, "!" ~ c.name.value);

        if (kind.isNull)
        {
            return;
        }

        compileBasicCommandIfItHasArgument(tb, c);

        OptionValue value;
        Option valueOpt;
        valueOpt.position = 0;
        valueOpt.valueType = optionTypeFromTrackPropertyKind(kind.get);
        valueOpt.values = &value;

        if (!_optionProc.processOptions([valueOpt], c.arguments, "!" ~ c.name.value, c.location, tb.compositionBuilder.currentTime))
        {
            return;
        }

        if (kind.get == TrackPropertyKind.duration)
        {
            float t = value.data.get!float;
            tb.compositionBuilder.conductorTrackBuilder.incrementPersistentDurationOffset(t);
        }
        else
        {
            Algebraic!(int, float) n;

            if (isIntegerProperty(kind.get))
            {
                n = value.data.get!int;
            }
            else
            {
                n = value.data.get!float;
            }

            tb.incrementPersistentOffset(kind.get, n);
        }
    }

    private void addUniformRandomPriorSpec(MultiTrackBuilder tb, ast.ModifierCommand c)
    {
        assert(c !is null);
        assert(c.name.value == "rand");

        auto kind = trackPropertyKindFromCommand(c.command, "!" ~ c.name.value);

        if (kind.isNull)
        {
            return;
        }

        compileBasicCommandIfItHasArgument(tb, c);

        OptionValue minValue;
        Option minValueOpt;
        minValueOpt.key = "min";
        minValueOpt.position = 0;
        minValueOpt.valueType = optionTypeFromTrackPropertyKind(kind.get);
        minValueOpt.values = &minValue;

        OptionValue maxValue;
        Option maxValueOpt;
        maxValueOpt.key = "max";
        maxValueOpt.position = 1;
        maxValueOpt.valueType = optionTypeFromTrackPropertyKind(kind.get);
        maxValueOpt.values = &maxValue;

        if (!_optionProc.processOptions([minValueOpt, maxValueOpt], c.arguments, "!" ~ c.name.value, c.location, tb.compositionBuilder.currentTime))
        {
            return;
        }

        if (kind.get == TrackPropertyKind.duration)
        {
            if (maxValue.data.get!float < minValue.data.get!float)
            {
                _diagnosticsHandler.maxIsLessThanMin(minValue.location, maxValue.location, "!" ~ c.name.value);
                return;
            }

            tb.compositionBuilder.conductorTrackBuilder.addDurationPriorSpec(
                new UniformRandomPriorSpec!(typeof(_rng), float)(&_rng, minValue.data.get!float, maxValue.data.get!float)
            );
        }
        else
        {
            Algebraic!(PriorSpec!int, PriorSpec!float) priorSpec;

            if (isIntegerProperty(kind.get))
            {
                if (maxValue.data.get!int < minValue.data.get!int)
                {
                    _diagnosticsHandler.maxIsLessThanMin(minValue.location, maxValue.location, "!" ~ c.name.value);
                    return;
                }

                priorSpec = cast(PriorSpec!int)new UniformRandomPriorSpec!(typeof(_rng), int)(
                    &_rng, minValue.data.get!int, maxValue.data.get!int
                );
            }
            else
            {
                if (maxValue.data.get!float < minValue.data.get!float)
                {
                    _diagnosticsHandler.maxIsLessThanMin(minValue.location, maxValue.location, "!" ~ c.name.value);
                    return;
                }

                priorSpec = cast(PriorSpec!float)new UniformRandomPriorSpec!(typeof(_rng), float)(
                    &_rng, minValue.data.get!float, maxValue.data.get!float
                );
            }

            tb.addPriorSpec(kind.get, priorSpec);
        }
    }

    private void addNormalRandomPriorSpec(MultiTrackBuilder tb, ast.ModifierCommand c)
    {
        assert(c !is null);
        assert(c.name.value == "nrand");

        auto kind = trackPropertyKindFromCommand(c.command, "!" ~ c.name.value);

        if (kind.isNull)
        {
            return;
        }

        compileBasicCommandIfItHasArgument(tb, c);

        auto type = optionTypeFromTrackPropertyKind(kind.get);

        OptionValue meanValue;
        Option meanValueOpt;
        meanValueOpt.key = "mean";
        meanValueOpt.position = 0;
        meanValueOpt.valueType = type;
        meanValueOpt.values = &meanValue;

        OptionValue sdValue;
        Option sdValueOpt;
        sdValueOpt.key = "stddev";
        sdValueOpt.position = 1;

        if (type == OptionType.integer)
        {
            sdValueOpt.valueType = OptionType.floatingPoint;
        }
        else
        {
            sdValueOpt.valueType = type;
        }

        sdValueOpt.values = &sdValue;

        if (!_optionProc.processOptions([meanValueOpt, sdValueOpt], c.arguments, "!" ~ c.name.value, c.location, tb.compositionBuilder.currentTime))
        {
            return;
        }

        if (sdValue.data.get!float < 0.0f)
        {
            _diagnosticsHandler.negativeStdDev(sdValue.location, "!" ~ c.name.value);
            return;
        }

        if (kind.get == TrackPropertyKind.duration)
        {
            tb.compositionBuilder.conductorTrackBuilder.addDurationPriorSpec(
                new NormalRandomPriorSpec!(typeof(_rng), float)(&_rng, meanValue.data.get!float, sdValue.data.get!float)
            );
        }
        else
        {
            Algebraic!(PriorSpec!int, PriorSpec!float) priorSpec;

            if (isIntegerProperty(kind.get))
            {
                priorSpec = cast(PriorSpec!int)new NormalRandomPriorSpec!(typeof(_rng), int)(
                    &_rng, meanValue.data.get!int, sdValue.data.get!float
                );
            }
            else
            {
                priorSpec = cast(PriorSpec!float)new NormalRandomPriorSpec!(typeof(_rng), float)(
                    &_rng, meanValue.data.get!float, sdValue.data.get!float
                );
            }

            tb.addPriorSpec(kind.get, priorSpec);
        }
    }

    private void addOnNotePriorSpec(MultiTrackBuilder tb, ast.ModifierCommand c)
    {
        import std.range : enumerate;

        assert(c !is null);
        assert(c.name.value == "on_note");

        auto kind = trackPropertyKindFromCommand(c.command, "!" ~ c.name.value);

        if (kind.isNull)
        {
            return;
        }

        compileBasicCommandIfItHasArgument(tb, c);

        OptionValue[] values;
        Option valueOpt;
        valueOpt.multi = true;
        valueOpt.position = 0;
        valueOpt.valueType = optionTypeFromTrackPropertyKind(kind.get);
        valueOpt.values = appender(&values);

        OptionValue repeatCountValue;
        Option repeatCountValueOpt;
        repeatCountValueOpt.optional = true;
        repeatCountValueOpt.key = "repeat";
        repeatCountValueOpt.valueType = OptionType.integer;
        repeatCountValueOpt.values = &repeatCountValue;

        if (!_optionProc.processOptions([valueOpt, repeatCountValueOpt], c.arguments, "!" ~ c.name.value, c.location, tb.compositionBuilder.currentTime))
        {
            return;
        }

        int repeatCount = repeatCountValue.data.hasValue ? repeatCountValue.data.get!int : 1;

        if (repeatCount < 0)
        {
            _diagnosticsHandler.negativeRepeatCount(repeatCountValue.location, "!" ~ c.name.value);
            return;
        }

        alias getValues(T) = () => values.enumerate.map!(x => tuple(x.index.to!int, x.value.data.get!T)).array;

        if (kind.get == TrackPropertyKind.duration)
        {
            tb.compositionBuilder.conductorTrackBuilder.addDurationPriorSpec(
                new OnNotePriorSpec!float(tb.compositionBuilder.currentNoteCount, repeatCount, getValues!float())
            );
        }
        else
        {
            Algebraic!(PriorSpec!int, PriorSpec!float) priorSpec;

            if (isIntegerProperty(kind.get))
            {
                priorSpec = cast(PriorSpec!int)new OnNotePriorSpec!int(
                    tb.compositionBuilder.currentNoteCount, repeatCount, getValues!int()
                );
            }
            else
            {
                priorSpec = cast(PriorSpec!float)new OnNotePriorSpec!float(
                    tb.compositionBuilder.currentNoteCount, repeatCount, getValues!float()
                );
            }

            tb.addPriorSpec(kind.get, priorSpec);
        }
    }

    private void addOnTimePriorSpec(MultiTrackBuilder tb, ast.ModifierCommand c, bool linearInterpolation)
    {
        import std.range : slide;
        import std.typecons : No;

        assert(c !is null);
        assert(c.name.value == "on_time" || c.name.value == "on_time_l");

        auto kind = trackPropertyKindFromCommand(c.command, "!" ~ c.name.value);

        if (kind.isNull)
        {
            return;
        }

        compileBasicCommandIfItHasArgument(tb, c);

        OptionValue[] values;
        Option valueOpt;
        valueOpt.multi = true;
        valueOpt.position = 0;
        valueOpt.key = OptionType.duration;
        valueOpt.valueType = optionTypeFromTrackPropertyKind(kind.get);
        valueOpt.values = appender(&values);

        if (!_optionProc.processOptions([valueOpt], c.arguments, "!" ~ c.name.value, c.location, tb.compositionBuilder.currentTime))
        {
            return;
        }

        alias getValues(T) = () => values.slide!(No.withPartial)(2, 2).map!(x => tuple(x[0].data.get!float, x[1].data.get!T)).array;

        if (kind.get == TrackPropertyKind.duration)
        {
            tb.compositionBuilder.conductorTrackBuilder.addDurationPriorSpec(
                new OnTimePriorSpec!float(tb.compositionBuilder.currentTime, getValues!float(), linearInterpolation)
            );
        }
        else
        {
            Algebraic!(PriorSpec!int, PriorSpec!float) priorSpec;

            if (isIntegerProperty(kind.get))
            {
                priorSpec = cast(PriorSpec!int)new OnTimePriorSpec!int(
                    tb.compositionBuilder.currentTime, getValues!int(), linearInterpolation
                );
            }
            else
            {
                priorSpec = cast(PriorSpec!float)new OnTimePriorSpec!float(
                    tb.compositionBuilder.currentTime, getValues!float(), linearInterpolation
                );
            }

            tb.addPriorSpec(kind.get, priorSpec);
        }
    }

    private void addTransition(MultiTrackBuilder tb, ast.ModifierCommand c)
    {
        assert(c !is null);
        assert(c.name.value == "transition");

        auto kind = trackPropertyKindFromCommand(c.command, "!" ~ c.name.value);

        if (kind.isNull)
        {
            return;
        }

        compileBasicCommandIfItHasArgument(tb, c);

        OptionValue targetValue;
        Option targetValueOpt;
        targetValueOpt.key = "target";
        targetValueOpt.position = 0;
        targetValueOpt.valueType = optionTypeFromTrackPropertyKind(kind.get);
        targetValueOpt.values = &targetValue;

        OptionValue durationValue;
        Option durationValueOpt;
        durationValueOpt.key = "duration";
        durationValueOpt.position = 1;
        durationValueOpt.valueType = OptionType.duration;
        durationValueOpt.values = &durationValue;

        auto cb = tb.compositionBuilder;
        auto cdb = cb.conductorTrackBuilder;

        if (!_optionProc.processOptions([targetValueOpt, durationValueOpt], c.arguments, "!" ~ c.name.value, c.location, cb.currentTime))
        {
            return;
        }

        if (kind.get == TrackPropertyKind.duration)
        {
            float t = targetValue.data.get!float;
            cdb.setDuration(OptionalSign.plus, t);
            cdb.addDurationPriorSpec(
                new OnTimePriorSpec!float(cb.currentTime, [tuple(0.0f, -t), tuple(durationValue.data.get!float, 0.0f)], true)
            );
        }
        else
        {
            Algebraic!(int, float) target;
            Algebraic!(PriorSpec!int, PriorSpec!float) priorSpec;

            if (isIntegerProperty(kind.get))
            {
                int t = targetValue.data.get!int;
                target = t;
                priorSpec = cast(PriorSpec!int)new OnTimePriorSpec!int(
                    cb.currentTime, [tuple(0.0f, -t), tuple(durationValue.data.get!float, 0)], true
                );
            }
            else
            {
                float t = targetValue.data.get!float;
                target = t;
                priorSpec = cast(PriorSpec!float)new OnTimePriorSpec!float(
                    cb.currentTime, [tuple(0.0f, -t), tuple(durationValue.data.get!float, 0.0f)], true
                );
            }

            tb.setTrackProperty(kind.get, OptionalSign.plus, target);
            tb.addPriorSpec(kind.get, priorSpec);
        }
    }

    private Nullable!byte evaluateAsByte(string context, ast.Expression expr)
    {
        assert(expr !is null);

        int v = _intEvaluator.evaluate(expr);

        if (!(0 <= v && v <= 127))
        {
            _diagnosticsHandler.valueIsOutOfRange(expr.location, context, 0, 127, v);
            return typeof(return).init;
        }

        return typeof(return)(v.to!byte);
    }

    private int countNoteLikeCommands(ast.Command c, SourceLocation requestLoc, string requestContext)
    {
        assert(c !is null);

        switch (c.kind)
        {
        case ast.CommandKind.basic:
            auto bc = cast(ast.BasicCommand)c;
            return (bc.name == "r" && bc.sign == OptionalSign.none) || bc.name == "_" ? 1 : 0;

        case ast.CommandKind.note:
            return 1;

        case ast.CommandKind.scoped:
            auto sc = cast(ast.ScopedCommand)c;
            return sc.commands.map!(x => countNoteLikeCommands(x, requestLoc, requestContext)).sum(0);

        default:
            _diagnosticsHandler.cannotCountNoteLikeCommand(c.location, requestLoc, requestContext);
            return 0;
        }
    }

    private Nullable!TrackPropertyKind trackPropertyKindFromCommand(ast.Command c, string context)
    {
        auto bc = cast(ast.BasicCommand)c;

        if (bc is null)
        {
            _diagnosticsHandler.expectedTrackPropertyCommand(c.location, context);
            return typeof(return).init;
        }

        switch (bc.name)
        {
        case "l":
            return typeof(return)(TrackPropertyKind.duration);

        case "n":
            return typeof(return)(TrackPropertyKind.keyShift);

        case "o":
            return typeof(return)(TrackPropertyKind.octave);

        case "q":
            return typeof(return)(TrackPropertyKind.gateTime);

        case "t":
            return typeof(return)(TrackPropertyKind.timeShift);

        case "v":
            return typeof(return)(TrackPropertyKind.velocity);

        default:
            _diagnosticsHandler.expectedTrackPropertyCommand(bc.location, context);
            return typeof(return).init;
        }
    }

    private void compileBasicCommandIfItHasArgument(MultiTrackBuilder tb, ast.ModifierCommand c)
    {
        assert(c !is null);
        auto bc = cast(ast.BasicCommand)c.command;

        if (bc !is null && bc.argument !is null)
        {
            compileCommand(tb, bc);
        }
    }

    private OptionType optionTypeFromTrackPropertyKind(TrackPropertyKind kind)
    {
        final switch (kind)
        {
        case TrackPropertyKind.duration:
        case TrackPropertyKind.timeShift:
            return OptionType.duration;

        case TrackPropertyKind.octave:
        case TrackPropertyKind.keyShift:
            return OptionType.integer;

        case TrackPropertyKind.velocity:
            return OptionType.floatRatio127;

        case TrackPropertyKind.gateTime:
            return OptionType.floatRatio100;
        }
    }

    private BlockScopeContext saveContext()
    {
        return BlockScopeContext(
            _noteMacroManager.saveContext(),
            _expressionMacroManager.saveContext()
        );
    }

    private void restoreContext(BlockScopeContext c)
    {
        _expressionMacroManager.restoreContext(c.expressionMacroManagerContext);
        _noteMacroManager.restoreContext(c.noteMacroManagerContext);
    }

    private DiagnosticsHandler _diagnosticsHandler;
    private SourceManager _sourceManager;
    private Parser _parser;
    private NoteMacroManager _noteMacroManager;
    private ExpressionMacroManager _expressionMacroManager;
    private DurationExpressionEvaluator _durationEvaluator;
    private NumericExpressionEvaluator!int _intEvaluator;
    private NumericExpressionEvaluator!float _floatEvaluator;
    private StringExpressionEvaluator _strEval;
    private CommandBlockExpressionEvaluator _commandEval;
    private OptionProcessor _optionProc;
    private XorShift128Plus _rng;
    private int _includeDepth = 0;
}
