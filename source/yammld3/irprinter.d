
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
            _writer.startElement("Track", [XMLAttribute("Name", track.name), XMLAttribute("Channel", track.channel.text)]);

            foreach (c; track.commands)
            {
                printCommand(c);
            }

            _writer.endElement();
        }

        _writer.endElement();
        _writer.endDocument();
    }

    private void printCommand(Command c)
    {
        assert(c !is null);

        final switch (c.kind)
        {
        case IRKind.note:
            printCommand(cast(Note)c);
            break;

        case IRKind.controlChange:
            printCommand(cast(ControlChange)c);
            break;

        case IRKind.programChange:
            printCommand(cast(ProgramChange)c);
            break;

        case IRKind.setTempo:
            printCommand(cast(SetTempoEvent)c);
            break;

        case IRKind.setMeter:
            printCommand(cast(SetMeterEvent)c);
            break;

        case IRKind.setKeySig:
            printCommand(cast(SetKeySigEvent)c);
            break;

        case IRKind.textMetaEvent:
            printCommand(cast(TextMetaEvent)c);
            break;

        case IRKind.systemReset:
            printCommand(cast(SystemReset)c);
            break;
        }
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
            [XMLAttribute("NominalTime", e.nominalTime.text), XMLAttribute("KeySig", e.tonic.keyNameToString() ~ (e.isMinor ? " Maj" : " Min"))]
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

    private XMLWriter!Writer _writer;
}
