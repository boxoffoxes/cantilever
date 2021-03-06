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
.set FLAG_TABLE_SIZE, (127-32) # non-space ASCII chars
.set CELL_BITS, 2
.set CELL_SIZE, (1<<CELL_BITS)
.set DS_SIZE, (64*CELL_SIZE)
.set link, 0

.set BASE_4_YEAR, 1461
.set LILIAN_CORRECTION, 6345

// #define CANTILEVER_COMPILATION_TRACE
//#define CANTILEVER_EXECUTION_TRACE
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
#define DATA .int

#define ToS %ebx

# Structural macros ##################################

.set LFA_OFFS, (1*CELL_SIZE)
.set BFA_OFFS, (2*CELL_SIZE)
.set CFA_OFFS, (3*CELL_SIZE)
.set PFA_OFFS, (4*CELL_SIZE)

.macro header label, name, behav
	.section .data
	.align CELL_SIZE, 0
dict_label_\label:
	DATA (100001f - 100000f - 1)
	100000:
	.ifeqs "\name", ""
		.asciz "\label"
	.else
		.asciz "\name"
	.endif
	100001:
	.align CELL_SIZE, 0
dict_\label:
	DATA link
	DATA dict_label_\label
	DATA \behav
.set link, dict_\label
.endm

.macro prim label, name, behav=storeinc
	header \label, "\name", \behav
\label:
	DATA prim_\label
	.section .text
	.align CELL_SIZE
prim_\label:
	TRACE_CODE
.endm

.macro word label, name, behav=storeinc, handler=do
	header \label, "\name", \behav
\label:
	DATA \handler
word_\label:
.endm

.macro constant label, val, name
	word \label, "\name", , doconst
	# push $\val
	# next
	DATA \val
.endm

.macro variable label, val=0, name
	word \label, "\name", , dovar
var_\label:
	DATA \val
.endm

.macro string label, str, name
	constant \label, str_\label, "\name"
	.section .data
str_\label:
	DATA (20001f - str_text_\label - 1)
str_text_\label:
	.asciz "\str"
	20001:
	.align CELL_SIZE, 0
.endm

# Code macros ########################################

.macro next
	mov (%esi), %eax
	add $CELL_SIZE, %esi
	jmp *(%eax)
	.align CELL_SIZE
.endm

.macro end
	DATA endcol
.endm

.macro string_len_in_cells reg
	shr $CELL_BITS, \reg
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
	and $0xfffffffc, %edi
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
# C-style functions                                  #
######################################################

# Initialisation #####################################

.section .data
constant HeapBaseAddr . "heap-base-addr"


.section .text

.globl _start
.align CELL_SIZE
_start:
	cld
	mov (%esp), %eax
	mov %eax, var_argc
	lea CELL_SIZE(%esp), %eax
	mov %eax, var_argv
	mov %eax, var_argv0
	mov $0xd50d50, ToS
	mov %esp, var_ds0
	mov %esp, %ebp
	sub $DS_SIZE, %ebp
	mov %ebp, var_rs0
	mov $cold_start, %esi
next

# Utility function ###################################

.align CELL_SIZE
_fill_buffer:
	# ToS has been preserved before we were called
	mov $__NR_read, %eax
	mov var_inChannel, ToS
	mov var_ioBuffer, %ecx
	mov %ecx, var_bufpos  // reset buffer position
	mov $BUFFER_SIZE, %edx
	int $0x80
	test %eax, %eax
	jbe _eof
	add %eax, %ecx
	mov %ecx, var_bufend
	// fallthrough
.align CELL_SIZE
_key:  # leaves result on ToS
	mov var_bufpos, %edx
	cmp var_bufend, %edx
	jae _fill_buffer
	movzbl (%edx), ToS
	inc %edx
	mov %edx, var_bufpos
ret

.align CELL_SIZE
_eof:
	mov var_ioBuffer, %eax
	mov %eax, var_bufend
	mov %eax, var_bufpos
	pop %eax   # _key return addr (we're using regular CPU call-ret)
	pop %eax   # _word return addr
	pop %eax   # the function that called _key or _word had already pushed ToS
	mov $_eof_wrap, %esi
next

#ifdef CANTILEVER_EXECUTION_TRACE
_space_buffer:
	.space 128, ' '
.align CELL_SIZE
_trace:
	# print spaces based on return stack depth
	push %eax
	mov var_rs0, %edx
	mov $2, ToS
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

.align CELL_SIZE
_word:  // copy the next word into wordbuffer
	// skip whitespace
	call _key
	cmpb $' ', %bl
	jbe _word 
	// copy word
	mov $wordbuffer_text, %edx
1:
	movb %bl, (%edx)
	inc %edx
	cmpl $end_wordbuffer, %edx
	jae 2f // buffer overflow!
	pushrs %edx  // save our pointer
	call _key
	poprs %edx   // ...and restore it
	cmpb $' ', %bl
	ja 1b
	movl $0, CELL_SIZE(%edx)  // add two words of nulls after word
	//mov $0, 8(%edx)
	// populate the length field of the buffer
	movl $0, (%edx)
	sub $wordbuffer_text, %edx
	mov %edx, wordbuffer
ret
2:  # TODO: THIS MAY BE BORKED!
	// TODO: should skip the rest of the long word too...
	movl $0x202e2e2e, wordbuffer+12 // truncate the long word with "... "
	movl $12, wordbuffer
	movl $wordbuffer, (%ebp)  // over-write our return address
	push $str_TooLong
	# handle error. Was function, but used only here
	mov $_error_wrap, %esi
next

# Wrappers for calling words from code ###############
.align CELL_SIZE
cold_start:
	DATA initialiseVM

.align CELL_SIZE
_error_wrap:
	DATA lit, 2, error

.align CELL_SIZE
_eof_wrap:
	DATA EndOfFile, raise, tailcall, reset

######################################################
# Forth-style code words                             #
######################################################

# codewords ##########################################

.align CELL_SIZE
do:
TRACE_CODE
	pushrs %esi  // save return address
	lea CELL_SIZE(%eax), %esi
next

.align CELL_SIZE
doconst:
	push ToS
	mov CELL_SIZE(%eax), ToS
TRACE_CODE
next

.align CELL_SIZE
dovar:
	push ToS
	lea CELL_SIZE(%eax), ToS
TRACE_CODE
next


# The black-magic of forth: data with behaviour.
#
# ... | dodoes | behav | data ...
#
# A more typical implementation would have been:
# 
# ... | dodoes | ptr | data ... | behav
#                  \______________7
#
# but we remove the indirection as we have anonymous functions
#
.align CELL_SIZE
dodoes:
	push ToS
	pushrs %esi
	lea (2*CELL_SIZE)(%eax), ToS
	mov CELL_SIZE(%eax), %esi
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

# prims
prim syscall0  # id -- result
	mov ToS, %eax
	int $0x80
	mov %eax, ToS
next
prim syscall1  # arg id -- result
	mov ToS, %eax
	pop ToS
	int $0x80
	mov %eax, ToS
next
prim syscall2  # arg2 arg1 id -- result
	mov ToS, %eax
	pop ToS
	pop %ecx
	int $0x80
	mov %eax, ToS
next
prim syscall3  # arg3 arg2 arg1 id -- result
	mov ToS, %eax
	pop ToS
	pop %ecx
	pop %edx
	int $0x80
	mov %eax, ToS
next

prim syscall6  # arg6 arg5 ... arg1 id -- result
	# This is slightly different because for >5 args
	# Linux expects args to be passed by pointer.
	# In this case we simply use the stack
	mov ToS, %eax
	mov %esp, ToS
	int $0x80
	add $(6*CELL_SIZE), %esp
	mov %eax, ToS
next

# IO prims ###########################################

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

prim key   # -- c
	push ToS
	call _key
next

prim word  # -- str
	push ToS
	call _word
	// push the address of temporary buffer
	mov $wordbuffer, ToS
next

# Logical and bitwise prims ##########################

constant true, -1
constant false, 0

prim match "matches?" # n1 n2 -- n1 bool
	# semi-destructive equals for pattern matching
	xor %eax, %eax
	cmpl (%esp), ToS
	setne %al
	dec %eax
	mov %eax, ToS
next

prim between "btw?"  # n lower upper -- bool
	pop %ecx  # lower
	pop %eax  # n
	sub %ecx, ToS  # upper-lower
	sub %ecx, %eax  # n-lower
	xor %ecx, %ecx  
	cmp ToS, %eax
	seta %cl
	dec %ecx
	mov %ecx, ToS
next

prim eq, "=" // a b -- bool
	pop %eax
	xor %ecx, %ecx
	cmpl %eax, ToS
	setne %cl
	dec %ecx
	mov %ecx, ToS
next
prim neq, "<>" // a b -- bool
	pop %eax
	xor %ecx, %ecx
	cmpl %eax, ToS
	sete %cl
	dec %ecx
	mov %ecx, ToS
next
prim ge, ">="
	pop %edx
	xor %ecx, %ecx
	cmpl ToS, %edx
	setl %cl
	dec %ecx
	mov %ecx, ToS
next
prim gt, ">"
	pop %edx
	xor %ecx, %ecx
	cmpl ToS, %edx
	setle %cl
	dec %ecx
	mov %ecx, ToS
next
prim le, "<="
	pop %edx
	xor %ecx, %ecx
	cmpl ToS, %edx
	setg %cl
	dec %ecx
	mov %ecx, ToS
next
prim lt, "<"
	pop %eax
	xor %ecx, %ecx
	cmpl ToS, %eax
	setge %cl
	dec %ecx
	mov %ecx, ToS
next

prim and
	pop %eax
	and %eax, ToS
next
prim or
	pop %eax
	or %eax, ToS
next
prim xor
	pop %eax
	xor %eax, ToS
next
prim not
	not ToS
next

prim bool
	xor %eax, %eax
	test ToS, ToS
	setz %al
	dec %eax
	mov %eax, ToS
next

prim lshift, "shift-up" // int n -- int
	mov ToS, %ecx
	pop ToS
	shl %cl, ToS
next
prim rshift, "shift-down" // int n -- int
	mov ToS, %ecx
	pop ToS
	sar %cl, ToS
next

# Arithmetic prims ###################################

constant zero, 0, "0"
constant one,  1, "1"
constant minus_one, -1 "-1"

prim mul, "*"  // int int -- int
	pop %eax
	imull ToS
	mov %eax, ToS
	// TODO: check for overflow
next

prim mulDiv, "*/" // int int int -- int
	mov ToS, %ecx
	pop %eax
	imull (%esp)
	idiv %ecx
	mov %eax, ToS
next

prim udivmod, "/modu" # int int -- int int
	pop %eax
	xor %edx, %edx
	divl ToS
	mov %edx, ToS
	push %eax
next
prim divmod  "/mod" # int int -- int int
	pop %eax
	cdq  // sign-extend %eax into %edx
	idivl ToS
	mov %edx, ToS
	push %eax
next

prim sub, "-" // int int -- int
	pop %eax
	sub ToS, %eax
	mov %eax, ToS
next
prim add, "+" // int int -- int
	pop %eax
	add %eax, ToS
next

prim neg
	negl ToS
next

prim inc, "1+"
	incl ToS
next
prim dec, "1-"
	decl ToS
next

prim double, "2*"
	shl $1, ToS
next

prim min // int int -- int
	pop %eax
	cmpl %eax, ToS
	jl 1f
	mov %eax, ToS
1:
next
prim max
	pop %eax
	cmpl %eax, ToS
	jg 1f
	mov %eax, ToS
1:
next

prim umin // uint uint -- uint
	pop %eax
	cmpl %eax, ToS
	jb 1f
	mov %eax, ToS
1:
next
prim umax
	pop %eax
	cmpl %eax, ToS
	ja 1f
	mov %eax, ToS
1:
next

prim sumCells, "sum-cells"  # array count -- int
	mov ToS, %ecx
	pop %edx
	xor %eax, %eax
1:
	jcxz 2f
	dec %ecx
	add %edx, %eax
	jmp 1b
2:
	mov %eax, ToS
next

# Data Stack manipulation prims ######################

prim dspGet, "dsp@"
	push ToS
	mov %esp, ToS
next
prim dspSet, "dsp!"
	mov ToS, %esp
	pop ToS
next
prim dsDepth, "ds-depth"
	push ToS
	mov var_ds0, ToS
	sub %esp, ToS
	sar $CELL_BITS, ToS
	dec ToS  # because ToS is in a register
next

prim drop
	pop ToS
next
prim nip
	lea CELL_SIZE(%esp), %esp
next
prim swap  // a b -- b a
	xchg ToS, (%esp)
next
.data
dupcount: DATA 0

prim dup
	incl dupcount
	cmp var_ds0, %esp
	jae crash
	push ToS
next
crash:
	xor %eax, %eax
	mov (%eax), %eax
prim over
	push ToS
	mov CELL_SIZE(%esp), ToS
next

# Return stack prims #################################

prim rspGet, "rsp@"
	push ToS
	mov %ebp, ToS
next
prim rspSet, "rsp!"
	mov ToS, %ebp
	pop ToS
next
prim rsDepth, "rs-depth"
	push ToS
	mov var_rs0, ToS
	sub %ebp, ToS
	sar $CELL_BITS, ToS
next

prim push
	pushrs ToS
	pop ToS
next
prim peek
	push ToS
	mov (%ebp), ToS
next
prim pop
	push ToS
	poprs ToS
next
prim stash
	pushrs ToS
next
prim trash
	poprs %eax
next

prim wlen  #  addr -- n-cells
	# -1 means a primitive or other non-inlinable word
	# otherwise returns the length in cells of the word
	mov $-1, %ecx
	mov %esi, %edx
	mov ToS, %esi
	lodsl
	cmpl $do, %eax
	jne 2f
	mov $endcol, %eax
	xchg %esi, %edi
	repne scasl
	xchg %esi, %edi
	not %ecx
	dec %ecx
2:
	mov %edx, %esi
	mov %ecx, ToS
next

variable curframe
prim frame
	mov curframe, %eax
	pushrs %eax
	mov %ebp, curframe
next
prim unframe
	mov curframe, %ebp
	poprs %eax
	mov %eax, curframe
next
prim local, "$$"  # n -- addr
	# get cell n of current frame
	not ToS
	mov curframe, %eax
	lea (%eax, ToS, CELL_SIZE), %edx
	mov %edx, ToS
next
prim locals  # n -- 
	# create a frame with n local variables
	mov curframe, %eax
	pushrs %eax
	mov %ebp, curframe
	mov ToS, %ecx
1:
	test %ecx, %ecx
	jz 2f
	pop %eax
	dec %ecx
	pushrs %eax
	jmp 1b
2:
	pushrs $do_unframe
	pop ToS
next
prim incVar "inc-var"
	incl (ToS)
	pop ToS
next
prim decVar "dec-var"
	decl (ToS)
	pop ToS
next

do_unframe:
	DATA unframe, return

# Instruction pointer ################################

prim ipGet, "ip@"
	push ToS
	mov %esi, ToS
next

# Memory access ######################################

prim get, "@"
	mov (ToS), ToS
next
prim getByte, "@b"
	movzbl (ToS), ToS
next

prim getStep "@+"  # addr -- addr' n
	mov (ToS), %eax
	addl $CELL_SIZE, ToS
	push ToS
	mov %eax, ToS
next

prim set "!" # int addr -- 
	pop %eax
	mov %eax, (ToS)
	pop ToS
next
prim setByte "!b" # int addr -- 
	pop %edx
	mov %dl, (ToS)
	pop ToS
next

prim dpGet, "dp@"
	push ToS
	mov %edi, ToS
next
prim dpSet, "dp!"
	mov ToS, %edi
	pop ToS
next

prim here
	push ToS
	mov %edi, ToS
next

prim dpAlign, "align-dp"
	align_dp
next

prim storeinc, ","
	mov ToS, (%edi)
	lea 4(%edi), %edi
	pop ToS
next

prim storebinc, ",b"
	mov %bl, (%edi)
	inc %edi
	pop ToS
next

prim cell
	shll $CELL_BITS, ToS
next

prim align // addr -- addr
	// align to cell boundary
	add $(CELL_SIZE-1), ToS
	andb $0xfc, %bl
next

prim isAnonymous "is-anon?" # addr -- bool
	# is addr in the anonymous area?
	mov var_anonCodeAreaAddr, %edx
	sub %edx, ToS
	xor %edx, %edx
	cmp $SCRATCH_SIZE, ToS
	seta %dl
	dec %edx
	mov %edx, ToS
next

# Flow control #######################################

prim endcol
	poprs %esi
next
prim return
	poprs %esi
next

prim data  # -- addr
	push ToS
	mov (%esi), %eax
	lea CELL_SIZE(%esi), ToS
	lea CELL_SIZE(%esi, %eax), %esi
next

prim branch
	add (%esi), %esi
next

prim zbranch   #  bool -- 
	mov (%esi), %eax
	#lodsl                  # distance to branch
	add $CELL_SIZE, %esi
	xor %ecx, %ecx
	sub $CELL_SIZE, %eax   # because lodsl incremented %esi
	test ToS, ToS        # bool is zero?
	setnz %cl
	pop ToS
	dec %ecx
	and %ecx, %eax         # %ecx is 0 if %edx is non-zero
	add %eax, %esi
next

prim tailcall, "tail:"
	mov (%esi), %esi
	lea CELL_SIZE(%esi), %esi
next

prim tailcallTOS, "tailcall-tos"
	lea CELL_SIZE(ToS), %esi
	pop ToS
next

prim call  # xt --
	mov ToS, %eax
	pop ToS
	jmp *(%eax)
next

prim inline   # xt --
	# TODO: this logic belongs in quote, not inline!
	mov -4(%edi), %eax
	cmp $quote, %eax
	je prim_storeinc  # don't inline quoted words!
	mov ToS, %eax
	pop ToS
	mov %esi, %edx
	lea 4(%eax), %esi
1:
	lodsl
	cmp $endcol, %eax
	je 2f
	stosl
	jmp 1b
2:
	mov %edx, %esi
next

# prim select "?"
# 	xor %edx, %edx
# 	xor %ecx, %ecx
# 	mov 8(%esp), %eax  # cond
# 	test %eax, %eax
# 	setnz %dl
# 	setz %cl
# 	dec %edx
# 	dec %ecx
# 	and (%esp), %edx  # else
# 	and 4(%esp), %ecx # then
# 	addl %ecx, %edx
# 	lea 8(%esp), %esp
# 	mov %edx, (%esp)
# next

# Numeric literals ###################################

prim lit
	push ToS
	mov (%esi), ToS
	add $CELL_SIZE, %esi
next
# we give this a different name to make code easier to read
prim quote, "'"
	push ToS
	mov (%esi), ToS
	add $CELL_SIZE, %esi
next

# Memory copying prims ###############################

prim copyBytes, "copy-bytes"  # from nbytes to --
	xchg %edi, ToS  # save DP
	pushrs %esi      # save IP
	pop %ecx
	pop %esi
	rep movsb
	poprs %esi
	mov ToS, %edi
	pop ToS
next
prim copy, "copy" # from ncells to --
	xchg %edi, ToS # save DP
	pushrs %esi
	pop %edi
	pop %ecx
	pop %esi
	rep movsl
	poprs %esi
	mov ToS, %edi
	pop ToS
next
prim keep  # addr len -- addr
	# move a temporary value len cells long from addr into the dictionary 
	align_dp
	mov %esi, %edx  # save IP
	mov ToS, %ecx        # length in cells
	pop %esi        # get source
	mov %edi, ToS       # push permanent address
	rep movsl
	mov %edx, %esi  # restore IP
next
prim forget  # cfa -- 
	# take the next compiled word, and delete it and 
	# everything following it in the dictionary
	sub $CFA_OFFS, ToS
	mov ToS, var_dictPtr
	mov (ToS), ToS
	mov ToS, var_dictionary
	pop ToS
next

# String handling prims ##############################

prim strEq "s=" # str str -- bool
	xor %edx, %edx
	pushrs %esi
	pushrs %edi
	mov ToS, %esi
	pop %edi
	mov (%esi), %ecx
	string_len_in_cells %ecx
	inc %ecx  # extra one for the length field
	repe cmpsl
	setnz %dl
	dec %edx
	mov %edx, ToS
	poprs %edi
	poprs %esi
next

prim lenz  // zstr -- int
	pushrs %edi
	xor %ecx, %ecx
	dec %ecx
	xor %eax, %eax
	mov ToS, %edi
	repne scasb
	inc %ecx
	not %ecx
	mov %ecx, ToS
	poprs %edi
next


# Numnber and date parser ###############################

.section .data
.align CELL_SIZE
number_char_class:
###    0  1  2  3  4  5  6  7  8  9  a  b  c  d  e  f
# 00: escape chars
.byte  1, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0
# 10: 
.byte  0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0
# 20:     !  "  #  $  %  &  '  (  )  *  +  ,  -  .  /
.byte  0, 0, 0, 0, 0, 0, 0, 3, 0, 0, 0, 0, 0, 6, 4, 0
# 30:  0  1  2  3  4  5  6  7  8  9  :  ;  <  =  >  ?
.byte  2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 5, 0, 0, 0, 0, 0
# # 40:  @  A  B  C  D  E  F  G  H  I  J  K  L  M  N  O
# .byte  0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0
# # 50:  P  Q  R  S  T  U  V  W  X  Y  Z  [  \  ]  ^  _
# .byte  0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0
# # 60:  `  a  b  c  d  e  f  g  h  i  j  k  l  m  n  o
# .byte  0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0
# # 70:  p  q  r  s  t  u  v  w  x  y  z  {  |  }  ~ DEL
# .byte  0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0

### Handlers
# 0: terminator
# 1: error
# 2: natural
# 3: char literal 'x'
# 4: fixed-point 123.45
# 5: time (x60) 10:00:03
# 6: date (x100) 2000-01-01
.align CELL_SIZE
jump_table:
	DATA _num_err, _num_done, _natural, _char_lit, _decimal, _time, _date
month_table:
	#      J    F   M   A   M   J   J    A    S    O    N    D
	DATA 306, 337, 0, 31, 61, 92, 122, 153, 184, 214, 245, 275

word number  #  str -- int bool
	DATA one, cell, add, znumber
end

prim znumber  # zstr -- int bool
	# see if zstr conforms to one of the supported 
	# number formats: 123 -123 123.456 12:34:56 2012-12-31
	xor %eax, %eax
	xor %edx, %edx
	pushrs %esi
	mov ToS, %esi  # zstr in %esi
	# add $CELL_SIZE, %esi
	# check for negative number
	movb (%esi), %al
	cmpb $'-', %al
	sete %al
	addl %eax, %esi  # increment zstr if negative
	push %eax
	mov $jump_table, ToS
	xor %eax, %eax  # %eax is accumulator.

.align CELL_SIZE
_natural:
	xor %ecx, %ecx
1:
	digit (%esi), %dl, 2f
	times_ten %ecx
	add %edx, %ecx
	inc %esi
	jmp 1b
2:
	add %ecx, %eax

.align CELL_SIZE
_choose_handler:
	# select handler
	movb (%esi), %dl
	cmp $':', %dl
	ja _num_err
	mov $number_char_class, %ecx
	movzbl (%ecx, %edx), %ecx
	mov (ToS, %ecx, CELL_SIZE), %ecx
	jmp *%ecx

.align CELL_SIZE
_decimal:
	inc %esi
	mov var_decimal_places, %ecx
	test %ecx, %ecx
	jz 3f
1:	
	mov (%esi), %dl
	test %dl, %dl
	jz 2f
	sub $'0', %dl
	cmp $9, %dl
	ja _num_err
	inc %esi
2:
	times_ten %eax
	addl %edx, %eax
	loop 1b
3:
	movb (%esi), %dl
	test %dl, %dl
	jz _num_done  # exactly the right number of decimals
	inc %esi
	jmp 3b

.align CELL_SIZE
_char_lit:
	inc %esi
	test %eax, %eax
	jnz _num_err
	mov (%esi), %al
	jmp _num_done
.align CELL_SIZE
_time:
	inc %esi
	times_60 %eax
	jmp _natural

.align CELL_SIZE
_date:
	inc %esi
#ifdef CANTILEVER_CHEAP_DATE
	# Use a date format useless for anything
	# but comparison ( YYYY x 10000 + MM x 100 + DD )
	times_ten %eax
	times_ten %eax
	jmp _natural
#else
	# We use Lilian Date, which is a count of days since the 
	# start of the Gregorian calendar, where 15 Oct 1582 is 1 (_not_ 0!)
	# However, because our algorithm uses unsigned arithmetic for parsing
	# speed, dates before 1st March 1600 will be incorrect!

	# first calculate year offset from 1600
	subl $1600, %eax
	push %eax  # no of years
	xor %edx, %edx
	xor %eax, %eax

_month:
	mov (%esi), %dl
	cmp $'-', %dl
	je 2f
	sub $'0', %dl
	cmp $9, %dl
	ja _num_err
	inc %esi
	times_ten %eax
	add %edx, %eax
	jmp _month
2:
	# calculate number of days using month_table table above, based on
	# formula from  <http://christophe.lavarenne.free.fr/tagnumen.html>
	inc %esi
	cmp $12, %eax
	ja _num_err  # month>12? I don't think so!
	cmp $3, %eax
	setb %dl     #  %dl = 1 if jan or feb, 0 otherwise
	sub %edx, (%esp)  # we count years from 1st March, so yr-1 for jan or feb
	dec %eax     # month->index (0-11)
	mov $month_table, %ecx
	mov (%ecx, %eax, CELL_SIZE), %eax   # days to start of month
	push %eax
	xor %eax, %eax
	xor %edx, %edx
_day:
	mov (%esi), %dl
	cmp $0, %dl
	je 3f
	sub $'0', %dl
	cmp $9, %dl
	ja _num_err
	inc %esi
	times_ten %eax
	add %edx, %eax
	jmp _day
3:
	pop %ecx        # days to start of month from March
	add %eax, %ecx  # total days from start of year (-mm-dd portion)
	pop %eax        # remember our year from earlier?
	push %ecx
	push %eax

	# calculate missed century leap-days...
	mov $100, %ecx
	divl %ecx      # divide %eax by 100 for centuries
	mov %eax, ToS	
	shr $2, %eax    # divide 100 yr missed-leaps by 4 for 400 year leaps
	sub ToS, %eax
	# convert years to days
	xchg (%esp), %eax
	mov $BASE_4_YEAR, %ecx   # (1461 = 365.25 * 4) I love fixed-point. A base-4 fxp saves us a div!)
	mull %ecx
	shr $2, %eax   # convert back from base-4 fix-point
	pop %edx
	pop %ecx
	add %edx, %eax
	add %ecx, %eax
	add $LILIAN_CORRECTION, %eax  # Convert to Lilian date
#	pop %edx
#	jmp _num_done
	jmp _num_done
#endif

.align CELL_SIZE
_num_err:
	poprs %esi
	movl $0, (%esp)  # over-write sign
	mov $0, ToS
next

.align CELL_SIZE
_num_done:
	# apply negative from earlier
	pop %edx
	test %edx, %edx
	jz 4f
	neg %eax
4:
	poprs %esi
	push %eax
	mov $-1, ToS
next


# List prims #########################################

prim length # list -- int 
	xor %ecx, %ecx
1:
	mov (ToS), ToS
	test ToS, ToS
	loopnz 1b
2:
	not %ecx
	mov %ecx, ToS
next


######################################################
# Forth-style non-primitive words                    #
######################################################

# Startup code #######################################

word initialiseVM
	# initialise the dictionary pointer
	DATA getBrkAddr, dup, dictPtr, set, dpSet
	# allocate default heap
	DATA lit, HEAP_SIZE, setHeapSize
	# create scratchpad
	DATA lit, SCRATCH_SIZE, buffer, scratchpadAddr, set
	# create anon code area
	DATA lit, SCRATCH_SIZE, buffer, anonCodeAreaAddr, set
	# set up an IO buffer
	DATA lit, BUFFER_SIZE, buffer, ioBuffer, set
	# initialise commandline flag handler
	DATA lit, FLAG_TABLE_SIZE, cell, buffer, flagTableAddr, set
	# are there any commandline args...
	DATA argc, get, dec, zbranch, JUMP(1f)
	# ...yes, then open the first one
	#DATA argv, get, one, cell, add, get
	DATA handleArgs
1:
	DATA welcome
DATA tailcall, reset
end

word reset
	DATA rs0, get, rspSet 
	DATA interpreter, get
DATA tailcallTOS
end

# word initCommandlineFlags, "init-commandline-flags"
#	DATA quote, singleStepper, lit, 'S', flag
# end

word handleArgs, "handle-args"
	# first set this function to be our EOF handler
	DATA quote, handleNextArg, handles, EndOfFile
	DATA tailcall, handleNextArg
end
word handleNextArg, "handle-next-arg"
	# DATA semicolon  # any uncalled code from the previous file?
	# check if there's an argument left to handle
	# TODO: doesn't close open files! oops
	DATA nextArg, dup, zbranch, JUMP(1f)
	DATA zopenIn, tailcall, reset
1:
	# no args left: switch to reading stdin and
	# reset EOF handler
	DATA drop, stdin, inChannel, set
	DATA quote, exit0, handles, EndOfFile
DATA tailcall, reset
end
word nextArg, "next-arg"
	DATA argv, get, one, cell, add
	DATA dup, argv, set
	DATA get
end

# Strings #############################################

constant spc, 32, "'spc'"

word stringCellLength, "string-cell-length"   #  str -- n
	DATA get, lit, CELL_BITS, rshift, inc, inc  # byte length, plus null, plus length field
end
word keeps   # tmpStr -- str
	DATA dup, stringCellLength, keep
end
word copys   # str addr -- 
	DATA push, dup, stringCellLength, pop, copy
end

word scanz # zstr pred -- addr
	DATA push, dec
1:
	DATA inc, dup, getByte
	DATA dup, zbranch, JUMP(2f)  # reached the NULL terminator at the end of the string
	DATA peek, call, zbranch, JUMP(1b)
	DATA dup
2:
	DATA nip, trash
end
word scanIn "scan-in"  # pred -- c
	# read chars from in-channel until pred returns true
	DATA push  # store the pred off the stack
1:
	DATA key, peek, call
	DATA zbranch, JUMP(1b)
	DATA trash
end

word clearInputBuffer, "clear-input-buffer"
	DATA bufend, get, bufpos, set
end

# Errors & Exception handling #################################

word handles
	# usage: ' fun handles Exception
	#    set fun as handler for Exception
	DATA peek, get, call, set
	DATA pop, one, cell, add
	DATA push
end

word raise  # excp -- 
	DATA dup, get                 #  excp hndl
	DATA dup, zbranch, JUMP(1f)   #  excp hndl
	DATA nip, call, return
1:
	DATA drop, labelForVar        #  lbl
	DATA ErrorUnhandled, puts
	DATA WarningColour, colour, puts, NoColour, colour, error
end

# Default handler for EOF is to exit. This is over-ridden
# when reading from files passed on the commandline.
variable EndOfFile, exit0

string ErrorColour,   "[31m"
string WarningColour, "[33m"
string NoColour,      "[0m"

word error
	DATA inChannel, get, isATTY, zbranch, JUMP(1f)
	DATA clearInputBuffer, reset
1:
DATA one, exit
end

# Numeric Output #######################################

word digit_to_char, "digit-to-char" # n -- c
	DATA dup 
	DATA zero, lit, 9, between, zbranch, JUMP(1f)
	DATA lit, '0', add
	DATA branch, JUMP(2f)
1:
	DATA lit, 'a'-10, add
2:
end
word decompose  # n base -- 0 c ... 
	DATA push, zero, swap
1:
	DATA peek, udivmod, digit_to_char, swap
	DATA dup, zbranch, JUMP(2f), branch, JUMP(1b)
2:
	DATA drop, trash
end
word putsign     # n -- u
	DATA dup, lit, (1<<(CELL_SIZE*8-1)), and, zbranch, JUMP(1f)
	DATA neg, lit, '-', putc
1:
end
word putnumber   # n base --
	DATA decompose
3:
	DATA putc, dup, zbranch, JUMP(4f), branch, JUMP(3b)
4:
	DATA drop
end

# String output #########################################

word lens  # str -- int
	DATA get
end

word warn  # zstr len -- 
	DATA errChannel, get, write
end
word warns # nstr --
	DATA stash, one, cell, add
	DATA pop, get, warn
end

# buffered output
variable outbuf
variable outbuflen
word clearout "clear-out"
	DATA zero, outbuflen, set
end
word flushout "flush-out"
	DATA outbuf, get, outbuflen, get, outChannel, get, write
	DATA clearout
end

word bufferedputz
	DATA dup, lenz, stash
	DATA outbuf, get, outbuflen, get, add
	DATA copyBytes
	DATA pop, outbuflen, get, add, outbuflen, set
end
# unbuffered output
word put   # zstr len --
	DATA outChannel, get, write
end
word putz # zstr --
	DATA dup, lenz
	DATA put
end
word puts #  nstr --  
	DATA stash, one, cell, add
	DATA pop, get, put
end

word putc  # c --
	DATA dup, dspGet, one, put
	DATA drop, drop # drop on-stack buffer
end

word putn // n --
	DATA putsign
	DATA lit, 10
	DATA putnumber
end
word putx // n --
	DATA lit, 16
	DATA putnumber
end

word colour  #  colour -- 
	DATA push
	DATA outChannel, get, isATTY, zbranch, JUMP(1f)
	DATA peek, puts
1:
	DATA trash
end


# File IO ###############################################

word zopen   # zstr mode -- fh
	# syscall3 requires arg order: perms mode zstr callid
	DATA swap, push, push
	DATA lit, 0666, pop, pop
	DATA SysOpen, syscall3
	DATA dup, zero, lt, zbranch, JUMP(1f)
	DATA drop, FileOpenFailed, raise
1:
end
word open  # str mode -- fh
	DATA push
	DATA one, cell, add
	DATA pop, zopen
end

word zopenIn, "zopen-in"
	DATA ReadOnly, zopen, inChannel, set
end
word openIn, "open-in"
	DATA ReadOnly, open, inChannel, set
end
word openOut, "open-out"
	# TODO: doesn't check for errors!
	DATA open, outChannel, set
end

word close  # fh -- err
	DATA SysClose, syscall1
end
word closeOut, "close-out"
	DATA outChannel, get, close
	DATA stdout, outChannel, set
end
word closeIn, "close-in"
	DATA inChannel, get, close
	DATA stdin, inChannel, set
end

word write  # str len fh -- 
	DATA push
	DATA swap, pop
	DATA SysWrite, syscall3
	DATA drop # discard result
end
word read   # buf len fh -- n
	DATA push, swap, pop
	DATA SysRead, syscall3
end

variable FileOpenFailed
variable MmapFailed
variable FailedToMunmapFile
variable CouldNotStatFile

word statFD "stat-fd"
	DATA here, stash, swap, SysStat, syscall2
	DATA zero, lt, zbranch, JUMP(1f)
	DATA CouldNotStatFile, raise
1:
	DATA pop
end

# Get the st_size field of the C stat struct
word st_size ".st_size"
	DATA lit, 5, cell, add
end

word fileLength  "file-length" # fd -- len
	DATA statFD, st_size, get
end


# Memory management ######################################

word setBrkAddr "set-brk-addr"  # addr -- addr
	DATA SysBrk, syscall1
end
word getBrkAddr, "get-brk-addr"  #  -- addr
	DATA zero, setBrkAddr
end
word getHeapSize "get-heap-size"  # -- n
	DATA getBrkAddr, HeapBaseAddr, sub
end

# Todo: error handling on the following two functions
word setHeapSize "set-heap-size"  # n --
	DATA HeapBaseAddr, add, setBrkAddr, drop
end
word growHeap "grow-heap"  # n --
	DATA getBrkAddr, add, setBrkAddr, drop
end


# System interface ########################################

word exit0, "0-exit"
	DATA zero, exit
end

word exit #  n -- 
	DATA SysExit, syscall1
end

word bye, , call
	DATA byebye, puts, nl
	DATA zero, exit
end

constant TCGETS, 0x00005401
word isATTY "is-a-tty?"  # fd -- bool
	DATA push, scratchpadAddr, get, TCGETS, pop, SysIOCtl, syscall3
	DATA zero, eq
end

# Memory mapping

constant MapShared,     MAP_SHARED
constant MapPrivate,    MAP_PRIVATE
constant MapAnonymous,  MAP_ANONYMOUS
constant MapStack,      MAP_STACK

constant ProtRead,      PROT_READ
constant ProtWrite,     PROT_WRITE
constant ProtExec,      PROT_EXEC
constant ProtGrowsDown, PROT_GROWSDOWN
constant ProtGrowsUp,   PROT_GROWSUP

word mmap  # fd flags prot len -- addr
	DATA push, push, push, push
	#     offs  fd   flag prot len  addr
	DATA zero, pop, pop, pop, pop, zero, SysMmap, syscall6
	DATA dup, lit, -200, minus_one, between, zbranch, JUMP(1f)
	DATA MmapFailed, raise
1:
end
word munmap  # len addr -- 
	DATA SysMunmap, syscall2
	DATA drop  # todo: error handling
end

# Create a mem-mapped buffer
word buffer  # len -- addr
	DATA push
	DATA minus_one                        # fd is ignored
	DATA MapPrivate, MapAnonymous, or     # set map options
	DATA ProtWrite, ProtRead, or          # set protections
	DATA pop, mmap
end

word mmapFd "mmap-fd" # fd len -- addr
	DATA push, MapShared, ProtRead, pop, mmap
end

word bufferZFile "buffer-zfile" # zstr -- addr len fd
	DATA ReadOnly, zopen, stash
	DATA dup, fileLength, stash, mmapFd
	DATA pop, pop
end

word bufferFile "buffer-file"  # str -- addr len fd
	DATA one, cell, add
	DATA bufferZFile
end


# Dictionary lookup ###################################

.section .data
.align CELL_SIZE, 0
wordbuffer:
	DATA 0
wordbuffer_text:
	.space WORD_BUFFER_SIZE
end_wordbuffer:
	DATA 0 // space for padding

word notFoundHandler "not-found-handler"  # str
	DATA WarningColour, colour
	DATA puts, NoColour, colour, NotFound, puts, nl
DATA error
end

word find // str -- xt behav
	DATA push  # save str
	DATA dictionary
1:
	DATA get, dup, zbranch, JUMP(2f)
	DATA dup, label, peek, strEq
	DATA zbranch, JUMP(1b)
	DATA dup, cfa, swap, behaviour, trash, return
2:
	DATA drop, peek, number, zbranch, JUMP(3f)
	DATA quote, compileLiteral, trash, return
3:
	DATA drop, pop, NotFoundException, raise
end

word lfa, ".lfa"  # entry -- addr
	DATA lit, LFA_OFFS, add
end
word cfa, ".cfa" // entry -- codeAddr
	DATA lit, CFA_OFFS, add
end
word bfa, ".bfa"
	DATA lit, BFA_OFFS, add
end
word pfa, ".pfa"
	DATA lit, PFA_OFFS, add
end

word label, ".label"  // entry -- str
	DATA lfa, get
end
word behaviour, ".behaviour" 
	DATA bfa, get
end
word cfaToLabel, ".cfa->.label"
	DATA lit, CFA_OFFS, sub
	DATA label
end

word labelForVar, "label-for-var"
	DATA one, cell, sub, cfaToLabel
end

word nl
	DATA lit, '\n', putc
end

word compileLiteral, "compile-literal" // n --
	DATA quote, lit, storeinc, storeinc
end

# Words that create words ############################

variable NotInADataBlock

word lambda, "[", call  # -- addr
	DATA quote, data, storeinc
	DATA here, zero, storeinc
	DATA DoAddr, storeinc
end
word endLambda, "]", call  # addr --
	DATA quote, return, storeinc
	DATA here, over, one, cell, add, sub, swap, set
end
word dataLength, "data-length"  # lambda -- len
	DATA dup, lit, 2, cell, sub, get   # fetch the data instruction
	DATA quote, data, eq, zbranch, JUMP(1f)
	DATA one, cell, sub, get, return      # get the length in bytes and return
1:
	DATA NotInADataBlock, raise
end

word as, , call # addr -- 
	# a word to compile a definition from a lambda in anonymous code space
	DATA semicolon, useDict
	DATA word, keeps, header
	DATA dup, dataLength  # get length of data block
	DATA lit, CELL_BITS, rshift, keep, drop  # convert to cell length and keep.
end

word header  # str --
	DATA dpAlign
	DATA here, push
	DATA dictionary, get, storeinc  # compile link to current head of dict
	DATA storeinc                   # compile label address
	DATA quote, storeinc, storeinc  # store the default behaviour
	DATA pop, dictionary, set       # store our new word in the dict
end

word define  #  str interp --
	DATA swap, header, storeinc
end

word defdoes   # str --
	DATA quote, dodoes, define, zero, storeinc  # behaviour field
end
word defword   # str -- 
	DATA quote, do, define
end
word defconst  # val str -- 
	DATA quote, doconst, define
end
word defvar    # val str --
	DATA quote, dovar, define
end

word create
	DATA semicolon, useDict
	DATA word, keeps, defdoes
end
word createImm, "create-immed"
	DATA create, immed
end
word does
	# This is subtle! pop gives us the address of the word after
	# does in the definition (and prevents subsequent code executing).
	# We put it in the link field of the word create has just made.
	DATA pop, dictionary, get, pfa, set
	# Finally we switch back to anonymous mode
	DATA useAnon
end
word createConstant, "create-constant"  # val --
	# constant: potentially needs to evaluate the preceding expression
	# so there's a value waiting
	DATA semicolon, useDict
	DATA word, keeps, defconst, storeinc
	DATA useAnon
end
word createVariable, "create-variable"  # --
	DATA semicolon, useDict
	DATA word, keeps, defvar
	DATA zero, storeinc
	DATA useAnon
end
word createWord, "create-word"
	DATA semicolon, useDict
	DATA word, keeps, defword
end
word immed, "#immediate", call
	DATA dictionary, get, bfa, quote, call, swap, set
end
word hashinline, "#inline", call
	DATA dictionary, get, bfa, quote, inline, swap, set
end

word constantColon, "constant:", call
	DATA createConstant
end
word variableColon, "variable:", call
	DATA createVariable
end
word colon, ":", call
	DATA createWord
end
word semicolon, ";", call
	DATA quote, endcol, storeinc
	DATA here, isAnonymous, zbranch, JUMP(1f)
	DATA anonCodeAreaAddr, get, call
1:
DATA tailcall, useAnon
end

word useDict, "use-dict"
	DATA here, isAnonymous, zbranch, JUMP(1f)
	DATA dictPtr, get, dpSet
1:
end
word useAnon, "use-anon"
	DATA here, isAnonymous, not, zbranch, JUMP(1f)
	DATA here, dictPtr, set
1:
	DATA anonCodeAreaAddr, get, dpSet
	DATA DoAddr, storeinc
DATA tailcall, prompt
end

word welcome
	DATA inChannel, get, isATTY, zbranch, JUMP(1f)
	DATA WelcomeMessage, puts
1:
end
word prompt
	DATA inChannel, get, isATTY, zbranch, JUMP(1f)
	DATA nl, spc, putc, dsDepth, putn
	DATA lit, ',', putc, rsDepth, putn
	DATA promptText, get, puts
1:
end

variable DataStackUnderflow
variable DataStackOverflow

word interpret
	DATA useAnon
1:
	DATA word, find, call
	DATA branch, JUMP(1b)
end

word suppress, "`", call
	DATA word, find, drop, storeinc
end

.section .rodata

constant DoAddr,      do
constant DoConstAddr, doconst
constant DoDoesAddr,  dodoes
constant WordBuffer, wordbuffer
constant CellBits, CELL_BITS
constant CellSize, CELL_SIZE

#ifdef CANTILEVER_CHEAP_DATE
constant CheapDate, -1
#else
constant CheapDate, 0
#endif
constant Base4Year, BASE_4_YEAR
constant LilianCorrection, LILIAN_CORRECTION

variable argc
variable argv
variable argv0

variable ioBuffer, , "io-buffer"
variable bufpos
variable bufend
variable scratchpadAddr, , "scratchpad-addr"
variable anonCodeAreaAddr, , "anon-code-area-addr"

variable ds0
variable rs0
variable dp0
variable flagTableAddr
variable dictPtr, ,"dict-ptr"

variable NotFoundException, notFoundHandler

string WelcomeMessage "Welcome to Cantilever\n\n\tType an expression in Reverse-Polish form \n\tterminated with [33m;[0m or [33m=[0m (to see a numeric result). \n\tIf you have rlwrap installed you can use tab-completion\n"
string byebye, "\n-- Toodle-pip!\n"
string TooLong, "Word too long: "
string NotFound, " is neither a dictionary word nor a recognised number\n"
string InvalidEsc, "Invalid escape char: "
string UnbalancedRSInBranch, "Unbalanced use of RS in one branch of pattern match at "
string ErrorUnhandled, "Unhandled exception: "
string DefaultPrompt, " ok "

variable decimal_places, 0, "decimal-places"

variable promptText, str_DefaultPrompt, "prompt-text"
variable interpreter, interpret
variable dictionary, link   # MUST BE LAST
