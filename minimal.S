#include <asm/unistd.h>
#include "macros.S"

.section .flat, "awx", @progbits


.globl _start
.align 4, 0x90
_start:
	cld
	mov %esp, DSP
	lea -2048(%esp), RSP // use part of call stack for data stack
	mov var_H, RegA
	jmp *var_M


/* cdecl calling convention register preservation rules
 * caller-saved:
 		%eax, %ecx, %edx
 * all other registers are callee-saved:

This means that any wrapper for calling C functions
needs to preserve %eax
 */
call_prim_from_c:
	// TODO: save registers such that cantilever prims can be called from
	// C. function address expected on stack.
	ret
	
/* state diagram explanation
    ( x -- y  / abcdeimrv )
	x -- y is the data stack effect
	Letters after the slash indicate what side effects result:
		abcde: These are the virtual GP registers RegA to RegE
		m: write to main memory
		i: system calls
		r: non call/ret return stack manipulation 
		v: write to variable
*/

prim key
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
	jz prim_bye
	movzbl var_K, ToS
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
	push RegA
	push RegC
	_clear RegC
	mov var_H, RegA  // use the heap for our temporary string buffer
	inc RegA         // leave space for the char count.
0:
	call prim_store_byte_inc
	inc RegC
	call prim_key
	cmp $' ', %al
	jbe 1f
	jmp 0b
1:
	_clear ToS            // zero %eax
	stosl                 // add 8 bytes of zeroes after word
	stosl
	mov var_H, RegA
	mov %cl, (RegA)       // save character count
	mov RegA, ToS         // push the label address
	pop RegC
	pop RegA
end

prim get_suffix
	// ( l -- l a )
	_dup                 // -- l l
	movzbl (ToS), ToS    // -- l n    get str count
	addl NoS, ToS        // -- l l+n  add addr of string to get last char
	movzbl (ToS), ToS    // -- l b    get last char
	shl $24, ToS            // -- 0 0xBB000000
	addl $0x5f5f03, ToS     // -- 0 3"__b"
	push ToS
	movl RSP, ToS
	call prim_lookup_word
	pop RegB // discard label buffer
end

prim strip_suffix
	// ( l0 -- l1 )
	_clear RegB
	movb (ToS), %bl
	decb (ToS)
	addl ToS, RegB
	movb Zero, (RegB)
end

prim lookup_word
	// ( l -- a )
	push RegA
	call prim_D      // -- l @D
	call prim_fetch_from_addr_on_stack // -- l D
	call prim_set_A  // -- l
	_dup             // -- l l
	mov (ToS ), ToS  // -- l n
1:
	// Test first cell
	lea -16(RegA), RegA
	call prim_fetch  // -- l n n1
	test ToS, ToS 
	jz 2f
	cmp NoS, ToS 
	_drop            // -- l n
	jne 1b
	// found a match TODO: doesn't check second portion of label yet
	mov 8(RegA), ToS   // -- l a
	_nip               // -- a
	pop RegA
	jmp 10001f
2:
	pop RegA
	_nip             // -- n 0
	_nip             // -- 0
end

prim eval
	// ( l -- ?? )
	mov ToS, RegE   // store our label address somewhere harmless for future use
	call prim_lookup_word  // -- a
	test ToS, ToS
	jz 1f
	movb (ToS), %bl
	cmpb $0x90, %bl  // immediate words
	je prim_apply
	jmp prim_compile_call
1:
	mov RegE, ToS          // -- l
	call prim_parse_number // -- n bool
	test ToS, ToS
	_drop                  // -- n
	jz 2f
	jmp prim_data
2:
	mov RegE, ToS          // -- l
	call prim_get_suffix   // -- l a
	test ToS, ToS
	jz parse_fail
	_swap                  // -- a l
	call prim_strip_suffix // -- a l1
	_swap                  // -- l1 a
	jmp prim_apply


prim compile_call
	// ( a -- )
	mov RegA, var_Z  // save addr of last compiled instruction
	movb $0xe8, (RegA)
	inc RegA
	_advance_cell RegA
	sub RegA, ToS
	mov ToS, -4(RegA)
	_drop
	mov RegA, var_H
end

prim quote
	// ( l -- an )
	mov ToS, RegE    // save string address
	call prim_lookup_word  // -- a
	test ToS, ToS
	stc  // something that can be tested to determine if we have an address or a number
	jnz 1f
	// lookup failed 
	mov RegE, ToS
	call prim_parse_number // -- n bool
	test ToS, ToS
	jz parse_fail
	_drop
1:
end

parse_fail:
	mov RegE, ToS
	_swap
	mov $msg_not_found, ToS
	jmp prim_fail

prim apply
	// ( a -- )
	_pop RegB
	jmp *RegB

prim exec
	// ( l -- ? )
	call prim_quote  //  -- n
	jnc 1f           // carry flag not set - this is a literal, not a function
	jmp prim_apply
1:
	mov RegE, ToS
	_push $msg_tried_to_execute_a_literal
	jmp prim_fail

prim data
	// ( n -- )
	mov %edi, var_Z        // -- save addr of instr
	_push $0x89fc768d      // -- n x    this is _dup in hex. TODO: proper inlining!
	call prim_store_inc    // -- n
	_dup                   // -- n n
	mov $0x06, %al         // -- n xb   last byte of _dup
	call prim_store_byte_inc // -- n
	_push $0xb8            // -- n b   movb instruction
	call prim_store_byte_inc // -- n
	call prim_store_inc      // --
	mov RegA, var_H
end

prim literal_byte
	_dup
	pop ToS            // get our return address
	inc ToS            // skip the literal value
	push ToS           // push the new return address
	movzbl -1(ToS), ToS // fetch the literal we just skipped
end

prim dup
	_dup
end

prim drop
	_drop
end

prim nip
	_nip
end

prim swap
	_swap
end

prim push
	pop RegB // make sure our return address
	push ToS
	_drop
	push RegB // remains on ToRS
end

prim pop
	pop RegB // our return address
	_dup
	pop ToS
	push RegB
end

prim set_A
	mov ToS, RegA
	_drop
end

prim get_A
	_dup
	mov RegA, ToS
end

prim add
	addl NoS, ToS
	_nip
end

prim subtract
	_swap
	subl NoS, ToS
	_nip
end

prim inc
	inc ToS
end

prim dec
	dec ToS
end

prim equals
	// ( n n -- n bool )
	cmp NoS, ToS
	jne 1f
	mov $-1, ToS
	jmp 10001f
1:
	_clear ToS
end

prim greater_than
	cmp NoS, ToS
	jle 1f
	mov $-1, ToS
	jmp 10001f
1:
	_clear ToS
end

prim less_than
	cmp NoS, ToS
	jge 1f
	mov $-1, ToS
	jmp 10001f
1:
	_clear ToS
end

prim cond_return
	test ToS, ToS
	_drop
	jz 1f
	pop RegB
1:
end

prim else
	// ( a1 -- a2 )
	_immediate
	movb $0xeb, (RegA)  // write a jmp instruction
	inc RegA            // and increment RegA
	_push RegA          // push RegA onto stack
	_swap               // bring addr saved by if to top
	inc RegA            // leave a byte for the jump addr
	// fallthrough
prim endif
	// ( a -- )
	_immediate
	mov ToS, RegB       // 
	subl RegA, RegB     // calculate relative address
	not RegB            // this is one less than %edi-%ebx, which should be correct
	test $0x100, RegB   // TODO: what's this doing?!
	jz 1f
	mov $msg_failed_conditional, ToS
	_push $msg_failed_conditional
	jmp prim_fail
1:
	movb %bl, (ToS)
	_drop
end

prim if
	// ( -- a )
	_immediate
	_push $0x74adc085  // magic number: "test %eax, %eax ; _drop ; je $0"  TODO: only supports up to 127 byte jump!
	stosl
	mov RegA, ToS    // leave a copy of the target on the stack
	movb Zero, (RegA)    // leave space for the offset
	inc RegA
	mov RegA, var_H  // update the free address
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
	push RegC
	push RegA
	push RegE
	_pop RegE // -- l
	_clear RegC
	movb (RegA), %cl
	inc RegA   // skip count
	_clear ToS
	mov RegE, %ebx
1:
	mull %ebx    // %eax * 10
	call prim_fetch_byte_inc
	subb $'0', %al
	cmpb $9, %al     // TODO: won't work for bases larger than 10!
	ja 2f
	call prim_add
	loop 1b
	_push $-1
	jmp 3f
2:
	_clear ToS
3:
	pop RegE
	pop RegA
	pop RegC
end

prim parse_hex
	// ( l -- n bool )
	push RegC
	push RegA
	_clear RegC
	movb (RegA), %cl
	dec %cl       // skip the
	dec %cl       // 0x prefix
	add $3, RegA  // ...
	_clear ToS
1:
	shl $4, ToS                        // -- n
	call prim_fetch_byte_inc           // -- n b
	call prim_parse_hex_digit          // -- n n
	jnc 3f    // carry not set = failure
	call prim_add                      // -- n
	loop 1b
	pop RegA
	pop RegC
	_dup
	mov $-1, %eax
	jmp 10001f
3:
	pop RegA
	pop RegC
	_clear ToS
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
	and $0xf, ToS
	add $'0', ToS
	cmp $'9', ToS
	jbe 1f
	add $39, ToS
1:
	_swap
	shr $4, ToS
end

prim emit_hex
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

prim def
	// ( l -- )  TODO should align to cell boundary with nop.
	push RegA
	_dup
	mov 4(ToS), ToS // -- l id1
	_swap
	mov (ToS), ToS  // -- id1 id0    // make an identifier
	call prim_D      // -- id1 id0 @d  // get dict address
	call prim_fetch_from_addr_on_stack // id1 id0 d
	call prim_set_A  // -- id1 id0    // ...and set A
	call prim_store_inc   // -- id0 
	call prim_store_inc   // -- 
	call prim_H      // -- @h     // current heap address
	call prim_fetch_from_addr_on_stack  // -- h
	call prim_store_inc   // --       // store the code address
	add $4, RegA     // --       // unused cell
	mov RegA, var_D  // --       // save new dictionary address
	pop RegA
end

prim study_word
	// ( w -- )
	call prim_set_A
	_clear RegC
	movb (RegA), %cl
	inc RegA
end

prim fetch_byte
	_dup
	movzbl (RegA), ToS
end

prim fetch_byte_inc
	_dup
	movzbl (RegA), ToS
	inc RegA
end

prim fetch
	_push (RegA)
end

prim fetch_from_addr_on_stack
	// ( a -- n )
	mov (ToS), ToS
end

prim fetch_inc
	_push (RegA)
	_advance_cell RegA
end

prim store_byte
	movb %al, (RegA)
	_drop
end

prim store_byte_inc
	stosb
	_drop
end

prim store_alloc_byte
	call prim_store_byte_inc
	mov RegA, var_H
end

prim store
	movl ToS, (RegA)
	_drop
end

prim store_inc
	stosl
	_drop
end

prim store_to_addr_on_stack
	// ( n a -- )	
	movl NoS, RegB
	_nip
	mov RegB, (ToS)
	_drop
end

prim emit
	// uses real register names rather than macros because
	// register usage of this function is OS defined and 
	// will not change with different threading models
	push %ecx
	push ToS  // ...except here!
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
end

prim warn
	// ( id id -- )
	call prim_emit_id
	call prim_emit_id
	_push $'\n'
	call prim_emit
end

prim fail
	// ( id id -- )
	call prim_warn
	_push $1
	jmp prim_exit

prim bye
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
variable Z, heap      // addr of last instruction compiled

message not_found "Not a dictionary word or number: "
message number_parse_fail "Invalid number format: "
message welcome "Cantilever v0.0\n"
message tried_to_execute_a_literal "Tried to execute a non-function value: "
message failed_conditional "Conditional code block too long\n"


heap:
.space 1024

.align 8,0
dict:
entry "", _start
entry "dict",  prim_D
entry "here",  prim_H
entry "main",  prim_M
entry "prev",  prim_Z

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

// word suffixes
entry "__:",        prim_def
entry "__'",        prim_quote
entry "__#",        prim_exec

// data prefixes
entry "0x__",       prim_parse_hex

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
entry "if",       prim_if
entry "else",     prim_else
entry "endif",    prim_endif

// IO
entry ".",     prim_emit
entry ".h",    prim_emit_hex
entry ".id",   prim_emit_id

// Misc
entry "bye",      prim_bye
entry "exit",     prim_exit
entry "key",      prim_key
entry "word",     prim_word
entry "find",     prim_lookup_word
entry "apply",    prim_apply
entry "base",     prim_base

// legacy
entry "$",        prim_data
entry ",",        prim_store_alloc_byte
end_dict:





