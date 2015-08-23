#include <asm/unistd.h>
#include <asm/mman.h>

.set HEAP_SIZE, 128*1024*1024  # 128M
.set SCRATCH_SIZE, 16*1024     # 16k
.set CELL_BITS, 2
.set CELL_SIZE, (1<<CELL_BITS)
.set DS_SIZE, (64*CELL_SIZE)

.set link, 0

#################################################
# Macros
#################################################


#define JUMP(tgt) (tgt - .)

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
.macro variable label, val=0, name
	constant \label, var_\label, "\name"
	var_\label:
	.long \val
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
	lea CELL_SIZE(%esp), %eax
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
prim minus_one "-1"
	push $-1
next
prim zero "0"
	push $0
next
prim one "1"
	push $1
next
prim cell
	shll $CELL_BITS, (%esp)
next

# VM Registers ##############################
prim dp_set, "dp!"
	pop %edi
next
prim dsp, "dsp@"
	push %esp
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
prim inc, "1+"
	incl (%esp)
next
prim dec, "1-"
	decl (%esp)
next
prim add, "+"
	pop %eax
	add %eax, (%esp)
next
prim udivmod  # int int -- int int
	pop %ebx
	pop %eax
	// cdq  // sign-extend %eax into %edx
	divl %ebx
	push %eax
	push %edx
next
prim divmod  # int int -- int int
	pop %ebx
	pop %eax
	cdq  // sign-extend %eax into %edx
	idivl %ebx
	push %eax
	push %edx
next


# Bitwise ops ###############################
prim or
	pop %eax
	or %eax, (%esp)
next
prim and
	pop %eax
	and %eax, (%esp)
next


# Logical ops ###############################
prim eq, "eq?" // a b -- bool
	pop %eax
	pop %edx
	xor %ecx, %ecx
	cmpl %eax, %edx
	setne %cl
	dec %ecx
	push %ecx
next
prim le, "or-less?"
	pop %eax
	pop %edx
	xor %ecx, %ecx
	cmpl %eax, %edx
	setg %cl
	dec %ecx
	push %ecx
next
prim ge, "or-more?"
	pop %eax
	pop %edx
	xor %ecx, %ecx
	cmpl %eax, %edx
	setl %cl
	dec %ecx
	push %ecx
next



# Stack manipulation ########################
prim dup
	push (%esp)
next
prim drop
	pop %eax
next
prim swap
	pop %eax
	pop %edx
	push %eax
	push %edx
next
prim nip
	pop %eax
	pop %edx
	push %eax
next

# Return stack ##############################
prim push
	pop %eax
	pushrs %eax
next
prim pop
	poprs %eax
	push %eax
next
prim stash
	mov (%esp), %eax
	pushrs %eax
next

# memory access #############################
prim get, "@"
	pop %eax
	push (%eax)
next
prim set, "!"
	pop %eax
	pop %edx
	mov %edx, (%eax)
next

# program flow control ######################
prim zbranch
	lodsl                 # dist to branch
	pop %edx              # boolean to test
	xor %ecx, %ecx
	sub $CELL_SIZE, %eax  # because lodsl increments %esi
	test %edx, %edx       # bool is zero?
	setnz %cl
	dec %ecx
	and %ecx, %eax        # %ecx is 0 if %edx is non-zero
	add %eax, %esi
next
prim branch
	add (%esi), %esi
next
prim call
	pop %eax
	jmp *(%eax)
next

# string handling ###########################
prim lenz  // zstr -- int
	pushrs %edi
	xor %ecx, %ecx
	xor %eax, %eax
	dec %ecx
	pop %edi
	repne scasb
	inc %ecx
	not %ecx
	push %ecx
	poprs %edi
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
	# create scratchpad
	.long lit, SCRATCH_SIZE, buffer, scratchpad_addr, set
	# are there any commandline args...
	.long argc, get, dec, zbranch, JUMP(1f)
	# ...yes, then open the first one
	.long argv, get, one, cell, add, get
	.long buffer_zfIle
1:
	.long lit, -17, lit, 10, udivmod, digit_to_char, putc, digit_to_char, putc
	# create input buffer
	# hand off control to the main loop
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

# basic io ##################################
word write  # str len fh -- 
	.long push
	.long swap, pop
	.long SysWrite, syscall3
	.long drop # discard result
end
word put   # zstr len --
	.long stdout, write
end
word putz # zstr --
	.long dup, lenz
	.long put
end
word putc  # c --
	.long dsp, one, put
	.long drop # drop on-stack buffer
end

# logical functions #########################
word between, "between?"
	.long push, push, dup
	.long pop, ge, swap
	.long pop, le, and
end

# number conversion #########################
word digit_to_char, "digit-to-char" # n -- c
	.long dup 
	.long zero, lit, 9, between, zbranch, JUMP(1f)
	.long lit, '0', add
	.long branch, JUMP(2f)
1:
	.long lit, 'a'-10, add
2:
end
word int_to_str, "int-to-zstr"  # n base -- zstr
	.long stash
	.long divmod, 
end

# filesystem access #########################
constant stdin,  0
constant stdout, 1
constant stderr, 2

# NOTE: these values are octal!
constant ReadOnly,   0
constant WriteOnly,  01101
constant ReadWrite,  02202

variable FileOpenFailed, 0
variable CouldNotStatFile, 0

word stat_fd "stat-fd"
	.long scratchpad_addr, swap, SysStat, syscall2
	.long system_error_reported, zbranch, JUMP(1f)
	.long CouldNotStatFile, raise
1:
	.long scratchpad_addr
end
word st_size ".st_size"
	.long lit, 5, cell, add
end
word file_length  "file-length" # fd -- len
	.long stat_fd, st_size, get
end


word system_error_reported, "system-error-reported?"
	.long lit, 255, or, minus_one, eq # zero on error
end
word zopen   # zstr mode -- fh
	# syscall3 requires arg order: perms mode zstr callid
	.long swap, push, push
	.long lit, 0666, pop, pop
	.long SysOpen, syscall3
	.long dup, system_error_reported
	.long zbranch, JUMP(1f)
	.long drop, FileOpenFailed, raise
1:
end


# memory-mapping ############################
constant MapShared,     MAP_SHARED
constant MapPrivate,    MAP_PRIVATE
constant MapAnonymous,  MAP_ANONYMOUS
constant MapStack,      MAP_STACK

constant ProtRead,      PROT_READ
constant ProtWrite,     PROT_WRITE
constant ProtExec,      PROT_EXEC
constant ProtGrowsDown, PROT_GROWSDOWN
constant ProtGrowsUp,   PROT_GROWSUP

# exceptions
variable MmapFailed, 0

word mmap  # fd flags prot len -- addr
	.long push, push, push, push
	#     offs  fd   flag prot len  addr
	.long zero, pop, pop, pop, pop, zero, SysMmap, syscall6
	# check return code
	.long dup, system_error_reported
	.long zbranch, JUMP(1f)
	.long MmapFailed, raise
1:
end
word mmap_fd "mmap-fd" # fd len -- addr
	.long push, MapShared, ProtRead, pop, mmap
end
word munmap  # len addr -- 
	.long SysMunmap, syscall2
	.long drop  # todo: error handling
end

word buffer  # len -- addr
	.long push
	.long minus_one                     # fd is ignored
	.long MapPrivate, MapAnonymous, or  # set map options
	.long ProtWrite, ProtRead, or       # set protections
	.long pop, mmap
end

word buffer_zfIle "buffer-zfile" # zstr -- addr len fd
	# TODO: not keeping track of the fd or filename
	.long ReadOnly, zopen # , stash
	.long dup, file_length, mmap_fd #, stash, mmap_fd
	# .long pop, pop
end

#################################################
# Exception handling
#################################################

word raise
	.long dup, get
	.long dup, zbranch, JUMP(1f)
	.long nip, call, done
1:
	.long lit, 42, exit
end


#################################################
# Variables
#################################################

.bss
.align CELL_SIZE
variable argc
variable argv

variable ds0
variable rs0

variable scratchpad_addr,,"scratchpad-addr"
