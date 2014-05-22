#include <asm/unistd.h>

.section .flat, "awx", @progbits

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

// a word is immediate if its first instruction is a nop
.macro _immediate
	nop
.endm

// every primitive is word-aligned for speed of execution
.macro prim label
.align 4,0x90
prim_\label:
.endm

.macro variable name, val=0
prim \name
	_dup
	mov var_\name, %eax
	ret
.align 4
var_\name:
	.int \val
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

/*.macro entry key, addr
.short \key
.short \addr - _start
.endm*/


.globl _start
.align 4, 0x90
_start:
	cld
	mov %esp, %esi
	lea -2048(%esp), %esp // use part of call stack for data stack
	mov var_H, %edi
	jmp *var_M

prim key
	// ( -- b )
	_dup
	push %ecx
	xor %ebx, %ebx
	mov $var_K, %ecx
	mov %ebx, %edx
	inc %edx
	mov $__NR_read, %eax
	int $0x80
	test %eax, %eax
	jz prim_bye
	movzbl var_K, %eax
	pop %ecx
	ret

prim drop_spaces
	// ( -- b )
	call prim_key
	cmp $' ', %al
	ja 1f
	_drop
	jmp prim_drop_spaces
1:
	ret

prim word
	// ( -- l )   TODO: built-in stack smash here!
	call prim_drop_spaces
	push %edi
	push %ecx
	xor %ecx, %ecx
	mov var_H, %edi  // use the heap for our temporary string buffer
	inc %edi         // leave space for the char count.
0:
	call prim_store_byte_inc
	inc %ecx
	call prim_key
	cmp $' ', %al
	jbe 1f
	jmp 0b
1:
	xor %eax, %eax        // zero %eax
	stosl                 // add 8 bytes of zeroes after word
	stosl
	mov var_H, %edi
	mov %cl, (%edi)       // save character count
	mov %edi, %eax        // push the label address
	pop %ecx
	pop %edi
	ret

prim lookup_word
	// ( l -- a )
	push %edi
	call prim_D      // -- l D
	call prim_set_A  // -- l
	_dup
	mov (%eax), %eax // -- l n
1:
	// Test first cell
	lea -16(%edi), %edi
	call prim_fetch  // -- l n n1
	test %eax, %eax
	jz 2f
	cmp (%esi), %eax
	_drop            // -- l n
	jne 1b
	// found a match TODO: doesn't check second portion of label yet
	mov 8(%edi), %eax  // -- l a
	_nip               // -- a
	pop %edi
	ret
2:
	pop %edi
	_nip             // -- n 0
	_nip             // -- 0
	ret


prim lookup
	// ( b -- a )
	push %edi
	call prim_D          // -- b D
	call prim_set_A      // -- b
1:
	lea -4(%edi), %edi
	call prim_fetch_byte // -- b b1
	mov %al, %ah
	mov (%esi), %al      // -- b b1b pack bytes to be compared into %eax
	_nip                 // -- b1b
	test %ah, %ah
	jz 2f               // end of dict with no match
	cmp %ah, %al
	jne 1b
	// found a match
	mov (%edi), %eax
	shr $16, %eax        // remove the key
	add $_start, %eax    // uncompress addr
	pop %edi
	ret
2:
	xor %eax, %eax       // lookup failed. Return zero
	pop %edi
	ret

prim eval
	// ( l -- ?? )
	mov %eax, %ebp   // store our label address somewhere harmless for future use
	call prim_lookup_word
	test %eax, %eax
	jz 2f
	mov (%eax), %bl
	cmp $0x90, %bl	// if the first instruction is a nop then the word is immediate
	je prim_exec
	// fall-through
prim compile_call
	// ( a -- )
	_immediate
	movb $0xe8, (%edi)
	inc %edi
	lea 4(%edi), %edi
	sub %edi, %eax
	mov %eax, -4(%edi)
	_drop
	mov %edi, var_H
	ret
2:
	// try to interpret as number
	mov %ebp, %eax  // recover our saved address
	call prim_parse_number
	test %eax, %eax
	jz 3f  // failed to parse a number
	_drop
	jmp prim_data
	ret
3:
	movl $0x100, %eax
	jmp prim_error

prim exec
	_immediate
	mov %eax, %ebx
	_drop
	jmp *%ebx

prim quote
	// ( -- a )
	_immediate
	call prim_word
	call prim_lookup_word
	ret

prim data
	// ( n -- )
	_immediate
	_dup
	mov $0xb8, %eax
	call prim_store_byte_inc
	call prim_store_inc
	mov %edi, var_H
	ret

prim literal_byte
	_dup
	pop %eax           // get our return address
	inc %eax           // skip the literal value
	push %eax          // push the new return address
	movzbl -1(%eax), %eax // fetch the literal we just skipped
	ret

prim dup
	_dup
	ret

prim drop
	_drop
	ret

prim nip
	_nip
	ret

prim swap
	_swap
	ret

prim push
	pop %ebx // make sure our return address
	push %eax
	_drop
	push %ebx // remains on ToRS
	ret

prim pop
	pop %ebx // our return address
	_dup
	pop %eax
	push %ebx
	ret

prim set_A
	mov %eax, %edi
	_drop
	ret

prim get_A
	_dup
	mov %edi, %eax
	ret

prim add
	addl (%esi), %eax
	_nip
	ret

prim subtract
	subl (%esi), %eax
	_nip
	ret


prim equals
	cmp (%esi), %eax
	jne 1f
	mov $-1, %eax
	ret
1:
	xor %eax, %eax
	ret

prim greater_than
	cmp (%esi), %eax
	jle 1f
	mov $-1, %eax
	ret
1:
	xor %eax, %eax
	ret

prim less_than
	cmp (%esi), %eax
	jge 1f
	mov $-1, %eax
	ret
1:
	xor %eax, %eax
	ret

prim cond_return
	test %eax, %eax
	_drop
	jz 1f
	pop %ebx
1:
	ret

prim parse_number
	// ( l -- n bool )
	cmpb $'9', 1(%eax)  // TODO: need to handle this more gracefully. Also decimals
	jg prim_bye
prim parse_hex
	// ( l -- n bool )
	push %ecx
	push %edi
	xor %ecx, %ecx
	movb (%edi), %cl
	inc %edi
	xor %eax, %eax
1:
	shl $4, %eax
	call prim_fetch_byte_inc
	call prim_parse_hex_digit
	call prim_add
	loop 1b
	pop %edi
	pop %ecx
	_dup
	mov $-1, %eax  // TODO always succeeds eek!
	ret

prim parse_hex_digit
	sub $'0', %al
	cmp $9, %al
	jbe 1f
	sub $('a' - ':'), %al
	// TODO: error checking
1:
	ret

prim extract_hex_digit
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
	push %ecx
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
	pop %ecx
	ret

prim def
	// ( -- )  TODO fix for using words
	_immediate
	call prim_get_A  // save A register
	call prim_push   // ...on return stack
	call prim_D      // get dict address
	call prim_set_A  // ...and set A
	call prim_key    // read a byte
	call prim_store_byte_inc // ...and store it in the dict
	inc %edi         // skip unused byte
	call prim_H      // get current heap address
	subl $_start, %eax    // ... and subtract _start
	mov %ax, (%edi)  // copy the low 16 bits from ToS to the dict
	inc %edi         // and increment
	inc %edi         // ...by 16 bits
	mov %edi, var_D  // save new dictionary address
	call prim_pop    // fetch stored value from rstack
	call prim_set_A  // and restore to A register
	ret


prim fetch_byte
	_dup
	movzbl (%edi), %eax
	ret

prim fetch_byte_inc
	_dup
	movzbl (%edi), %eax
	inc %edi
	ret

prim fetch
	_dup
	movl (%edi), %eax
	ret

prim fetch_inc
	_dup
	movl (%edi), %eax
	lea 4(%edi), %edi
	ret

prim store_byte
	movb %al, (%edi)
	_drop
	ret

prim store_byte_inc
	stosb
	_drop
	ret

prim store_alloc_byte
	call prim_store_byte_inc
	mov %edi, var_H
	ret

prim store
	movl %eax, (%edi)
	_drop
	ret

prim store_inc
	stosl
	_drop
	ret

prim emit
	push %ecx
	push %eax
	xor %ebx, %ebx
	inc %ebx
	mov %esp, %ecx
	mov %ebx, %edx
	mov $__NR_write, %eax
	int $0x80
	_drop
	pop %ebx // discard the buffer we created on the rstack
	pop %ecx
	ret

prim repl
	call prim_word
	call prim_eval
	jmp prim_repl

prim bye
	xor %eax, %eax
prim error
	mov %eax, %ebx
	xor %eax, %eax
	inc %eax
	int $0x80


variable D, end_dict  // dictionary
variable H, heap      // heap addr
variable K, 0         // last key read
variable M, prim_repl // addr of main function

heap:
.space 1024

.align 8,0
dict:
entry "", _start
entry "dict",  prim_D
entry "here",  prim_H
entry "main",  prim_M

// memory access
entry "a@",       prim_get_A
entry "a!",       prim_set_A
entry "@",        prim_fetch
entry "@b",       prim_fetch_byte
entry "!",        prim_store
entry "!+",       prim_store_inc
entry "!b",       prim_store_byte
entry "!b+",      prim_store_byte_inc

// word manipulation
entry ":",        prim_def
entry "'",        prim_quote
entry "#",        prim_exec

// stack manipulation
entry "dup",      prim_dup
entry "drop",     prim_drop
entry "nip",      prim_nip
entry "swap",     prim_swap

// return stack manipulation
entry "push",     prim_push
entry "pop",      prim_pop

// Arithmetic
entry "+",        prim_add
entry "-",        prim_subtract

// logical and conditional
entry "=",        prim_equals
entry "<",        prim_less_than
entry ">",        prim_greater_than
entry "?;",       prim_cond_return

// IO
entry "emit",     prim_emit
entry "emitHex",  prim_emit_hex

// Misc
entry "bye",      prim_bye
entry "key",      prim_key
entry "word",     prim_word

// legacy
entry "$",        prim_data
entry ",",        prim_store_alloc_byte
end_dict:





