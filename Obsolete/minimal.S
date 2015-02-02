#include <asm/unistd.h>

.set dict, 0
#include "macros.S"

.section .flat, "awx", @progbits


.globl _start
.align 4, 0x90
_start:
	cld
	mov %esp, %esi
	lea -2048(%esp), %esp // use part of call stack for data stack
	movl %esp, var_rs0
	movl var_H, %edi
	movl var_D, %eax
	addl $16, %eax
	movl %eax, var_free_dict
	_clear %eax
	jmp *var_M


/* cdecl calling convention register preservation rules
 * caller-saved:
 		%eax, %ecx, %edx
 * all other registers are callee-saved:

This means that any wrapper for calling C functions
needs to preserve %eax
 */
/* state diagram explanation
    ( x -- y  / abcdeimrv )
	x -- y is the data stack effect
	Letters after the slash indicate what side effects result:
		abcde: These are the virtual GP registers %edi to %ebp
		m: write to main memory
		i: system calls
		r: non call/ret return stack manipulation 
		v: write to variable
*/

prim key // TODO: buffered IO
	// ( -- b / K )
	_dup
	push %ecx
	_clear %ebx
	mov $var_K, %ecx
	mov %ebx, %edx
	inc %edx
	mov $__NR_read, %eax
	int $0x80
	test %eax, %eax
	jz prim_bye       // TODO: not PIC
	movzbl var_K, %eax
	pop %ecx
end

prim drop_spaces
	// ( -- b / K )
	call prim_key
	cmp $' ', %al
	ja 1f
	_drop
	jmp prim_drop_spaces
1:
end

prim word
	// ( -- l / Kw )   TODO: built-in stack smash here!
	call prim_drop_spaces
	push %edi
	push %ecx
	_clear %ecx
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
	_clear %eax            // zero %eax
	stosl                 // add 8 bytes of zeroes after word
	stosl
	mov var_H, %edi
	mov %cl, (%edi)       // save character count
	mov %edi, %eax         // push the label address
	pop %ecx
	pop %edi
end

prim get_suffix
	// ( w -- d )
	movzbl (%eax), %ecx    // get str count
	addl %ecx, %eax        // -- w+n  add addr of string to get last char
	movzbl (%eax), %eax    // -- b    get last char
	shl $24, %eax          // -- 0xBB000000
	orl $0x5f5f03, %eax    // -- 3"__b"
	push %eax              // temp word buffer on RS
	movl %esp, %eax        // -- buf
	call prim_find         // -- d 
	pop %ebx               // discard word buffer
end

prim strip_suffix
	// ( l0 -- l1 )
	/* warning: must not modify %ebx! */
	_clear %ecx
	movb (%eax), %cl
	decb (%eax)
	addl %eax, %ecx
	movb $0, (%ecx)
end

prim xt
	// ( d -- xt )
	_xt
end

prim xh
	// ( d -- xh )
	_xh
end

prim find
	// ( w -- d )
	movl (%eax), %edx // -- 
	movl var_D, %eax  // -- da
1: 
	movl (%eax), %eax // -- d
	test %eax, %eax   // reached end of dict?
	jz 2f
	movl 12(%eax), %ecx  // using %ecx to save stack shuffling
	cmpl %ecx, %edx
	jnz 1b
2:
end

/*
prim lookup_word
	// ( l -- a )
	push %edi
	call prim_D      // -- l @D
	call prim_fetch  // -- l D
	call prim_set_hp  // -- l
	_dup             // -- l l
	mov (%eax), %eax  // -- l n
1:
	// Test first cell
	lea -16(%edi), %edi
	_pushds %edi     // -- l n a
	call prim_fetch  // -- l n n1
	test %eax, %eax 
	jz 2f
	cmp (%esi), %eax 
	_drop            // -- l n
	jne 1b
	// found a match TODO: doesn't check second portion of label yet
	mov 8(%edi), %eax   // -- l a
	_nip               // -- a
	pop %edi
	jmp 10001f
2:
	pop %edi
	_nip             // -- n 0
	_nip             // -- 0
end
*/

prim eval2
	// ( l -- ?? )
	mov %eax, %ebp   // store our label address somewhere harmless for future use
	call prim_find  // -- d
	test %eax, %eax // not found?
	jz 1f
	movl 8(%eax), %ebx  // get execution handler to %ebx
	_xt                 // -- xt
	jmp *%ebx

1:  /* not found in dictionary, try number conversion */
	mov %ebp, %eax          // -- l
	call prim_parse_number // -- n bool
	test %eax, %eax
	_drop                  // -- n
	jz 2f
	jmp prim_data
2:
	mov %ebp, %eax         // -- l
	_dup                   // -- l l
	call prim_get_suffix   // -- l d
	test %eax, %eax        // not a recognised suffix?
	jz parse_fail
	_xt                    // -- l xt
	_popds %ebx            // -- l
	call prim_strip_suffix // -- l1
	jmp *%ebx

/*
prim eval
	// ( l -- ?? )
	mov %eax, %ebp   // store our label address somewhere harmless for future use
	call prim_lookup_word  // -- a
	test %eax, %eax
	jz 1f
	movb (%eax), %bl
	cmpb $0x90, %bl  // immediate words
	je prim_apply
	jmp prim_compile_call
1:
	mov %ebp, %eax          // -- l
	call prim_parse_number // -- n bool
	test %eax, %eax
	_drop                  // -- n
	jz 2f
	jmp prim_data
2:
	mov %ebp, %eax          // -- l
	call prim_get_suffix   // -- l a
	test %eax, %eax
	jz parse_fail
	_swap                  // -- a l
	call prim_strip_suffix // -- a l1
	_swap                  // -- l1 a
	jmp prim_apply

*/
prim compile_call
	// ( a -- )
	_update_Z        // save addr of last compiled instruction
	movb $0xe8, (%edi)
	inc %edi
	_alloc_cell
	sub %edi, %eax
	mov %eax, -4(%edi)
	_drop
	mov %edi, var_H
end

prim suffix_immed, "__#"
	// ( l -- )
	call prim_find  // -- d
	test %eax, %eax
	jz 1f
	_xt             // -- xt
prim handle_immed
	_popds %ebx     // --
	jmp *%ebx
1:
	movl %ebp, %eax        // -- l
	call prim_parse_number // n bool
	test %eax, %eax
	_drop
	jz parse_fail
end



prim quote
	// ( l -- xt )
	movl %eax, %ebp // save string
	call prim_find  // -- d
	test %eax, %eax
	jz parse_fail
	_xt             // -- xt
end

/* prim quote
	// ( l -- an )
	mov %eax, %ebp    // save string address
	call prim_lookup_word  // -- a
	test %eax, %eax
	stc  // something that can be tested to determine if we have an address or a number
	jnz 1f
	// lookup failed 
	mov %ebp, %eax
	call prim_parse_number // -- n bool
	test %eax, %eax
	jz parse_fail
	_drop
1:
end
*/

prim compile_quote
	_update_Z
	call prim_quote
	call prim_data
end

prim apply
	// ( a -- )
	_popds %ebx
	jmp *%ebx

prim exec
	// ( l -- ? )
	call prim_quote  //  -- n
	jnc 1f           // carry flag not set - this is a literal, not a function
	jmp prim_apply
1:
	mov %ebp, %eax
	call prim_parse_number
	test %eax, %eax
	jz parse_fail
	_drop
end
	/* mov %ebp, %eax
	_pushds $msg_tried_to_execute_a_literal
	jmp prim_fail */

prim data
	// ( n -- )
	_update_Z              // -- save addr of instr
	_pushds $0x89fc768d      // -- n x    this is _dup in hex. TODO: proper inlining!
	call prim_store_inc    // -- n
	_dup                   // -- n n
	mov $0x06, %al         // -- n xb   last byte of _dup
	call prim_store_byte_inc // -- n
	_pushds $0xb8            // -- n b   movb instruction
	call prim_store_byte_inc // -- n
	call prim_store_inc      // --
	mov %edi, var_H
end

prim word_literal
	// ( -- w )
	_dup
	mov (%esp), %eax    // fetch our return address (where string is stored)
	movzbl (%eax), %ecx  // fetch count
	add %ecx, (%esp)   // update our return address by string length..
	incl (%esp)         // ...plus one for the length count.
end

prim literal_byte
	_dup
	pop %eax            // get our return address onto ToS
	inc %eax            // skip the literal value
	push %eax           // push the new return address
	movzbl -1(%eax), %eax // fetch the literal we just skipped
end


#include "primitives.S"


prim compile_else, "else", prim_handle_immed
	// ( a1 -- a2 )
	movb $0xeb, (%edi)  // write a jmp instruction
	inc %edi            // and increment %edi
	_pushds %edi          // push %edi onto stack
	_swap               // bring addr saved by compile_if to top
	inc %edi            // leave a byte for the jump addr
	// fallthrough
prim compile_endif, "endif", prim_handle_immed
	// ( a -- )
	_update_Z
	mov %eax, %ebx       // 
	subl %edi, %ebx     // calculate relative address
	not %ebx            // this is one less than %edi-%ebx, which should be correct
	test $0x100, %ebx   // TODO: what's this doing?! Testing if jmp is too far?
	jz 1f
	mov $msg_failed_conditional, %eax
	_pushds $msg_failed_conditional
	jmp prim_fail
1:
	movb %bl, (%eax)
	mov %edi, var_H
	_drop
end

prim compile_if, "if", prim_handle_immed
	// ( -- a )
	_update_Z
	_pushds $0x74adc085  // magic number: "test %eax, %eax ; _drop ; je $0"  TODO: only supports up to 127 byte jump!
	stosl
	mov %edi, %eax    // leave a copy of the target on the stack
	movb $0, (%edi)    // leave space for the offset
	inc %edi
	mov %edi, var_H  // update the free address
end


prim parse_number
	// ( l -- n bool )
	mov 1(%eax), %ebx     // -- l
	cmpw $0x7830, %bx       // 0x prefix
	je prim_parse_hex
	// no prefix? fall through to base 10
	_dup                  // -- l l
	movl $10, %eax        // -- l 10
prim base
	// ( l n -- n bool )
	push %ecx
	push %edi
	push %ebp
	_popds %ebp // -- l
	_clear %ecx
	movb (%edi), %cl
	inc %edi   // skip count
	_clear %eax
	mov %ebp, %ebx
1:
	mull %ebx    // %eax * 10
	call prim_fetch_byte_inc
	subb $'0', %al
	cmpb $9, %al     // TODO: won't work for bases larger than 10!
	ja 2f
	call prim_add
	loop 1b
	_pushds $-1
	jmp 3f
2:
	_clear %eax
3:
	pop %ebp
	pop %edi
	pop %ecx
end

prim parse_hex
	// ( l -- n bool )
	push %ecx
	push %edi
	_clear %ecx
	movb (%edi), %cl
	dec %cl       // skip the
	dec %cl       // 0x prefix
	add $3, %edi  // ...
	_clear %eax
1:
	shl $4, %eax                        // -- n
	call prim_fetch_byte_inc           // -- n b
	call prim_parse_hex_digit          // -- n n
	jnc 3f    // carry not set = failure
	call prim_add                      // -- n
	loop 1b
	pop %edi
	pop %ecx
	_dup
	mov $-1, %eax
	jmp 10001f
3:
	pop %edi
	pop %ecx
	_clear %eax
end


prim parse_hex_digit
	// ( b -- n )
	subb $'0', %al
	cmpb $9, %al
	jbe 1f
	subb $('a' - ':'), %al
	cmpb $15, %al
	jbe 1f
	clc  // indicate failure
	jmp 10001f
1:
	stc  // indicate success
end

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
end

prim emit_hex, ".h"
	push %ecx
	_dup
	mov $'0', %eax
	call prim_emit
	_dup
	mov $'x', %eax
	call prim_emit
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
end

prim def, "__:"
	// ( l -- )
	movl var_D, %edx         // current head of dict
	movl var_free_dict, %ebx // next free dict locn
	movl %edx, (%ebx)        // store pointer to next entry
	movl %edi, 4(%ebx)       // store heap address as xt
	movl $prim_compile_call, 8(%ebx) // store default xh. TODO: use config var
	movl (%eax), %eax   // l -- n
	movl %eax, 12(%ebx)      // TODO: partial label only: use mm0 or xmm0
	movl %ebx, var_D         // save new head of list
	leal 16(%ebx), %ebx      // advance to free dict location
	movl %ebx, var_free_dict // store free dict
	_drop
end
/*
	push %edi
	_dup
	mov 4(%eax), %eax // -- l id1
	_swap
	mov (%eax), %eax  // -- id1 id0    // make an identifier
	call prim_D      // -- id1 id0 @d  // get dict address
	call prim_fetch  // id1 id0 d
	call prim_set_hp  // -- id1 id0    // ...and set A
	call prim_store_inc   // -- id0 
	call prim_store_inc   // -- 
	call prim_H      // -- @h     // current heap address
	call prim_fetch  // -- h
	call prim_store_inc   // --       // store the code address
	add $4, %edi     // --       // unused cell
	mov %edi, var_D  // --       // save new dictionary address
	pop %edi
end */

prim store_alloc_byte, "!b+"
	call prim_store_byte_inc
	mov %edi, var_H
end

prim emit, ".b"
	push %ecx
	push %eax
	_clear %ebx
	inc %ebx
	mov %esp, %ecx   // we just pushed the char we wish to print, so our buffer is on the rstack
	mov %ebx, %edx
	mov $__NR_write, %eax
	int $0x80
	_drop
	pop %ecx  // discard the buffer we created on the rstack
	pop %ecx
end

parse_fail:
	mov %ebp, %eax
	_swap
	mov $msg_not_found, %eax
prim fail
	// ( w w -- )
	call prim_warn
	// Forth trick: clear the RS
	movl var_rs0, %esp
	// and back into the repl...
prim repl
	call prim_word
	call prim_eval2
	jmp prim_repl

prim emit_id, ".id"
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
end

prim warn
	// ( id id -- )
	call prim_emit_id
	call prim_emit_id
	_pushds $'\n'
	call prim_emit
end


prim bye
	xor %eax, %eax
prim exit
	mov %eax, %ebx
	xor %eax, %eax
	inc %eax
	int $0x80


variable H, heap      // heap addr
variable K, 0         // last key read
variable M, prim_repl // addr of main function
variable Z, heap      // addr of last instruction compiled
variable rs0, 0       // empty return stack pointer

message not_found "Not a dictionary word or number: "
message number_parse_fail "Invalid number format: "
message welcome "Cantilever v0.0\n"
message tried_to_execute_a_literal "Tried to execute a non-function value: "
message failed_conditional "Conditional code block too long\n"

variable free_dict, 0 // free dictionary space
variable D, dict           // dictionary

heap:
.space 1024

.section .dictionary
dictionary:





