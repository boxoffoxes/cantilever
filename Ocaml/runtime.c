#include <stdio.h>

extern int cantilever_main();

main(int argc, char **argv) {
	printf("%d\n", cantilever_main());
	return 0;
}
