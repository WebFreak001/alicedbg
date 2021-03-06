/**
 * MS-DOS MZ file dumper
 *
 * License: BSD 3-clause
 */
module adbg.dumper.objs.printmz;

import core.stdc.stdio;
import core.stdc.config : c_long;
import core.stdc.stdlib : EXIT_SUCCESS, EXIT_FAILURE, malloc, realloc;
import core.stdc.time : time_t, tm, localtime, strftime;
import adbg.obj.loader : obj_info_t;
import adbg.disasm.disasm : disasm_params_t, adbg_dasm_line, DisasmMode;
import adbg.obj.fmt.pe;

extern (C):

/// Print MZ info to stdout, a file_info_t structure must be loaded before
/// calling this function.
/// Params:
/// 	fi = File information
/// 	dp = Disassembler parameters
/// 	flags = Show X flags
/// Returns: Non-zero on error
int adbg_dmpr_print_mz(obj_info_t *fi, disasm_params_t *dp, int flags) {
	//TODO: MZ
	
	return EXIT_SUCCESS;
}