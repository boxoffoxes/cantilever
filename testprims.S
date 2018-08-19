#define CANTILEVER_TEST_HARNESS

/* 
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

.macro variable label name value=0
	.section .data
	.align CELL_SIZE
\label:     .quad dovar
var_\label: .quad \value
.endm

.macro constant label name value
	.section .data
	.align CELL_SIZE
\label:     .quad doconst
var_\label: .quad \value
.endm
*/ 

#include "cantilever64.S"

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
	pushds $7
	pushds $-10
	pushds $10
	testprim between
	expect $-1
	check_stack
# eq
	pushds $10
	pushds $11
	testprim eq 1
	expect $0
	check_stack
	pushds $10
	pushds $10
	testprim eq 2
	expect $-1
	check_stack
# neq
# ge
# gt
# le
# lt
	pushds $10
	pushds $11
	testprim lt 1
	expect $-1
	check_stack
	pushds $10
	pushds $10
	testprim lt 2
	expect $0
	check_stack
	pushds $10
	pushds $9
	testprim lt 3
	expect $0
	check_stack

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
	pushds $17
	pushds $33
	testprim min 1
	expect $17
	check_stack
	pushds $17
	pushds $-33
	testprim min 2
	expect $-33
	check_stack
# max
	pushds $17
	pushds $33
	testprim max 1
	expect $33
	check_stack
	pushds $17
	pushds $-33
	testprim max 2
	expect $17
	check_stack
# umin
	pushds $17
	pushds $33
	testprim umin 1
	expect $17
	check_stack
	pushds $17
	pushds $-33
	testprim umin 2
	expect $17
	check_stack
# umax
	pushds $17
	pushds $33
	testprim umax 1
	expect $33
	check_stack
	pushds $17
	pushds $-33
	testprim umax 2
	expect $-33
	check_stack
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
	movq $999, testbuf
	pushds $testbuf
	testprim incVar
	cmpq $1000, testbuf
	jne fail
	check_stack
# decVar
	pushds $testbuf
	testprim decVar
	expect $testbuf
	cmpq $999, testbuf
	jne fail
	check_stack
# ipGet
	testprim ipGet 
	expect $(900b+8)
	check_stack
# get
	movq $-919, testbuf
	pushds $testbuf
	testprim get
	expect $-919
	check_stack
# getByte
	movb $0xf3, testbuf
	pushds $testbuf
	testprim getByte
	expect $0xf3
	check_stack
# getStep
# set
	pushds $-7721
	pushds $testbuf
	testprim set
	mov testbuf, %r10
	cmp $-7721, %r10
	check_stack
# setByte
	pushds $0x99
	pushds $testbuf
	testprim setByte
	cmpb $0x99, testbuf
	check_stack
# dpGet
	testprim dpGet
	expect %rdi
	check_stack
# dpSet
	pushds $testbuf
	testprim dpSet
	cmp $testbuf, %rdi
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
	pushds $0
	testprim align 0
	expect $0
	check_stack
	pushds $1
	testprim align 1
	expect $8
	check_stack
	pushds $7
	testprim align 2
	expect $8
	check_stack

# isAnonymous
# endcol
# return

.section .data
.align CELL_SIZE
test_data: .quad do, data,24, dec,dec,dec, swap,dec,endcol
.section .text
# data
	pushds $39
	testprim test_data
	expect $38
	expect $test_data+24
	check_stack


.section .data
.align CELL_SIZE
test_zbranch: .quad do, zbranch,16, dec, endcol
test_branch:  .quad do, branch,16, dec, inc, endcol
.section .text
# branch
	pushds $376
	testprim test_branch
	expect $377
 	check_stack
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


.section .data
.align CELL_SIZE
decrement:    .quad do, dec, endcol
test_call:    .quad do, quote,decrement, call, endcol
test_tail:    .quad do, tailcall,decrement, dec, endcol
test_tailtos: .quad do, quote,decrement, tailcallTOS, dec, endcol
.section .text
# tailcall
	pushds $77
	testprim test_tail
	expect $76
	check_stack
# tailcallTOS
	pushds $189
	testprim test_tailtos
	expect $188
	check_stack
# call
	# non-prim words
	pushds $0xabcdf
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

.section .data
.align CELL_SIZE
s1: .asciz "hello world"
s5: .quad -1, -1
.section .text
# copyBytes
	pushds $s1
	pushds $12
	pushds $s5
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

.section .data
.align CELL_SIZE
s2: .quad 1f-.
	.asciz "hello worlds"
1: .align CELL_SIZE
s3: .quad 2f-.
	.asciz "hello wolds"
2: .align CELL_SIZE
s4: .quad 3f-.
	.asciz "hello worl"
3: .align CELL_SIZE
.section .text
# strEq
	pushds $s2
	pushds $s3
	testprim strEq 1
	expect $0
	check_stack

	pushds $s2
	pushds $s4
	testprim strEq 2
	expect $0
	check_stack

	pushds $s2
	pushds $s2
	testprim strEq 3
	expect $-1
	check_stack
# lenz
	pushds $decimal1
	testprim lenz 1
	expect $15
	check_stack
	pushds $s1
	testprim lenz 2
	expect $11
	check_stack

.section .data
natural1: .asciz "1234"
negative: .asciz "-1234"
decimal1: .asciz "3.1415926535898"
charlit1: .asciz "'x'"
time1:    .asciz "00:10:01"
date1:    .asciz "2000-01-01"
.section .text
# znumber
	pushds $natural1
	testprim znumber 1
	expect $-1
	expect $1234
	check_stack

	pushds $negative
	testprim znumber 2
	expect $-1
	expect $-1234
	check_stack

	pushds $decimal1  # with zero decimal places
	testprim znumber 3
	expect $-1
	expect $3
	check_stack

	movq $2, var_decimal_places
	pushds $decimal1
	testprim znumber 4
	expect $-1
	expect $314
	check_stack

	movq $15, var_decimal_places
	pushds $decimal1
	testprim znumber 5
	expect $-1
	mov $3141592653589800, %r10
	expect %r10
	check_stack

	pushds $charlit1
	testprim znumber 6
	expect $-1
	expect $'x'
	check_stack

	pushds $time1
	testprim znumber 7
	expect $-1
	expect $601
	check_stack

	pushds $date1
	testprim znumber 8
	expect $-1
	expect $152383
	check_stack

.section .data
list: .quad (.+8), (.+8), (.+8), (.+8), (.+8), (.+8), 0
.section .text
# length
	pushds $list
	testprim length
	expect $6
	check_stack

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
test_consume:
	.quad do, quote, 0x0f0f0f, return
rpt:
	# .quad do, repeat,inc, return

.lcomm vrbl CELL_SIZE
.lcomm testbuf 4096

