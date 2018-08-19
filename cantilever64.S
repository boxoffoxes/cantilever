#include <sys/syscall.h>
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
#include <sys/mman.h>
#else
#include <asm/mman.h>
#endif

# Register allocation:
#   %rbx : Top of stack
#   %rsp : Data stack pointer
#   %rbp : Return stack pointer
#   %rsi : Instruction pointer
#   %rdi : Dictionary pointer

#define JUMP(tgt) (tgt - .)
#define DATA .quad

.set HEAP_SIZE, 128*1024*1024  # 128 meg
.set SCRATCH_SIZE, 16*1024     # 16k
.set BUFFER_SIZE,  16*1024     # 16k
.set WORD_BUFFER_SIZE, 256
.set FLAG_TABLE_SIZE, (127-32) # non-space ASCII chars
.set CELL_BITS, 3
.set CELL_SIZE, (1<<CELL_BITS)
.set DS_SIZE, 4096
.set link, 0

.set BASE_4_YEAR, 1461
.set LILIAN_CORRECTION, 6345

#ifdef CANTILEVER_EXECUTION_TRACE
#define TRACE_CODE call _trace
#else
#define TRACE_CODE
#endif

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
.macro next
	lodsq
	jmp *(%rax)
.endm

.macro end
	DATA endcol
.endm

.macro pushrs reg
	lea -CELL_SIZE(%rbp), %rbp
	movq \reg, (%rbp)
.endm

.macro poprs reg
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


.section .data
constant HeapBaseAddr . "heap-base-addr"

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
	mov $0xd50d50, %rbx
	mov %rsp, var_ds0
	mov %rsp, %rbp
	sub $DS_SIZE, %rbp
	mov %rbp, var_rs0
	mov $cold_start, %rsi
next

.align CELL_SIZE
_fill_buffer:
	# ToS has been preserved before we were called
	mov $SYS_read, %rax
	mov var_inChannel, %rbx
	mov var_ioBuffer, %rcx
	mov %rcx, var_bufpos  // reset buffer position
	mov $BUFFER_SIZE, %rdx
	syscall
	test %rax, %rax
	jbe _eof
	add %rax, %rcx
	mov %rcx, var_bufend
	// fallthrough
.align CELL_SIZE, 0x90
_key:  # leaves result on ToS
	mov var_bufpos, %rdx
	cmp var_bufend, %rdx
	jae _fill_buffer
	movzbq (%rdx), %rbx
	inc %rdx
	mov %rdx, var_bufpos
ret

.align CELL_SIZE
_eof:
	mov var_ioBuffer, %rax
	mov %rax, var_bufend
	mov %rax, var_bufpos
	pop %rax   # _key return addr (we're using regular CPU call-ret)
	pop %rax   # _word return addr
	pop %rax   # the function that called _key or _word had already pushed ToS
	mov $_eof_wrap, %rsi
next

.align CELL_SIZE
_word:  // copy the next word into wordbuffer
	// skip whitespace
	call _key
	cmpb $' ', %bl
	jbe _word 
	// copy word
	mov $wordbuffer_text, %rdx
1:
	movb %bl, (%rdx)
	inc %rdx
	cmp $end_wordbuffer, %rdx
	jae 2f // buffer overflow!
	pushrs %rdx  // save our pointer
	call _key
	poprs %rdx   // ...and restore it
	cmpb $' ', %bl
	ja 1b
	movq $0, CELL_SIZE(%rdx)  // add two words of nulls after word
	//mov $0, 8(%edx)
	// populate the length field of the buffer
	movq $0, (%rdx)
	sub $wordbuffer_text, %rdx
	mov %rdx, wordbuffer
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
#ifndef CANTILEVER_TEST_HARNESS
.align CELL_SIZE
cold_start:
	DATA initialiseVM
#endif

.align CELL_SIZE
_error_wrap:
	DATA lit, 2, error

.align CELL_SIZE
_eof_wrap:
	DATA EndOfFile, raise, tailcall, reset


.align CELL_SIZE
do:
	pushrs %rsi
	lea CELL_SIZE(%rax), %rsi
next
.align CELL_SIZE
dovar:
	push %rbx
	lea CELL_SIZE(%rax), %rbx
next
.align CELL_SIZE
doconst:
	push %rbx
	mov CELL_SIZE(%rax), %rbx
next
.align CELL_SIZE
dodoes:
	push %rbx
	pushrs %rsi
	lea (2*CELL_SIZE)(%rax), %rbx
	mov CELL_SIZE(%rax), %rsi
next



prim syscall0  # id -- result
	mov %rbx, %rax
	syscall
	mov %rax, %rbx
next
prim syscall1  # arg id -- result
	mov %rdi, %r11
	mov %rbx, %rax
	pop %rdi
	syscall
	mov %rax, %rbx
	mov %r11, %rdi
next
prim syscall2  # arg2 arg1 id -- result
	mov %rdi, %r11
	mov %rsi, %r12
	mov %rbx, %rax
	pop %rdi
	pop %rsi
	syscall
	mov %rax, %rbx
	mov %r12, %rsi
	mov %r11, %rdi
next
prim syscall3  # arg3 arg2 arg1 id -- result
	mov %rdi, %r11
	mov %rsi, %r12
	mov %rbx, %rax
	pop %rdi
	pop %rsi
	pop %rdx
	syscall
	mov %rax, %rbx
	mov %r12, %rsi
	mov %r11, %rdi
next
prim syscall6  # arg6 arg5 ... arg1 id -- result
	mov %rdi, %r11
	mov %rsi, %r12
	mov %rbx, %rax
	pop %rdi
	pop %rsi
	pop %rdx
	pop %r10
	pop %r8
	pop %r9
	syscall
	mov %rax, %rbx
	mov %r12, %rsi
	mov %r11, %rdi
next
prim key   # -- c
	push %rbx
	call _key
next
prim word  # -- str
	push %rbx
	call _word
	mov $wordbuffer, %rbx
next
# prim match "matches?" # n1 n2 -- n1 bool
prim between "btw?"  # n lower upper -- 
	pop %rcx  # lower
	pop %rax  # n
	sub %rcx, %rbx  # upper-lower
	sub %rcx, %rax  # n-lower
	xor %rcx, %rcx  
	cmp %rbx, %rax
	seta %cl
	dec %rcx
	mov %rcx, %rbx
next



prim eq, "=" // a b -- bool
	pop %rax
	xor %rcx, %rcx
	cmp %rax, %rbx
	setne %cl
	dec %rcx
	mov %rcx, %rbx
next
word neq, "<>" // a b -- bool
	DATA eq, not
next
# prim ge, ">="
next
# prim gt, ">"
next
# prim le, "<="
prim lt, "<"
	pop %rax
	xor %rcx, %rcx
	cmp %rbx, %rax
	setge %cl
	dec %rcx
	mov %rcx, %rbx
next


prim and
	and (%rsp), %rbx
	pop %rax
next
prim or
	or (%rsp), %rbx
	pop %rax
next
prim xor
	xor (%rsp), %rbx
	pop %rax
next
prim not
	not %rbx
next

prim bool
	xor %rcx, %rcx
	test %rbx, %rbx
	setnz %cl
	dec %rcx
	mov %rcx, %rbx
next
prim lshift, "shift-up" // int n -- int
	mov %rbx, %rcx
	pop %rbx
	shl %cl, %rbx
next
prim rshift, "shift-down" // int n -- int
	mov %rbx, %rcx
	pop %rbx
	sar %cl, %rbx
next
prim mul, "*"  // int int -- int
	pop %rax
	imul %rbx
	mov %rax, %rbx
next
# prim mulDiv, "*/" // int int int -- int
prim udivmod, "/modu" # n d -- q r
	pop %rax
	xor %rdx, %rdx
	div %rbx
	push %rax
	mov %rdx, %rbx
next
prim divmod  "/mod" # n d -- q r
	pop %rax
	cqo
	idiv %rbx
	push %rax
	mov %rdx, %rbx
next
prim sub, "-" // int int -- int
	sub %rbx, (%rsp)
	pop %rbx
next
prim add, "+" // int int -- int
	add (%rsp), %rbx
	pop %rax
next
prim neg
	neg %rbx
next
prim inc, "1+"
	inc %rbx
next
prim dec, "1-"
	dec %rbx
next
prim double, "2*"
	shl $1, %rbx
next
prim min // int int -- int
	pop %rax
	cmp %rax, %rbx
	cmovg %rax, %rbx
next
prim max
	pop %rax
	cmp %rax, %rbx
	cmovl %rax, %rbx
next
prim umin // uint uint -- uint
	pop %rax
	cmp %rax, %rbx
	cmova %rax, %rbx
next
prim umax
	pop %rax
	cmp %rax, %rbx
	cmovb %rax, %rbx
next
# prim sumCells, "sum-cells"  # array count -- int
	# sumCells is not used

prim dspGet, "dsp@"
	push %rbx
	mov %rsp, %rbx
next
prim dspSet, "dsp!"
	# this is ugly, as ToS is stored in RBX
	lea -CELL_SIZE(%rbx), %rsp
	pop %rbx
next
prim dsDepth, "ds-depth"
	push %rbx
	mov var_ds0, %rbx
	sub %rsp, %rbx
	sar $CELL_BITS, %rbx
	dec %rbx  # because of the sentinel
next

prim drop
	pop %rbx
next
prim nip
	pop %rax
next
prim swap  // a b -- b a
	xchg %rbx, (%rsp)
next
prim dup
	push %rbx
next
prim over
	push %rbx
	mov CELL_SIZE(%rsp), %rbx
next
prim rspGet, "rsp@"
	push %rbx
	mov %rbp, %rbx
next
prim rspSet, "rsp!"
	mov %rbp, %rbx
	pop %rax
next
prim rsDepth, "rs-depth"
	push %rbx
	mov var_rs0, %rbx
	sub %rbp, %rbx
	sar $CELL_BITS, %rbx
next
prim push
	pushrs %rbx
	pop %rbx
next
prim peek
	push %rbx
	mov (%rbp), %rbx
next
prim pop
	push %rbx
	poprs %rbx
next
prim stash
	pushrs %rbx
next
prim trash
	poprs %rax
next
# prim wlen  #  addr -- n-cells
	# wlen is not used
# prim frame
	# frame is not used
prim unframe
	mov curframe, %rbp
	poprs %rax
	mov %rax, curframe
next
prim local, "$$"  # n -- addr
	not %rbx
	mov curframe, %rax
	lea (%rax, %rbx, CELL_SIZE), %rbx
next
prim locals  # n -- 
	mov curframe, %rax
	pushrs %rax
	mov %rbp, curframe
	mov %rbp, %rcx
1:	test %rcx, %rcx
	jz 2f
	pop %rax
	dec %rcx
	pushrs %rax
	jmp 1b
2:	pushrs $do_unframe
	pop %rbx
next
do_unframe:
	DATA unframe, return
prim incVar "inc-var"
	incq (%rbx)
	pop %rbx
next
prim decVar "dec-var"
	decq (%rbx)
next
prim ipGet, "ip@"
	push %rbx
	mov %rsi, %rbx
next
prim get, "@"
	mov (%rbx), %rbx
next
prim getByte, "@b"
	movzbq (%rbx), %rbx
next
prim getStep "@+"  # addr -- addr' n
	lea CELL_SIZE(%rbx), %rax
	mov (%rbx), %rbx
	push %rax
next
prim set "!" # int addr -- 
	pop (%rbx)
	pop %rbx
next
prim setByte "!b" # int addr -- 
	pop %rax
	movb %al, (%rbx)
	pop %rbx
next
prim here
prim dpGet, "dp@"
	push %rbx
	mov %rdi, %rbx
next
prim dpSet, "dp!"
	mov %rbx, %rdi
	pop %rbx
next
prim dpAlign, "align-dp"
	align_dp
next
prim storeinc, ","
	mov %rbx, %rax
	stosq
	pop %rbx
next
prim storebinc, ",b"
	mov %rbx, %rax
	stosb
	pop %rbx
next
prim cell
	shl $CELL_BITS, %rbx
next
prim align // addr -- addr
	add $(CELL_SIZE-1), %rbx
	andb $0xf8, %bl
next
prim isAnonymous "is-anon?" # addr -- bool
	mov var_anonCodeAreaAddr, %rdx
	sub %rdx, %rbx
	xor %rdx, %rdx
	cmp $SCRATCH_SIZE, %rbx
	seta %dl
	dec %rdx
	mov %rdx, %rbx
next
prim endcol
prim return
	poprs %rsi
next
prim data  # -- addr
	push %rbx
	mov (%rsi), %rax
	lea CELL_SIZE(%rsi), %rbx
	lea CELL_SIZE(%rsi, %rax), %rsi
next
prim branch
	add (%rsi), %rsi
next
prim zbranch   #  bool -- 
	lodsq
	lea -CELL_SIZE(%rsi, %rax), %rax
	test %rbx, %rbx
	cmovz %rax, %rsi
	pop %rbx
next
prim tailcall, "tail:"
	mov (%rsi), %rsi
	lea CELL_SIZE(%rsi), %rsi
next
prim tailcallTOS, "tailcall-tos"
	lea CELL_SIZE(%rbx), %rsi
	pop %rbx
next
prim call  # xt --
	mov %rbx, %rax
	pop %rbx
	jmp *(%rax)
next
prim inline   # xt --
	mov -CELL_SIZE(%rdi), %rax
	cmp $quote, %rax
	je prim_storeinc  # don't inline quoted words!
	mov %rbx, %rax
	pop %rbx
	mov %rsi, %rdx
	lea 4(%rax), %rsi
1:
	lodsq
	cmp $endcol, %rax
	je 2f
	stosq
	jmp 1b
2:
	mov %rdx, %rsi
next
prim lit
prim quote, "'"
	push %rbx
	lodsq
	mov %rax, %rbx
next
prim copyBytes, "copy-bytes"  # from nbytes to --
	pop %rcx
	pop %r10
	xchg %rdi, %rbx
	xchg %rsi, %r10
	rep movsb
	mov %r10, %rsi
	mov %rbx, %rdi
	pop %rbx
next
prim copy, "copy" # from ncells to --
	pop %rcx
	pop %r10
	xchg %rdi, %rbx
	xchg %rsi, %r10
	rep movsq
	mov %r10, %rsi
	mov %rbx, %rdi
	pop %rbx
next
prim keep  # addr len -- addr
	# move a temporary value len cells long from addr into the dictionary 
	align_dp
	mov %rsi, %rdx  # save IP
	mov %rbx, %rcx        # length in cells
	pop %rsi        # get source
	mov %rdi, %rbx       # push permanent address
	rep movsq
	mov %rdx, %rsi  # restore IP
next
# prim forget  # cfa -- 
prim strEq "s=" # sstr dstr -- bool
	xor %rdx, %rdx
	pop %r10
	mov %rbx, %r11
	xchg %rsi, %r10
	xchg %rdi, %r11
	mov (%rsi), %rcx
	lea 2(,%rcx, CELL_SIZE), %rcx
	repe cmpsl
	setnz %dl
	dec %rdx
	mov %rdx, %rbx
	mov %r10, %rsi
	mov %r11, %rdi
next
prim lenz  // zstr -- int
	xchg %rbx, %rdi
	xor %rcx, %rcx
	dec %rcx
	xor %rax, %rax
	repne scasb
	inc %rcx
	not %rcx
	mov %rbx, %rdi
	mov %rcx, %rbx
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
	DATA _num_err, _num_done, _natural, _char_lit, _decimal, _time, _date
month_table:
	#      J    F   M   A   M   J   J    A    S    O    N    D
	DATA 306, 337, 0, 31, 61, 92, 122, 153, 184, 214, 245, 275

word number  #  str -- int bool
	DATA one, cell, add, znumber
end


.section .text
prim znumber  # zstr -- int bool
	# see if zstr conforms to one of the supported 
	# number formats: 123 -123 123.456 12:34:56 2012-12-31
	xor %rax, %rax
	xor %rdx, %rdx
	pushrs %rsi
	mov %rbx, %rsi  # zstr in %esi
	# check for negative number
	movb (%rsi), %al
	cmpb $'-', %al
	sete %al
	add %rax, %rsi  # increment zstr if negative
	push %rax   # 1 if neg, 0 if pos
	mov $jump_table, %rbx
	xor %rax, %rax  # %rax is accumulator.

.align CELL_SIZE
_natural:
	xor %rcx, %rcx
1:
	digit (%rsi), %dl, 2f
	times_ten %rcx
	add %rdx, %rcx
	inc %rsi
	jmp 1b
2:
	add %rcx, %rax

.align CELL_SIZE
_choose_handler:
	# select handler based on first non-digit
	movb (%rsi), %dl
	cmp $':', %dl
	ja _num_err  # not a supported number format
	mov $number_char_class, %rcx
	movzbq (%rcx, %rdx), %rcx
	mov (%rbx, %rcx, CELL_SIZE), %rcx
	jmp *%rcx

.align CELL_SIZE
_decimal:
	inc %rsi
	mov var_decimal_places, %rcx
	test %rcx, %rcx
	jz 3f
1:	
	mov (%rsi), %dl
	test %dl, %dl
	jz 2f
	sub $'0', %dl
	cmp $9, %dl
	ja _num_err
	inc %rsi
2:
	times_ten %rax
	add %rdx, %rax
	loop 1b
3:
	movb (%rsi), %dl
	test %dl, %dl
	jz _num_done  # exactly the right number of decimals
	inc %rsi
	jmp 3b

.align CELL_SIZE
_char_lit:
	inc %rsi
	test %rax, %rax
	jnz _num_err
	mov (%rsi), %al
	jmp _num_done

.align CELL_SIZE
_time:
	inc %rsi
	times_60 %rax
	jmp _natural
.align CELL_SIZE
_date:
	inc %rsi
#ifdef CANTILEVER_CHEAP_DATE
	# Use a date format useless for anything
	# but comparison ( YYYY x 10000 + MM x 100 + DD )
	times_ten %rax
	times_ten %rax
	jmp _natural
#else
	# We use Lilian Date, which is a count of days since the 
	# start of the Gregorian calendar, where 15 Oct 1582 is 1 (_not_ 0!)
	# However, because our algorithm uses unsigned arithmetic for parsing
	# speed, dates before 1st March 1600 will be incorrect!

	# first calculate year offset from 1600
	sub $1600, %rax
	push %rax  # no of years
	xor %rdx, %rdx
	xor %rax, %rax

_month:
	mov (%rsi), %dl
	cmp $'-', %dl
	je 2f
	sub $'0', %dl
	cmp $9, %dl
	ja _num_err
	inc %rsi
	times_ten %rax
	add %rdx, %rax
	jmp _month
2:
	# calculate number of days using month_table table above, based on
	# formula from  <http://christophe.lavarenne.free.fr/tagnumen.html>
	inc %rsi
	cmp $12, %rax
	ja _num_err  # month>12? I don't think so!
	cmp $3, %rax
	setb %dl     #  %dl = 1 if jan or feb, 0 otherwise
	sub %rdx, (%rsp)  # we count years from 1st March, so yr-1 for jan or feb
	dec %rax     # month->index (0-11)
	mov $month_table, %rcx
	mov (%rcx, %rax, CELL_SIZE), %rax   # days to start of month
	push %rax
	xor %rax, %rax
	xor %rdx, %rdx
_day:
	mov (%rsi), %dl
	cmp $0, %dl
	je 3f
	sub $'0', %dl
	cmp $9, %dl
	ja _num_err
	inc %rsi
	times_ten %rax
	add %rdx, %rax
	jmp _day
3:
	pop %rcx        # days to start of month from March
	add %rax, %rcx  # total days from start of year (-mm-dd portion)
	pop %rax        # remember our year from earlier?
	push %rcx
	push %rax

	# calculate missed century leap-days...
	mov $100, %rcx
	div %rcx      # divide %eax by 100 for centuries
	mov %rax, %rbx	
	shr $2, %rax    # divide 100 yr missed-leaps by 4 for 400 year leaps
	sub %rbx, %rax
	# convert years to days
	xchg (%rsp), %rax
	mov $BASE_4_YEAR, %rcx   # (1461 = 365.25 * 4) I love fixed-point. A base-4 fxp saves us a div!)
	mul %rcx
	shr $2, %rax   # convert back from base-4 fix-point
	pop %rdx
	pop %rcx
	add %rdx, %rax
	add %rcx, %rax
	add $LILIAN_CORRECTION, %rax  # Convert to Lilian date
	jmp _num_done
#endif

.align CELL_SIZE
_num_err:
	poprs %rsi
	movl $0, (%rsp)  # over-write sign
	mov $0, %rbx
next

.align CELL_SIZE
_num_done:
	# apply negative from earlier
	pop %rdx
	test %rdx, %rdx
	jz 4f
	neg %rax
4:
	poprs %rsi
	push %rax
	mov $-1, %rbx
next
prim length # list -- int 
	xor %rcx, %rcx
1:	mov (%rbx), %rbx
	test %rbx, %rbx
	loopnz 1b
2:	not %rcx
	mov %rcx, %rbx
next

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

string DefaultPrompt, " ok "
string byebye, "\n-- Toodle-pip!\n"
string TooLong, "Word too long: "
string ErrorUnhandled, "Unhandled exception: "
string ErrorColour,   "[31m"
string WarningColour, "[33m"
string NoColour,      "[0m"
string NotFound, " is neither a dictionary word nor a recognised number\n"
string WelcomeMessage "Welcome to Cantilever\n\n\tType an expression in Reverse-Polish form \n\tterminated with [33m;[0m or [33m=[0m (to see a numeric result). \n\tIf you have rlwrap installed you can use tab-completion\n"


constant zero, 0, "0"
constant one,  1, "1"
constant minus_one, -1 "-1"
constant DoAddr,      do
constant DoConstAddr, doconst
constant DoDoesAddr,  dodoes
constant WordBuffer, wordbuffer
constant CellBits, CELL_BITS
constant CellSize, CELL_SIZE

# System call numbers
constant SysExit,  SYS_exit
constant SysRead,  SYS_read
constant SysWrite, SYS_write
constant SysOpen,  SYS_open
constant SysClose, SYS_close
constant SysStat,  SYS_fstat
constant SysMmap,  SYS_mmap
constant SysMunmap, SYS_munmap
constant SysBrk,   SYS_brk
constant SysIOCtl, SYS_ioctl
constant SysTime,  SYS_time
constant SysNanosleep, SYS_nanosleep

#ifdef CANTILEVER_CHEAP_DATE
constant CheapDate, -1
#else
constant CheapDate, 0
#endif
constant Base4Year, BASE_4_YEAR
constant LilianCorrection, LILIAN_CORRECTION

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


variable NotFoundException, notFoundHandler

variable rs0
variable ds0
variable argc
variable argv
variable argv0

variable ioBuffer, , "io-buffer"
variable bufpos
variable bufend
variable scratchpadAddr, , "scratchpad-addr"
variable anonCodeAreaAddr, , "anon-code-area-addr"
variable flagTableAddr
variable dictPtr, ,"dict-ptr"
variable interpreter, interpret

variable promptText, str_DefaultPrompt, "prompt-text"
variable decimal_places
variable curframe
variable dictionary, link   # MUST BE LAST
