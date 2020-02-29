
module yammld3.irprinter;

import yammld3.common;
import yammld3.ir;

private string keyNameToString(KeyName key)
{
    final switch (key)
    {
    case KeyName.c:
        return "C";

    case KeyName.cSharp:
        return "C#";

    case KeyName.d:
        return "D";

    case KeyName.dSharp:
        return "D#";

    case KeyName.e:
        return "E";

    case KeyName.f:
        return "F";

    case KeyName.fSharp:
        return "F#";

    case KeyName.g:
        return "G";

    case KeyName.gSharp:
        return "G#";

    case KeyName.a:
        return "A";

    case KeyName.aSharp:
        return "A#";

    case KeyName.b:
        return "B";
    }
}

private string systemKindToString(SystemKind kind)
{
    final switch (kind)
    {
    case SystemKind.gm:
        return "GM";

    case SystemKind.gs:
        return "GS";

    case SystemKind.xg:
        return "XG";
    }
}

private string gsInsertionEffectTypeToString(GSInsertionEffectType type)
{
    final switch (type)
    {
    case GSInsertionEffectType.thru:
        return "Thru";

    case GSInsertionEffectType.stereoEQ:
        return "Stereo-EQ";

    case GSInsertionEffectType.spectrum:
        return "Spectrum";

    case GSInsertionEffectType.enhancer:
        return "Enhancer";

    case GSInsertionEffectType.humanizer:
        return "Humanizer";

    case GSInsertionEffectType.overdrive:
        return "Overdrive";

    case GSInsertionEffectType.distortion:
        return "Distortion";

    case GSInsertionEffectType.phaser:
        return "Phaser";

    case GSInsertionEffectType.autoWah:
        return "Auto Wah";

    case GSInsertionEffectType.rotary:
        return "Rotary";

    case GSInsertionEffectType.stereoFlanger:
        return "Stereo Flanger";

    case GSInsertionEffectType.stepFlanger:
        return "Step Flanger";

    case GSInsertionEffectType.tremolo:
        return "Tremolo";

    case GSInsertionEffectType.autoPan:
        return "Auto Pan";

    case GSInsertionEffectType.compressor:
        return "Compressor";

    case GSInsertionEffectType.limiter:
        return "Limiter";

    case GSInsertionEffectType.hexaChorus:
        return "Hexa Chorus";

    case GSInsertionEffectType.tremoloChorus:
        return "Tremolo Chorus";

    case GSInsertionEffectType.stereoChorus:
        return "Stereo Chorus";

    case GSInsertionEffectType.spaceD:
        return "Space D";

    case GSInsertionEffectType._3dChorus:
        return "3D Chorus";

    case GSInsertionEffectType.stereoDelay:
        return "Stereo Delay";

    case GSInsertionEffectType.modDelay:
        return "Mod Delay";

    case GSInsertionEffectType._3TapDelay:
        return "3 Tap Delay";

    case GSInsertionEffectType._4TapDelay:
        return "4 Tap Delay";

    case GSInsertionEffectType.tmCtrlDelay:
        return "Tm Ctrl Delay";

    case GSInsertionEffectType.reverb:
        return "Reverb";

    case GSInsertionEffectType.gateReverb:
        return "Gate Reverb";

    case GSInsertionEffectType._3dDelay:
        return "3D Delay";

    case GSInsertionEffectType._2PitchShifter:
        return "2 Pitch Shifter";

    case GSInsertionEffectType.fbPShifter:
        return "Fb P.Shifter";

    case GSInsertionEffectType._3dAuto:
        return "3D Auto";

    case GSInsertionEffectType._3dManual:
        return "3D Manual";

    case GSInsertionEffectType.loFi1:
        return "Lo-Fi 1";

    case GSInsertionEffectType.loFi2:
        return "Lo-Fi 2";

    case GSInsertionEffectType.odChorus:
        return "OD->Chorus";

    case GSInsertionEffectType.odFlanger:
        return "OD->Flanger";

    case GSInsertionEffectType.odDelay:
        return "OD->Delay";

    case GSInsertionEffectType.dsChorus:
        return "DS->Chorus";

    case GSInsertionEffectType.dsFlanger:
        return "DS->Flanger";

    case GSInsertionEffectType.dsDelay:
        return "DS->Delay";

    case GSInsertionEffectType.ehChorus:
        return "EH->Chorus";

    case GSInsertionEffectType.ehFlanger:
        return "EH->Flanger";

    case GSInsertionEffectType.ehDelay:
        return "EH->Delay";

    case GSInsertionEffectType.choDelay:
        return "Cho->Delay";

    case GSInsertionEffectType.flDelay:
        return "FL->Delay";

    case GSInsertionEffectType.choFlanger:
        return "Cho->Flanger";

    case GSInsertionEffectType.rotaryMulti:
        return "Rotary Multi";

    case GSInsertionEffectType.gtrMulti1:
        return "GTR Multi 1";

    case GSInsertionEffectType.gtrMulti2:
        return "GTR Multi 2";

    case GSInsertionEffectType.gtrMulti3:
        return "GTR Multi 3";

    case GSInsertionEffectType.cleanGtMulti1:
        return "Clean Gt Multi 1";

    case GSInsertionEffectType.cleanGtMulti2:
        return "Clean Gt Multi 2";

    case GSInsertionEffectType.bassMulti:
        return "Bass Multi";

    case GSInsertionEffectType.rhodesMulti:
        return "Rhodes Multi";

    case GSInsertionEffectType.keyboardMulti:
        return "Keyboard Multi";

    case GSInsertionEffectType.choPlusDelay:
        return "Cho/Delay";

    case GSInsertionEffectType.flPlusDelay:
        return "FL/Delay";

    case GSInsertionEffectType.choPlusFlanger:
        return "Cho/Flanger";

    case GSInsertionEffectType.od1PlusOd2:
        return "OD1/Od2";

    case GSInsertionEffectType.odPlusRotary:
        return "OD/Rotary";

    case GSInsertionEffectType.odPlusPhaser:
        return "OD/Phaser";

    case GSInsertionEffectType.odPlusAutoWah:
        return "OD/AutoWah";

    case GSInsertionEffectType.phPlusRotary:
        return "PH/Rotary";

    case GSInsertionEffectType.phPlusAutoWah:
        return "PH/AutoWah";
    }
}

public final class IRPrinter(Writer)
{
    import std.conv : text;
    import yammld3.xmlwriter : XMLAttribute, XMLWriter;

    public this(Writer output, string indent = "")
    {
        _writer = new XMLWriter!Writer(output, indent);
    }

    public void printComposition(Composition composition)
    {
        assert(composition !is null);
        _writer.startDocument();
        _writer.startElement("Composition", [XMLAttribute("Name", composition.name)]);

        foreach (track; composition.tracks)
        {
            _writer.startElement(
                "Track",
                [
                    XMLAttribute("Name", track.name),
                    XMLAttribute("Channel", track.channel.text),
                    XMLAttribute("TrailingBlankTime", track.trailingBlankTime.text)
                ]
            );

            foreach (c; track.commands)
            {
                assert(c !is null);
                c.visit!(x => printCommand(x));
            }

            _writer.endElement();
        }

        _writer.endElement();
        _writer.endDocument();
    }

    private void printCommand(Note note)
    {
        assert(note !is null);

        auto attr = [
            XMLAttribute("NominalTime", note.nominalTime.text),
            XMLAttribute("NominalDuration", note.nominalDuration.text),
            XMLAttribute("IsRest", note.isRest.text)
        ];

        if (!note.isRest)
        {
            attr ~= [
                XMLAttribute("Key", note.noteInfo.key.text),
                XMLAttribute("Velocity", note.noteInfo.velocity.text),
                XMLAttribute("TimeShift", note.noteInfo.timeShift.text),
                XMLAttribute("LastNominalDuration", note.noteInfo.lastNominalDuration.text),
                XMLAttribute("GateTime", note.noteInfo.gateTime.text)
            ];
        }

        _writer.writeElement("Note", attr);
    }

    private void printCommand(ControlChange cc)
    {
        assert(cc !is null);

        _writer.writeElement(
            "ControlChange",
            [XMLAttribute("NominalTime", cc.nominalTime.text), XMLAttribute("Code", cc.code.text), XMLAttribute("Value", cc.value.text)]
        );
    }

    private void printCommand(ProgramChange pc)
    {
        assert(pc !is null);

        _writer.writeElement(
            "ProgramChange",
            [
                XMLAttribute("NominalTime", pc.nominalTime.text),
                XMLAttribute("BankLSB", pc.bankLSB.text),
                XMLAttribute("BankMSB", pc.bankMSB.text),
                XMLAttribute("Program", pc.program.text)
            ]
        );
    }

    private void printCommand(PitchBendEvent pb)
    {
        assert(pb !is null);

        _writer.writeElement(
            "PitchBendEvent",
            [XMLAttribute("NominalTime", pb.nominalTime.text), XMLAttribute("Bend", pb.bend.text)]
        );
    }

    private void printCommand(SetTempoEvent e)
    {
        assert(e !is null);

        _writer.writeElement(
            "SetTempoEvent",
            [XMLAttribute("NominalTime", e.nominalTime.text), XMLAttribute("Tempo", e.tempo.text)]
        );
    }

    private void printCommand(SetMeterEvent e)
    {
        assert(e !is null);

        _writer.writeElement(
            "SetMeterEvent",
            [XMLAttribute("NominalTime", e.nominalTime.text), XMLAttribute("Meter", e.meter.numerator.text ~ "/" ~ e.meter.denominator.text)]
        );
    }

    private void printCommand(SetKeySigEvent e)
    {
        assert(e !is null);

        _writer.writeElement(
            "SetKeySigEvent",
            [XMLAttribute("NominalTime", e.nominalTime.text), XMLAttribute("KeySig", e.tonic.keyNameToString() ~ (e.isMinor ? " Min" : " Maj"))]
        );
    }

    private void printCommand(TextMetaEvent e)
    {
        assert(e !is null);

        _writer.writeElement(
            "TextMetaEvent",
            [XMLAttribute("NominalTime", e.nominalTime.text), XMLAttribute("Kind", e.metaEventKind.text), XMLAttribute("Text", e.text)]
        );
    }

    private void printCommand(SystemReset r)
    {
        assert(r !is null);

        _writer.writeElement(
            "SystemReset",
            [XMLAttribute("NominalTime", r.nominalTime.text), XMLAttribute("Kind", r.systemKind.systemKindToString())]
        );
    }

    private void printCommand(GSInsertionEffectOn c)
    {
        assert(c !is null);

        _writer.writeElement(
            "GSInsertionEffectOn",
            [XMLAttribute("NominalTime", c.nominalTime.text), XMLAttribute("On", c.on ? "On" : "Off")]
        );
    }

    private void printCommand(GSInsertionEffectSetType c)
    {
        assert(c !is null);

        _writer.writeElement(
            "GSInsertionEffectSetType",
            [XMLAttribute("NominalTime", c.nominalTime.text), XMLAttribute("Kind", c.type.gsInsertionEffectTypeToString())]
        );
    }

    private void printCommand(GSInsertionEffectSetParam c)
    {
        assert(c !is null);

        _writer.writeElement(
            "GSInsertionEffectSetParam",
            [XMLAttribute("NominalTime", c.nominalTime.text), XMLAttribute("Index", c.index.text), XMLAttribute("Value", c.value.text)]
        );
    }

    private XMLWriter!Writer _writer;
}
