
# Logical and bitwise prims ##########################

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

prim depth
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

prim rdepth
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
	# TODO: should probably adjust DP too!
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


