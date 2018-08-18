ASSEMBLER32=gcc -static -nostdlib -m32 -g 
ASSEMBLER64=gcc -static -nostdlib -m64 -g
STEM=cantilever
TARGET=$(STEM)
TARGET64=cantilever64
# PROF_TARGET=$(STEM)-profile


all: $(TARGET)

# Misc/all-words

test: $(TARGET)
	./cantilever core.clvr Tests/*.clvr

test64: testprims
#	./cantilever64 core.clvr test-library.clvr core-tests.clvr
	./testprims ; echo $$?

testprims : testprims.S prims64.S
	$(ASSEMBLER64) -o $@ $<

Misc/all-words : $(TARGET) foundation.clvr
	echo "dump-dicts ;" | ./cantilever foundation.clvr | sort > $@

sloc: $(TARGET).S
	cat $< | grep -v '^\s*$$' | grep -v '^\s*#[^a-z]' | grep -v '^\s*//' | wc -l

%64: %64.S
	$(ASSEMBLER64) -o $@ $<

%: %.S
	$(ASSEMBLER32) -o $@ $<


inc/sys_defs.h :
	cpp -dM $< > $@

