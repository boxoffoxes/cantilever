#include <asm/unistd.h>

.section .flat, "awx", @progbits
.set IMMEDIATE, 0x1

.macro _drop
	lodsl
.endm

.macro _dup
	lea -4(%esi), %esi
	movl %eax, (%esi)
.endm

.macro _nip
	lea 4(%esi), %esi
.endm

.macro _swap
	xchg %eax, (%esi)
.endm


.macro prim label
.align 4,0x90
prim_\label:
.endm

.macro variable name, val=0
.align 4,0x90
var_\name:
	.int \val

prim \name
	_dup
	mov $var_\name, %eax
	ret
.endm

.macro entry name, func, flags=0
	.ascii "\name"
	.align 4, 0
	.int (\func + \flags)
.endm



.globl _start
.align 4, 0x90
_start:
	// set up stack
	mov %esp, %esi
	lea -2048(%esp), %esp // use part of call stack for data stack
	mov var_H, %edx
1:
	call prim_word  // ( -- str )
	push %eax
	call prim_lookup
	test %eax, %eax
	jnz 2f

	pop %eax
	call prim_parse_hex
	call handle_data
	jmp 1b
2:
	pop %ebx  // discard the unneeded string
	call handle_xt
	mov %edx, var_H
	jmp 1b


// handlers

.align 4, 0x90
handle_xt:
	test $0x1, %eax
	jz handle_compile
	dec %eax // clear the low bit.
	jmp handle_immed

.align 4, 0x90
handle_compile:
	movb $0xe8, (%edx)
	mov %edx, var_Z // save location of last compiled instr
	inc %edx
	lea 4(%edx), %edx
	sub %edx, %eax
	mov %eax, -4(%edx)
	_drop
	mov %edx, var_H
	ret

.align 4, 0x90
handle_data:
	push %ecx
	mov $(end_dup-prim_dup), %ecx
	xchg %edx, %edi
	push %esi
	mov $prim_dup, %esi
	rep movsb
	xchg %edx, %edi
	pop %esi
	pop %ecx
	ret

prim immed
	// ( a -- ?? )
handle_immed:
	mov %eax, %ebx
	_drop  // remove xt after storing to %ebx
	jmp *%ebx


// PRIMITIVES

prim make_dict_entry
	// ( a -- )
	call prim_word
	call prim_make_label
	mov var_D, %ebx
	mov %eax, (%ebx)
	_drop
	mov %eax, 4(%ebx)
	lea 8(%ebx), %ebx
	mov %ebx, var_D
	ret

prim less_than
	// ( n1 n2 -- n1 bool )
	// semi-non-destructive! Signed comparison
	cmp %eax, (%esi)
	mov $0, %eax  // don't use xor, as it affects CPU flags!
	jle 1f
	dec %eax  // -1 is true (forth convention)
1:
	ret

prim not_equal
	// ( n1 n2 -- n1 bool )
	sub (%esi), %eax   // cheating a little!
	ret

prim equal
	// ( n1 n2 -- n1 bool )
	cmp %eax, (%esi)  // if equal ZF is set
	mov $-1, %eax
	jz 1f
	inc %eax
1:
	ret

prim dup
	_dup
end_dup:
	ret

prim make_label
	// ( str -- l )
	mov 4(%eax), %eax  // skipping the count. label is simply the first four chars of str
	ret

prim fail
	xor %eax, %eax
	inc %eax
	call *%eax


prim fetch_A
	_dup
	mov %edx, %eax

prim set_A
	mov %eax, %edx
	_drop
	ret

prim inc_A
	inc %edx
	ret

prim fetch
	// ( a -- n )
	mov (%eax), %eax
	ret

prim fetch_byte
	// ( a -- b )
	movzbl (%eax), %eax   // == AT&T syntax for movzx!
	ret

prim store_byte
	// ( b -- )
	movb %al, (%edx)
	_drop
	ret

prim store_inc_byte
	// ( b -- )
	movb %al, (%edx)
	_drop
	inc %edx
	ret

prim jump_to_addr
	// ( a -- ??? )
	mov %eax, %ebx
	_drop
	jmp *%ebx

prim double
	// ( n -- 2n )
	shl $1, %eax
	ret

prim halve
	// ( 2n -- n )
	sar $1, %eax
	ret

prim xor
	// ( n1 n2 -- n1^n2 )
	xor (%esi), %eax
	_nip
	ret

prim or
	// ( n1 n2 -- n1|n2 )
	or (%esi), %eax
	_nip
	ret

prim swap
	_swap
	ret

prim word
	// ( -- str )
	// warning: stores temporary string on the heap without allocating space
	push %ecx
	push %edx
0:
	call prim_key
	cmp $32, %eax
	jbe 20f // skip whitespace
	mov $0, %ecx
	mov var_H, %edx
	lea 4(%edx), %edx
1:
	call prim_store_inc_byte
	inc %ecx
	call prim_key
	cmp $32, %eax
	jbe 2f
	jmp 1b
2:
	test $0xffffff80, %ecx  // is the word longer than 128 chars? TODO: fail if so
	movl $0, (%edx) // make sure there are zeroes after string, just in case!
	mov var_H, %eax
	mov %ecx, (%eax)
	pop %edx
	pop %ecx
	ret
20:
	_drop
	jmp 0b


prim key
	// ( -- b )
	_dup
	push %ecx
	push %edx
	xor %ebx, %ebx
	mov $var_K, %ecx
	mov %ebx, %edx  // warning: clobbering A register
	inc %edx
	mov $__NR_read, %eax
	int $0x80
	test %eax, %eax
	jz prim_bye
	movzbl var_K, %eax
	pop %edx
	pop %ecx
	ret

prim emit
	// ( b -- )
	push %ecx
	push %edx
	push %eax
	xor %ebx, %ebx
	inc %ebx
	mov %esp, %ecx
	mov %ebx, %edx
	mov $__NR_write, %eax
	int $0x80
	_drop
	pop %ebx // discard the buffer we created on the rstack
	pop %edx
	pop %ecx
	ret

prim extract_hex_digit
	// ( n -- b n>>4 )
	_dup
	and $0xf, %eax
	add $'0', %eax
	cmp $'9', %eax
	jbe 1f
	add $39, %eax
1:
	_swap
	shr $4, %eax
	ret

prim emit_hex
	// ( n -- )
	xor %ecx, %ecx
1:
	call prim_extract_hex_digit
	inc %ecx
	test %eax, %eax
	jnz 1b
	_drop
2:
	call prim_emit
	loop 2b
	ret

prim parse_hex_digit
	// ( b -- n )
	sub $'0', %al
	cmp $9, %al
	jbe 1f
	sub $('a' - ':'), %al
	// TODO: error checking
1:
	ret

prim parse_hex
	// ( a -- n )
	push %ecx
	push %edx
	mov (%eax), %ecx
	cmp $8, %ecx
	ja prim_fail
	lea 4(%eax), %edx
	xor %ebp, %ebp // buffer for intermediate results
	xor %eax, %eax
1:
	mov (%edx), %al
	inc %edx
	call prim_parse_hex_digit
	shl $4, %ebp
	or %eax, %ebp
	loop 1b
	
	mov %ebp, %eax
	pop %edx
	pop %ecx
	ret


prim lookup
	// ( str -- xt )
	push %edx
	mov var_D, %edx
	call prim_make_label   // ( -- l )
1:
	lea -8(%edx), %edx
	cmpl $0, (%edx)
	jz 2f  // lookup failed. leave a zero on ToS
	cmp %eax, (%edx)
	jne 1b
2:
	mov 4(%edx), %eax
	pop %edx
	ret
	


prim bye
	// ( -- )
	xor %eax, %eax  // we're about to quit, so clobbering ToS doesn't matter
	// fall-through!
prim exit
	// ( n -- )
	mov %eax, %ebx
	xor %eax, %eax
	inc %eax
	int $0x80

prim ret
	ret
end_ret:

prim return
	// ( -- )
	movb $0xc3, (%edx) // ret instruction
	mov %edx, var_Z
	inc %edx
	// fall-through!
prim align
	mov $0x909090, %edx
	add $3, %edx
	and $-4, %edx
	mov %edx, var_H // todo: is this safe?
	ret


prim quote
	// ( -- xt )
	call prim_word
	push %eax
	call prim_lookup
	test %eax, %eax
	jnz 1f
	pop %eax
	call prim_parse_hex
	ret
1:
	pop %ebx  // discard unneeded string
	ret


variable K
variable B, _start
variable D, end_dict
variable H, heap
variable Z, 0 // addr of last compiled instruction

.align 4
heap:
.space 1024

.align 4
dict:

// dictionary.

.int 0
.int 0

entry "::", prim_make_dict_entry, IMMEDIATE
entry "#",  prim_immed, IMMEDIATE
entry "'",  prim_quote, IMMEDIATE
entry "=",  prim_equal
entry "<",  prim_less_than
entry "exit", prim_exit
entry "bye", prim_bye, IMMEDIATE
entry "H",  prim_H
entry "D",  prim_D
entry "dup", prim_dup
entry ".c",  prim_emit
entry ".",   prim_emit_hex
entry "!",   prim_store_byte
entry "@",   prim_fetch_byte
entry ";"    prim_return, IMMEDIATE
entry "#."   prim_emit_hex, IMMEDIATE


end_dict:  // must be at the end!
