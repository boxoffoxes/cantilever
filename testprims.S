#include <sys/syscall.h>

.set CELL_BITS, 3
.set CELL_SIZE, (1<<CELL_BITS)
.set DS_SIZE, 4096

#ifdef __OpenBSD__
.section ".note.openbsd.ident", "a"
        .p2align 2
        .long   8
        .long   4
        .long   1
        .ascii "OpenBSD\0"
        .long   0
        .p2align 2
.section .text
#endif

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
\label:     .quad dovar
var_\label: .quad 0
.endm

#include "prims64.S"

.macro testprim word n
	# must not change CPU flags
testing_\word\n:
	lea 1(%r15), %r15  # increment test number
	mov $900f, %rsi
	next
	nop
.align CELL_SIZE
900: .quad \word, (.+8)
	.quad (.+8)
	nop
.endm

.macro expect n
	cmp \n, %rbx
	jne fail
	pop %rbx
.endm

.macro check_stack
	cmp var_ds0, %rsp
	jne stackfail
	cmp $0xd50d50, %rbx
	jne sentinelfail
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

# syscall0
# syscall1
# syscall2
# syscall3
# syscall6
# key
# word
# match
# between
# eq
# neq
# ge
# gt
# le
# lt
# and
	pushds $0xff0
	pushds $0x07f
	testprim and
	expect $0x070
	check_stack
# or
	pushds $0xaaaaaaaaaaaaaaaa
	mov %rbx, %r10
	pushds $0x5555555555555554
	mov %rbx, %r13   # save for _xor later!
	testprim or
	expect $-2
	check_stack
# xor
	pushds $0xaaaaaaaaaaaaaaaa
	mov %rbx, %r10
	pushds $-2
	testprim xor
	expect %r13  # saved from _or above
	check_stack
# not
	pushds $55
	testprim not
	expect $-56
	check_stack
# bool
# lshift
	pushds $0x101
	pushds $3
	testprim lshift
	expect $0x808
	check_stack
# rshift
	# sign extension, with negative
	pushds $-1
	pushds $60
	testprim rshift 1
	expect $-1
	check_stack
	# ...and for a positive
	pushds $0x804
	pushds $3
	testprim rshift 2
	expect $0x100
	check_stack
# mul
	pushds $17
	pushds $38
	testprim mul 1
	expect $646
	cmp $0, %rdx
	jne fail
	pushds $-333
	pushds $3
	testprim mul 2
	expect $-999
	cmp $-1, %rdx
	jne fail
	check_stack
# mulDiv
# udivmod
	pushds $-1
	pushds $(1<<32)
	testprim udivmod 1
	mov $0xffffffff, %r10
	expect %r10
	expect %r10
	check_stack
	pushds $11
	pushds $2
	testprim udivmod 2
	expect $1  # the remainder
	expect $5
	jne fail
	check_stack
# divmod
	pushds $-11
	pushds $2
	testprim divmod
	expect $-1
	expect $-5
	jne fail
	check_stack
# sub
	pushds $112
	pushds $15
	testprim sub
	expect $97
	check_stack
# add
	pushds $112
	pushds $15
	testprim add
	expect $127
	check_stack
# neg
	pushds $47
	testprim neg
	expect $-47
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
# double
	pushds $-13
	testprim double
	expect $-26
	check_stack
# min
# max
# umin
# umax
# sumCells
# dspGet
	testprim dspGet
	expect %rsp
	check_stack
# dspSet
	pushds $99    # stack should be cleared by _setdsp
	pushds $100
	pushds $101
	pushds var_ds0
	testprim dspSet  # doing this loses the sentinel in %rbx
	check_stack
# dsDepth
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
# dup
	pushds $0xbbbbb
	testprim dup
	expect $0xbbbbb
	expect $0xbbbbb
	check_stack
# over
# rspGet
	testprim rspGet
	expect %rbp
	check_stack
# rspSet
# rsDepth
# push & pop
	pushds $0xdead0
	testprim push
	check_stack
	testprim pop
	expect $0xdead0
	check_stack
# stash peek and trash
	pushds $0xbeef1
	testprim stash
	expect $0xbeef1
	check_stack
	testprim peek
	expect $0xbeef1
	check_stack
	testprim trash
	cmp %rbp, var_rs0
	jne fail
	check_stack
# wlen
# frame
# unframe
# local
# locals
# incVar
	movq $999, buffer
	pushds $buffer
	testprim incVar
	cmpq $1000, buffer
	jne fail
	check_stack
# decVar
	pushds $buffer
	testprim decVar
	expect $buffer
	cmpq $999, buffer
	jne fail
	check_stack
# ipGet
	testprim ipGet 
	expect $(900b+8)
	check_stack
# get
	movq $-919, buffer
	pushds $buffer
	testprim get
	expect $-919
	check_stack
# getByte
	movb $0xf3, buffer
	pushds $buffer
	testprim getByte
	expect $0xf3
	check_stack
# getStep
# set
	pushds $-7721
	pushds $buffer
	testprim set
	mov buffer, %r10
	cmp $-7721, %r10
	check_stack
# setByte
	pushds $0x99
	pushds $buffer
	testprim setByte
	cmpb $0x99, buffer
	check_stack
# dpGet
	testprim dpGet
	expect %rdi
	check_stack
# dpSet
	pushds $buffer
	testprim dpSet
	cmp $buffer, %rdi
	jne fail
	check_stack
# here
	testprim here
	expect %rdi
	check_stack
# dpAlign
	mov %rdi, %r10
	mov $0xf9, %rdi
	testprim dpAlign 1     # check that misaligned DP is aligned
	cmp $0x100, %rdi
	jne fail
	testprim dpAlign 2     # check that already-aligned DP is not changed
	cmp $0x100, %rdi
	jne fail
	mov %r10, %rdi     # restore original DP
	check_stack
# storeinc
	lea CELL_SIZE(%rdi), %r10
	pushds $-919
	testprim storeinc
	cmp %rdi, %r10
	jne fail
	mov -CELL_SIZE(%rdi), %rax
	cmp $-919, %rax
	jne fail
	check_stack
# storebinc
	lea 1(%rdi), %r10
	pushds $22
	testprim storebinc
	cmp %rdi, %r10
	jne fail
	movb -1(%rdi), %al
	cmpb $22, %al
	check_stack
# cell
	pushds $5
	testprim cell
	expect $(5*CELL_SIZE)
	check_stack
# align
# isAnonymous
# endcol
# return
# data
.section .data
.align CELL_SIZE
test_zbranch: .quad do, zbranch,16, dec, return
.section .text
# branch
# zbranch
	pushds $53
	pushds $0
	testprim test_zbranch 1
	expect $53
	check_stack

	pushds $53
	pushds $8
	testprim test_zbranch 2
	expect $52
	check_stack

	pushds $53
	pushds $-1
	testprim test_zbranch 3
	expect $52
	check_stack
# tailcall
# tailcallTOS
# call
	# non-prim words
	pushds $test_call
	testprim call 1
	expect $0xabcde
	check_stack
	# prim words
	pushds $500
	pushds $55
	pushds $add
	testprim call 2
	expect $555
	check_stack
# inline
# lit
.section .data
.align CELL_SIZE
test_literal: .quad do, lit,0x775, return
test_quote:   .quad do, quote,cold_start, return
.section .text
	testprim test_literal
	expect $0x775
	check_stack
# quote
	testprim test_quote
	expect $cold_start
	check_stack
# copyBytes
	push $s1
	push $12
	push $s5
	testprim copyBytes
	cmpb $'h', s5
	jne fail
	cmpb $'d', s5+10
	jne fail
	cmpb $0, s5+11
	jne fail
	check_stack
# copy
# keep
# forget
# strEq
# lenz
# znumber
# length


/*
# _nxt  we're pretty sure next works by now!
#	testprim _nxt 
# _shr
	pushds $-1
	mov $60, %rcx
	testprim _shr
	expect $15
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
	testprim syscall1
	# fallthrough on failure

fail:
	mov %r15, %rdi
	mov $SYS_exit, %rax
	syscall
	
sentinelfail:
	xor %r14, %r14
	movq $0, (%r14)
	
stackfail:
	xor %r14, %r14
	movq $0, (%r14)
	
	
test_ifzero:
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

