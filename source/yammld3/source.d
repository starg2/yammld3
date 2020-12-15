// Copyright (c) 2020 Starg.
// SPDX-License-Identifier: BSD-3-Clause

module yammld3.source;

import std.range.primitives;

/// A base interface for a source file.
public interface SourceInput
{
    /// The path to the source file.
    @property string path() const;

    /// The contents of the source file.
    @property string contents() const;
}

/// An implementation of SourceInput.
/// Uses MmFile for file access.
public class FileInput : SourceInput
{
    import std.mmfile : MmFile;

    public this(string filePath)
    {
        _filePath = filePath;
        _mmFile = new MmFile(filePath);
        _contents = cast(string)_mmFile[];
    }

    public override @property string path() const
    {
        return _filePath;
    }

    public override @property string contents() const
    {
        return _contents;
    }

    private string _filePath;
    private MmFile _mmFile;
    private string _contents;
}

/// Wraps SourceInput and caches the offsets of the newline characters.
public final class Source
{
    public this(SourceInput input)
    {
        _input = input;
        _newLineOffsets = [0];
    }

    public @property string path() const
    {
        return _input.path;
    }

    public @property string contents() const
    {
        return _input.contents;
    }

    /// Gets the specified line. `lineNumber` is 1-based.
    public string getLine(size_t lineNumber)
    {
        if (lineNumber >= _newLineOffsets.length)
        {
            size_t offset = _newLineOffsets.empty ? 0 : _newLineOffsets.back + 1;
            auto view = contents;

            while (offset < view.length)
            {
                if (view[offset] == '\n')
                {
                    _newLineOffsets ~= offset;
                }

                if (lineNumber < _newLineOffsets.length)
                {
                    return getLineNoCheck(lineNumber);
                }

                offset++;
            }

            _newLineOffsets ~= view.length;
            return contents[$..$];
        }

        return getLineNoCheck(lineNumber);
    }

    private string getLineNoCheck(size_t lineNumber)
    {
        auto view = contents[_newLineOffsets[lineNumber - 1].._newLineOffsets[lineNumber]];

        if (!view.empty && view.front == '\n')
        {
            view.popFront();
        }

        if (!view.empty && view.back == '\r')
        {
            view.popBack();
        }

        return view;
    }

    private SourceInput _input;
    private size_t[] _newLineOffsets;
}

public struct SourceOffset
{
    string getLine()
    {
        assert(source !is null);
        return source.getLine(line);
    }

    Source source;
    size_t line;    // 1-based
    size_t column;  // 0-based, in byte
}

/// Represents the source location.
public struct SourceLocation
{
    this(SourceOffset from, size_t len)
    {
        offset = from;
        length = len;
    }

    this(SourceOffset from, SourceOffset to)
    {
        assert(from.source is to.source);
        assert((from.line == to.line && from.column <= to.column) || from.line < to.line);

        offset = from;

        if (from.line < to.line)
        {
            length = (to.getLine().ptr + to.column) - (from.getLine().ptr + from.column);
        }
        else
        {
            length = to.column - from.column;
        }

        assert(length <= source.contents.length);
    }

    this(SourceLocation from, SourceLocation to)
    {
        assert(from.source is to.source);
        assert((from.line == to.line && from.column <= to.column) || from.line < to.line);

        offset = from.offset;

        if (from.line < to.line)
        {
            length = (to.getLine().ptr + to.column) - (from.getLine().ptr + from.column) + to.length;
        }
        else
        {
            length = to.column - from.column + to.length;
        }

        assert(length <= source.contents.length);
    }

    SourceOffset offset;
    alias offset this;
    size_t length;
}

private string resolvePath(string targetPath, string basePath)
{
    import std.path : buildPath, dirName;

    auto baseDir = dirName(basePath);
    return baseDir == "." ? targetPath : buildPath(baseDir, targetPath);
}

/// Manages source files
public final class SourceManager
{
    public void addIncludePath(string dir)
    {
        _includePaths ~= dir;
    }

    public Source getOrLoadSource(string targetPath, string basePath)
    {
        import std.meta : AliasSeq;

        static foreach (dg; AliasSeq!(tryGetSource, tryLoadSource))
        {
            {
                auto s = dg(resolvePath(targetPath, basePath));

                if (s !is null)
                {
                    return s;
                }
            }

            foreach (i; _includePaths)
            {
                auto s = dg(resolvePath(targetPath, i));

                if (s !is null)
                {
                    return s;
                }
            }
        }

        return null;
    }

    private Source tryGetSource(string path)
    {
        return _pathToSourceMap.get(path, null);
    }

    private Source tryLoadSource(string path)
    {
        SourceInput input;

        try
        {
            input = new FileInput(path);
        }
        catch (Exception)
        {
            return null;
        }

        auto src = new Source(input);
        _pathToSourceMap[path] = src;
        return src;
    }

    private Source[string] _pathToSourceMap;
    private string[] _includePaths;
}
