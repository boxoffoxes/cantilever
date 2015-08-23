#include <asm/unistd.h>
#include <asm/mman.h>

.set HEAP_SIZE, 128*1024*1024  # 128 meg

.set CELL_BITS, 2
.set CELL_SIZE, (1<<CELL_BITS)
.set DS_SIZE, (64*CELL_SIZE)

.set link, 0

#################################################
# Macros
#################################################

# Structural macros #########################
.macro header label, name, dict
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
	.set \dict, dict_\label
.endm

.macro prim label, name, dict=link
	header \label "\name", \dict
	\label:
	.long prim_\label
	.section .text
	.align CELL_SIZE
	prim_\label:
.endm

.macro word label, name, dict=link, handler=do
	header \label "\name", \dict
	\label:
	.long \handler
	word_\label:
.endm

.macro constant label, val, name
	word \label, "\name", , doconst
	.int \val
.endm

.macro end
	.long done
.endm

# Code macros ###############################
.macro next
	lodsl
	jmp *(%eax)
	.align CELL_SIZE
.endm
.macro pushrs reg
	lea -CELL_SIZE(%ebp), %ebp
	mov \reg, (%ebp)
.endm
.macro poprs, reg
	mov (%ebp), \reg
	lea CELL_SIZE(%ebp), %ebp
.endm


#################################################
# Regular functions
#################################################

.section .data
constant heap_base_addr . "heap-base-addr"

.text
.globl _start
.align CELL_SIZE
_start: 
	cld
	# argc
	mov (%esp), %eax
	mov %eax, var_argc
	# argv
	lea 4(%esp), %eax
	mov %eax, var_argv
	# data stack
	push $0
	mov %esp, var_ds0
	# return stack
	mov %esp, %ebp
	sub $DS_SIZE, %ebp	
	mov %ebp, var_rs0
	# hand over control to the runtime
	mov $cold_start, %esi
next

# Codewords #################################
.align CELL_SIZE
do:
	pushrs %esi
	lea CELL_SIZE(%eax), %esi
next

.align CELL_SIZE
doconst:
	push CELL_SIZE(%eax)
next


# Wrapper for calling words from code #######
.align CELL_SIZE
cold_start:
	.long initialise_vm, reset

#################################################
# Primitive words
#################################################

prim done, "]"
	poprs %esi
next

# Numeric literals ##########################
prim lit
	lodsl
	push %eax
next
prim zero "0"
	push $0
next

# VM Registers ##############################
prim dp_set, "dp!"
	pop %edi
next

# System calls ##############################

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

# Arithmetic ################################
prim add, "+"
	pop %eax
	add %eax, (%esp)
next

# Stack manipulation ########################
prim drop
	pop %eax
next


#################################################
# High-level words
#################################################
.data

# Starting and exiting VM ###################
word initialise_vm
	# initialise the dictionary pointer
	.long get_brk_addr, dp_set
	# allocate default heap
	.long lit, HEAP_SIZE, set_heap_size
	# create input buffer
	# create scratchpad
	# create anon code area
	.long zero_exit
end

word zero_exit, "0-exit"
	.long zero, exit
end

word exit
	.long SysExit, syscall1
end

word reset
end


# Memory management #########################
word set_brk_addr "set-brk-addr"  # addr -- addr
	.long SysBrk, syscall1
end

word get_brk_addr, "get-brk-addr"  #  -- addr
	.long zero, set_brk_addr
end

word set_heap_size, "set-heap-size" # n --
	.long heap_base_addr, add, set_brk_addr, drop
end

#################################################
# Variables
#################################################

.data
.align CELL_SIZE
var_argc:
	.long 0
var_argv:
	.long 0
var_ds0:
	.long 0
var_rs0:
	.long 0
