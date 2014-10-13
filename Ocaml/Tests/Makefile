CC=gcc -m32 -g

test : test.o runtime.o
	$(CC) -o $@ $^

% : %.c
	$(CC) -c %< 

% : %.S
	%(CC) -c %<

clean:
	rm -f test a.out *.o
