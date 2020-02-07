
import std.range.primitives;
import std.stdio;

import yammld3;

private class CommandLineErrorException : Exception
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
	OperationMode mode;
	string inputFile;
	string outputFile;
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
			else if (arg == "/o")
			{
				arg = "-o";
			}
			else if (arg == "/r")
			{
			    arg = "-r";
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
		else if (arg == "-o")
		{
			if (!cmdInfo.outputFile.empty)
			{
				stderr.writeln("command line error: cannot specify multiple output files");
				throw new CommandLineErrorException();
			}

			i++;

			if (i < args.length)
			{
				cmdInfo.outputFile = args[i];
			}
			else
			{
				stderr.writeln("command line error: expected file name after '-o'");
				throw new CommandLineErrorException();
			}
		}
		else if (arg == "-r")
		{
		    cmdInfo.mode = OperationMode.printIR;
		}
		else
		{
			if (arg == "--")
			{
				i++;

				if (i >= args.length)
				{
					stderr.writeln("command line error: expected file name after '--'");
					throw new CommandLineErrorException();
				}
			}

			if (!cmdInfo.inputFile.empty)
			{
				stderr.writeln("command line error: cannot specify multiple input files");
				throw new CommandLineErrorException();
			}

			cmdInfo.inputFile = args[i];
		}
	}

	return cmdInfo;
}

private string makeOutputFilePath(CommandLineInfo cmdInfo)
{
    import std.path : setExtension;

    if (!cmdInfo.outputFile.empty)
    {
        return cmdInfo.outputFile;
    }

    final switch (cmdInfo.mode)
    {
    case OperationMode.compile:
        return cmdInfo.inputFile.setExtension("mid");

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
	writeln(`YAMMLd3 MML Compiler
Copyright (C) 2020 Starg

Usage: yammld3 <options> <input file>

Options:

    --                 escape '-'
    -a                 print abstract syntax tree
    -h                 print this help message
    -o <output file>   specify output file
    -r                 print intermediate representation
`);
}

int main(string[] args)
{
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
			import std.exception : enforce, ErrnoException;

			if (cmdInfo.inputFile.empty)
			{
				stderr.writeln("command line error: input file not specified");
				throw new CommandLineErrorException();
			}

			string outFilePath = makeOutputFilePath(cmdInfo);

			scope (failure)
			{
				import std.file : exists, remove;

				if (!outFilePath.empty && exists(outFilePath))
				{
					remove(outFilePath);
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

			auto parser = new Parser(diagnosticsHandler);
			auto astModule = parser.parseModule(src).enforce!FatalErrorException("failed to parse file");

            if (cmdInfo.mode == OperationMode.printAST)
            {
                if (diagnosticsHandler.hasErrors)
                {
    				throw new FatalErrorException("error occurred");
                }

                auto fileWriter = outFile.lockingTextWriter();
                auto astPrinter = new ASTPrinter!(typeof(fileWriter))(fileWriter, "  ");
                astPrinter.printModule(astModule);
                return 0;
            }

            auto irGenerator = new IRGenerator(diagnosticsHandler);
            auto ir = irGenerator.compileModule(astModule).enforce!FatalErrorException("failed to generate IR");

            if (cmdInfo.mode == OperationMode.printIR)
            {
                if (diagnosticsHandler.hasErrors)
                {
                    throw new FatalErrorException("error occurred");
                }

                auto fileWriter = outFile.lockingTextWriter();
                auto irPrinter = new IRPrinter!(typeof(fileWriter))(fileWriter, "  ");
                irPrinter.printComposition(ir);
                return 0;
            }

            auto midiGenerator = new MIDIGenerator(diagnosticsHandler);
            auto midiEvents = midiGenerator.generateMIDI(ir).enforce!FatalErrorException("failed to generate MIDI events");

            if (diagnosticsHandler.hasErrors)
            {
				throw new FatalErrorException("error occurred");
            }

			auto fileWriter = outFile.lockingBinaryWriter();
			auto midiWriter = new MIDIWriter!(typeof(fileWriter))(diagnosticsHandler, fileWriter);
			midiWriter.writeMIDI(cmdInfo.inputFile, midiEvents);

			return 0;
		}
	}
	catch (FatalErrorException e)
	{
		return 1;
	}
	catch (CommandLineErrorException e)
	{
	    return 2;
	}
}
