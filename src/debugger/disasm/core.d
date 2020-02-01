module debugger.disasm.core;

import debugger.arch;
import utils.str;
private import debugger.disasm.arch.x86 : x86_internals_t;

extern (C):

/// Disassembler parameters structure
struct disasm_params_t { align(1):
	/// Character buffer for MACHINE CODE
	char [DISASM_BUF_SIZE]mcbuf;
	/// Character buffer index and current length for MACHINE CODE
	size_t mcbufi;
	/// Character buffer for MNEMONICS
	char [DISASM_BUF_SIZE]mnbuf;
	/// Character buffer index and current length for MNEMONICS
	size_t mnbufi;
	union {
		/// Memory address entry point. This value is modified to point
		/// to the next instruction address. Acts as instruction
		/// pointer/program counter.
		void *addr;
		/// Memory address entry point. This value is modified to point
		/// to the next instruction address. Acts as instruction
		/// pointer/program counter.
		size_t addrv;
		// Aliases
		ubyte  *addru8; 	/// Used internally
		ushort *addru16;	/// Used internally
		uint   *addru32;	/// Used internally
		ulong  *addru64;	/// Used internally
		byte   *addri8; 	/// Used internally
		short  *addri16;	/// Used internally
		int    *addri32;	/// Used internally
		long   *addri64;	/// Used internally
		float  *addrf32;	/// Used internally
		double *addrd32;	/// Used internally
	}
	/// Saved address position before the operation begins, good for
	/// printing purposes or calculating the delta after disassembling.
	size_t thisaddr;
	/// Error code. See DisasmError enumeration for more details.
	DisasmError error;
	/// Platform to disasm. See the DisasmABI enum for more details.
	ubyte abi;
	/// Assembler style. See DisasmStyle enums for more details.
	ubyte style;
	/// Operation mode. See DISASM_I_* flags. If unset, calculate
	/// and modify address pointer only.
	ubyte include;
	/// Demangle option. See DisasmDemangle enum.
	ubyte demangle;
	/// Settings flags. See DISASM_O_* flags.
	ushort options;
	x86_internals_t x86;	/// Used internally
}
pragma(msg, "* disasm_params_t.sizeof: ", disasm_params_t.sizeof);

//
// Enumerations
//

/// Disassembler error
enum DisasmError {
	None,	/// Nothing to report, you can continue
	NoAuto,	/// Automatic mode is unavailable for compiled platform
	NoABI,	/// Invalid ABI was selected
	Illegal,	/// Illegal/invalid opcode
}

/// Disassembler ABI
enum DisasmABI : ubyte {
	Auto,	/// Automatic (platform-dependant)
	x86,	/// x86
	x86_64,	/// AMD64
	ARM,	/// (Not implemented) ARM
	ARM64,	/// (Not implemented) AArch64
}

/// Disassembler x86 styles
enum DisasmStyleX86 : ubyte {
	Dasm,	/// (Not implemented) D inline x86 assembler
	Nasm,	/// (Not implemented) (NASM) Netwide Assembler
	Masm,	/// (Not implemented) (MASM) Microsoft Assembler
	Ideal,	/// (Not implemented) Borland Ideal
	Hyde,	/// (Not implemented) Randall Hyde High Level Assembly Language
	Att,	/// (Not implemented) AT&T
}

/// Disassembler symbol demangling
enum DisasmDemangle : ubyte {
	None,	/// (Not implemented) Leave symbol as-is
	C,	/// (Not implemented) C mangling
}

//
// Disasm constants
//

/// Character buffer size
enum DISASM_BUF_SIZE = 128;

version (X86)
	enum DISASM_DEFAULT_ABI = DisasmABI.x86;	/// Platform default ABI
else
version (X86_64)
	enum DISASM_DEFAULT_ABI = DisasmABI.x86_64;	/// Platform default ABI
else
version (ARM)
	enum DISASM_DEFAULT_ABI = DisasmABI.ARM;	/// Platform default ABI
else
version (AArch64)
	enum DISASM_DEFAULT_ABI = DisasmABI.ARM64;	/// Platform default ABI
else
	enum DISASM_DEFAULT_ABI = DisasmABI.Auto;	/// Platform default ABI


//
// Include bits
//

enum DISASM_I_MACHINECODE	= 0b0000_0001;	/// Include machine code
enum DISASM_I_MNEMONICS	= 0b0000_0010;	/// Include instruction mnemonics
enum DISASM_I_SYMBOLS	= 0b0000_0100;	/// (Not implemented) Include symbols
enum DISASM_I_SOURCE	= 0b0000_1000;	/// (Not implemented) Include source code
enum DISASM_I_COMMENTS	= 0b0001_0000;	/// (Not implemented) Include inlined comments
enum DISASM_I_EVERYTHING	= 0xFF;	/// Include everything

//
// Option bits
//

/// Diasm option: Go backwards instead of forward. More expensive to calculate!
enum DISASM_O_BACKWARD	= 0x0002;
/// Diasm option: Lower-case machine code instructions
enum DISASM_O_MACHLOWERCASE	= 0x0004;
/// Diasm option: Lower-case mnemonics instructions
enum DISASM_O_INTRLOWERCASE	= 0x0008;

/// Diasm option: Lower-case machine code instructions and mnemonics instructions
enum DISASM_O_LOWERCASE	= DISASM_O_MACHLOWERCASE | DISASM_O_INTRLOWERCASE;

/**
 * Disassemble from a memory pointer given in params. The caller must ensure
 * memory access rights are present and bounds must be respected.
 * Params:
 * 	p = Disassembler parameters
 * Returns: Error code if non-zero
 */
int disasm_line(ref disasm_params_t p) {
	with (p) mcbufi = mnbufi = 0;

	if (p.abi == DisasmABI.Auto) {
		p.abi = DISASM_DEFAULT_ABI;
	}

	p.error = DisasmError.None;
	p.thisaddr = p.addrv;

	with (DisasmABI)
	switch (p.abi) {
	case x86: disasm_x86(p); break;
	case x86_64: disasm_x86_64(p); break;
	default: return DisasmError.NoABI;
	}

	with (p) mcbuf[mcbufi] = mnbuf[mnbufi] = 0;

	if (p.options & DISASM_O_MACHLOWERCASE)
		strlcase(cast(char*)p.mcbuf, DISASM_BUF_SIZE);
	if (p.options & DISASM_O_INTRLOWERCASE)
		strlcase(cast(char*)p.mnbuf, DISASM_BUF_SIZE);

	return p.error;
}

//TODO: ushort disasm_optstr(const(char)*) -- Interpret string value for disasm option

//
// Disasm internals/utilities
//
// NOTE: The include checking is not done in these functions for performance
//       reasons (pushing 3+ values into stack just a bit to be checked is
//       silly).
//

package:
private import core.stdc.stdarg;

immutable const(char) *UNKNOWN_OP = "??";

void mnill(ref disasm_params_t p) {
	if (p.include & DISASM_I_MACHINECODE)
		mnadd(p, UNKNOWN_OP);
	p.error = DisasmError.Illegal;
}

void mcaddx8(ref disasm_params_t p, ubyte v) {
	mcaddf(p, "%02X ", v);
}
void mcaddx16(ref disasm_params_t p, ushort v) {
	mcaddf(p, "%04X ", v);
}
void mcaddx32(ref disasm_params_t p, uint v) {
	mcaddf(p, "%08X ", v);
}

void mcadd(ref disasm_params_t p, const(char) *str) {
	with (p)
	mcbufi = stradd(cast(char*)mcbuf, DISASM_BUF_SIZE, mcbufi, str);
}

void mcaddf(ref disasm_params_t p, const(char) *f, ...) {
	va_list va;
	va_start(va, f);
	with (p)
	mcbufi = straddva(cast(char*)mcbuf, DISASM_BUF_SIZE, mcbufi, f, va);
}

void mnadd(ref disasm_params_t p, const(char) *str) {
	with (p)
	mnbufi = stradd(cast(char*)mnbuf, DISASM_BUF_SIZE, mnbufi, str);
}

void mnaddf(ref disasm_params_t p, const(char) *f, ...) {
	va_list va;
	va_start(va, f);
	with (p)
	mnbufi = straddva(cast(char*)mnbuf, DISASM_BUF_SIZE, mnbufi, f, va);
}