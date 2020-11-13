
module yammld3.irprinter;

import std.conv : text;
import std.range.primitives;

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

private string ccCodeToText(ControlChangeCode cc)
{
    switch (cc)
    {
    case ControlChangeCode.bankSelectMSB:
        return "Bank Select MSB";

    case ControlChangeCode.modulation:
        return "Modulation";

    case ControlChangeCode.breathController:
        return "Breath Controller";

    case ControlChangeCode.footController:
        return "Foot Controller";

    case ControlChangeCode.portamentoTime:
        return "Portamento Time";

    case ControlChangeCode.dataEntry:
        return "Data Entry";

    case ControlChangeCode.channelVolume:
        return "Channel Volume";

    case ControlChangeCode.balance:
        return "Balance";

    case ControlChangeCode.pan:
        return "Pan";

    case ControlChangeCode.expression:
        return "Expression";

    case ControlChangeCode.effectControl1:
        return "Effect Control 1";

    case ControlChangeCode.effectControl2:
        return "Effect Control 2";

    case ControlChangeCode.generalPurposeController1:
        return "General Purpose Controller 1";

    case ControlChangeCode.generalPurposeController2:
        return "General Purpose Controller 2";

    case ControlChangeCode.generalPurposeController3:
        return "General Purpose Controller 3";

    case ControlChangeCode.generalPurposeController4:
        return "General Purpose Controller 4";

    case ControlChangeCode.bankSelectLSB:
        return "Bank Select LSB";

    case ControlChangeCode.hold1:
        return "Hold 1";

    case ControlChangeCode.portamento:
        return "Portamento";

    case ControlChangeCode.sostenuto:
        return "Sostenuto";

    case ControlChangeCode.softPedal:
        return "Soft Pedal";

    case ControlChangeCode.legatoFootswitch:
        return "Legato Footswitch";

    case ControlChangeCode.hold2:
        return "Hold 2";

    case ControlChangeCode.soundVariation:
        return "Sound Variation";

    case ControlChangeCode.harmonicIntensity:
        return "Harmonic Intensity";

    case ControlChangeCode.releaseTime:
        return "Release Time";

    case ControlChangeCode.attackTime:
        return "Attack Time";

    case ControlChangeCode.brightness:
        return "Brightness";

    case ControlChangeCode.decayTime:
        return "Decay Time";

    case ControlChangeCode.vibratoRate:
        return "Vibrato Rate";

    case ControlChangeCode.vibratoDepth:
        return "Vibrato Depth";

    case ControlChangeCode.vibratoDelay:
        return "Vibrato Delay";

    case ControlChangeCode.generalPurposeController5:
        return "General Purpose Controller 5";

    case ControlChangeCode.generalPurposeController6:
        return "General Purpose Controller 6";

    case ControlChangeCode.generalPurposeController7:
        return "General Purpose Controller 7";

    case ControlChangeCode.generalPurposeController8:
        return "General Purpose Controller 8";

    case ControlChangeCode.portamentoControl:
        return "Portamento Control";

    case ControlChangeCode.effect1Depth:
        return "Effect 1 Depth (Reverb)";

    case ControlChangeCode.effect2Depth:
        return "Effect 2 Depth (Tremolo)";

    case ControlChangeCode.effect3Depth:
        return "Effect 3 Depth (Chorus)";

    case ControlChangeCode.effect4Depth:
        return "Effect 4 Depth (Celeste)";

    case ControlChangeCode.effect5Depth:
        return "Effect 5 Depth (Phaser)";

    case ControlChangeCode.dataIncrement:
        return "Data Increment";

    case ControlChangeCode.dataDecrement:
        return "Data Decrement";

    case ControlChangeCode.nonRegisteredParameterNumberMSB:
        return "Non Registered Parameter Number MSB";

    case ControlChangeCode.nonRegisteredParameterNumberLSB:
        return "Non Registered Parameter Number LSB";

    case ControlChangeCode.registeredParameterNumberLSB:
        return "Registered Parameter Number LSB";

    case ControlChangeCode.registeredParameterNumberMSB:
        return "Registered Parameter Number MSB";

    case ControlChangeCode.allSoundOff:
        return "All Sound Off";

    case ControlChangeCode.resetAllControllers:
        return "Reset All Controllers";

    case ControlChangeCode.localControl:
        return "Local Control";

    case ControlChangeCode.allNotesOff:
        return "All Notes Off";

    case ControlChangeCode.omniOn:
        return "Omni On";

    case ControlChangeCode.omniOff:
        return "Omni Off";

    case ControlChangeCode.mono:
        return "Mono";

    case ControlChangeCode.poly:
        return "Poly";

    default:
        return cc.text;
    }
}

private string metaEventKindToString(MetaEventKind kind)
{
    final switch (kind)
    {
    case MetaEventKind.sequenceNumber:
        return "Sequence Number";

    case MetaEventKind.textEvent:
        return "Text Event";

    case MetaEventKind.copyright:
        return "Copyright";

    case MetaEventKind.sequenceName:
        return "Sequence Name";

    case MetaEventKind.instrumentName:
        return "Instrument Name";

    case MetaEventKind.lyrics:
        return "Lyrics";

    case MetaEventKind.marker:
        return "Marker";

    case MetaEventKind.cuePoint:
        return "Cue Point";

    case MetaEventKind.channelPrefix:
        return "Channel Prefix";

    case MetaEventKind.endOfTrack:
        return "End Of Track";

    case MetaEventKind.setTempo:
        return "Set Tempo";

    case MetaEventKind.smpteOffset:
        return "SMPTE Offset";

    case MetaEventKind.timeSignature:
        return "Time Signature";

    case MetaEventKind.keySignature:
        return "Key Signature";

    case MetaEventKind.sequencerSpecific:
        return "Sequencer Specific";
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
            auto attr = [
                XMLAttribute("Name", track.name),
                XMLAttribute("Channel", track.channel.text),
                XMLAttribute("TrailingBlankTime", track.trailingBlankTime.text)
            ];

            if (track.commands.empty)
            {
                _writer.writeElement("Track", attr);
            }
            else
            {
                _writer.startElement("Track", attr);

                foreach (c; track.commands)
                {
                    assert(c !is null);
                    c.visit!(x => printCommand(x));
                }

                _writer.endElement();
            }
        }

        _writer.endElement();
        _writer.endDocument();
    }

    private void printCommand(Note note)
    {
        assert(note !is null);

        _writer.writeElement(
            "Note",
            [
                XMLAttribute("NominalTime", note.nominalTime.text),
                XMLAttribute("NominalDuration", note.nominalDuration.text),
                XMLAttribute("LastNominalDuration", note.lastNominalDuration.text),
                XMLAttribute("Key", note.keyInfo.key.value.text),
                XMLAttribute("KeyMode", note.keyInfo.key.relative ? "Relative" : "Absolute"),
                XMLAttribute("Velocity", note.keyInfo.velocity.text),
                XMLAttribute("TimeShift", note.keyInfo.timeShift.text),
                XMLAttribute("GateTime", note.keyInfo.gateTime.text)
            ]
        );
    }

    private void printCommand(ControlChange cc)
    {
        assert(cc !is null);

        _writer.writeElement(
            "ControlChange",
            [XMLAttribute("NominalTime", cc.nominalTime.text), XMLAttribute("Code", cc.code.ccCodeToText()), XMLAttribute("Value", cc.value.text)]
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
            [XMLAttribute("NominalTime", e.nominalTime.text), XMLAttribute("Kind", e.metaEventKind.metaEventKindToString()), XMLAttribute("Text", e.text)]
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
