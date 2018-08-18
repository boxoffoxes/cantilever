# Register allocation:
#   %rbx : Top of stack
#   %rsp : Data stack pointer
#   %rbp : Return stack pointer
#   %rsi : Instruction pointer
#   %rdi : Dictionary pointer

.macro next
	lodsq
	jmp *(%rax)
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


# prim syscall0  # id -- result
prim syscall1  # arg id -- result
	mov %rdi, %r11
	mov %rbx, %rax
	pop %rdi
	syscall
	mov %rax, %rbx
	pop %rdi
	mov %r11, %rdi
next
# prim syscall2  # arg2 arg1 id -- result
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
# prim endcol
prim return
	poprs %rsi
next
# prim data  # -- addr
# prim branch
prim zbranch   #  bool -- 
	lodsq
	lea -CELL_SIZE(%rsi, %rax), %rax
	test %rbx, %rbx
	cmovz %rax, %rsi
	pop %rbx
next
# prim tailcall, "tail:"
# prim tailcallTOS, "tailcall-tos"
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
	xchg %rdi, %rbx
	mov %rsi, %r10
	pop %rcx
	pop %rsi
	rep movsb
	mov %r10, %rsi
	mov %rbx, %rdi
	pop %rbx
next
# prim copy, "copy" # from ncells to --
# prim keep  # addr len -- addr
# prim forget  # cfa -- 
# prim strEq "s=" # str str -- bool
# prim lenz  // zstr -- int
# prim znumber  # zstr -- int bool
# prim length # list -- int 



variable rs0
variable ds0
variable argc
variable argv
variable argv0
