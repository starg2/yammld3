// Copyright (c) 2020 Starg.
// SPDX-License-Identifier: BSD-3-Clause

import std.range.primitives;
import std.stdio;

import core.time : Duration, MonoTime;

import yammld3;

private class CommandLineException : Exception
{
    public this(string msg = "command line error", string file = __FILE__, size_t line = __LINE__) @nogc @safe pure nothrow
    {
        super(msg, file, line);
    }
}

private enum OperationMode
{
    compile,
    printAST,
    printIR,
    help
}

private struct CommandLineInfo
{
    OperationMode mode = OperationMode.compile;
    string inputFile;
    string outputFile;
    string[] includePaths;
    bool timePasses;
}

private CommandLineInfo parseCommandLine(string[] args)
{
    CommandLineInfo cmdInfo;

    if (args.length <= 1)
    {
        cmdInfo.mode = OperationMode.help;
        return cmdInfo;
    }

    for (size_t i = 1; i < args.length; i++)
    {
        string arg = args[i];

        version (Windows)
        {
            if (arg == "/h" || arg == "-?" || arg == "/?" || arg == "/help")
            {
                arg = "-h";
            }
            else if (arg == "/a")
            {
                arg = "-a";
            }
            else if (arg == "/I")
            {
                arg = "-I";
            }
            else if (arg == "/o")
            {
                arg = "-o";
            }
            else if (arg == "/r")
            {
                arg = "-r";
            }
            else if (arg == "/t")
            {
                arg = "-t";
            }
        }

        if (arg == "-h" || arg == "-help" || arg == "--help")
        {
            cmdInfo.mode = OperationMode.help;
        }
        else if (arg == "-a")
        {
            cmdInfo.mode = OperationMode.printAST;
        }
        else if (arg == "-I")
        {
            i++;

            if (i < args.length)
            {
                cmdInfo.includePaths ~= args[i];
            }
            else
            {
                stderr.writeln("command line error: expected directory name after '-I'");
                throw new CommandLineException();
            }
        }
        else if (arg == "-o")
        {
            if (!cmdInfo.outputFile.empty)
            {
                stderr.writeln("command line error: cannot specify multiple output files");
                throw new CommandLineException();
            }

            i++;

            if (i < args.length)
            {
                cmdInfo.outputFile = args[i];
            }
            else
            {
                stderr.writeln("command line error: expected file name after '-o'");
                throw new CommandLineException();
            }
        }
        else if (arg == "-r")
        {
            cmdInfo.mode = OperationMode.printIR;
        }
        else if (arg == "-t")
        {
            cmdInfo.timePasses = true;
        }
        else if (arg != "--" && !arg.empty && arg.front == '-')
        {
            stderr.writefln("command line error: unrecognized option '%s'", arg);
            throw new CommandLineException();
        }
        else
        {
            if (arg == "--")
            {
                i++;

                if (i >= args.length)
                {
                    stderr.writeln("command line error: expected file name after '--'");
                    throw new CommandLineException();
                }
            }

            if (!cmdInfo.inputFile.empty)
            {
                stderr.writeln("command line error: cannot specify multiple input files");
                throw new CommandLineException();
            }

            cmdInfo.inputFile = args[i];
        }
    }

    return cmdInfo;
}

private string makeOutputFilePath(CommandLineInfo cmdInfo)
{
    import std.path : baseName, setExtension;

    if (!cmdInfo.outputFile.empty)
    {
        return cmdInfo.outputFile;
    }

    final switch (cmdInfo.mode)
    {
    case OperationMode.compile:
        return cmdInfo.inputFile.setExtension("mid").baseName();

    case OperationMode.printAST:
    case OperationMode.printIR:
        return "";

    case OperationMode.help:
        assert(false);
    }
}

private string getOutputFileMode(CommandLineInfo cmdInfo)
{
    switch (cmdInfo.mode)
    {
    case OperationMode.compile:
        return "wb";

    default:
        return "w";
    }
}

private void printHelp()
{
    writeln("YAMMLd3 MML Compiler (" ~ versionString ~ ")" ~ `
Copyright (c) 2020-2021 Starg.

Usage: yammld3 <options> <input file>

Options:

    --                 escape '-'
    -a                 print abstract syntax tree
    -h                 print this help message
    -I <directory>     add include directory
    -o <output file>   specify output file
    -r                 print intermediate representation
    -t                 report timing information
`);
}

private struct PassTimingInfo
{
    string name;
    Duration duration;
}

private void printTimingInfo(PassTimingInfo[] info)
{
    assert(!info.empty);

    stderr.writeln();

    foreach (i; info[0..($ - 1)])
    {
        stderr.writefln("%-12s: %10.3f ms", i.name, i.duration.total!"usecs" / 1000.0f);
    }

    stderr.writeln();
    stderr.writefln("%-12s: %10.3f ms", info.back.name, info.back.duration.total!"usecs" / 1000.0f);
    stderr.writeln();
}

int main(string[] args)
{
    import std.exception : collectException, enforce, ErrnoException;
    import std.file : exists, FileException, isFile, remove;
    import std.path : absolutePath;

    try
    {
        auto cmdInfo = parseCommandLine(args);

        if (cmdInfo.mode == OperationMode.help)
        {
            printHelp();
            return 0;
        }
        else
        {
            auto timeStart = MonoTime.currTime;

            if (cmdInfo.inputFile.empty)
            {
                stderr.writeln("command line error: input file not specified");
                throw new CommandLineException();
            }

            string outFilePath = makeOutputFilePath(cmdInfo);

            scope (failure)
            {
                if (!outFilePath.empty && exists(outFilePath) && isFile(outFilePath))
                {
                    collectException!FileException(remove(outFilePath));
                }
            }

            File outFile;

            try
            {
                outFile = outFilePath.empty ? stdout : File(outFilePath, getOutputFileMode(cmdInfo));
            }
            catch (ErrnoException e)
            {
                stderr.writefln("fatal error: cannot open output file '%s'", outFilePath);
                throw new FatalErrorException("cannot open output file");
            }

            auto diagnosticsHandler = new SimpleDiagnosticsHandler(stderr);
            auto sourceManager = new SourceManager();
            auto src = sourceManager.getOrLoadSource(cmdInfo.inputFile, "");

            if (src is null)
            {
                diagnosticsHandler.cannotOpenFile(cmdInfo.inputFile);
                assert(false);
            }

            foreach (inc; cmdInfo.includePaths)
            {
                sourceManager.addIncludePath(absolutePath(inc));
            }

            auto timeBeforeParse = MonoTime.currTime;
            auto timingInfo = [PassTimingInfo("load", timeBeforeParse - timeStart)];

            auto parser = new Parser(diagnosticsHandler);
            auto astModule = parser.parseModule(src).enforce!FatalErrorException("failed to parse file");

            auto timeAfterParse = MonoTime.currTime;
            timingInfo ~= PassTimingInfo("parse", timeAfterParse - timeBeforeParse);

            if (cmdInfo.mode == OperationMode.printAST)
            {
                if (diagnosticsHandler.hasErrors)
                {
                    throw new FatalErrorException("error occurred");
                }

                auto fileWriter = outFile.lockingTextWriter();
                auto astPrinter = new ASTPrinter!(typeof(fileWriter))(fileWriter, "  ");
                astPrinter.printModule(astModule);

                auto timeEnd = MonoTime.currTime;
                timingInfo ~= PassTimingInfo("print ast", timeEnd - timeAfterParse);
                timingInfo ~= PassTimingInfo("total", timeEnd - timeStart);

                if (cmdInfo.timePasses)
                {
                    printTimingInfo(timingInfo);
                }

                return 0;
            }

            auto irGenerator = new IRGenerator(diagnosticsHandler, sourceManager, parser);
            auto ir = irGenerator.compileModule(astModule).enforce!FatalErrorException("failed to generate IR");

            auto timeAfterIRGen = MonoTime.currTime;
            timingInfo ~= PassTimingInfo("irgen", timeAfterIRGen - timeAfterParse);

            if (cmdInfo.mode == OperationMode.printIR)
            {
                if (diagnosticsHandler.hasErrors)
                {
                    throw new FatalErrorException("error occurred");
                }

                auto fileWriter = outFile.lockingTextWriter();
                auto irPrinter = new IRPrinter!(typeof(fileWriter))(fileWriter, "  ");
                irPrinter.printComposition(ir);

                auto timeEnd = MonoTime.currTime;
                timingInfo ~= PassTimingInfo("print ir", timeEnd - timeAfterIRGen);
                timingInfo ~= PassTimingInfo("total", timeEnd - timeStart);

                if (cmdInfo.timePasses)
                {
                    printTimingInfo(timingInfo);
                }

                return 0;
            }

            auto midiGenerator = new MIDIGenerator(diagnosticsHandler);
            auto midiEvents = midiGenerator.generateMIDI(ir).enforce!FatalErrorException("failed to generate MIDI events");

            auto timeAfterMIDIGen = MonoTime.currTime;
            timingInfo ~= PassTimingInfo("midigen", timeAfterMIDIGen - timeAfterIRGen);

            if (diagnosticsHandler.hasErrors)
            {
                throw new FatalErrorException("error occurred");
            }

            auto fileWriter = outFile.lockingBinaryWriter();
            auto midiWriter = new MIDIWriter!(typeof(fileWriter))(diagnosticsHandler, fileWriter);
            midiWriter.writeMIDI(cmdInfo.inputFile, midiEvents);

            auto timeEnd = MonoTime.currTime;
            timingInfo ~= PassTimingInfo("write midi", timeEnd - timeAfterMIDIGen);
            timingInfo ~= PassTimingInfo("total", timeEnd - timeStart);

            if (cmdInfo.timePasses)
            {
                printTimingInfo(timingInfo);
            }

            return 0;
        }
    }
    catch (FatalErrorException e)
    {
        return 1;
    }
    catch (CommandLineException e)
    {
        return 2;
    }
}
