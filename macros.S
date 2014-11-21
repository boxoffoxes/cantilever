/*
 * 
 * the data stack
 * 	 ToS   %eax
 * 	 ToSl  %al
 * 	 NoS   (%esi)
 * 	 DSP   %esi
 * 
 * the return stack
 * 	 ToRS  (%esp)
 * 	 RSP   %esp
 * 
 * special purpose registers
 * 	 Zero  $0
 * 
 * General purpose registers:
 * RegA is the Address Register, RegC is the string counter
 * 	 RegA  %edi
 * 	 RegB  %ebx
 * 	 RegBl %bl
 * 	 RegC  %ecx
 * 	 RegCl  %cl
 * 	 RegD  %edx
 * 	 RegE  %ebp
 * 
 */

// var_Z is the most recently compiled instruction
.macro _update_Z
	mov %edi, var_Z
.endm

// advance the heap pointer
.macro _alloc_cell
	lea 4(%edi), %edi
.endm

.macro _clear reg
	xor \reg, \reg
.endm

.macro _drop
	lodsl
.endm

.macro _dup
	lea -4(%esi), %esi
	movl %eax, (%esi)
.endm

.macro _pushds val
	_dup
	movl \val, %eax
.endm

.macro _popds dest
	mov %eax, \dest
	_drop
.endm

.macro _nip
	lea 4(%esi), %esi
.endm

.macro _swap
	xchg %eax, (%esi)
.endm

.macro _over
	_dup
	movl 4(%esi), %eax
.endm


.macro _xt
	movl 4(%eax), %eax
.endm

.macro _xh
	movl 8(%eax), %eax
.endm

.macro _xl
	movl 12(%eax), %eax
.endm

// a word is immediate if its first instruction is a nop
.macro _immediate
	nop
.endm

.macro header label, name, handler
.section .data
.globl header_\label
header_\label:
	.int dict
	.int prim_\label
	.int \handler
	.byte 10001f - 10000f
10000:
	.ascii "\name"
10001:
.align 4, 0
.set dict, header_\label
.endm

.macro prim label, name, handler=prim_compile_call
.ifeqs "\name", ""
	header \label, "\label", \handler
.else
	header \label, "\name", \handler
.endif
.section .flat
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
	mov $var_\name, %eax
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

.macro entry key, addr, in=0, out=0, se=0, ioff=0, ilen=0
.byte  2f - 1f
1:
.ascii "\key"
2:
.align 8, 0
.int \addr
.byte \in-\out, \ioff, \ilen, 0
.endm
