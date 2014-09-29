.globl cantilever_main
cantilever_main:
   pusha
   movl %esp, c_stack
   movl cantilever_ds_ptr, %esi
   movl cantilever_rs_ptr, %esp
   lea -4(%esi), %esi ; movl %eax, (%esi) ; xor %eax, %eax ; inc %eax
   lea -4(%esi), %esi ; movl %eax, (%esi) ; movl $2, %eax
/*  3  */
   lea -4(%esi), %esi ; movl %eax, (%esi) ; movl $4, %eax
/*  5 */
   lea -4(%esi), %esi ; movl %eax, (%esi) ; xor %eax, %eax ; dec %eax
   lea -4(%esi), %esi ; movl %eax, (%esi) ; xor %eax, %eax
   lea -4(%esi), %esi ; movl %eax, (%esi) ; movl $string_000, %eax
.data
string_000:
    .asciz " hello world"
10001:
.text

   lea -4(%esi), %esi ; movl %eax, (%esi) ; movl $6, %eax
   lea -4(%esi), %esi ; movl %eax, (%esi) ; movl $7, %eax
   addl (%esi), %eax ;    lea 4(%esi), %esi
   lea -4(%esi), %esi ; movl %eax, (%esi) ; movl $8, %eax
   subl (%esi), %eax ;    lea 4(%esi), %esi
   lea -4(%esi), %esi ; movl %eax, (%esi) ; xor %eax, %eax ; inc %eax
   lea -4(%esi), %esi ; movl %eax, (%esi) ; xor %eax, %eax ; inc %eax
   test (%esi), %eax ; setne %al ; and $0xff, %eax ; dec %eax ;    lea 4(%esi), %esi
   lea -4(%esi), %esi ; movl %eax, (%esi) ; movl $2, %eax
   lea -4(%esi), %esi ; movl %eax, (%esi) ; xor %eax, %eax ; inc %eax
   test (%esi), %eax ; setne %al ; and $0xff, %eax ; dec %eax ;    lea 4(%esi), %esi
   lea -4(%esi), %esi ; movl %eax, (%esi) ; xor %eax, %eax ; inc %eax
   lea -4(%esi), %esi ; movl %eax, (%esi) ; xor %eax, %eax ; inc %eax
   cmpl (%esi), %eax ; setge %al ; and $0xff, %eax ; dec %eax ;    lea 4(%esi), %esi
   lea -4(%esi), %esi ; movl %eax, (%esi) ; xor %eax, %eax ; inc %eax
   lea -4(%esi), %esi ; movl %eax, (%esi) ; movl $2, %eax
   cmpl (%esi), %eax ; setge %al ; and $0xff, %eax ; dec %eax ;    lea 4(%esi), %esi
   lea -4(%esi), %esi ; movl %eax, (%esi) ; movl $2, %eax
   lea -4(%esi), %esi ; movl %eax, (%esi) ; xor %eax, %eax ; inc %eax
   cmpl (%esi), %eax ; setge %al ; and $0xff, %eax ; dec %eax ;    lea 4(%esi), %esi
   lea -4(%esi), %esi ; movl %eax, (%esi)
   movl %esi, cantilever_ds_ptr
   movl c_stack, %esp
   popa
   ret
.data
c_stack:
   .int 0
