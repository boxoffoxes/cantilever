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

prim swap
	_swap
end

/* Return stack shuffling prims */

prim push    // TODO: not inlinable, due to rstack manipulation!
	pop RegB // make sure our return address
	push ToS
	_drop
	push RegB // remains on ToRS
end

prim pop     // TODO: not inlinable
	pop RegB // our return address
	_dup
	pop ToS
	push RegB
end

/* Memory address register prims */

prim set_A
	mov ToS, RegA
	_drop
end

prim get_A
	_dup
	mov RegA, ToS
end

prim study_word
	// ( w -- )
	call prim_set_A
	_clear RegC
	movb (RegA), %cl
	inc RegA
end


/* Arithmetic */

prim add
	addl NoS, ToS
	_nip
end

prim subtract
	_swap
	subl NoS, ToS
	_nip
end

prim inc
	inc ToS
end

prim dec
	dec ToS
end

/* Comparison operators */

prim equals
	// ( n n -- n bool )
	cmp ToS, NoS
	setne ToSl    // Set %al to 1 if not equal, 0 otherwise
	and $0xff, ToS // make sure all high bits are unset
	dec ToS      // ToS now -1 if equal or 0 if not. No jump required!
end

prim greater_than
	// ( n n -- n bool )
	cmp ToS, NoS
	setle ToSl
	and $0xff, ToS
	dec ToS
end

prim less_than
	// ( n n -- n bool )
	cmp ToS, NoS
	setge ToSl
	and $0xff, ToS
	dec ToS
end

/* Flow control */

prim cond_return  // TODO: not inlinable
	// ( bool -- )
	test ToS, ToS
	_drop
	jz 1f
	pop RegB
1:
end

prim if   // TODO: not inlinable
	// ( bool -- )
	test ToS, ToS
	pop ToS     // return addr contains addr of end of conditional block
	jnz 1f
	push (ToS)  // set this as our real return address
	jmp 2f
1:
	add $4, ToS // skip the jump address
	push ToS
2:
	_drop
end

prim jump // TODO: not inlinable
	// ( -- )
	// unconditional jump
	pop RegB
	push (RegB)
end

/* memory access */

prim fetch_byte
	// ( a -- b )
	movzbl (ToS), ToS
end

prim fetch_byte_inc
	// ( -- b )
	_dup
	movzbl (RegA), ToS
	inc RegA
end

prim fetch 
	// ( a -- n )
	mov (ToS), ToS
end

prim fetch_inc
	// ( -- n )
	_dup
	mov (RegA), ToS
	addl $4, RegA
end

prim store_byte
	// ( b a -- )
	mov NoS, RegB
	_nip
	movb RegBl, (ToS)
	_drop
end

prim store_byte_inc
	// ( b -- )
	stosb  // TODO: Relies on RegA being %edi
	_drop
end

prim store
	// ( n a -- )
	mov NoS, RegB
	_nip
	mov RegB, (ToS)
	_drop
end

prim store_inc
	// ( n -- )
	stosl  // TODO: Relies on RegA in %edi
	_drop
end

/* IO primitives */

