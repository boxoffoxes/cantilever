ASSEMBLER32=gcc -static -nostdlib -m32 -g 
STEM=cantilever
TARGET=$(STEM)
# PROF_TARGET=$(STEM)-profile


all: $(TARGET) Misc/all-words

test: $(TARGET)
	./cantilever foundation.clvr test-library.clvr core-tests.clvr

Misc/all-words : $(TARGET) foundation.clvr
	echo "dump-dicts ;" | ./cantilever foundation.clvr | sort > $@

sloc: $(TARGET).S
	cat $< | grep -v '^\s*$$' | grep -v '^\s*#[^a-z]' | grep -v '^\s*//' | wc -l

$(TARGET): $(TARGET).S inc/sys_defs.h
	$(ASSEMBLER32) -o $@ $<


inc/sys_defs.h : inc/required.h
	cpp -dM $< > $@

