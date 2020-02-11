
module yammld3.xmlwriter;

import std.range.primitives;

package class XMLException : Exception
{
    public this(string msg, string file = __FILE__, size_t line = __LINE__) @nogc @safe pure nothrow
    {
        super(msg, file, line);
    }
}

package struct XMLAttribute
{
    string key;
    string value;
}

package final class XMLWriter(Writer)
{
    public this(Writer output, string indent = "")
    {
        _output = output;
        _indent = indent;
    }

    public void startDocument()
    {
        if (!_elementStack.empty)
        {
            throw new XMLException("element stack is not empty");
        }

        if (_wroteRoot)
        {
            throw new XMLException("root element was already written");
        }

        put(_output, `<?xml version="1.0" encoding="UTF-8"?>`);
    }

    public void endDocument()
    {
        if (!_elementStack.empty)
        {
            throw new XMLException("element stack is not empty");
        }

        if (!_wroteRoot)
        {
            throw new XMLException("oot element was not written yet");
        }

        writeNewLineAndIndent();
    }

    public void startElement(string name, XMLAttribute[] attributes = null)
    {
        writeNewLineAndIndent();

        if (_elementStack.empty)
        {
            _wroteRoot = true;
        }

        _elementStack.assumeSafeAppend() ~= name;
        put(_output, "<");
        put(_output, name);
        writeAttributes(attributes);
        put(_output, ">");
    }

    public void endElement()
    {
        if (_elementStack.empty)
        {
            throw new XMLException("element stack is empty");
        }

        string name = _elementStack.back;
        _elementStack.popBack();

        writeNewLineAndIndent();
        put(_output, "</");
        put(_output, name);
        put(_output, ">");
    }

    public void writeElement(string name, XMLAttribute[] attributes = null)
    {
        writeNewLineAndIndent();

        if (_elementStack.empty)
        {
            _wroteRoot = true;
        }

        put(_output, "<");
        put(_output, name);
        writeAttributes(attributes);
        put(_output, " />");
    }

    public void writeElement(string name, string value)
    {
        writeElement(name, null, value);
    }

    public void writeElement(string name, XMLAttribute[] attributes, string value)
    {
        writeNewLineAndIndent();

        if (_elementStack.empty)
        {
            _wroteRoot = true;
        }

        put(_output, "<");
        put(_output, name);
        writeAttributes(attributes);
        put(_output, ">");

        escapeAndWriteString(value);

        put(_output, "</");
        put(_output, name);
        put(_output, ">");
    }

    public void writeComment(string comment)
    {
        import std.algorithm.searching : canFind;

        if (comment.canFind("--"))
        {
            throw new XMLException("xml comments cannot include '--'");
        }

        writeNewLineAndIndent();

        put(_output, _indent.empty ? "<!--" : "<!-- ");
        put(_output, comment);
        put(_output, _indent.empty ? "-->" : " -->");
    }

    private void writeAttributes(XMLAttribute[] attributes)
    {
        foreach (a; attributes)
        {
            put(_output, " ");
            put(_output, a.key);
            put(_output, `="`);
            escapeAndWriteString(a.value);
            put(_output, '"');
        }
    }

    private void escapeAndWriteString(string str)
    {
        foreach (c; str)
        {
            switch (c)
            {
            case '<':
                put(_output, "&lt;");
                break;

            case '>':
                put(_output, "&gt;");
                break;

            case '"':
                put(_output, "&quot;");
                break;

            case '\'':
                put(_output, "&apos;");
                break;

            case '&':
                put(_output, "&amp;");
                break;

            default:
                put(_output, c);
                break;
            }
        }
    }

    private void writeNewLineAndIndent()
    {
        if (!_wroteRoot)
        {
            put(_output, "\n");
        }
        else if (!_indent.empty)
        {
            import std.range : repeat;
            put(_output, "\n");
            put(_output, _indent.repeat(_elementStack.length));
        }
    }

    private Writer _output;
    private string _indent;
    private string[] _elementStack;
    private bool _wroteRoot = false;
}
