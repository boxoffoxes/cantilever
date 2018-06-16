######################################################
# Minimal set of assembly primitives                 #
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


