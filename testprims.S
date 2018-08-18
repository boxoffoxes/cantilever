#include <sys/syscall.h>

.set CELL_BITS, 3
.set CELL_SIZE, (1<<CELL_BITS)
.set DS_SIZE, 4096


.section ".note.openbsd.ident", "a"
        .p2align 2
        .long   8
        .long   4
        .long   1
        .ascii "OpenBSD\0"
        .long   0
        .p2align 2
.section .text


.macro prim label name
.section .data
	.align CELL_SIZE
\label: .quad prim_\label
.section .text
	.align CELL_SIZE
prim_\label:
.globl \label
.endm

.macro word label name ii=do
.section .data
	.align CELL_SIZE
\label: .quad \ii
.endm

.macro variable label name
	.section .data
	.align CELL_SIZE
\label: .quad dovar
var_\label: .quad 0
.endm

#include "prims64.S"

.macro testprim word
	# must not change CPU flags
testing_\word:
	lea 1(%r15), %r15  # increment test number
	mov $900f, %rsi
	next
.align CELL_SIZE
900: .quad \word, (.+8)
	.quad (.+8)
.endm

.macro expect n
	cmp \n, %rbx
	jne fail
	pop %rbx
.endm

.macro check_stack
	cmp ds0, %rsp
	jne stackfail
	cmp $0xd50d50, %rbx
	jne stackfail
.endm

.macro pushds val
	push %rbx
	mov \val, %rbx
.endm

.section .text
.align CELL_SIZE
cold_start:
	.quad start_of_tests, 0

start_of_tests:
	.quad (.+8)

# dup
	pushds $0xbbbbb
	testprim dup
	expect $0xbbbbb
	expect $0xbbbbb
	check_stack
/*
# drop
	pushds $-17
	pushds $99
	testprim drop
	expect $-17
	check_stack 
# nip
	pushds $-19
	pushds $77
	testprim nip
	expect $77
	check_stack
# swap
	pushds $33
	pushds $-44
	testprim swap
	expect $33
	expect $-44
	check_stack
# pick
	pushds $50
	pushds $40
	pushds $30
	pushds $20
	pushds $10
	pushds $0

	pushds $5
	testprim pick
	expect $50

	pushds $4
	testprim pick
	expect $40

	pushds $0
	testprim pick
	expect $0

	expect $0
	expect $10
	expect $20
	expect $30
	expect $40
	expect $50

	check_stack

## getip
#	testprim getip
#	expect $900b
#	check_stack
# setip   # if setip didn't work, nothing would -- it's used in does_colon
#	pushds $test_setip
#	testprim setip
#	expect $0x9a9a9a  # pushed by test__setip
#	check_stack
# _getdsp
	pushds $0
	testprim _getdsp
	expect %rsp
	jne fail
	check_stack
# _setdsp
	pushds $99    # stack should be cleared by _setdsp
	pushds $100
	pushds $101
	pushds ds0
	testprim _setdsp
	check_stack
# _settmp
# _gettmp
	pushds $test_call
	testprim _sett
	mov $0, %rbx
	testprim _gett
	expect $test_call
	check_stack
# clrt
	mov $-38, %rdx
	testprim clrt
	cmp $0, %rdx
	jne fail
	check_stack
# _getd
	pushds $-178
	testprim _getd
	expect %rdi
	check_stack
# _setd
	pushds $buffer
	testprim _setd
	expect $buffer
	cmp $buffer, %rdi
	jne fail
	check_stack
# alignd
	mov %rdi, %r10
	mov $0xf9, %rdi
	testprim alignd      # check that misaligned DP is aligned
	cmp $0x100, %rdi
	testprim alignd      # check that already-aligned DP is not changed
	cmp $0x100, %rdi
	jne fail
	mov %r10, %rdi
	check_stack
# xdtos
	mov %rdi, %r10
	pushds $0
	testprim xdtos
	expect %r10
	mov %r10, %rdi
	check_stack
# _comma
	lea CELL_SIZE(%rdi), %r10
	pushds $-919
	testprim _comma
	expect $-919
	cmp %rdi, %r10
	jne fail
	check_stack
# _comma4
	lea 4(%rdi), %r10
	pushds $920
	testprim _comma4
	expect $920
	cmp %rdi, %r10
	jne fail
	check_stack
# _comma2
	lea 2(%rdi), %r10
	pushds $921
	testprim _comma2
	expect $921
	cmp %rdi, %r10
	jne fail
	check_stack
# _commab
	lea 1(%rdi), %r10
	pushds $22
	testprim _commab
	expect $22
	cmp %rdi, %r10
	jne fail
	check_stack
# _gets and _sets
	pushds $10101
	testprim _sets
	expect $10101
	cmp $10101, %rsi
	jne fail
	pushds $0
	testprim _gets
	expect $10101
	check_stack
# xstos
	pushds $0
	testprim xstos
	expect $10101
	cmp $0, %rsi
	jne fail
	check_stack
# xsd
	mov %rsi, %r10
	mov %rdi, %r11
	testprim xsd
	cmp %r10, %rdi
	jne fail
	cmp %r11, %rsi
	jne fail
	check_stack
# _getrsp
	pushds $0
	testprim _getrsp
	expect %rbp
	check_stack
# _setrsp
# push
	pushds $0xdead0
	testprim push
	check_stack
# pop
	testprim pop
	expect $0xdead0
	check_stack
# stash
	pushds $0xbeef1
	testprim stash
	expect $0xbeef1
	check_stack
# peek
	testprim peek
	expect $0xbeef1
	check_stack
# trash
	testprim trash
	cmp %rbp, rs0
	jne fail
	check_stack
# fetch
	pushds $buffer
	testprim fetch
	expect $-919
	check_stack
# _store
	pushds $-7721
	pushds $buffer
	testprim _store
	expect $buffer
	mov buffer, %r10
	cmp $-7721, %r10
	check_stack
# fetchb
	pushds $buffer+CELL_SIZE+4+2
	testprim fetchb
	expect $22
	check_stack
# _storeb
	pushds $0x99
	pushds $buffer
	testprim _storeb
	expect $buffer
	cmpb $0x99, buffer
	check_stack
# _setc
	pushds $765
	testprim _setc
	expect $765
	check_stack
# _getc
	pushds $0
	testprim _getc
	expect $765
	check_stack
# clrc
	testprim clrc
	cmp $0, %rcx
	jne fail
	check_stack
# _nxt  we're pretty sure next works by now!
#	testprim _nxt 
# _lit32  # _lit32 is just a placeholder for inlining literals
	pushds $0
	testprim _lit32
	expect $-1
	check_stack
# _lit  # _lit32 is just a placeholder for inlining literals
	pushds $-1
	testprim _lit
	expect $0
	check_stack
# _zero   # _zero uses xor to zoro ToS: optimisation for x86
	pushds $-1
	testprim _zero
	expect $0
	check_stack
# inc
	pushds $-883
	testprim inc
	expect $-882
	check_stack
# dec
	pushds $663
	testprim dec
	expect $662
	check_stack
# adv
	pushds $19
	testprim adv
	expect $27
	check_stack
# adv4
	pushds $190
	testprim adv4
	expect $194
	check_stack
# adv2
	pushds $1
	testprim adv2
	expect $3
	check_stack
# _add
	pushds $112
	pushds $15
	testprim _add
	expect $127
	expect $112
	check_stack
# _sub
	pushds $112
	pushds $15
	testprim _sub
	expect $15
	expect $97
	check_stack
# neg
	pushds $47
	testprim neg
	expect $-47
	check_stack
# not
	pushds $55
	testprim not
	expect $-56
	check_stack
# _or
	pushds $0xaaaaaaaaaaaaaaaa
	mov %rbx, %r10
	pushds $0x5555555555555554
	mov %rbx, %r13   # save for _xor later!
	testprim _or
	expect $-2
	expect %r10
	check_stack
# _and
	pushds $0xff0
	pushds $0x07f
	testprim _and
	expect $0x070
	expect $0xff0
	check_stack
# _xor
	pushds $0xaaaaaaaaaaaaaaaa
	mov %rbx, %r10
	pushds $-2
	testprim _xor
	expect %r13  # saved from _or above
	expect %r10
	check_stack
# _shl
	pushds $0x101
	mov $3, %rcx
	testprim _shl
	expect $0x808
	check_stack
# _shr
	pushds $-1
	mov $60, %rcx
	testprim _shr
	expect $15
	check_stack
# _sar
	# sign extension, with negative
	pushds $-1
	mov $60, %rcx
	testprim _sar
	expect $-1
	check_stack
	# ...and for a positive
	pushds $0x804
	mov $3, %rcx
	testprim _sar
	expect $0x100
	check_stack
# _incv
	pushds $vrbl
	testprim _incv
	expect $vrbl
	cmpq $1, vrbl
	jne fail
	check_stack
# _decv
	pushds $vrbl
	testprim _decv
	expect $vrbl
	cmpq $0, vrbl
	jne fail
	check_stack
# _cmp
# _jmpl
# _jmps
# _jtbl
# _sex
	# _sex positive
	pushds $9999
	testprim _sex
	expect $9999
	cmp $0, %rdx
	jne fail
	# _sex negative
	pushds $-9999
	testprim _sex
	expect $-9999
	cmp $-1, %rdx
	jne fail
	check_stack
# _mul
	pushds $17
	pushds $38
	testprim _mul
	expect $646
	expect $17
	cmp $0, %rdx
	jne fail
	pushds $-333
	pushds $3
	testprim _mul
	expect $-999
	expect $-333
	cmp $-1, %rdx
	jne fail
	check_stack
# _umul
	pushds $2
	pushds $-1 # no sign extend!
	testprim _umul
	expect $-2
	expect $2
	cmp $1, %rdx  # we've doubled ((ulong) -1), so only high bit is here
	jne fail
	check_stack
# _div
	pushds $2   # divsor. Opposite to what you might expect
	pushds $-11
	cqo
	testprim _div
	expect $-5
	expect $2
	cmp $-1, %rdx  # the remainder
	jne fail
	check_stack
# _udiv
	pushds $2   # divsor. Opposite to what you might expect
	pushds $11
	xor %rdx, %rdx  # clear the high 64 bits!
	testprim _udiv
	expect $5
	expect $2
	cmp $1, %rdx  # the remainder
	jne fail
	check_stack
# double
	pushds $-13
	testprim double
	expect $-26
	check_stack
# cells
	pushds $5
	testprim cells
	expect $(5*CELL_SIZE)
	check_stack
# ifzero
	# testprim ifzero
	pushds $53
	pushds $0
	testprim test_ifzero
	expect $54

	pushds $53
	pushds $8
	testprim test_ifzero
	expect $53

	pushds $53
	pushds $-1
	testprim test_ifzero
	expect $53
	check_stack
# ifneg
	# testprim ifneg
	pushds $53
	pushds $0
	testprim test_ifneg
	expect $53

	pushds $53
	pushds $8
	testprim test_ifneg
	expect $53

	pushds $53
	pushds $-17
	testprim test_ifneg
	expect $52

# consume
	# testprim consume
	# testprim return
	testprim test_consume
	expect $0x0f0f0f
# call
	# non-prim words
	pushds $test_call
	testprim call
	expect $0xabcde
	check_stack
	# prim words
	pushds $500
	pushds $55
	pushds $_add
	testprim call
	expect $555
	expect $500
	check_stack
# syscall is tested at the very end, when we quit with no error...
# _scan
	
# _scanb
	pushds $'w'
	mov $s1, %rdi
	mov $12, %rcx
	testprim _scanb
	expect $'w'
	cmp $(s1+7), %rdi
	jne fail
	cmp $5, %rcx
	jne fail
	check_stack
# _cpyb
	mov $s5, %rdi
	mov $s1, %rsi
	mov $12, %rcx
	testprim _cpyb
	cmpb $'h', s5
	jne fail
	cmpb $'d', s5+10
	jne fail
	cmpb $0, s5+11
	jne fail
	check_stack
# _cpy
# _cmpb and _cmpeq
	pushds $0
	mov $s1, %rsi
	mov $s4, %rdi
	mov $(s5-s4), %rcx
	testprim _cmpmb
	je fail
	testprim _cmpeq
	expect $0

	pushds $0
	mov $s1, %rsi
	mov $s2, %rdi
	mov $(s2-s1), %rcx
	testprim _cmpmb
	je fail
	testprim _cmpeq
	expect $0

	pushds $0
	mov $s1, %rsi
	mov $s1, %rdi
	mov $(s2-s1), %rcx
	testprim _cmpmb
	testprim _cmpeq
	expect $1
	check_stack
# jtnorm
	pushds $17
	pushds $10
	pushds $18
	testprim jtnorm
	expect $7

	pushds $-1
	pushds $10
	pushds $18
	testprim jtnorm
	expect $8

	pushds $1
	pushds $-10
	pushds $0
	testprim jtnorm
	expect $10

	check_stack
# repeat
	pushds $0
	mov $17, %rcx
	testprim rpt
	expect $17
	cmp $0, %rcx
	jne fail
	check_stack
	

*/
end_of_tests:
	pushds $0
	pushds $SYS_exit
	pushds $1
	testprim syscall1
	# fallthrough on failure

stackfail:
	
	
fail:
	mov %r15, %rdi
	mov $SYS_exit, %rax
	syscall
	
test_ifneg:
	# .quad do, ifneg,dec, return
test_efzero:
	# .quad do, ifzero,inc, return
test_call:
	.quad do, quote, 0xabcde, return
test_consume:
	.quad do, quote, 0x0f0f0f, return
rpt:
	# .quad do, repeat,inc, return

.section .data
s1: .asciz "hello world"
s2: .asciz "hello worlds"
s3: .asciz "hello wolds"
s4: .asciz "hello worl"
s5: .quad -1, -1

.lcomm vrbl CELL_SIZE
.lcomm buffer 4096
