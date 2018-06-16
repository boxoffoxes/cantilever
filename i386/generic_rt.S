#include <asm/unistd.h>
// #include <bits/socket.h>
#include <asm/mman.h>
// #include "inc/sys_defs.h"

# Warnings: be very careful about using push 
# and pop in non-Forth functions -- there's a
# return address on top of the stack!

# Useful values ######################################
.set HEAP_SIZE, 128*1024*1024  # 128 meg
.set SCRATCH_SIZE, 16*1024     # 16k
.set BUFFER_SIZE,  16*1024     #  4k
.set WORD_BUFFER_SIZE, 256
.set CELL_SHIFT, 2
.set CELL_SIZE, (1<<CELL_SHIFT)
.set DS_SIZE, (64*CELL_SIZE)
.set link, 0

.set BASE_4_YEAR, 1461
.set LILIAN_CORRECTION, 6345


#ifdef CANTILEVER_EXECUTION_TRACE
#define TRACE_CODE call _trace
#else
#define TRACE_CODE
#endif


######################################################
# macros                                             #
######################################################

#define JUMP(tgt) (tgt - .)
#define _DATA .long

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
	_DATA (100001f - 100000f - 1)
	100000:
	.ifeqs "\name", ""
		.asciz "\label"
	.else
		.asciz "\name"
	.endif
	100001:
	.align CELL_SIZE, 0
dict_\label:
	_DATA link
	_DATA dict_label_\label
	_DATA \behav
.set link, dict_\label
.endm

.macro prim label, name, behav=compiled
	header \label, "\name", \behav
\label:
	_DATA prim_\label
	.section .text
	.align CELL_SIZE
prim_\label:
	TRACE_CODE
.endm

.macro word label, name, behav=storeinc, handler=do
	header \label, "\name", \behav
\label:
	_DATA \handler
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
	_DATA \val
.endm

.macro string label, str, name
	constant \label, str_\label, "\name"
	.section .data
str_\label:
	_DATA (20001f - str_text_\label - 1)
str_text_\label:
	.asciz "\str"
	20001:
	.align CELL_SIZE, 0
.endm

# Code macros ########################################

.macro next
	lodsl
	jmp *(%eax)
	.align CELL_SIZE
.endm

.macro end
	_DATA return
.endm

.macro string_len_in_cells reg
	shr $CELL_SHIFT, \reg
	inc \reg
.endm

.macro pushrs reg
	lea -CELL_SIZE(%ebp), %ebp
	movl \reg, (%ebp)
.endm

.macro poprs, reg
	mov (%ebp), \reg
	lea CELL_SIZE(%ebp), %ebp
.endm

.macro align_dp
	add $(CELL_SIZE-1), %edi
	and $(~(CELL_SIZE-1)), %edi
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
	mov (%esp), %eax
	mov %eax, var_argc
	lea 4(%esp), %eax
	mov %eax, var_argv
	mov %eax, var_argv0
	push $0
	mov %esp, var_ds0
	mov %esp, %ebp
	sub $DS_SIZE, %ebp
	mov %ebp, var_rs0
	mov $cold_start, %esi
next

# Utility function ###################################

#ifdef CANTILEVER_EXECUTION_TRACE
_space_buffer:
	.space 128, ' '
.align CELL_SIZE
_trace:
	# print spaces based on return stack depth
	push %eax
	mov var_rs0, %edx
	mov $2, %ebx
	mov $__NR_write, %eax
	mov $_space_buffer, %ecx
	sub %ebp, %edx
	int $0x80
	# print function name
	mov (%esp), %eax
	mov (LFA_OFFS-CFA_OFFS)(%eax), %ecx
	mov (%ecx), %edx
	add $CELL_SIZE, %ecx
	mov $__NR_write, %eax
	int $0x80
	# print return char
	mov $__NR_write, %eax
	push $10
	mov %esp, %ecx
	mov $1, %edx
	int $0x80
	pop %ecx
	pop %eax
ret
#endif

# Wrappers for calling words from code ###############
.align CELL_SIZE
cold_start:
	_DATA initialiseVM

######################################################
# Forth-style code words                             #
######################################################

# codewords ##########################################

.align CELL_SIZE
do:
TRACE_CODE
	pushrs %esi  // save return address
	lea 4(%eax), %esi
next

.align CELL_SIZE
doconst:
	push 4(%eax)
TRACE_CODE
next

.align CELL_SIZE
dovar:
	lea 4(%eax), %edx
	push %edx
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
	pushrs %esi
	lea 8(%eax), %edx
	mov 4(%eax), %esi
	push %edx
next


######################################################
# Minimal system interface                           #
######################################################

prim qrx "?rx"  # -- b bool
	# 1: char waiting. 0: no char
	push $0
	mov $__NR_read, %eax
	mov var_inChannel, %ebx
	mov %esp, %ecx
	mov $1, %edx
	int $0x80
	test %eax, %eax
	ja 1f        # jump if no error, and not eof
	dec %eax
	mov %eax, (%esp) # otherwise return an unreasonable character value
1:	push $-1
next

prim tx "tx!"   # b --
	mov $__NR_write, %eax
	mov $1, %ebx
	mov %esp, %ecx
	mov $1, %edx
	int $0x80
	pop %eax
next



# IO prims ###########################################

# prims
prim syscall0  # id -- result
	pop %eax
	int $0x80
	push %eax
next
prim syscall1  # arg id -- result
	pop %eax
	pop %ebx
	int $0x80
	push %eax
next
prim syscall2  # arg2 arg1 id -- result
	pop %eax
	pop %ebx
	pop %ecx
	int $0x80
	push %eax
next
prim syscall3  # arg3 arg2 arg1 id -- result
	pop %eax
	pop %ebx
	pop %ecx
	pop %edx
	int $0x80
	push %eax
next

prim syscall6  # arg6 arg5 ... arg1 id -- result
	# This is slightly different because for >5 args
	# Linux expects args to be passed by pointer.
	# In this case we simply use the stack
	pop %eax
	mov %esp, %ebx
	int $0x80
	add $(6*CELL_SIZE), %esp
	push %eax
next


# System calls #######################################

# System call numbers
constant SysExit,  __NR_exit
constant SysRead,  __NR_read
constant SysWrite, __NR_write
constant SysOpen,  __NR_open
constant SysClose, __NR_close
constant SysStat,  __NR_fstat
constant SysMmap,  __NR_mmap
constant SysMunmap, __NR_munmap
constant SysBrk,   __NR_brk
constant SysIOCtl, __NR_ioctl
constant SysTime,  __NR_time
constant SysNanosleep, __NR_nanosleep


# basic IO
constant stdin,  0
constant stdout, 1
constant stderr, 2

variable inChannel, 0, "in-channel"
variable outChannel, 1, "out-channel"
variable errChannel, 2, "err-channel"

# NOTE: values are octal!
constant ReadOnly,   0
constant WriteOnly,  01101
constant ReadWrite,  02202

