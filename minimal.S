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
	//nop
.endm

// every primitive is word-aligned for speed of execution
.macro prim label
.byte 0x90
.align 4, 0x90
prim_\label:
.endm

.macro variable name, val=0
prim \name
	_dup
	mov $var_\name, %eax
	ret
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
	call prim_D      // -- l @D
	call prim_fetch_from_addr_on_stack // -- l D
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
	call prim_D          // -- b @D
	call prim_fetch_from_addr_on_stack  // -- b D
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
	je prim_apply
	// fall-through
prim compile_call
	// ( a -- )
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
	jz parse_fail  // failed to parse a number. Error handling shared with prim_quote
	_drop
	jmp prim_data
	ret

prim quote
	// ( -- a )
	_immediate
	call prim_word
	mov %eax, %ebp    // save string address
	call prim_lookup_word
	test %eax, %eax
	stc  // something that can be tested to determine if we have an address or a number
	jnz 1f
	// lookup failed 
	mov %ebp, %eax
	call prim_parse_number
	test %eax, %eax
	jz parse_fail
	_drop
1:
	ret

parse_fail:
	mov %ebp, %eax
	_swap
	mov $msg_not_found, %eax
	jmp prim_fail

prim apply
	// ( a -- ?? )
	mov %eax, %ebx
	_drop
	jmp *%ebx

prim exec
	// ( -- ? )
	_immediate
	call prim_quote
	jnc 1f   // carry flag not set - this is a literal, not a function
	jmp prim_apply
1:
	mov %ebp, %eax
	_dup
	mov $msg_tried_to_execute_a_literal, %eax
	jmp prim_fail

prim data
	// ( n -- )
	_immediate
	_dup                   // -- n n
	mov $0x89fc768d, %eax  // -- n x    this is _dup in hex. TODO: proper inlining!
	call prim_store_inc    // -- n
	_dup                   // -- n n
	mov $0x06, %al         // -- n xb   last byte of _dup
	call prim_store_byte_inc // -- n
	_dup
	mov $0xb8, %eax          // -- n b   movb instruction
	call prim_store_byte_inc // -- n
	call prim_store_inc      // --
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
	_swap
	subl (%esi), %eax
	_nip
	ret

prim inc
	inc %eax
	ret

prim dec
	dec %eax
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
	cmpb $'9', 1(%eax)  // TODO: decimals
	jg 3f
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
3:
	xor %eax, %eax
	_dup
	ret

prim parse_hex_digit
	// ( b -- n )
	sub $'0', %al
	cmp $9, %al
	jbe 1f
	sub $('a' - ':'), %al
	cmp $15, %al
	ja parse_number_fail
1:
	ret
parse_number_fail:
	mov %ebp, %eax
	_dup 
	mov $msg_number_parse_fail, %eax
	jmp prim_fail

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

prim align_heap
	// ( -- )
	mov var_H, %ebx
	movl $0x90909090, (%ebx)
	addl $4, %ebx
	andl $0xfffffffb, %ebx
	mov %ebx, var_H
	ret

prim def
	// ( -- )  TODO should align to cell boundary with nop.
	_immediate
	push %edi
	call prim_align_heap
	call prim_word   // -- l
	_dup
	mov 4(%eax), %eax // -- id1
	_swap
	mov (%eax), %eax // -- id1 id0    // make an identifier
	call prim_D      // -- id1 id0 @d  // get dict address
	call prim_fetch_from_addr_on_stack // id1 id0 d
	call prim_set_A  // -- id1 id0    // ...and set A
	call prim_store_inc   // -- id0 
	call prim_store_inc   // -- 
	call prim_H      // -- @h     // current heap address
	call prim_fetch_from_addr_on_stack  // -- h
	call prim_store_inc   // --       // store the code address
	add $4, %edi     // --       // unused cell
	mov %edi, var_D  // --       // save new dictionary address
	pop %edi
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

prim fetch_from_addr_on_stack
	// ( a -- n )
	mov (%eax), %eax
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

prim store_to_addr_on_stack
	// ( n a -- )	
	mov (%esi), %ebx
	_nip
	mov %ebx, (%eax)
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

prim emit_id
	// ( id -- )
	push %ecx
	push %edi
	xor %ecx, %ecx
	mov (%eax), %cl
	mov %eax, %edi
	inc %edi
1:
	call prim_fetch_byte_inc
	call prim_emit
	loop 1b
	pop %edi
	pop %ecx
	_drop
	ret

prim warn
	// ( id id -- )
	call prim_emit_id
	call prim_emit_id
	_dup
	mov $'\n', %eax
	call prim_emit
	ret

prim fail
	// ( id id -- )
	call prim_warn
	_dup
	mov $1, %eax
	jmp prim_exit

prim bye
	_immediate
	xor %eax, %eax
prim exit
	mov %eax, %ebx
	xor %eax, %eax
	inc %eax
	int $0x80


variable D, end_dict  // dictionary
variable H, heap      // heap addr
variable K, 0         // last key read
variable M, prim_repl // addr of main function

message not_found "Not a dictionary word or number: "
message number_parse_fail "Invalid number format: "
message welcome "Cantilever v0.0\n"
message tried_to_execute_a_literal "Tried to execute a non-function value: "


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
//entry "@",        prim_fetch
entry "@",       prim_fetch_from_addr_on_stack
entry "@b",       prim_fetch_byte
entry "!",        prim_store
entry "!+",       prim_store_inc
entry "!b",       prim_store_byte
entry "!b+",      prim_store_byte_inc
entry "!!",       prim_store_to_addr_on_stack

// word manipulation
entry ":",        prim_def-1
entry "'",        prim_quote-1
entry "#",        prim_exec-1

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
entry "1+",       prim_inc
entry "1-",       prim_dec

// logical and conditional
entry "=",        prim_equals
entry "<",        prim_less_than
entry ">",        prim_greater_than
entry "?;",       prim_cond_return

// IO
entry ".",     prim_emit
entry ".h",  prim_emit_hex
entry ".id",   prim_emit_id

// Misc
entry "#bye",     prim_bye-1
entry "bye",      prim_bye
entry "exit",     prim_exit
entry "key",      prim_key
entry "word",     prim_word

// legacy
entry "$",        prim_data
entry ",",        prim_store_alloc_byte
end_dict:





