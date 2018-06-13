ASSEMBLER32=gcc -static -nostdlib -m32 -g 
ASSEMBLER64=gcc -static -nostdlib -m64 -g
ASSEMBLER=$(ASSEMBLER32)
STEM=cantilever
TARGET=$(STEM)
# PROF_TARGET=$(STEM)-profile


all: $(TARGET)

# Misc/all-words

test: $(TARGET)
	./cantilever core.clvr test-library.clvr core-tests.clvr

Misc/all-words : $(TARGET) foundation.clvr
	echo "dump-dicts ;" | ./cantilever foundation.clvr | sort > $@

sloc: $(TARGET).S
	cat $< | grep -v '^\s*$$' | grep -v '^\s*#[^a-z]' | grep -v '^\s*//' | wc -l

%: %.S
	$(ASSEMBLER) -o $@ $<


inc/sys_defs.h :
	cpp -dM $< > $@

