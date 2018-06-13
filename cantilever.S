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

.macro prim label, name, behav=storeinc
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
	lodsl
	jmp *(%eax)
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
	.long initialiseVM

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
# Minimal set of prims                               #
######################################################

prim return
	poprs %esi
next

prim nez, "0<>"   # int -- bool
	pop %eax
	xor %edx, %edx
	test %eax, %eax
	setz %dl
	dec %edx
	push %edx
next

prim ltz "0<"
	pop %eax
	cdq
	push %edx
next

prim get, "@"
	pop %eax
	push (%eax)
next

prim set "!" # int addr -- 
	pop %eax
	pop %edx
	mov %edx, (%eax)
next

prim and
	pop %eax
	and %eax, (%esp)
next
prim or
	pop %eax
	or %eax, (%esp)
next
prim xor
	pop %eax
	xor %eax, (%esp)
next

prim add, "+" // a b -- a+b
	pop %eax
	add %eax, (%esp)
next

prim spGet, "sp@"
	push %esp
next
prim spSet, "sp!"
	pop %esp
next

prim rpGet, "rp@"
	push %ebp
next
prim rpSet, "rp!"
	pop %ebp
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

# Logical and bitwise prims ##########################

constant true, -1
constant false, 0

prim between "btw?"  # n lower upper -- bool
	pop %edx  # upper
	pop %ecx  # lower
	pop %eax  # n
	sub %ecx, %edx  # upper-lower
	sub %ecx, %eax  # n-lower
	xor %ecx, %ecx  
	cmp %edx, %eax
	seta %cl
	dec %ecx
	push %ecx
next

prim eq, "=" // a b -- bool
	pop %eax
	pop %edx
	xor %ecx, %ecx
	cmpl %eax, %edx
	setne %cl
	dec %ecx
	push %ecx
next
prim lt, "<"
	pop %eax
	pop %edx
	xor %ecx, %ecx
	cmpl %eax, %edx
	setge %cl
	dec %ecx
	push %ecx
next

prim lshift, "<<" // int n -- int
	pop %ecx
	pop %eax
	shl %cl, %eax
	push %eax
next
prim rshift, ">>" // int n -- int
	pop %ecx
	pop %eax
	sar %cl, %eax
	push %eax
next

# Arithmetic prims ###################################

literal zero, 0
literal one,  1
literal two,  2
literal five, 5
literal seven, 7
literal nine, 9
literal ten, 10
literal sixteen, 16

literal minus_one, -1
literal minus_two_hundred, -200

constant asc_0, '0', "'0'"
constant asc_a, 'a', "'a'"
constant asc_minus, '-', "'-'"
constant asc_comma, ',', "','"
constant asc_spc, ' ', "'spc'"
constant asc_nl, '\n', "'\n'"

prim mul, "*"  // int int -- int
	pop %eax
	imull (%esp)
	mov %eax, (%esp)
	// TODO: check for overflow
next

prim mulDiv, "*/" // int int int -- int
	pop %ecx
	pop %eax
	imull (%esp)
	idiv %ecx
	mov %eax, (%esp)
next

prim udivmod, "u/mod" # nu de -- q r
	pop %ebx
	pop %eax
	xor %edx, %edx
	divl %ebx
	push %eax
	push %edx
next
prim divmod  "/mod" # int int -- int int
	pop %ebx
	pop %eax
	cdq  // sign-extend %eax into %edx
	idivl %ebx
	push %eax
	push %edx
next

prim sub, "-" // int int -- int
	pop %eax
	sub %eax, (%esp)
next

prim neg
	negl (%esp)
next

prim inc, "1+"
	incl (%esp)
next
prim dec, "1-"
	decl (%esp)
next

prim double, "2*"
	pop %eax
	shl $1, %eax
	push %eax
next

prim min // int int -- int
	pop %eax
	cmpl (%esp), %eax
	jge 1f
	mov %eax, (%esp)
1:
next
prim max
	pop %eax
	cmpl (%esp), %eax
	jle 1f
	mov %eax, (%esp)
1:
next

prim umin // uint uint -- uint
	pop %eax
	cmpl (%esp), %eax
	jae 1f
	mov %eax, (%esp)
1:
next
prim umax
	pop %eax
	cmpl (%esp), %eax
	jbe 1f
	mov %eax, (%esp)
1:
next

# Data Stack manipulation prims ######################

prim dsDepth, "ds-depth"
	mov var_ds0, %eax
	sub %esp, %eax
	sar $CELL_SHIFT, %eax
	push %eax
next

prim drop
	pop %eax
next
prim nip
	pop %eax
	pop %edx
	push %eax
next
prim swap  // a b -- b a
	pop %eax
	pop %edx
	push %eax
	push %edx
next
prim dup
	push (%esp)
next
prim over
	push CELL_SIZE(%esp)
next

# Return stack prims #################################

prim rsDepth, "rs-depth"
	mov var_rs0, %eax
	sub %ebp, %eax
	sar $CELL_SHIFT, %eax
	push %eax
next

prim push
	pop %eax
	pushrs %eax
next
prim peek
	push (%ebp)
next
prim pop
	poprs %eax
	push %eax
next
prim stash
	mov (%esp), %eax
	pushrs %eax
next
prim trash
	poprs %eax
next

# Memory access ######################################

prim getb, "@b"
	xor %eax, %eax
	pop %edx
	mov (%edx), %al
	push %eax
next
prim getStep "@+"  # addr -- addr' n
	mov (%esp), %eax
	addl $4, (%esp)
	push (%eax)
next

prim setb "!b" # int addr -- 
	pop %eax
	pop %edx
	mov %dl, (%eax)
next

prim dpGet, "dp@"
	push %edi
next
prim dpSet, "dp!"
	pop %edi
next

prim incVar "++"
	pop %eax
	incl (%eax)
next
prim decVar "--"
	pop %eax
	decl (%eax)
next

prim here
	push %edi
next

prim dpAlign, "align-dp"
	align_dp
next

prim storeinc, ","
	pop %eax
	stosl
next

prim cell
	shll $CELL_SHIFT, (%esp)
next

prim align // addr -- addr
	// align to cell boundary
	pop %eax
	add $(CELL_SIZE-1), %eax
	andb $(~(CELL_SIZE-1)), %al
	push %eax
next

# Flow control #######################################

prim branch
	add (%esi), %esi
next

prim zbr  # bool --
	lodsl
	pop %edx
	test %edx, %edx
	jnz 1f
	mov %eax, %esi
1:
next

prim tc
	mov (%esi), %esi
	lea 4(%esi), %esi
next

prim call
	pop %eax
	jmp *(%eax)
next

# Numeric literals ###################################
# must be pre-defined as constants!

prim quote, "'"
	lodsl
	push %eax
next

# Memory copying prims ###############################

prim copy, "copy" # from ncells to --
	mov %edi, %edx # save DP
	pushrs %esi
	pop %edi
	pop %ecx
	pop %esi
	rep movsl
	poprs %esi
	mov %edx, %edi
next
prim keep  # addr len -- addr
	# move a temporary value len cells long from addr into the dictionary 
	align_dp
	mov %esi, %edx  # save IP
	pop %ecx        # length in cells
	pop %esi        # get source
	push %edi       # push permanent address
	rep movsl
	mov %edx, %esi  # restore IP
next
prim forget  # cfa -- 
	# take the next compiled word, and delete it and 
	# everything following it in the dictionary
	pop %eax
	sub $CFA_OFFS, %eax
	mov %eax, var_dictPtr
	mov (%eax), %eax
	mov %eax, var_dictionary
next

# String handling prims ##############################

prim strEq # str str -- bool
	xor %edx, %edx
	pushrs %esi
	pushrs %edi
	pop %esi
	pop %edi
	mov (%esi), %ecx
	string_len_in_cells %ecx
	inc %ecx  # extra one for the length field
	repe cmpsl
	setnz %dl
	dec %edx
	push %edx
	poprs %edi
	poprs %esi
next

prim lenz  // zstr -- int
	pushrs %edi
	xor %ecx, %ecx
	dec %ecx
	xor %eax, %eax
	pop %edi
	repne scasb
	inc %ecx
	not %ecx
	push %ecx
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
	.long _num_err, _num_done, _natural, _char_lit, _decimal, _time, _date
month_table:
	#      J    F   M   A   M   J   J    A    S    O    N    D
	.long 306, 337, 0, 31, 61, 92, 122, 153, 184, 214, 245, 275

word number  #  str -- int bool
	.long one, cell, add, znumber
end

prim znumber  # zstr -- int bool 
	# see if zstr conforms to one of the supported 
	# number formats: 123 -123 123.456 12:34:56 2012-12-31
	xor %eax, %eax
	xor %edx, %edx
	pushrs %esi
	pop %esi  # zstr in %esi
	# add $CELL_SIZE, %esi
	# check for negative number
	movb (%esi), %al
	cmpb $'-', %al
	sete %al
	addl %eax, %esi  # increment zstr if negative
	push %eax
	mov $jump_table, %ebx
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
	mov (%ebx, %ecx, 4), %ecx
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
	# However, because our algorithm uses unsigned arithmetic, dates 
	# before 1st March 1600 will be incorrect!

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
	mov (%ecx, %eax, 4), %eax   # days to start of month
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
	mov %eax, %ebx	
	shr $2, %eax    # divide 100 yr missed-leaps by 4 for 400 year leaps
	sub %ebx, %eax
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
	pop %edx # discard sign
	poprs %esi
	push $0
	push $0
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
	push $-1
next



######################################################
# Forth-style non-primitive words                    #
######################################################

# Startup code #######################################

word initialiseVM
	# initialise the dictionary pointer
	.long getBrkAddr, dup, dictPtr, set, dpSet
	# allocate default heap
	.long HeapSize, setHeapSize
	# create scratchpad
	.long ScratchSize, buffer, scratchpadAddr, set
	# set up an IO buffer
	.long BufferSize, buffer, ioBuffer, set
	# initialise commandline flag handler
	#.long FlagTableSize, cell, buffer, flagTableAddr, set
	# are there any commandline args...
	.long argc, get, dec, zbr,(1f)
	# ...yes, then open the first one
	#.long argv, get, one, cell, add, get
	.long handleArgs
1:
	.long welcome
.long tc, reset

word reset
	.long rs0, get, rpSet 
.long tc, interpreter

word handleArgs, "handle-args"
	# first set this function to be our EOF handler
	.long quote, handleNextArg, handles, EndOfFile
	.long tc, handleNextArg
end
word handleNextArg, "handle-next-arg"
	# .long semicolon  # any uncalled code from the previous file?
	# check if there's an argument left to handle
	.long nextArg, dup, zbr,(1f)
	.long zopenIn, tc, reset
1:
	# no args left: switch to reading stdin and
	# reset EOF handler
	.long drop, stdin, inChannel, set
	.long quote, exit0, handles, EndOfFile
.long tc, reset
word nextArg, "next-arg"
	.long argv, get, one, cell, add
	.long dup, argv, set
	.long get
end

# IO ##################################################

word not
	.long minus_one, xor
end

#: abs ( n -- u ) dup 0< ?[ neg ] ;
word abs
	.long dup, ltz, zbr,(1f), neg
1:
end

word pad
	.long scratchpadAddr, get
end
word build  # addr b -- addr'
	.long over, setb, one, add
	.long key, asc_spc, over, lt, zbr,(1f)
	.long tc, build
1:	.long drop
end
word skipws  # -- b
	.long key, asc_spc, over, lt, not, zbr,(1f)
	.long drop, tc, skipws
1:
end

# : key  ?rx 0= ?[ key ;] dup 0< ?[ EndOfFile raise ;] ;
word key
	.long qrx, zero, eq, zbr,(1f), tc, key
1:	.long dup, ltz, zbr,(2f), EndOfFile, raise
2:
end
word word   # -- str
	.long WordBuffer, one, cell, add
	.long dup, skipws, build, zero, over, set, swap, sub
	.long WordBuffer, set, WordBuffer
end

# Strings #############################################

constant spc, 32, "'spc'"

word stringCellLength, "string-cell-length"   #  str -- n
	.long get, CellShift, rshift, inc, inc  # byte length, plus null, plus length field
end
word keeps   # tmpStr -- str
	.long dup, stringCellLength, keep
end
word copys   # str addr -- 
	.long push, dup, stringCellLength, pop, copy
end

word clearInputBuffer, "clear-input-buffer"
	.long key, asc_nl, eq, zbr,(1f), return
1:	.long tc,clearInputBuffer
end

# Errors & Exception handling #################################

word handles
	# usage: ' fun handles Exception
	#    set fun as handler for Exception
	.long peek, get, call, set
	.long pop, one, cell, add
	.long push
end

word raise  # excp -- 
	.long dup, get                 #  excp hndl
	.long dup, zbr,(1f)  #  excp hndl
	.long nip, call, return
1:
	.long drop, labelForVar        #  lbl
	.long ErrorUnhandled, puts
	.long WarningColour, colour, puts, NoColour, colour, error
end

# Default handler for EOF is to exit. This is over-ridden
# when reading from files passed on the commandline.
variable EndOfFile, exit0

string ErrorColour,   "[31m"
string WarningColour, "[33m"
string NoColour,      "[0m"

word error
	.long inChannel, get, isATTY, zbr,(1f)
	.long clearInputBuffer, reset
1:
.long one, exit


# Numeric Output #######################################

#: digit-to-char  dup 0 9 btw? ?[ '0' + ;] 'a' 10 - + ;
word digit_to_char, "digit-to-char" # n -- c
	.long dup 
	.long zero, nine, between, zbr,(1f)
	.long asc_0, add, return
1:
	.long asc_a, ten, sub, add
end

#: digit ( u -- c ) 9 over < 7  and  + 48 + ;
word digit
	.long nine, over, lt, seven,  and,  add, asc_0, add
end
#: extract ( n base -- n c ) 0 swap um/mod digit ;
word extract
	.long udivmod, digit
end
#: <# ( -- ) pad hld ! ;
word formatted, "<#"
	.long pad, hld, set
end
#: hold ( b -- ) hld @ 1 - dup hld ! c! ;
word hold
	.long hld, get, one, sub, dup, hld, set, setb
end
#: #  ( u -- u ) base @ extract hold ;
word holddigit, "#"
	.long base, get, extract, hold
end
#: #s ( u -- 0 ) # dup ?[ #s ;] ;
word holdint, "#s"
	.long holddigit, dup, zbr,(1f), tc, holdint
1:
end
#: sign ( n -- ) 0< ?[ '-' hold ] ;
word sign
	.long ltz, zbr,(1f), asc_minus, hold
1:
end
#: #> ( w -- str len ) drop hld @ pad over - ;
word unformatted "#>"
	.long drop, hld, get, pad, over, sub
end
#: str ( n -- str len ) dup push abs <# #s pop sign #> ;
word str
	.long dup, push, abs, formatted, holdint, pop, sign, unformatted
end

#: u.  ( u -- ) <# #s #> space type ;
word putu "u."
	.long formatted, holdint, unformatted, put
end
#: . ( w -- ) base @ 10 xor ?[ u. ;] str type ;
word putn "."
	.long base, get, ten, xor, zbr,(1f), tc, putu
1:	.long str, put
end
word putx "x."
	.long base, get, swap, hex, putn, base, set
end

word hex
	.long sixteen, base, set
end
word decimal
	.long ten, base, set
end
word binary
	.long two, base, set
end


# String output #########################################

word lens  # str -- int
	.long get
end

word warn  # zstr len -- 
	.long errChannel, get, write
end
word warns # nstr --
	.long stash, one, cell, add
	.long pop, get, warn
end

word put   # zstr len --
	.long outChannel, get, write
end
word putz # zstr --
	.long dup, lenz
	.long put
end
word puts #  nstr --  
	.long stash, one, cell, add
	.long pop, get, put
end

word putc  # c --
	.long spGet, one, put
	.long drop # drop on-stack buffer
end

word colour  #  colour -- 
	.long push
	.long outChannel, get, isATTY, zbr,(1f)
	.long peek, puts
1:
	.long trash
end


# File IO ###############################################
constant OpenPerms 0666
word zopen   # zstr mode -- fh
	# syscall3 requires arg order: perms mode zstr callid
	.long swap, push, push
	.long OpenPerms, pop, pop
	.long SysOpen, syscall3
	.long dup, zero, lt, zbr,(1f)
	.long drop, FileOpenFailed, raise
1:
end
word open  # str mode -- fh
	.long push
	.long one, cell, add
	.long pop, zopen
end

word zopenIn, "zopen-in"
	.long ReadOnly, zopen, inChannel, set
end
word openIn, "open-in"
	.long ReadOnly, open, inChannel, set
end
word openOut, "open-out"
	# TODO: doesn't check for errors!
	.long open, outChannel, set
end

word close  # fh -- err
	.long SysClose, syscall1
end
word closeOut, "close-out"
	.long outChannel, get, close
	.long stdout, outChannel, set
end
word closeIn, "close-in"
	.long inChannel, get, close
	.long stdin, inChannel, set
end

word write  # str len fh -- 
	.long push
	.long swap, pop
	.long SysWrite, syscall3
	.long drop # discard result
end
word read   # buf len fh -- n
	.long push, swap, pop
	.long SysRead, syscall3
end

variable FileOpenFailed
variable MmapFailed
variable FailedToMunmapFile
variable CouldNotStatFile

word statFD "stat-fd"
	.long here, stash, swap, SysStat, syscall2
	.long zero, lt, zbr,(1f)
	.long CouldNotStatFile, raise
1:
	.long pop
end

# Get the st_size field of the C stat struct
word st_size ".st_size"
	.long five, cell, add
end

word fileLength  "file-length" # fd -- len
	.long statFD, st_size, get
end


# Memory management ######################################

word setBrkAddr "set-brk-addr"  # addr -- addr
	.long SysBrk, syscall1
end
word getBrkAddr, "get-brk-addr"  #  -- addr
	.long zero, setBrkAddr
end
word getHeapSize "get-heap-size"  # -- n
	.long getBrkAddr, HeapBaseAddr, sub
end

# Todo: error handling on the following two functions
word setHeapSize "set-heap-size"  # n --
	.long HeapBaseAddr, add, setBrkAddr, drop
end
word growHeap "grow-heap"  # n --
	.long getBrkAddr, add, setBrkAddr, drop
end


# System interface ########################################

word exit0, "0-exit"
	.long zero, exit
end

word exit #  n -- 
	.long SysExit, syscall1
end

word bye
	.long byebye, puts, nl
	.long zero, exit
end

constant TCGETS, 0x00005401
word isATTY "is-a-tty?"  # fd -- bool
	.long push, scratchpadAddr, get, TCGETS, pop, SysIOCtl, syscall3
	.long zero, eq
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
	.long push, push, push, push
	#     offs  fd   flag prot len  addr
	.long zero, pop, pop, pop, pop, zero, SysMmap, syscall6
	.long dup, minus_two_hundred, minus_one, between, zbr,(1f)
	.long MmapFailed, raise
1:
end
word munmap  # len addr -- 
	.long SysMunmap, syscall2
	.long drop  # todo: error handling
end

# Create a mem-mapped buffer
word buffer  # len -- addr
	.long push
	.long minus_one                        # fd is ignored
	.long MapPrivate, MapAnonymous, or     # set map options
	.long ProtWrite, ProtRead, or          # set protections
	.long pop, mmap
end

word mmapFd "mmap-fd" # fd len -- addr
	.long push, MapShared, ProtRead, pop, mmap
end

word bufferZFile "buffer-zfile" # zstr -- addr len fd
	.long ReadOnly, zopen, stash
	.long dup, fileLength, stash, mmapFd
	.long pop, pop
end

word bufferFile "buffer-file"  # str -- addr len fd
	.long one, cell, add
	.long bufferZFile
end


# Dictionary lookup ###################################

.section .data
.align CELL_SIZE, 0
wordbuffer:
	.long 0
wordbuffer_text:
	.space WORD_BUFFER_SIZE
end_wordbuffer:
	.long 0 // space for padding

word notFoundHandler "not-found-handler"  # str
	.long WarningColour, colour
	.long puts, NoColour, colour, NotFound, puts, nl
.long error

	
# : find  @ dup ?[ 2dup label streq ?[ nip dup cfa swap behavior ;] find ;] ;
word find // str dict -- xt bh | str 0
	.long get, dup, zbr,(2f)
	.long over, over, label, strEq, zbr,(1f)
	.long nip, dup, cfa, swap, behaviour, return
1:	.long tc, find
2:
end

word lfa, ".lfa"  # entry -- addr
	.long LfaOffs, add
end
word cfa, ".cfa" // entry -- codeAddr
	.long CfaOffs, add
end
word bfa, ".bfa"
	.long BfaOffs, add
end
word pfa, ".pfa"
	.long PfaOffs, add
end

word label, ".label"  // entry -- str
	.long lfa, get
end
word behaviour, ".behaviour" 
	.long bfa, get
end
word cfaToLabel, ".cfa->.label"
	.long CfaOffs, sub
	.long label
end

word labelForVar, "label-for-var"
	.long one, cell, sub, cfaToLabel
end

word nl
	.long ten, putc
end

# Words that create words ############################

word header  # str --
	.long dpAlign
	.long here, push
	.long dictionary, get, storeinc  # compile link to current head of dict
	.long storeinc                   # compile label address
	.long quote, storeinc, storeinc  # store the default behaviour
	.long pop, dictionary, set       # store our new word in the dict
end

word define  #  str interp --
	.long swap, header, storeinc
end

word defdoes   # str --
	.long quote, dodoes, define, zero, storeinc  # behaviour field
end
word defword   # str -- 
	.long quote, do, define
end
word defconst  # val str -- 
	.long quote, doconst, define
end
word defvar    # val str --
	.long quote, dovar, define
end

word create
	.long word, keeps, defdoes
end
word does
	# This is subtle! pop gives us the address of the word after
	# does in the definition (and prevents subsequent code executing).
	# We put it in the link field of the word create has just made.
	.long pop, dictionary, get, pfa, set
end
word createConstant, "create-constant"  # val --
	.long word, keeps, defconst, storeinc
end
word createVariable, "create-variable"  # --
	.long word, keeps, defvar
	.long zero, storeinc
end
word createWord, "create-word"
	.long word, keeps, defword
end
word immed, "#immediate", call
	.long dictionary, get, bfa, quote, call, swap, set
end

word constantColon, "constant:"
	.long createConstant
end
word variableColon, "variable:"
	.long createVariable
end
word colon, ":"
	.long createWord
.long tc, compiler

word semicolon, ";", call
	.long compile,return
	.long trash  # return to the interpreter loop that called compiler
end

word mark
	.long here, zero, storeinc
end
word resolve
	.long here, swap, set
end

word if, "?[", call
	.long compile,zbr, mark
end
word endif, "]", call
	.long resolve
end
word case, "=[", call
	.long compile,over,  compile,eq,  compile,zbr,  mark
end
word endcase, ";]", call
	.long compile,return,  resolve
end

word welcome
	.long inChannel, get, isATTY, zbr,(1f)
	.long WelcomeMessage, puts
1:
end
word prompt
	.long inChannel, get, isATTY, zbr,(1f)
	.long nl, spc, putc, dsDepth, putn
	.long asc_comma, putc, rsDepth, putn
	.long promptText, get, puts
1:
end

word compile
	# read from the instruction stream and compile a call to it
	.long pop, getStep, storeinc, push
end

#: compiler ( -- ) word dictionary find dup ?[ call compiler ;]
#                  drop NotFoundException raise ;
word compiler
	.long word, dictionary, find
	.long dup, zbr,(1f), call, tc,compiler
1:	.long drop, NotFoundException,raise
end

#: interpreter ( -- ) prompt word dictionary 
#	find    ?[ call interpreter ;]
#	number  ?[ interpreter ;]
#	NotFoundException raise
word interpreter
	.long prompt, word, dictionary
	.long find,         zbr,(1f), call, tc,interpreter
1:	.long dup, number,  zbr,(2f), nip,  tc,interpreter
2:	.long drop, NotFoundException,raise
end


.section .rodata

constant DoAddr,      do
constant DoConstAddr, doconst
constant DoDoesAddr,  dodoes
constant WordBuffer, wordbuffer
constant CellShift CELL_SHIFT
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

variable ds0
variable rs0
variable dp0
variable dictPtr, ,"dict-ptr"
variable hld
variable base, 10

variable NotFoundException, notFoundHandler

string WelcomeMessage "Welcome to Cantilever\n\n\tType an expression in Reverse-Polish form \n\tterminated with [33m;[0m or [33m=[0m (to see a numeric result). \n\tIf you have rlwrap installed you can use tab-completion\n"
string byebye, "\n-- Toodle-pip!\n"
string TooLong, "Word too long: "
string NotFound, " is neither a dictionary word nor a recognised number\n"
string InvalidEsc, "Invalid escape char: "
string ErrorUnhandled, "Unhandled exception: "
string DefaultPrompt, " ok "

variable decimal_places, 0, "decimal-places"

variable promptText, str_DefaultPrompt, "prompt-text"
variable dictionary, link   # MUST BE LAST
