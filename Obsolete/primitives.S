/* Data-stack shuffling primitives */

prim dup
	_dup
end

prim drop
	_drop
end

prim nip
	_nip
end

prim tuck
	_swap
	_over
end

prim swap
	_swap
end

prim over
	_over
end

/* Return stack shuffling prims */

prim push    // TODO: not inlinable, due to rstack manipulation!
	pop %ebx // make sure our return address
	push %eax
	_drop
	push %ebx // remains on ToRS
end

prim pop     // TODO: not inlinable
	pop %ebx // our return address
	_dup
	pop %eax
	push %ebx
end

/* Memory address register prims */

prim set_hp
	mov %eax, %edi
	_drop
end

prim get_hp
	_dup
	mov %edi, %eax
end


/* Arithmetic */

prim add, "+"
	addl (%esi), %eax
	_nip
end

prim subtract, "-"
	_swap
	subl (%esi), %eax
	_nip
end

prim inc, "1+"
	inc %eax
end

prim dec, "1-"
	dec %eax
end

/* Comparison operators */

prim equals
	// ( n n -- n bool )
	cmp %eax, (%esi)
	setne %al    // Set %al to 1 if not equal, 0 otherwise
	and $0xff, %eax // make sure all high bits are unset
	dec %eax      // ToS now -1 if equal or 0 if not. No jump required!
end

prim greater_than
	// ( n n -- n bool )
	cmp %eax, (%esi)
	setle %al
	and $0xff, %eax
	dec %eax
end

prim less_than
	// ( n n -- n bool )
	cmp %eax, (%esi)
	setge %al
	and $0xff, %eax
	dec %eax
end

/* Flow control */

prim cond_return  // TODO: not inlinable
	// ( bool -- )
	test %eax, %eax
	_drop
	jz 1f
	pop %ebx
1:
end

prim if   // TODO: not inlinable
	// ( bool -- )
	test %eax, %eax
	pop %eax     // return addr contains addr of end of conditional block
	jnz 1f
	push (%eax)  // set this as our real return address
	jmp 2f
1:
	add $4, %eax // skip the jump address
	push %eax
2:
	_drop
end

prim jump // TODO: not inlinable
	// ( -- )
	// unconditional jump
	pop %ebx
	push (%ebx)
end

/* memory access */

prim fetch_byte
	// ( a -- b )
	movzbl (%eax), %eax
end

prim fetch_byte_inc
	// ( -- b )
	_dup
	movzbl (%edi), %eax
	inc %edi
end

prim fetch 
	// ( a -- n )
	mov (%eax), %eax
end

prim fetch_inc
	// ( -- n )
	_dup
	mov (%edi), %eax
	addl $4, %edi
end

prim store_byte
	// ( b a -- )
	mov (%esi), %ebx
	_nip
	movb %bl, (%eax)
	_drop
end

prim store_byte_inc
	// ( b -- )
	stosb
	_drop
end

prim store
	// ( n a -- )
	mov (%esi), %ebx
	_nip
	mov %ebx, (%eax)
	_drop
end

prim store_inc
	// ( n -- )
	stosl
	_drop
end

/* IO primitives */

