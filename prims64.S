# Register allocation:
#   %rbx : Top of stack
#   %rsp : Data stack pointer
#   %rbp : Return stack pointer
#   %rsi : Instruction pointer
#   %rdi : Dictionary pointer

.set BASE_4_YEAR, 1461
.set LILIAN_CORRECTION, 6345

.macro next
	lodsq
	jmp *(%rax)
.endm

.macro end
	.quad endcol
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
next
# prim syscall3  # arg3 arg2 arg1 id -- result
# prim syscall6  # arg6 arg5 ... arg1 id -- result
# prim key   # -- c
# prim word  # -- str
# prim match "matches?" # n1 n2 -- n1 bool
# prim between "btw?"  # n lower upper -- bool



prim eq, "=" // a b -- bool
	pop %rax
	xor %rcx, %rcx
	cmp %rbx, %rax
	setne %cl
	dec %cl
	mov %rcx, %rbx
next
word neq, "<>" // a b -- bool
	.quad eq, not
next
# prim ge, ">="
next
# prim gt, ">"
next
# prim le, "<="
# prim lt, "<"

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
# prim min // int int -- int
# prim max
# prim umin // uint uint -- uint
# prim umax
# prim sumCells, "sum-cells"  # array count -- int

prim dspGet, "dsp@"
	push %rbx
	mov %rsp, %rbx
next
prim dspSet, "dsp!"
	# this is ugly, as ToS is stored in RBX
	lea -CELL_SIZE(%rbx), %rsp
	pop %rbx
next
# prim dsDepth, "ds-depth"

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
# prim frame
# prim unframe
# prim local, "$$"  # n -- addr
# prim locals  # n -- 
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
	andb $0xfc, %bl
next
# prim isAnonymous "is-anon?" # addr -- bool
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
# prim inline   # xt --
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
# prim copy, "copy" # from ncells to --
# prim keep  # addr len -- addr
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
	.quad _num_err, _num_done, _natural, _char_lit, _decimal, _time, _date
month_table:
	#      J    F   M   A   M   J   J    A    S    O    N    D
	.quad 306, 337, 0, 31, 61, 92, 122, 153, 184, 214, 245, 275

word number  #  str -- int bool
	.quad one, cell, add, znumber
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


constant zero, 0, "0"
constant one,  1, "1"
constant minus_one, -1 "-1"


variable rs0
variable ds0
variable argc
variable argv
variable argv0
variable decimal_places
