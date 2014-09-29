#include <stdio.h>

extern int cantilever_main();

#define CANTILEVER_STACK_SIZE 512

int cantilever_dstack[CANTILEVER_STACK_SIZE];
int cantilever_rstack[CANTILEVER_STACK_SIZE];
int cantilever_heap[4096];

int *cantilever_ds_ptr = cantilever_dstack + CANTILEVER_STACK_SIZE;
int *cantilever_rs_ptr = cantilever_rstack + CANTILEVER_STACK_SIZE;

void dump_stack() {
	int i;
	while (cantilever_ds_ptr < &cantilever_dstack[CANTILEVER_STACK_SIZE-1]) {
		printf("\t% 8x  % 12d\n", *cantilever_ds_ptr, *cantilever_ds_ptr);
		cantilever_ds_ptr++;
	}
	printf("\n");
}

int main(int argc, char **argv) {
	int n;
	cantilever_main();
	n = &cantilever_dstack[CANTILEVER_STACK_SIZE-1] - cantilever_ds_ptr;
	printf("Stack is %d deep:\n", n);
	dump_stack(cantilever_dstack, n);
	return 0;
}
