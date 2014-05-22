
.set HEAP_PTR, .

.macro _dup
	lea -4(%esi), %esi
	mov %eax, (%esi)
.endm

.macro _drop
	lodsl
.endm

.macro _clear reg
	xor \reg, \reg
.endm

.macro prim label
.text
word_\label:
.endm

.macro next
	ret
.endm


.macro word label
.text
word_\label:
.endm

.macro endw
	ret
.endm


.macro _call w
	call word_\w
.endm

.macro _tail w
	jmp word_\w
.endm

.macro _lit int
	_dup
	movl \int, %eax
.endm


.macro _variable name val=0
.data
.align 4
	.set HEAP_PTR, .
\name:
	.int \val
.text
word_\name:
	_dup
	movl $HEAP_PTR, %eax
	ret
.endm

.macro _constant name val
.text
.align 4
	_dup
	movl \val, %eax
	ret
.endm


_variable io_buffer

_variable heap_free HEAP_PTR+4

#include <asm/unistd.h>
.text

prim Emit
	// ( ch -- )
	mov $1, %ebx   // stdout
	mov $io_buffer, %ecx  // buffer to write
	mov %al, (%ecx) // character to write
	mov $1, %edx   // no of chars
	mov $__NR_write, %eax // syscall id
	int $0x80
	_drop
next

prim Key
	// ( -- ch )
	mov $0, %ebx  // stdin
	mov $io_buffer, %ecx
	mov $1, %edx  // no of chars
	mov $__NR_read, %eax
	int $0x80
	mov (%ecx), %eax
next

prim Fetch
	// ( a -- n )
	mov (%eax), %eax
next

prim Store
	// ( n a -- )
	mov %eax, %ebx
	_drop
	mov %eax, (%ebx)
	_drop
next

prim CellPlus
	// ( n -- n+4 )
	add $4, %eax
next

.text
.align 4
.globl _start
_start:
	cld
	_clear %eax
	lea -1024(%esp), %esi  // configure stack pointer
	_call Key
	_call Emit

exit:
	// ( n -- )
	mov %eax, %ebx
	mov $__NR_exit, %eax	
	int $0x80


