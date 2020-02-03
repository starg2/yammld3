
module yammld3.irgen;

import std.range.primitives;

import ast = yammld3.ast;
import yammld3.common;
import yammld3.eval;
import ir = yammld3.ir;
import yammld3.irgenutil;
import yammld3.priorspec;

private float delegate(float, ast.TimeLiteral) timeEvaluator(ConductorTrackBuilder cdb)
{
    return (startTime, t) => cdb.toTime(startTime, t.time);
}

public final class IRGenerator
{
    import std.conv : to;
    import std.random : Random;
    import std.typecons : Nullable;
    import std.variant : Algebraic;

    import yammld3.diagnostics : DiagnosticsHandler;
    import yammld3.source : SourceLocation;

    public this(DiagnosticsHandler handler)
    {
        _diagnosticsHandler = handler;
    }

    public ir.Composition compileModule(ast.Module am)
    {
        assert(am !is null);
        auto cb = new CompositionBuilder(am.name);
        auto tb = cb.selectDefaultTrack();
        compileCommands(tb, am.commands);
        return cb.build();
    }

    private void compileCommands(MultiTrackBuilder tb, ast.Command[] commands)
    {
        foreach (c; commands)
        {
            assert(c !is null);
            compileCommand(tb, c);
        }
    }

    private void compileCommand(MultiTrackBuilder tb, ast.Command c)
    {
        assert(c !is null);

        final switch (c.kind)
        {
        case ast.CommandKind.basic:
            compileBasicCommand(tb, cast(ast.BasicCommand)c);
            break;

        case ast.CommandKind.note:
            compileNoteCommand(tb, cast(ast.NoteCommand)c);
            break;

        case ast.CommandKind.extension:
            compileExtensionCommand(tb, cast(ast.ExtensionCommand)c);
            break;

        case ast.CommandKind.scoped:
            compileScopedCommand(tb, cast(ast.ScopedCommand)c);
            break;

        case ast.CommandKind.modifier:
            compileModifierCommand(tb, cast(ast.ModifierCommand)c);
            break;

        case ast.CommandKind.repeat:
            compileRepeatCommand(tb, cast(ast.RepeatCommand)c);
            break;

        case ast.CommandKind.tuplet:
            compileTupletCommand(tb, cast(ast.TupletCommand)c);
            break;

        case ast.CommandKind.chord:
            compileChordCommand(tb, cast(ast.ChordCommand)c);
            break;
        }
    }

    private void compileBasicCommand(MultiTrackBuilder tb, ast.BasicCommand c)
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
            // pitch bend
            _diagnosticsHandler.notImplemented(c.location, "i command");
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

    private void compileNoteCommand(MultiTrackBuilder tb, ast.NoteCommand c)
    {
        assert(c !is null);

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
            auto de = new DurationExpressionEvaluator(_diagnosticsHandler, timeEvaluator(cdb));
            duration = de.evaluate(curTime, c.duration);
        }

        ir.NoteInfo noteInfo;
        noteInfo.key = c.octaveShift * 12 + cast(int)c.baseKey + c.accidental;
        noteInfo.velocity = 0.0f;
        noteInfo.timeShift = 0.0f;
        noteInfo.lastNominalDuration = duration;
        noteInfo.gateTime = 0.0f;

        ir.Note note;
        note.nominalTime = curTime;
        note.noteInfo = noteInfo;
        note.nominalDuration = duration;

        tb.putNote(noteCount, curTime, note);
        cb.currentTime = curTime + duration;
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
            auto de = new DurationExpressionEvaluator(_diagnosticsHandler, timeEvaluator(cdb));
            duration = de.evaluate(curTime, c.argument);
        }

        ir.Note note;
        note.nominalTime = curTime;
        note.nominalDuration = duration;

        tb.putNote(noteCount, curTime, note);
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
        auto de = new DurationExpressionEvaluator(_diagnosticsHandler, timeEvaluator(cb.conductorTrackBuilder));
        float duration = de.evaluate(curTime, c.argument);

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
            auto de = new DurationExpressionEvaluator(_diagnosticsHandler, timeEvaluator(cdb));
            duration = de.evaluate(curTime, c.argument);
        }

        tb.extendPreviousNote(noteCount, curTime, duration);
        cb.currentTime = curTime + duration;
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

        auto de = new DurationExpressionEvaluator(_diagnosticsHandler, timeEvaluator(cdb));
        cdb.setDuration(sign, de.evaluate(curTime, arg));
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
                auto ie = new NumericExpressionEvaluator!int(_diagnosticsHandler);
                value = ie.evaluate(arg);
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
                auto fe = new NumericExpressionEvaluator!float(_diagnosticsHandler);
                value = toPercentage(kind, fe.evaluate(arg));
            }
        }
        
        tb.setTrackProperty(kind, sign, value);
    }

    private void compileExtensionCommand(MultiTrackBuilder tb, ast.ExtensionCommand c)
    {
        assert(c !is null);

        switch (c.name.value)
        {
        case "attack_time":
            compileControlChangeCommand(tb, ir.ControlChangeCode.attackTime, c);
            break;

        case "brightness":
            compileControlChangeCommand(tb, ir.ControlChangeCode.brightness, c);
            break;

        case "channel":
            setChannel(tb, c);
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

        case "decay_time":
            compileControlChangeCommand(tb, ir.ControlChangeCode.decayTime, c);
            break;

        case "expression":
            compileControlChangeCommand(tb, ir.ControlChangeCode.expression, c);
            break;

        case "fork":
            compileForkCommand(tb, c);
            break;

        case "gm_reset":
            resetSystem(tb.compositionBuilder, ir.SystemKind.gm, c);
            break;

        case "gs_reset":
            resetSystem(tb.compositionBuilder, ir.SystemKind.gs, c);
            break;

        case "key":
            setKeySignature(tb.compositionBuilder, c);
            break;

        case "meter":
            setMeter(tb.compositionBuilder, c);
            break;

        case "pan":
            compileControlChangeCommand(tb, ir.ControlChangeCode.pan, c);
            break;

        case "program":
            setProgram(tb, c);
            break;

        case "release_time":
            compileControlChangeCommand(tb, ir.ControlChangeCode.releaseTime, c);
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

        case "tempo":
            setTempo(tb.compositionBuilder, c);
            break;

        case "track":
            compileTrackCommand(tb, c);
            break;

        case "tremolo":
            compileControlChangeCommand(tb, ir.ControlChangeCode.effect2Depth, c);
            break;

        case "volume":
            compileControlChangeCommand(tb, ir.ControlChangeCode.channelVolume, c);
            break;

        case "xg_reset":
            resetSystem(tb.compositionBuilder, ir.SystemKind.xg, c);
            break;

        default:
            _diagnosticsHandler.undefinedExtensionCommand(c.location, c.name.value);
            break;
        }
    }

    private void compileScopedCommand(MultiTrackBuilder tb, ast.ScopedCommand c)
    {
        assert(c !is null);
        auto context = tb.saveContext();
        compileCommands(tb, c.commands);
        tb.restoreContext(context);
    }

    private void compileModifierCommand(MultiTrackBuilder tb, ast.ModifierCommand c)
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
        
        case "clear":
            clearPriorSpecs(tb, c);
            break;
        
        case "const":
            addConstPriorSpec(tb, c);
            break;
        
        case "nrand":
            _diagnosticsHandler.notImplemented(c.location, "!" ~ c.name.value);
            break;
        
        case "on_note":
            _diagnosticsHandler.notImplemented(c.location, "!" ~ c.name.value);
            break;
        
        case "on_time":
            _diagnosticsHandler.notImplemented(c.location, "!" ~ c.name.value);
            break;
        
        case "on_time_l":
            _diagnosticsHandler.notImplemented(c.location, "!" ~ c.name.value);
            break;
        
        case "rand":
            _diagnosticsHandler.notImplemented(c.location, "!" ~ c.name.value);
            break;
        
        //case "transition":
        //    _diagnosticsHandler.notImplemented(c.location, "!" ~ c.name.value);
        //    break;
        
        default:
            _diagnosticsHandler.undefinedModifierCommand(c.location, c.name.value);
            break;
        }
    }

    private void compileRepeatCommand(MultiTrackBuilder tb, ast.RepeatCommand c)
    {
        assert(c !is null);

        int repeatCount = 2;

        if (c.repeatCount !is null)
        {
            auto ie = new NumericExpressionEvaluator!int(_diagnosticsHandler);
            repeatCount = ie.evaluate(c.repeatCount);

            if (repeatCount < 0)
            {
                _diagnosticsHandler.negativeRepeatCount(c.repeatCount.location);
                repeatCount = 0;
            }
        }

        foreach(i; 0..repeatCount)
        {
            auto context = tb.saveContext();
            compileCommand(tb, c.command);
            tb.restoreContext(context);
        }
    }

    private void compileTupletCommand(MultiTrackBuilder tb, ast.TupletCommand c)
    {
        assert(c !is null);
        auto cb = tb.compositionBuilder;
        auto cdb = cb.conductorTrackBuilder;
        int noteCount = cb.currentNoteCount;
        float curTime = cb.currentTime;

        float duration;

        if (c.duration is null)
        {
            duration = cdb.getDurationFor(noteCount, curTime);
        }
        else
        {
            auto de = new DurationExpressionEvaluator(_diagnosticsHandler, timeEvaluator(cdb));
            duration = de.evaluate(curTime, c.duration);
        }

        int noteLikeCommandCount = countNoteLikeCommands(c.command, c.location, "tuplet command");

        auto context = tb.saveContext();
        cdb.setDuration(OptionalSign.none, noteLikeCommandCount > 0 ? duration / noteLikeCommandCount : duration);
        compileCommand(tb, c.command);
        tb.restoreContext(context);
    }

    private void compileChordCommand(MultiTrackBuilder tb, ast.ChordCommand c)
    {
        assert(c !is null);

        auto cb = tb.compositionBuilder;
        float startTime = cb.currentTime;
        float endTime = startTime;

        foreach (child; c.children)
        {
            import std.algorithm.comparison : max;

            cb.currentTime = startTime;
            compileCommand(tb, child);
            endTime = max(endTime, cb.currentTime);
        }

        cb.currentTime = endTime;
    }

    private void setChannel(MultiTrackBuilder tb, ast.ExtensionCommand c)
    {
        assert(c !is null);
        assert(c.name.value == "channel");

        if (c.block !is null)
        {
            _diagnosticsHandler.unexpectedCommandBlock(c.location, "%" ~ c.name.value);
        }

        if (!verifySingleKeylessArgument(c))
        {
            return;
        }

        auto ie = new NumericExpressionEvaluator!int(_diagnosticsHandler);
        int ch = ie.evaluate(c.arguments.items[0].value);

        if (!(0 <= ch && ch < maxChannelCount))
        {
            _diagnosticsHandler.invalidChannel(c.arguments.items[0].value.location, "%" ~ c.name.value, ch);
        }

        tb.setChannel(ch);
    }

    private void compileControlChangeCommand(MultiTrackBuilder tb, ast.ExtensionCommand c)
    {
        assert(c !is null);
        assert(c.name.value == "control");

        if (c.block !is null)
        {
            _diagnosticsHandler.unexpectedCommandBlock(c.location, "%" ~ c.name.value);
        }

        if (c.arguments is null)
        {
            _diagnosticsHandler.expectedArgumentList(c.location, "%" ~ c.name.value);
            return;
        }

        if (c.arguments.items.length != 2)
        {
            _diagnosticsHandler.wrongNumberOfArguments(c.arguments.location, "%" ~ c.name.value, 2, c.arguments.items.length);
            return;
        }

        foreach (arg; c.arguments.items)
        {
            if (arg.key !is null)
            {
                _diagnosticsHandler.unexpectedArgumentKey(arg.key.location, "%" ~ c.name.value);
                return;
            }
        }

        auto code = evaluateAsByte("%" ~ c.name.value, c.arguments.items[0].value);
        auto value = evaluateAsByte("%" ~ c.name.value, c.arguments.items[1].value);

        if (code.isNull || value.isNull)
        {
            return;
        }

        ir.ControlChange cc;
        cc.nominalTime = tb.compositionBuilder.currentTime;
        cc.code = cast(ir.ControlChangeCode)code.get;
        cc.value = value.get;

        tb.setControlChange(cc);
    }
    
    private void compileControlChangeCommand(MultiTrackBuilder tb, ir.ControlChangeCode code, ast.ExtensionCommand c)
    {
        assert(c !is null);

        if (c.block !is null)
        {
            _diagnosticsHandler.unexpectedCommandBlock(c.location, "%" ~ c.name.value);
        }

        if (!verifySingleKeylessArgument(c))
        {
            return;
        }

        auto value = evaluateAsByte("%" ~ c.name.value, c.arguments.items[0].value);

        if (value.isNull)
        {
            return;
        }

        ir.ControlChange cc;
        cc.nominalTime = tb.compositionBuilder.currentTime;
        cc.code = code;
        cc.value = value.get;

        tb.setControlChange(cc);
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

        ir.ControlChange cc;
        cc.nominalTime = tb.compositionBuilder.currentTime;
        cc.code = code;
        cc.value = isBinary && value.get > 0 ? 127 : value.get;

        tb.setControlChange(cc);
    }

    private void resetSystem(CompositionBuilder cb, ir.SystemKind kind, ast.ExtensionCommand c)
    {
        assert(c !is null);
        
        if (c.block !is null)
        {
            _diagnosticsHandler.unexpectedCommandBlock(c.location, "%" ~ c.name.value);
        }

        if (c.arguments !is null && c.arguments.items.length > 0)
        {
            _diagnosticsHandler.wrongNumberOfArguments(c.arguments.location, "%" ~ c.name.value, 0, c.arguments.items.length);
        }
        
        cb.conductorTrackBuilder.resetSystem(cb.currentTime, kind);
    }

    private void setTempo(CompositionBuilder cb, ast.ExtensionCommand c)
    {
        assert(c !is null);
        assert(c.name.value == "tempo");

        if (c.block !is null)
        {
            _diagnosticsHandler.unexpectedCommandBlock(c.location, "%" ~ c.name.value);
        }

        if (!verifySingleKeylessArgument(c))
        {
            return;
        }

        auto fe = new NumericExpressionEvaluator!float(_diagnosticsHandler);
        float tempo = fe.evaluate(c.arguments.items[0].value);

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

        if (!verifySingleKeylessArgument(c))
        {
            return;
        }

        auto be = cast(ast.BinaryExpression)c.arguments.items[0].value;

        if (be is null || be.op.kind != ast.OperatorKind.slash)
        {
            _diagnosticsHandler.unexpectedExpressionKind(c.arguments.items[0].value.location, "%" ~ c.name.value);
            return;
        }

        auto ie = new NumericExpressionEvaluator!int(_diagnosticsHandler);
        Fraction!int m;
        m.numerator = ie.evaluate(be.left);
        m.denominator = ie.evaluate(be.right);

        if (m.denominator == 0)
        {
            _diagnosticsHandler.divideBy0(be.right.location);
            return;
        }

        // TODO: clamp value
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

        if (!verifySingleKeylessArgument(c))
        {
            return;
        }

        auto str = cast(ast.StringLiteral)c.arguments.items[0].value;

        if (str is null)
        {
            _diagnosticsHandler.unexpectedExpressionKind(c.arguments.items[0].value.location, "%" ~ c.name.value);
            return;
        }

        auto ks = makeKeySigEvent(cb.currentTime, str.value);

        if (ks.isNull)
        {
            _diagnosticsHandler.undefinedKeySignature(str.location, "%" ~ c.name.value);
            return;
        }

        cb.conductorTrackBuilder.setKeySig(ks.get);
    }
    
    private void addTextEventToConductorTrack(CompositionBuilder cb, ir.MetaEventKind kind, ast.ExtensionCommand c)
    {
        assert(c !is null);

        if (c.block !is null)
        {
            _diagnosticsHandler.unexpectedCommandBlock(c.location, "%" ~ c.name.value);
        }

        if (!verifySingleKeylessArgument(c))
        {
            return;
        }

        auto str = cast(ast.StringLiteral)c.arguments.items[0].value;

        if (str is null)
        {
            _diagnosticsHandler.unexpectedExpressionKind(c.arguments.items[0].value.location, "%" ~ c.name.value);
            return;
        }

        ir.TextMetaEvent te;
        te.nominalTime = cb.currentTime;
        te.kind = kind;
        te.text = str.value;
        cb.conductorTrackBuilder.addTextEvent(te);
    }

    private void setProgram(MultiTrackBuilder tb, ast.ExtensionCommand c)
    {
        assert(c !is null);
        assert(c.name.value == "program");

        if (c.block !is null)
        {
            _diagnosticsHandler.unexpectedCommandBlock(c.location, "%" ~ c.name.value);
        }

        if (c.arguments is null)
        {
            _diagnosticsHandler.expectedArgumentList(c.location, "%" ~ c.name.value);
            return;
        }

        ir.ProgramChange pc;
        pc.nominalTime = tb.compositionBuilder.currentTime;

        foreach (arg; c.arguments.items)
        {
            if (arg.key is null)
            {
                auto prog = evaluateAsByte("%" ~ c.name.value, arg.value);

                if (!prog.isNull)
                {
                    pc.program = prog.get;
                }
            }
            else
            {
                auto ident = cast(ast.Identifier)arg.key;

                if (ident.value == "bank_lsb")
                {
                    auto lsb = evaluateAsByte("%" ~ c.name.value, arg.value);

                    if (!lsb.isNull)
                    {
                        pc.bankLSB = lsb.get;
                    }
                }
                else if (ident.value == "bank_msb")
                {
                    auto msb = evaluateAsByte("%" ~ c.name.value, arg.value);

                    if (!msb.isNull)
                    {
                        pc.bankMSB = msb.get;
                    }
                }
                else
                {
                    _diagnosticsHandler.unexpectedArgumentKey(arg.key.location, "%" ~ c.name.value);
                }
            }
        }

        tb.setProgram(pc);
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

        if (c.arguments !is null)
        {
            if (c.arguments.items.length > 1)
            {
                _diagnosticsHandler.wrongNumberOfArguments(c.arguments.location, "%" ~ c.name.value, 0, 1, c.arguments.items.length);
            }
            else if (c.arguments.items.length == 1)
            {
                if (c.arguments.items[0].key !is null)
                {
                    _diagnosticsHandler.unexpectedArgumentKey(c.arguments.items[0].key.location, "%" ~ c.name.value);
                }
                else
                {
                    auto de = new DurationExpressionEvaluator(_diagnosticsHandler, timeEvaluator(cb.conductorTrackBuilder));
                    cb.currentTime = de.evaluate(0.0f, c.arguments.items[0].value);
                }
            }
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

        if (c.arguments !is null)
        {
            if (c.arguments.items.length > 1)
            {
                _diagnosticsHandler.wrongNumberOfArguments(c.arguments.location, "%" ~ c.name.value, 0, 1, c.arguments.items.length);
            }
            else if (c.arguments.items.length == 1)
            {
                if (c.arguments.items[0].key !is null)
                {
                    _diagnosticsHandler.unexpectedArgumentKey(c.arguments.items[0].key.location, "%" ~ c.name.value);
                }
                else
                {
                    auto de = new DurationExpressionEvaluator(_diagnosticsHandler, timeEvaluator(cb.conductorTrackBuilder));
                    startTime = de.evaluate(0.0f, c.arguments.items[0].value);
                }
            }
        }

        float endTime = startTime;

        foreach (command; c.block.commands)
        {
            import std.algorithm.comparison : max;

            cb.currentTime = startTime;
            compileCommand(tb, command);
            endTime = max(endTime, cb.currentTime);
        }

        cb.currentTime = endTime;
    }

    private void compileTrackCommand(MultiTrackBuilder tb, ast.ExtensionCommand c)
    {
        import std.array : appender;

        assert(c !is null);
        assert(c.name.value == "track");

        if (c.block is null)
        {
            _diagnosticsHandler.expectedCommandBlock(c.location, "%" ~ c.name.value);
            return;
        }

        if (c.arguments is null)
        {
            _diagnosticsHandler.expectedArgumentList(c.location, "%" ~ c.name.value);
        }

        auto trackNames = appender!(string[]);

        foreach (arg; c.arguments.items)
        {
            if (arg.key !is null)
            {
                _diagnosticsHandler.unexpectedArgumentKey(arg.key.location, "%" ~ c.name.value);
            }
            else
            {
                auto name = cast(ast.Identifier)arg.value;

                if (name is null)
                {
                    _diagnosticsHandler.unexpectedExpressionKind(arg.value.location, "%" ~ c.name.value);
                }
                else
                {
                    trackNames.put(name.value);
                }
            }
        }

        auto cb = tb.compositionBuilder;
        compileCommands(cb.selectTracks(trackNames[]), c.block.commands);
    }
    
    private void clearPriorSpecs(MultiTrackBuilder tb, ast.ModifierCommand c)
    {
        assert(c !is null);
        assert(c.name.value == "clear");
        
        if (c.arguments !is null && c.arguments.items.length != 0)
        {
            _diagnosticsHandler.wrongNumberOfArguments(c.arguments.location, "!" ~ c.name.value, 0, c.arguments.items.length);
            return;
        }
        
        auto kind = trackPropertyKindFromCommand(c.command, "!" ~ c.name.value);
        
        if (kind.isNull)
        {
            return;
        }
        
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
        
        if (c.arguments is null)
        {
            _diagnosticsHandler.expectedArgumentList(c.location, "!" ~ c.name.value);
            return;
        }
        
        if (c.arguments.items.length != 1)
        {
            _diagnosticsHandler.wrongNumberOfArguments(c.arguments.location, "!" ~ c.name.value, 1, c.arguments.items.length);
            return;
        }
        
        if (c.arguments.items[0].key !is null)
        {
            _diagnosticsHandler.unexpectedArgumentKey(c.arguments.items[0].key.location, "!" ~ c.name.value);
            return;
        }

        auto kind = trackPropertyKindFromCommand(c.command, "!" ~ c.name.value);
        
        if (kind.isNull)
        {
            return;
        }
        
        auto cb = tb.compositionBuilder;
        
        if (kind.get == TrackPropertyKind.duration)
        {
            auto de = new DurationExpressionEvaluator(_diagnosticsHandler, timeEvaluator(cb.conductorTrackBuilder));
            float t = de.evaluate(cb.currentTime, c.arguments.items[0].value);
            tb.compositionBuilder.conductorTrackBuilder.addDurationPriorSpec(new ConstantPriorSpec!float(t));
        }
        else
        {
            Algebraic!(PriorSpec!int, PriorSpec!float) priorSpec;
            
            if (isIntegerProperty(kind.get))
            {
                auto ie = new NumericExpressionEvaluator!int(_diagnosticsHandler);
                priorSpec = cast(PriorSpec!int)new ConstantPriorSpec!int(ie.evaluate(c.arguments.items[0].value));
            }
            else
            {
                auto fe = new NumericExpressionEvaluator!float(_diagnosticsHandler);
                priorSpec = cast(PriorSpec!float)new ConstantPriorSpec!float(fe.evaluate(c.arguments.items[0].value));
            }
            
            tb.addPriorSpec(kind.get, priorSpec);
        }
    }
    
    private bool verifySingleKeylessArgument(ast.ExtensionCommand c)
    {
        assert(c !is null);

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
            _diagnosticsHandler.unexpectedArgumentKey(c.arguments.items[0].key.location, "%" ~ c.name.value);
            return false;
        }

        return true;
    }

    private Nullable!byte evaluateAsByte(string context, ast.Expression expr)
    {
        assert(expr !is null);

        auto ie = new NumericExpressionEvaluator!int(_diagnosticsHandler);
        int v = ie.evaluate(expr);

        if (!(0 <= v && v <= 127))
        {
            _diagnosticsHandler.valueIsOutOfRange(expr.location, context, 0, 127, v);
            return typeof(return).init;
        }

        return typeof(return)(v.to!byte);
    }

    private int countNoteLikeCommands(ast.Command c, SourceLocation requestLoc, string requestContext)
    {
        import std.algorithm.iteration : map, sum;
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
    
    private DiagnosticsHandler _diagnosticsHandler;
    private Random _rng;
}
