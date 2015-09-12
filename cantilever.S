#include <asm/unistd.h>
#include <asm/mman.h>

# Warnings: be very careful about using push 
# and pop in non-Forth functions -- there's a
# return address on top of the stack!

# Useful values ######################################
.set HEAP_SIZE, 128*1024*1024  # 128 meg
.set SCRATCH_SIZE, 16*1024     # 16k
.set BUFFER_SIZE,  16*1024     #  4k
.set WORD_BUFFER_SIZE, 256
.set CELL_BITS, 2
.set CELL_SIZE, (1<<CELL_BITS)
.set DS_SIZE, (64*CELL_SIZE)
.set link, 0
.set mlink, 0

#define BASE_4_YEAR 1461
#define LILIAN_CORRECTION 6345

######################################################
# macros                                             #
######################################################

#define JUMP(tgt) (tgt - .)
#ifdef CANTILEVER_PROFILE
#define PROFILING_CODE \
	mov -4(%eax), %edx ; \
	inc %edx ; \
	mov %edx, -4(%eax) ;
#else
#define PROFILING_CODE
#endif

# Structural macros ##################################

.macro header label, name, dict=link
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
	.long \dict
	.long dict_label_\label
.set \dict, dict_\label
.endm

.macro prim label, name, dict=link
	header \label, "\name", \dict
#ifdef CANTILEVER_PROFILE
	.long 0
#else
	.long 1 // length is always 1 for prims
#endif
\label:
	.long prim_\label
	.section .text
	.align CELL_SIZE
prim_\label:
#ifdef CANTILEVER_PROFILE
	mov -4(%eax), %edx
	inc %edx
	mov %edx, -4(%eax)
#endif
.endm

.macro word label, name, dict=link, handler=do
	header \label, "\name", \dict
	.long 0
\label:
	.long \handler
word_\label:
.endm

.macro constant label, val, name
	word \label, "\name", , doconst
	# push $\val
	# next
	.int \val
99999:
.endm

.macro variable label, val=0, name
	constant \label, var_\label, "\name"
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
	99999:
.endm

.macro string_len_in_cells reg
	shr $CELL_BITS, \reg
	inc \reg
.endm

.macro pushrs reg
	lea -CELL_SIZE(%ebp), %ebp
	mov \reg, (%ebp)
.endm

.macro poprs, reg
	mov (%ebp), \reg
	lea CELL_SIZE(%ebp), %ebp
.endm

.macro align_dp
	add $3, %edi
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
constant heapBaseAddr . "heap-base-addr"


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

.align CELL_SIZE
_fill_buffer:
	mov $__NR_read, %eax
	mov var_inChannel, %ebx
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
_key:
	mov var_bufpos, %ebx
	cmp var_bufend, %ebx
	jae _fill_buffer
	movzbl (%ebx), %eax
	inc %ebx
	mov %ebx, var_bufpos
ret

.align CELL_SIZE
_eof:
	mov var_ioBuffer, %eax
	mov %eax, var_bufend
	mov %eax, var_bufpos
	mov $_eof_wrap, %esi
next

.align CELL_SIZE
_word:  // copy the next word into wordbuffer
	// skip whitespace
	call _key
	cmpb $' ', %al
	jbe _word 
	// copy word
	mov $wordbuffer_text, %edx
1:
	movb %al, (%edx)
	inc %edx
	cmpl $end_wordbuffer, %edx
	jae 2f // buffer overflow!
	pushrs %edx  // save our pointer
	call _key
	poprs %edx   // ...and restore it
	cmpb $' ', %al
	ja 1b
	movl $0, CELL_SIZE(%edx)  // add two words of nulls after word
	//mov $0, 8(%edx)
	// populate the length field of the buffer
	movl $0, (%edx)
	sub $wordbuffer_text, %edx
	mov %edx, wordbuffer
ret
2:
	// TODO: should skip the rest of the long word too...
	movl $0x202e2e2e, wordbuffer+12 // truncate the long word with "... "
	movl $12, wordbuffer
	movl $wordbuffer, (%esp)  // over-write our return address
	push $str_TooLong
	# handle error. Was function, but used only here
	mov $_error_wrap, %esi
next

# Wrappers for calling words from code ###############
.align CELL_SIZE
cold_start:
	.long initialiseVM, reset

.align CELL_SIZE
_error_wrap:
	.long lit, 2, compileError

.align CELL_SIZE
_eof_wrap:
	.long EndOfFile, raise, reset

######################################################
# Forth-style code words                             #
######################################################

# codewords ##########################################

.align CELL_SIZE
do:
	pushrs %esi  // save return address
	lea 4(%eax), %esi
	PROFILING_CODE
next

.align CELL_SIZE
doconst:
	push 4(%eax)
	PROFILING_CODE
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
# dodoes:
# 	# we don't pushrs; so we're tail-calling behav
# 	# pushrs %esi
# 	mov 4(%eax), %esi
# 	lea 8(%eax), %eax
# 	lea 4(%esi), %esi
# 	push %eax
# 	PROFILING_CODE
# next

# dodoes:
	# pushrs %esi
	# lea 4(%eax), %esi
	# lea 12(%eax), %eax
	# push %eax
# next

dodoes:
	# dodoes is effectively a tail-call. We jump directly to the 
	# code field of behav instead of calling next so that we 
	# leave the instruction pointer in %esi unmodified
	lea 8(%eax), %edx
	mov 4(%eax), %eax
	push %edx
	PROFILING_CODE
jmp *(%eax)



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

# Where we read our source code from
variable source, 0

# NOTE: values are octal!
constant ReadOnly,   0
constant WriteOnly,  01101
constant ReadWrite,  02202

prim key
	call _key
	push %eax
next

prim word  // -- str
	call _word
	// push the address and length
	push $wordbuffer
next

prim digit  // char -- int
	pop %eax
	cmpb $'9', %al
	jbe 1f
	andb $0xdf, %al // make letters upper-case
	cmpb $'A', %al
	jb 2f   // error
	subb $7, %al   // compact 
1:
	subb $'0', %al
next

# Logical prims ######################################

prim match "matches?" # n1 n2 -- n1 bool
	# semi-destructive equals for pattern matching
	pop %eax
	xor %ecx, %ecx
	cmpl (%esp), %eax
	setne %cl
	dec %ecx
	push %ecx
next

prim between "between?"  # n lower upper -- bool
	pop %edx  # upper
	pop %ecx  # lower
	pop %eax  # n
	sub %ecx, %edx
	sub %ecx, %eax
	xor %ecx, %ecx
	cmp %edx, %eax
	seta %cl
	dec %ecx
	push %ecx
next

prim eq, "eq?" // a b -- bool
	pop %eax
	pop %edx
	xor %ecx, %ecx
	cmpl %eax, %edx
	setne %cl
	dec %ecx
	push %ecx
next

prim neq, "ne?" // a b -- bool
	pop %eax
	pop %edx
	xor %ecx, %ecx
	cmpl %eax, %edx
	sete %cl
	dec %ecx
	push %ecx
next

prim ge, "ge?"
	pop %eax
	pop %edx
	xor %ecx, %ecx
	cmpl %eax, %edx
	setl %cl
	dec %ecx
	push %ecx
next

prim gt, "gt?"
	pop %eax
	pop %edx
	xor %ecx, %ecx
	cmpl %eax, %edx
	setle %cl
	dec %ecx
	push %ecx
next

prim le, "le?"
	pop %eax
	pop %edx
	xor %ecx, %ecx
	cmpl %eax, %edx
	setg %cl
	dec %ecx
	push %ecx
next

prim lt, "lt?"
	pop %eax
	pop %edx
	xor %ecx, %ecx
	cmpl %eax, %edx
	setge %cl
	dec %ecx
	push %ecx
next

prim ltu, "ltu?"
	pop %eax
	pop %edx
	xor %ecx, %ecx
	cmpl %eax, %edx
	setae %cl
	dec %ecx
	push %ecx
next


# Arithmetic prims ###################################

constant zero, 0, "0"
constant one,  1, "1"
constant minus_one, -1 "-1"

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

prim udivmod  # int int -- int int
	pop %ebx
	pop %eax
	xor %edx, %edx
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

prim sub, "-" // int int -- int
	pop %eax
	sub %eax, (%esp)
next

prim add, "+" // int int -- int
	pop %eax
	add %eax, (%esp)
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

# Bitwise prims ######################################

prim lshift, "bits-up" // int n -- int
	pop %ecx
	pop %eax
	shl %cl, %eax
	push %eax
next

prim rshift, "bits-down" // int n -- int
	pop %ecx
	pop %eax
	sar %cl, %eax
	push %eax
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

prim not
	pop %eax
	not %eax
	push %eax
next

prim bool
	pop %eax
	xor %edx, %edx
	test %eax, %eax
	setz %dl
	dec %edx
	push %edx
next

# Stack manipulation prims ###########################
prim dspGet, "dsp@"
	push %esp
next

prim dspSet, "dsp!"
	pop %esp
next

prim dsDepth, "ds-depth"
	mov var_ds0, %eax
	sub %esp, %eax
	sar $CELL_BITS, %eax
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
prim rsp, "rsp@"
	push %ebp
next

prim rspSet, "rsp!"
	pop %ebp
next

prim rsDepth, "rs-depth"
	mov var_rs0, %eax
	sub %ebp, %eax
	sar $CELL_BITS, %eax
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

# Instruction pointer ################################

prim ip, "ip@"
	push %esi
next

# Memory access ######################################

prim get, "@"
	pop %eax
	push (%eax)
next
prim getByte, "@b"
	xor %eax, %eax
	pop %edx
	mov (%edx), %al
	push %eax
next

prim set "!" // int addr -- 
	pop %eax
	pop %edx
	mov %edx, (%eax)
next
prim setByte "!b" // int addr -- 
	pop %eax
	pop %edx
	mov %dl, (%eax)
next

prim here
	push %edi
next

prim dpSet, "dp!"
	pop %edi
next

prim dpAlign
	align_dp
next

prim storeinc, ","
	pop %eax
	stosl
next

prim storecinc, ",c"
	pop %eax
	stosb
next

prim cell
	shll $CELL_BITS, (%esp)
next

prim align // addr -- addr
	// align to cell boundary
	pop %eax
	add $3, %eax
	andb $0xfc, %al
	push %eax
next

prim isAnonymous "is-anon?" # addr -- bool
	# is addr in the anonymous area?
	mov var_anonCodeAreaAddr, %edx
	pop %eax
	sub %edx, %eax
	xor %edx, %edx
	cmp $SCRATCH_SIZE, %eax
	seta %dl
	dec %edx
	push %edx
next

# Flow control #######################################

prim return
	poprs %esi
next

prim branch
	add (%esi), %esi
next

prim zbranch 
	lodsl                  # distance to branch
	pop %edx               # boolean to test
	xor %ecx, %ecx
	sub $CELL_SIZE, %eax   # because lodsl increments %esi
	test %edx, %edx        # bool is zero?
	setnz %cl
	dec %ecx
	and %ecx, %eax         # %ecx is 0 if %edx is non-zero
	add %eax, %esi
next

prim tailcall, "tail:"
	mov (%esi), %esi
	lea 4(%esi), %esi
next

prim call
	pop %eax
	jmp *(%eax)
next

# Numeric literals ###################################

prim lit
	lodsl
	push %eax
next

prim quote, "'"
	lodsl
	push %eax
next

# String handling prims ##############################

prim copys  # str addr -- str'
	mov %edi, %edx  # save DP
	pushrs %esi      # save IP
	pop %edi
	pop %esi
	push %edi # push addr as final string location
	lodsl
	mov %eax, %ecx
	stosl
	string_len_in_cells %ecx
	rep movsl
	poprs %esi
	mov %edx, %edi
next

prim keeps  // tmpStr -- str
	// make a temporary string permanent
	// align DP
	align_dp
	mov %esi, %edx
	pop %esi
	push %edi  // push permanent string address
	lodsl  // length into %eax
	mov %eax, %ecx
	stosl  // save length to dest
	string_len_in_cells %ecx
	repe movsl
	mov %edx, %esi
next

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

prim number  # str -- int bool
	# see if zstr conforms to one of the supported 
	# number formats: 123 -123 123.456 12:34:56 2012-12-31
	xor %eax, %eax
	xor %edx, %edx
	pushrs %esi
	pop %esi  # zstr in %esi
	add $4, %esi
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
	# Because of the algorithm used, dates before 1st March 1600 
	# will be incorrect!

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


# List prims #########################################

prim length # list -- int 
	xor %ecx, %ecx
	pop %eax
1:
	mov (%eax), %eax
	test %eax, %eax
	loopnz 1b
2:
	not %ecx
	push %ecx
next



######################################################
# Forth-style non-primitive words                    #
######################################################

# Startup code #######################################

word initialiseVM
	# initialise the dictionary pointer
	.long getBrkAddr, dictPtr, set
	# allocate default heap
	.long lit, HEAP_SIZE, setHeapSize
	# create scratchpad
	.long lit, SCRATCH_SIZE, buffer, scratchpadAddr, set
	# create anon code area
	.long lit, SCRATCH_SIZE, buffer, anonCodeAreaAddr, set
	# set up an IO buffer
	.long lit, BUFFER_SIZE, buffer, ioBuffer, set
	# are there any commandline args...
	.long argc, get, dec, zbranch, JUMP(1f)
	# ...yes, then open the first one
	#.long argv, get, one, cell, add, get
	.long handleArgs
1:
	.long reset
end

word reset
1:
	.long rs0, get, rspSet 
	.long anonymousCode
	.long prompt
	.long interpreter, get, call
	.long tailcall, reset
end

word handleArgs
	.long quote, handleArgs, handles, EndOfFile
	.long nextArg, dup, zbranch, JUMP(1f)
	.long dup, zopenIn, reset
1:
	.long stdin, inChannel, set
	.long quote, exit0, handles, EndOfFile
	.long welcome
end

word nextArg
	.long argv, get, one, cell, add
	.long dup, argv, set
	.long get
end


word anonymousCode
	.long anonCodeAreaAddr, get, dpSet
	.long quote, do, storeinc
end
word compiling
	.long go    # evaluate any args (e.g. for constant: or create)
	.long dictPtr, get, dpSet
end
word doneCompiling, "done-compiling"
	.long here, dictPtr, set
	.long anonymousCode
end
word compileSemi "compile-;"
	.long quote, return, storeinc
	.long here, isAnonymous, zbranch, JUMP(1f)
	.long tailcall, go
1:
	.long doneCompiling
end
word semiColon, ";", mlink
	.long tailcall, compileSemi
end
word go
	.long quote, return, storeinc
	.long anonCodeAreaAddr, get, call
	.long anonymousCode
	.long prompt
end




constant spc, 32, "'spc'"

word scanz # zstr pred -- addr
	.long push, dec
1:
	.long inc, dup, getByte
	.long dup, zbranch, JUMP(2f)  # reached the NULL terminator at the end of the string
	.long peek, call, zbranch, JUMP(1b)
	.long dup
2:
	.long nip, trash
end

word scan  # pred -- c
	# read chars from in-channel until pred returns true
	.long stash  # leave pred on the stack to give drop something to work on
1:
	.long drop, key, dup, peek, call
	.long zbranch, JUMP(1b)
	.long trash
end

word _skipSpaces
	.long spc, gt
end

word wordBuffer, "word-buffer"
	.long WordBuffer
end

# Exception handling #################################

word handles
	# usage: ' fun handles Exception
	#    set fun as handler for Exception
	.long peek, get, call, set
	.long pop, one, cell, add
	.long push
end

word raise
	.long dup, get
	.long dup, zbranch, JUMP(1f)
	.long nip, call, return
1:
	.long drop, labelForVar
	.long ErrorUnhandled, lit, 2, error
end

variable EndOfFile, exit0


# Unfiled ############################################

word digit_to_char, "digit-to-char" # n -- c
	.long dup 
	.long zero, lit, 9, between, zbranch, JUMP(1f)
	.long lit, '0', add
	.long branch, JUMP(2f)
1:
	.long lit, 'a'-10, add
2:
end
word decompose  # n base -- 0 c ... 
	.long push, zero, swap
1:
	.long peek, udivmod, digit_to_char, swap
	.long dup, zbranch, JUMP(2f), branch, JUMP(1b)
2:
	.long drop, trash
end
word putsign     # n -- u
	.long dup, lit, (1<<(CELL_SIZE*8-1)), and, zbranch, JUMP(1f)
	.long neg, lit, '-', putc
1:
end
word putnumber   # n base --
	.long decompose
3:
	.long putc, dup, zbranch, JUMP(4f), branch, JUMP(3b)
4:
	.long drop
end

word setBrkAddr "set-brk-addr"  # addr -- addr
	.long SysBrk, syscall1
end
word getBrkAddr, "get-brk-addr"  #  -- addr
	.long zero, setBrkAddr
end
word getHeapSize "get-heap-size"  # -- n
	.long getBrkAddr, heapBaseAddr, sub
end

# Todo: error handling on the following two functions
word setHeapSize "set-heap-size"  # n --
	.long heapBaseAddr, add, setBrkAddr, drop
end
word growHeap "grow-heap"  # n --
	.long getBrkAddr, add, setBrkAddr, drop
end

word exit0, "0-exit"
	.long zero, exit
end

word labelForVar, "label-for-var"
	.long lit, 4, cell, sub, get
end

word exit #  n -- 
	.long SysExit, syscall1
end

word bye, , mlink
	.long byebye, puts, nl
	.long zero, exit
end

word zopen   # zstr mode -- fh
	# syscall3 requires arg order: perms mode zstr callid
	.long swap, push, push
	.long lit, 0666, pop, pop
	.long SysOpen, syscall3
	.long dup, zero, lt, zbranch, JUMP(1f)
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

word closeOut
	.long outChannel, get, close
	.long stdout, outChannel, set
end
word closeIn
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
	.long zero, lt, zbranch, JUMP(1f)
	.long CouldNotStatFile, raise
1:
	.long pop
end

word st_size ".st_size"
	.long lit, 5, cell, add
end

word fileLength  "file-length" # fd -- len
	.long statFD, st_size, get
end

constant TCGETS, 0x00005401
word isATTY "is-a-tty?"  # fd -- bool
	.long push, scratchpadAddr, get, TCGETS, pop, SysIOCtl, syscall3
	.long zero, eq
end

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
	.long dup, lit, -200, minus_one, between, zbranch, JUMP(1f)
	.long MmapFailed, raise
1:
end
word munmap  # len addr -- 
	.long SysMunmap, syscall2
	.long drop  # todo: error handling
end

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

word incVar "inc-var"
	.long stash, get, inc, pop, set
end
word decVar "dec-var"
	.long stash, get, dec, pop, set
end


.section .data
.align CELL_SIZE, 0
wordbuffer:
	.long 0
wordbuffer_text:
	.space WORD_BUFFER_SIZE
end_wordbuffer:
	.long 0 // space for padding


variable _iterFunc

word search // S list (entry -> bool) -- T ?entry
	// todo: borked
	.long _iterFunc, set, push
1:
	.long pop, get, stash
	.long zbranch, JUMP(2f)
	.long peek, _iterFunc, get, call
	.long zbranch, JUMP(1b)  # not found, Try next
2:
	.long pop
	// .long lit, 32, putc, dup, putx, nl
end

word each  # dict fun -- 
	.long push
1:
	.long get
	.long dup, zbranch, JUMP(2f)
	.long peek, over, push, call
	.long pop
	.long branch, JUMP(1b)
2:
	.long trash, drop
end


word find // str dict -- entry
	.long swap, push  # save str
1:
	.long get, dup, zbranch, JUMP(2f), dup, label
	.long peek, strEq
	.long zbranch, JUMP(1b)
2:
	.long trash
end

word lfa, ".lfa"  # entry -- addr
	.long lit, CELL_SIZE, add
end

variable ProfilingNotEnabled
#ifdef CANTILEVER_PROFILE
word xCount ".xcount"
	.long lit, 2 * CELL_SIZE, add
end
#else
word xCount ".xcount"
	.long ProfilingNotEnabled, raise
end
word dotLen, ".len"
	.long lit, 2 * CELL_SIZE, add
end
#endif

word cfa, ".cfa" // entry -- codeAddr
	.long lit, 3 * CELL_SIZE, add
end

word pfa, ".pfa"
	.long lit, 4 * CELL_SIZE, add
end

word label, ".label"  // entry -- str
	.long lfa, get
end

word warn  # zstr len -- 
	.long errChannel, get, write
end

word put   # zstr len --
	.long outChannel, get, write
end

word putc  # c --
	.long dspGet, one, put
	.long drop # drop on-stack buffer
end

word lens  # str -- int
	.long get
end

word putz # zstr --
	.long dup, lenz
	.long put
end

word puts #  nstr --  
	.long stash, one, cell, add
	.long pop, get, put
end

word warns # nstr --
	.long stash, one, cell, add
	.long pop, get, warn
end

word putn // n --
	.long putsign
	.long lit, 10
	.long putnumber
end

word putx // n --
	.long lit, 16
	.long putnumber
end

word clearBuffer
	.long ioBuffer, get
	.long bufend, set
end

// It should definitely stop parsing a file if one is being loaded


word error  // ... str n -- 
	.long ResetColour, puts, nl
	.long Error, puts
	.long stash
1:
	.long zbranch, JUMP(2f)
	.long puts // error message
	.long ResetColour, puts
	.long pop, dec, stash
	.long branch, JUMP(1b)
2:
	.long trash, nl   // newline
	.long clearBuffer
	.long errorHandler, get, call    // this should never return
.long reset    // but this is here just in case

word fatalError, "fatal-error"
	.long ErrorWasFatal, puts
.long one, exit

word compileError, "compile-error"  # ... str n -- 
	.long inChannel, get, isATTY, not, zbranch, JUMP(1f)
	.long push, push, push
	.long currentDef, get, label
	.long InDefinition
	.long pop, pop, pop, inc, inc
	.long quote, fatalError, errorHandler, set
1:
.long error

word warning
	.long WarningPrefix, warns
	.long stash
1:
	.long zbranch, JUMP(2f)
	.long warns
	.long pop, dec, stash
	.long branch, JUMP(1b)
2:
	.long trash, ResetColour, puts, nl
end

word nl
	.long lit, '\n', putc
end

word compileWord, "compile-word" // cfa --
	.long here, lastCompiled, set
	.long storeinc
end

word compileLiteral, "compile-literal" // n --
	.long quote, lit, storeinc, storeinc
end

word report
	// This shouldn't be a word because that skews its view of 
	// the return stack. Unfortunately without refactoring we
	// can't call putn from a prim. :(
	.long dsReport, puts,   dsDepth, putn
	.long rsReport, puts,   rsDepth, putn
	.long nl
end


# Words that create words ############################

word header  // str dict --
	.long stash  # -- str dict / dict
	.long dpAlign
	.long here, push               # keep DP for later     -- str dict / dict dp
	.long get, storeinc          # compile link to to current head of dict   -- str  / dict dp
	.long storeinc                 # compile label address  -- / dict dp
	.long zero, storeinc         # compile length/xcount field   -- / dict dp
	.long peek, currentDef, set  # save our def as currentDef  -- / dict dp
	.long pop, pop, set          # set our address as new head of dict  -- /
end
word define  #  str dict interp --
	.long push, header, pop, storeinc
end


word defdoes   # str dict --
	.long quote, dodoes, define
end
word defword   # str dict -- 
	.long quote, do, define
end
word defconst  # val str dict -- 
	.long quote, doconst, define
end


word create  # behav --
	.long compiling
	.long word, keeps, words, defdoes, storeinc # , lit, return, storeinc
	.long doneCompiling
end
word createConstant, "create-constant"  # val --
	# constant: potentially needs to evaluate the preceding expression
	# so there's a value waiting
	.long compiling
	.long word, keeps, words, defconst, storeinc
	.long doneCompiling
end
word createVariable, "create-variable"  # --
	.long compiling
	.long word, keeps, words, defconst
	.long here, one, cell, add, storeinc
	.long zero, storeinc
	.long doneCompiling
end
word createWord, "create-word"
	.long compiling
	.long word, keeps, words, defword
end
word createMacro, "create-macro"
	.long compiling
	.long word, keeps, macros, defword
end


word constantColon, "constant:", mlink
	.long createConstant
end
word variableColon, "variable:", mlink
	.long createVariable
end
word colon, ":", mlink
	.long createWord
end
word macroColon, "macro:", mlink
	.long createMacro
end

word welcome
	.long inChannel, get, isATTY, zbranch, JUMP(0f)
	.long WelcomeMessage, puts
0:
end
word prompt
	.long inChannel, get, isATTY, zbranch, JUMP(0f)
	.long promptText, get, puts
0:
end

word findWord   # word -- entry
	.long words, find
end

word findMacro  # word -- entry
	.long macros, find
end

word wordOrNumber // word -- n bool
	.long stash, findWord, dup
	.long zbranch, JUMP(1f)
	// it's a word, get the CFA, clean RS and push -1
	.long trash, cfa, minus_one
	.long return
1:
	.long drop, peek, number
	.long zbranch, JUMP(2f)
	// it's a number, push 0
	.long trash, zero
	.long return
2:
	// error
	.long drop, pop
	.long NotFound, swap, lit, 2
	.long compileError
end

variable DataStackUnderflow
variable DataStackOverflow

word checkStacks "check-stacks"
	.long dspGet, ds0, get, gt, zbranch, JUMP(1f)
	.long DataStackUnderflow, raise
1:
	.long dspGet, rs0, get, le, zbranch, JUMP(2f)
	.long DataStackOverflow, raise
2:
end


word interpret
#	.long checkStacks
	.long word, stash, findMacro, dup
	.long zbranch, JUMP(1f)
	// it's a macro
	.long trash, cfa, call
	// .long branch, JUMP(0b)
	.long tailcall, interpret
1:
	// maybe it's a word or number...
	.long drop, pop, wordOrNumber  // errors handled here
	.long zbranch, JUMP(2f)
	.long compileWord
	.long tailcall, interpret
2:
	// if it's a number
	.long compileLiteral
	.long tailcall, interpret
end

word immed, "#", mlink
	.long word, wordOrNumber
	.long zbranch, JUMP(1f)
	.long call
1:
	// no special treatment needed for numnbers -- just leave on the stack
end

string dsReport "  ds: "
string rsReport "  rs: "

word hardReset "hard-reset"
	.long argv0, get, argv, set
	.long ds0, get, dspSet
	.long handleArgs, reset
end

.section .rodata

constant DoAddr,      do
constant DoConstAddr, doconst
constant DoDoesAddr,  dodoes
constant WordBuffer, wordbuffer
constant CellBits, CELL_BITS
constant CellSize, CELL_SIZE
#ifdef CANTILEVER_PROFILE
constant ProfilingEnabled, -1
#else
constant ProfilingEnabled, 0
#endif
#ifdef CANTILEVER_CHEAP_DATE
constant CheapDate, -1
#else
constant CheapDate, 0
constant Base4Year, BASE_4_YEAR
constant LilianCorrection, LILIAN_CORRECTION
#endif

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
variable lastCompiled, 0, "last-compiled"
variable errorHandler, reset, "error-handler"
variable dictPtr, ,"dict-ptr"

string WelcomeMessage "Welcome to Cantilever\n\n\tType an expression in Reverse-Polish form \n\tterminated with [33m;[0m or [33m=[0m (to see a numeric result). \n\tIf you have rlwrap installed you can use tab-completion\n"
string WarningPrefix, "--> Warning: [33m"
string Error, "==> [31mError. [33m"
string ResetColour, "[0m"
string InDefinition, "\n\tfollowing defintion of "
string At, "\" at [31m"
string byebye, "\n-- Toodle-pip!\n"
string TooLong, "Word too long: "
string NotFound, " not found"
string NumParse, "Invalid number: \""
string InvalidEsc, "Invalid escape char: "
# string FileOpenFailed, "Could not open file: "
string UnbalancedRSInBranch, "Unbalanced use of RS in one branch of pattern match at "
string ErrorWasFatal, "Error was fatal\n"
string ErrorUnhandled, "Unhandled exception: "
string DefaultPrompt, "\n ok: "

variable decimal_places, 0, "decimal-places"

variable main
variable promptText, str_DefaultPrompt, "prompt-text"
variable interpreter, interpret
variable macros, mlink
variable currentDef, words, "current-def"
variable words, link   # MUST BE LAST
