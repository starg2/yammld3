
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
    import std.variant : visit;
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
        c.visit!(x => printCommand(x));
    }

    private void printCommand(Note note)
    {
        auto attr = [
            XMLAttribute("NominalTime", note.nominalTime.text),
            XMLAttribute("NominalDuration", note.nominalDuration.text),
            XMLAttribute("IsRest", note.isRest.text)
        ];

        if (!note.noteInfo.isNull)
        {
            attr ~= [
                XMLAttribute("Key", note.noteInfo.get.key.text),
                XMLAttribute("Velocity", note.noteInfo.get.velocity.text),
                XMLAttribute("TimeShift", note.noteInfo.get.timeShift.text),
                XMLAttribute("LastNominalDuration", note.noteInfo.get.lastNominalDuration.text),
                XMLAttribute("GateTime", note.noteInfo.get.gateTime.text)
            ];
        }

        _writer.writeElement("Note", attr);
    }

    private void printCommand(ControlChange cc)
    {
        _writer.writeElement(
            "ControlChange",
            [XMLAttribute("NominalTime", cc.nominalTime.text), XMLAttribute("Code", cc.code.text), XMLAttribute("Value", cc.value.text)]
        );
    }

    private void printCommand(ProgramChange pc)
    {
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
        _writer.writeElement(
            "SetTempoEvent",
            [XMLAttribute("NominalTime", e.nominalTime.text), XMLAttribute("Tempo", e.tempo.text)]
        );
    }

    private void printCommand(SetMeterEvent e)
    {
        _writer.writeElement(
            "SetMeterEvent",
            [XMLAttribute("NominalTime", e.nominalTime.text), XMLAttribute("Meter", e.meter.numerator.text ~ "/" ~ e.meter.denominator.text)]
        );
    }

    private void printCommand(SetKeySigEvent e)
    {
        _writer.writeElement(
            "SetKeySigEvent",
            [XMLAttribute("NominalTime", e.nominalTime.text), XMLAttribute("KeySig", e.tonic.keyNameToString() ~ (e.isMinor ? " Maj" : " Min"))]
        );
    }

    private void printCommand(TextMetaEvent e)
    {
        _writer.writeElement(
            "TextMetaEvent",
            [XMLAttribute("NominalTime", e.nominalTime.text), XMLAttribute("Kind", e.kind.text), XMLAttribute("Text", e.text)]
        );
    }

    private void printCommand(SystemReset r)
    {
        _writer.writeElement(
            "SystemReset",
            [XMLAttribute("NominalTime", r.nominalTime.text), XMLAttribute("Kind", r.kind.systemKindToString())]
        );
    }

    private XMLWriter!Writer _writer;
}
