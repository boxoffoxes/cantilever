/* Register allocation
 * We make heavy use of preprocessor macros to
 * abstract registers and allow for easier
 * porting and changing of execution model
 */

// the data stack
#define ToS   %eax
#define NoS   (%esi)
#define DSP   %esi

// the return stack
#define ToRS  (%esp)
#define RSP   %esp

// special purpose registers
#define Zero  $0

// General purpose registers:
// RegA is the Address Register, RegC is the string counter
#define RegA  %edi
#define RegB  %ebx
#define RegC  %ecx
#define RegD  %edx
#define RegE  %ebp

// Thoughts on register saving:
//
// With threaded code it is non-trivial for non-primitives to 
// save registers when ideally the execution model is a stack
// machine, so the existence of CPU registers should really be
// hidden.

.macro _advance_cell reg
	lea 4(\reg), \reg
.endm

.macro _clear reg
	xor \reg, \reg
.endm

.macro _drop
	lodsl
.endm

.macro _dup
	lea -4(DSP), DSP
	movl ToS, NoS
.endm

.macro _pushds val
	_dup
	movl \val, ToS
.endm

.macro _popds dest
	mov ToS, \dest
	_drop
.endm

.macro _nip
	lea 4(DSP), DSP
.endm

.macro _swap
	xchg ToS, NoS
.endm

// a word is immediate if its first instruction is a nop
.macro _immediate
	nop
.endm

.macro prim label, word="\label", in=0, out=0, side=0, inline="prim_\label", len=(10001f - prim_\label)
.globl prim_\label
prim_\label:
.endm

.macro end
10001:
ret
.endm

.macro variable name, val=0
prim \name
	_dup
	mov $var_\name, ToS
end
.align 4
var_\name:
	.int \val
.endm

.macro message label txt
msg_\label:
	.byte 2f-1f
1:
	.ascii "\txt"
2:
.endm

.macro entry key, addr
.byte  2f - 1f
1:
.ascii "\key"
2:
.align 8, 0
.int \addr
.int 0
.endm
