######################################################
# Minimal set of assembly primitives                 #
######################################################

prim return
	poprs %rsi
next

prim nez, "0<>"   # int -- bool
	pop %rax
	xor %rdx, %rdx
	test %rax, %rax
	setz %dl
	dec %rdx
	push %rdx
next

prim ltz "0<"
	pop %rax
	cqo
	push %rdx
next

prim get, "@"
	pop %rax
	push (%rax)
next

prim set "!" # int addr -- 
	pop %rax
	pop %rdx
	mov %rdx, (%rax)
next

prim and
	pop %rax
	and %rax, (%rsp)
next
prim or
	pop %rax
	or %rax, (%rsp)
next
prim xor
	pop %rax
	xor %rax, (%rsp)
next

prim add, "+" // a b -- a+b
	pop %rax
	add %rax, (%rsp)
next

prim spGet, "sp@"
	push %rsp
next
prim spSet, "sp!"
	pop %rsp
next

prim rpGet, "rp@"
	push %rbp
next
prim rpSet, "rp!"
	pop %rbp
next


