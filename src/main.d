import core.stdc.stdlib : strtol, EXIT_SUCCESS, EXIT_FAILURE;
import core.stdc.string : strcmp;
import core.stdc.stdio;
import consts;
import ui.loop : loop_enter;
import ui.tui : tui_enter;
import debugger, dumper;
import os.err;

extern (C):
private:

enum OperatingModule {
	debugger, // can't use word "debug" and "debug_" is eh
	dumper,
	profiler
}

// for debugger
enum DebuggerUI {
	tui,
	loop,
//	interpreter,
//	tcp_json,
}

enum DebuggerMode {
	undecided,
	file,
	pid
}

/// "sub-help" screen for cshow
enum CLIPage {
	main,
	ui,
	dstyles,
	marchs,
	license,
}

/// CLI options
struct cliopt_t {
	OperatingModule mode;
	DebuggerUI ui;
	DebuggerMode debugtype;
	ushort pid;
	const(char) *file;
	const(char) *file_args;
	const(char) *file_env;
}

/// Version page
int cliver() {
	import ver = std.compiler;
	printf(
	"alicedbg-"~__PLATFORM__~" "~PROJECT_VERSION~"-"~__BUILDTYPE__~"  ("~__TIMESTAMP__~")\n"~
	"License: BSD-3-Clause <https://spdx.org/licenses/BSD-3-Clause.html>\n"~
	"Home: <https://git.dd86k.space/alicedbg>\n"~
	"Mirror: <https://github.com/dd86k/alicedbg>\n"~
	"Compiler: "~__VENDOR__~" %u.%03u, "~
		__TARGET_OBJ_FORMAT__~" obj format, "~
		__TARGET_FLOAT_ABI__~" float abi\n"~
	"CRT: "~__CRT__~" (cpprt: "~__TARGET_CPP_RT__~") on "~__OS__~"\n"~
	"CPU: "~__TARGET_CPU__~"\n"~
	"Features: dbg disasm\n"~
	"Disasm: x86\n",
	ver.version_major, ver.version_minor
	);
	return 0;
}

/// "sub-help" pages, such as -ui ? and the rest
int clipage(CLIPage h) {
	const(char) *r = void;
	with (CLIPage)
	final switch (h) {
	case main:
		r =
		"Aiming to be a simple debugger\n"~
		"Usage:\n"~
		"  alicedbg {-pid ID|-exec FILE} [OPTIONS...]\n"~
		"  alicedbg {--help|--version|--license}\n"~
		"\n"~
		"OPTIONS\n"~
		"  -exec      debugger: Load executable file\n"~
		"  -pid       debugger: Attach to process id\n"~
		"  -ui        Choose user interface (see -ui ?)\n";
		break;
	case ui:
		r =
		"Available UIs (default=tui)\n"~
		"tui ....... (WIP) Text UI with full debugging experience.\n"~
		"loop ...... Print exceptions, continues automatically, no user input.\n"
//		"tcp-json .. (Experimental) JSON API server via TCP.\n"
		;
	break;
	case dstyles:
		r =
		"Available disassembler styles\n"~
		"intel .... Intel syntax\n"~
		"nasm ..... Netwide Assembler syntax\n"~
		"att ...... AT&T syntax"
		;
	break;
	case marchs:
		r = "Architectures: x86, x86_64";
	break;
	case license:
		r =
`BSD 3-Clause License

Copyright (c) 2019-2020, dd86k <dd@dax.moe>
All rights reserved.

Redistribution and use in source and binary forms, with or without
modification, are permitted provided that the following conditions are met:

1. Redistributions of source code must retain the above copyright notice, this
   list of conditions and the following disclaimer.

2. Redistributions in binary form must reproduce the above copyright notice,
   this list of conditions and the following disclaimer in the documentation
   and/or other materials provided with the distribution.

3. Neither the name of the copyright holder nor the names of its
   contributors may be used to endorse or promote products derived from
   this software without specific prior written permission.

THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS"
AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE
DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT HOLDER OR CONTRIBUTORS BE LIABLE
FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL
DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR
SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER
CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY,
OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE
OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.`;
		break;
	}
	puts(r);
	return 0;
}

int main(int argc, const(char) **argv) {
	if (argc <= 1)
		return clipage(CLIPage.main);

	cliopt_t opt;	/// Defaults to .init
	disasm_params_t disopt;	/// .init

	// CLI
	for (size_t argi = 1; argi < argc; ++argi) {
		const(char) *arg = argv[argi] + 1;

		if (*argv[argi] != '-') goto L_CLI_DEFAULT;

		// debugger: select file
		if (strcmp(arg, "exec") == 0) {
			if (argi + 1 >= argc) {
				puts("cli: file argument missing");
				return EXIT_FAILURE;
			}
			opt.debugtype = DebuggerMode.file;
			opt.file = argv[++argi];
			continue;
		}
		/*
		if (strcmp(arg, "execarg") == 0) {
			
		}
		// Starting directory for file
		if (strcmp(arg, "execdir") == 0) {
			
		}*/

		// debugger: select pid
		if (strcmp(arg, "pid") == 0) {
			if (argi + 1 >= argc) {
				puts("cli: pid argument missing");
				return EXIT_FAILURE;
			}
			opt.debugtype = DebuggerMode.pid;
			const(char) *id = argv[++argi];
			opt.pid = cast(ushort)strtol(id, null, 10);
			continue;
		}

		// debugger: ui
		if (strcmp(arg, "ui") == 0) {
			if (argi + 1 >= argc) {
				puts("cli: ui argument missing");
				return EXIT_FAILURE;
			}
			const(char) *ui = argv[++argi];
			if (strcmp(ui, "tui") == 0)
				opt.ui = DebuggerUI.tui;
			else if (strcmp(ui, "loop") == 0)
				opt.ui = DebuggerUI.loop;
			else if (strcmp(ui, "?") == 0)
				return clipage(CLIPage.ui);
			else {
				printf("cli: ui \"%s\" not found, query \"-ui ?\" for a list\n",
					ui);
				return EXIT_FAILURE;
			}
			continue;
		}

		// dumper: file path
		if (strcmp(arg, "ddump") == 0) {
			if (argi + 1 >= argc) {
				puts("cli: path argument missing");
				return EXIT_FAILURE;
			}
			opt.mode = OperatingModule.dumper;
			opt.file = argv[++argi];
			continue;
		}

		// disassembler: machine architecture, affects disassembly
		if (strcmp(arg, "march") == 0) {
			if (argi + 1 >= argc) {
				puts("cli: ui argument missing");
				return EXIT_FAILURE;
			}
			const(char) *march = argv[++argi];
			if (strcmp(march, "x86") == 0)
				disopt.abi = DisasmABI.x86;
			else if (strcmp(march, "x86_64") == 0)
				disopt.abi = DisasmABI.x86_64;
			else if (strcmp(march, "thumb") == 0)
				disopt.abi = DisasmABI.arm_t32;
			else if (strcmp(march, "arm") == 0)
				disopt.abi = DisasmABI.arm_a32;
			else if (strcmp(march, "aarch64") == 0)
				disopt.abi = DisasmABI.arm_a64;
			else if (strcmp(march, "guess") == 0) {
				puts("guess feature not implemented");
				return EXIT_FAILURE;
			} else if (strcmp(march, "?") == 0)
				return clipage(CLIPage.marchs);
			else {
				printf("Unknown machine architecture: '%s'\n", march);
				return EXIT_FAILURE;
			}
			continue;
		}

		// disassembler: select style
		if (strcmp(arg, "dstyle") == 0) {
			if (argi + 1 >= argc) {
				puts("cli: ui argument missing");
				return EXIT_FAILURE;
			}
			const(char) *dstyle = argv[++argi];
			if (strcmp(dstyle, "intel") == 0)
				disopt.style = DisasmSyntax.Intel;
			else if (strcmp(dstyle, "nasm") == 0)
				disopt.style = DisasmSyntax.Nasm;
			else if (strcmp(dstyle, "att") == 0)
				disopt.style = DisasmSyntax.Att;
			else if (strcmp(dstyle, "?") == 0)
				return clipage(CLIPage.dstyles);
			else {
				printf("Unknown disassembler style: '%s'\n", dstyle);
				return EXIT_FAILURE;
			}
			continue;
		}

		// Choose demangle settings for symbols
		/*if (strcmp(arg, "demangle") == 0) {
			
		}*/

		// Choose debugging backend, currently unsupported and only
		// embedded option is available
		/*if (strcmp(arg, "backend") == 0) {
			
		}*/

		if (strcmp(arg, "version") == 0 || strcmp(arg, "-version") == 0)
			return cliver;
		if (strcmp(arg, "help") == 0 || strcmp(arg, "-help") == 0)
			return clipage(CLIPage.main);
		if (strcmp(arg, "-license") == 0)
			return clipage(CLIPage.license);

		continue;

		//
		// Default arguments
		//

L_CLI_DEFAULT:
		if (opt.file == null) {
			opt.mode = OperatingModule.debugger;
			opt.debugtype = DebuggerMode.file;
			opt.file = argv[argi];
		} else if (opt.file_args == null) {
			opt.file_args = argv[argi];
		} else if (opt.file_env == null) {
			opt.file_env = argv[argi];
		} else {
			puts("cli: Out of default parameters");
			return EXIT_FAILURE;
		}
	}

	with (OperatingModule)
	final switch (opt.mode) {
	case debugger:
		int e = void;
		with (DebuggerMode)
		switch (opt.debugtype) {
		case file:
			if ((e = dbg_file(opt.file)) != 0) {
				printf("dbg: ("~F_ERR~") %s\n", e, err_msg(e));
				return e;
			}
			break;
		case pid:
			if ((e = dbg_attach(opt.pid)) != 0) {
				printf("dbg: ("~F_ERR~") %s\n", e, err_msg(e));
				return e;
			}
			break;
		default:
			puts("cli: No file nor pid were specified.");
			return EXIT_FAILURE;
		}

		with (DebuggerUI)
		final switch (opt.ui) {
		case loop: return loop_enter;
		case tui: return tui_enter;
		}
	case dumper:
		return dump(opt.file, disopt);
	case profiler:
		puts("Profiling feature not yet implemented");
		break;
	}
	return 0;
}
