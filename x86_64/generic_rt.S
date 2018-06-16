#ifdef __LINUX__
#include <asm/unistd.h>
// #include <bits/socket.h>
#include <asm/mman.h>
// #include "inc/sys_defs.h"
#endif
#ifdef __OpenBSD__
#include <sys/syscall.h>
.section ".note.openbsd.ident", "a"
        .p2align 2
        .long   8
        .long   4
        .long   1
        .ascii "OpenBSD\0"
        .long   0
        .p2align 2

#endif

# Warnings: be very careful about using push 
# and pop in non-Forth functions -- there's a
# return address on top of the stack!

# Useful values ######################################
.set HEAP_SIZE, 128*1024*1024  # 128 meg
.set SCRATCH_SIZE, 16*1024     # 16k
.set BUFFER_SIZE,  16*1024     #  4k
.set WORD_BUFFER_SIZE, 256
.set CELL_SHIFT, 3
.set CELL_SIZE, (1<<CELL_SHIFT)
.set DS_SIZE, (64*CELL_SIZE)
.set link, 0

.set BASE_4_YEAR, 1461
.set LILIAN_CORRECTION, 6345

// #define CANTILEVER_COMPILATION_TRACE
#define CANTILEVER_EXECUTION_TRACE
// #define CANTILEVER_STACK_TRACE
// #define CANTILEVER_CHEAP_DATE


#ifdef CANTILEVER_EXECUTION_TRACE
#define TRACE_CODE call _trace
#else
#define TRACE_CODE
#endif


######################################################
# macros                                             #
######################################################

#define JUMP(tgt) (tgt - .)

# Structural macros ##################################

# proposed alternative dictionary format 
#   ...optional fields | &next | &label | &behav | xt ...
#                              ^ prev next-ptr

.set DFA_OFFS, (0*CELL_SIZE)  # -1*CELL_SIZE
.set LFA_OFFS, (1*CELL_SIZE)  # 0
.set BFA_OFFS, (2*CELL_SIZE)  # 1*CELL_SIZE
.set CFA_OFFS, (3*CELL_SIZE)  # 2*CELL_SIZE
.set PFA_OFFS, (4*CELL_SIZE)  # 3*CELL_SIZE

.macro header label, name, behav
	.section .data
	.align CELL_SIZE, 0
dict_label_\label:
	.long (100001f - 100000f - 1)
	100000:
	.ifeqs "\name", ""
		.asciz "\label"
	.else
		.asciz "\name"
	.endif
	100001:
	.align CELL_SIZE, 0
dict_\label:
	.long link
	.long dict_label_\label
	.long \behav
.set link, dict_\label
.endm

.macro prim label, name, behav=compiled
	header \label, "\name", \behav
\label:
	.long prim_\label
	.section .text
	.align CELL_SIZE
prim_\label:
	TRACE_CODE
.endm

.macro word label, name, behav=storeinc, handler=do
	header \label, "\name", \behav
\label:
	.long \handler
word_\label:
.endm

.macro constant label, val, name
	word \label, "\name", , doconst
	# push $\val
	# next
	.int \val
.endm

.macro literal label, val
	constant \label, \val, "\val"
.endm

.macro variable label, val=0, name
	word \label, "\name", , dovar
var_\label:
	.long \val
.endm

.macro string label, str, name
	constant \label, str_\label, "\name"
	.section .data
str_\label:
	.long (20001f - str_text_\label - 1)
str_text_\label:
	.asciz "\str"
	20001:
	.align CELL_SIZE, 0
.endm

# Code macros ########################################

.macro next
	lodsq
	jmp *(%rax)
	.align CELL_SIZE
.endm

.macro end
	.long return
.endm

.macro string_len_in_cells reg
	shr $CELL_SHIFT, \reg
	inc \reg
.endm

.macro pushrs reg
	lea -CELL_SIZE(%rbp), %rbp
	mov \reg, (%rbp)
.endm

.macro poprs, reg
	mov (%rbp), \reg
	lea CELL_SIZE(%rbp), %rbp
.endm

.macro align_dp
	add $(CELL_SIZE-1), %rdi
	and $(~(CELL_SIZE-1)), %rdi
.endm

.macro times_ten reg
	shl $1, \reg
	lea (\reg, \reg, 4), \reg
.endm
.macro times_60 reg
	shl $2, \reg
	lea (\reg, \reg, 4), \reg
	lea (\reg, \reg, 2), \reg
.endm

.macro digit from, to, err
	movb \from, \to
	sub $'0', \to
	cmp $9, \to
	ja \err
.endm

######################################################
# Non-forth-style functions                          #
######################################################

# Initialisation #####################################

.section .data
constant HeapBaseAddr . "heap-base-addr"
constant HeapSize HEAP_SIZE "heap-size"

constant ScratchSize SCRATCH_SIZE "scratch-size"
constant BufferSize BUFFER_SIZE "buffer-size"

constant LfaOffs LFA_OFFS
constant CfaOffs CFA_OFFS
constant BfaOffs BFA_OFFS
constant PfaOffs PFA_OFFS


.section .text

.globl _start
.align CELL_SIZE
_start:
	cld
	mov (%rsp), %rax
	mov %rax, var_argc
	lea CELL_SIZE(%rsp), %rax
	mov %rax, var_argv
	mov %rax, var_argv0
	push $0
	mov %rsp, var_ds0
	mov %rsp, %rbp
	sub $DS_SIZE, %rbp
	mov %rbp, var_rs0
	mov $cold_start, %rsi
next

# Utility function ###################################

#ifdef CANTILEVER_EXECUTION_TRACE
_space_buffer:
	.space 128, ' '
.align CELL_SIZE
_trace:
	# print spaces based on return stack depth
	push %rax
	mov var_rs0, %rdx
	mov $2, %rbx
	mov $__NR_write, %rax
	mov $_space_buffer, %rcx
	sub %rbp, %rdx
	int $0x80
	# print function name
	mov (%rsp), %rax
	mov (LFA_OFFS-CFA_OFFS)(%rax), %rcx
	mov (%rcx), %rdx
	add $CELL_SIZE, %rcx
	mov $__NR_write, %rax
	int $0x80
	# print return char
	mov $__NR_write, %rax
	push $10
	mov %rsp, %rcx
	mov $1, %rdx
	int $0x80
	pop %rcx
	pop %rax
ret
#endif

# Wrappers for calling words from code ###############
.align CELL_SIZE
cold_start:
	.long initialiseVM

######################################################
# Forth-style code words                             #
######################################################

# codewords ##########################################

.align CELL_SIZE
do:
TRACE_CODE
	pushrs %rsi  // save return address
	lea CELL_SIZE(%rax), %rsi
next

.align CELL_SIZE
doconst:
	push CELL_SIZE(%rax)
TRACE_CODE
next

.align CELL_SIZE
dovar:
	lea CELL_SIZE(%rax), %rdx
	push %rdx
TRACE_CODE
next


# The black-magic of forth: data with behaviour.
# 
# ... | dodoes | ptr | data ... | behav
#                  \______________7
#
#
.align CELL_SIZE
dodoes:
	pushrs %rsi
	lea (2*CELL_SIZE)(%rax), %rdx
	mov CELL_SIZE(%rax), %rsi
	push %rdx
next


