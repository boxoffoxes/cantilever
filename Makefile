tmp=tmp
SRC=primitives.S minimal.S macros.S


#slides.tex : slides.txt
#	pandoc -t beamer -o $@ -s --bibliography ../bibliography.bib $<

cantilever : ${SRC}
	gcc -m32 -g -nostdlib -static -Wl,--build-id=none -Wa,-n -o $@ minimal.S

%.o : %.S macros.S
	gcc -m32 -g -nostdlib -static -Wl,--build-id=none -Wa,-n -c -o $@ $<

# Temporary target for testing executable is not changed by introduction
# of macros for register names
check : minimal md5sum.txt
	strip minimal && md5sum -c md5sum.txt

%.pdf : %.tex 
	# img/*.pdf
	pdflatex -halt-on-error -output-directory=$(tmp) ../$< && mv $(tmp)/$@ ./

img/%.pdf : img/%.dot
	dot -Tpdf -o$@ $<

%.tex : %.txt
	#pandoc -V papersize:"a4paper" -V documentclass:"article" --csl ../Bibliography/ieee-with-url.csl --number-sections -t latex -o $@ -s $<
	pandoc -V papersize:"a4paper" -V documentclass:"article" -t latex -o $@ -s $<

%.S : %.txt
	awk '/^~~~~~/ {write=0} write == 1 {print $0;} /^~~~~* gnuassembler/ { write=1 } ' $< > $@

% : %.S
	gcc -m32 -g -nostdlib -static -Wl,--build-id=none -Wa,-n -o $@ $<

## Note that the -n assember flag is required to prevent multiple NOPs being converted to multibyte NOP instructions.


