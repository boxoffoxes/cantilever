
constant true, -1
constant false, 0

literal zero, 0
literal one,  1
literal two,  2
literal five, 5
literal seven, 7
literal nine, 9
literal ten, 10
literal sixteen, 16

literal minus_one, -1
literal minus_two_hundred, -200

constant asc_0, '0', "'0'"
constant asc_a, 'a', "'a'"
constant asc_minus, '-', "'-'"
constant asc_comma, ',', "','"
constant asc_spc, ' ', "'spc'"
constant asc_nl, '\n', "'\n'"


######################################################
# Forth-style non-primitive words                    #
######################################################

# Startup code #######################################

word initialiseVM
	# initialise the dictionary pointer
	_DATA getBrkAddr, dup, dictPtr, set, dpSet
	# allocate default heap
	_DATA HeapSize, setHeapSize
	# create scratchpad
	_DATA ScratchSize, buffer, scratchpadAddr, set
	# set up an IO buffer
	_DATA BufferSize, buffer, ioBuffer, set
	# initialise commandline flag handler
	#_DATA FlagTableSize, cell, buffer, flagTableAddr, set
	# are there any commandline args...
	_DATA argc, get, dec, zbr,(1f)
	# ...yes, then open the first one
	#_DATA argv, get, one, cell, add, get
	_DATA handleArgs
1:
	_DATA welcome
_DATA tc, reset

word reset
	_DATA rs0, get, rpSet 
_DATA tc, interpreter

word handleArgs, "handle-args"
	# first set this function to be our EOF handler
	_DATA quote, handleNextArg, handles, EndOfFile
	_DATA tc, handleNextArg
end
word handleNextArg, "handle-next-arg"
	# _DATA semicolon  # any uncalled code from the previous file?
	# check if there's an argument left to handle
	_DATA nextArg, dup, zbr,(1f)
	_DATA zopenIn, tc, reset
1:
	# no args left: switch to reading stdin and
	# reset EOF handler
	_DATA drop, stdin, inChannel, set
	_DATA quote, exit0, handles, EndOfFile
_DATA tc, reset
word nextArg, "next-arg"
	_DATA argv, get, one, cell, add
	_DATA dup, argv, set
	_DATA get
end

# IO ##################################################

word not
	_DATA minus_one, xor
end

#: abs ( n -- u ) dup 0< ?[ neg ] ;
word abs
	_DATA dup, ltz, zbr,(1f), neg
1:
end

word pad
	_DATA scratchpadAddr, get
end
word build  # addr b -- addr'
	_DATA over, setb, one, add
	_DATA key, asc_spc, over, lt, zbr,(1f)
	_DATA tc, build
1:	_DATA drop
end
word skipws  # -- b
	_DATA key, asc_spc, over, lt, not, zbr,(1f)
	_DATA drop, tc, skipws
1:
end

# : key  ?rx 0= ?[ key ;] dup 0< ?[ EndOfFile raise ;] ;
word key
	_DATA qrx, zero, eq, zbr,(1f), tc, key
1:	_DATA dup, ltz, zbr,(2f), EndOfFile, raise
2:
end
word word   # -- str
	_DATA WordBuffer, one, cell, add
	_DATA dup, skipws, build, zero, over, set, swap, sub
	_DATA WordBuffer, set, WordBuffer
end

#: comment ( b -- ) key over = ?[ drop ;] comment ;
word comment  # b --
	_DATA key, over, eq, zbr,(1f), drop, return
1: 	_DATA tc, comment
end
word commenteol, "\\", call   # --
	_DATA asc_nl, comment
end
#: nestcomm ( -- )  word cell+ @ 
#      '(' =[ depth ++  drop nestcomm ;]
#      ')' =[ depth --  drop nestcomm ;]  ;

# Strings #############################################

constant spc, 32, "'spc'"

word stringCellLength, "string-cell-length"   #  str -- n
	_DATA get, CellShift, rshift, inc, inc  # byte length, plus null, plus length field
end
word keeps   # tmpStr -- str
	_DATA dup, stringCellLength, keep
end
word copys   # str addr -- 
	_DATA push, dup, stringCellLength, pop, copy
end

word clearInputBuffer, "clear-input-buffer"
	_DATA key, asc_nl, eq, zbr,(1f), return
1:	_DATA tc,clearInputBuffer
end

# word packStr "pack-str"  # str len a -- pstr
	# _DATA dpAlign, stash, over, over, setb, inc, swap, move
# end

# Errors & Exception handling #################################

word handles
	# usage: ' fun handles Exception
	#    set fun as handler for Exception
	_DATA peek, getStep, call, set
	_DATA push
end

word raise  # excp -- 
	_DATA dup, get                 #  excp hndl
	_DATA dup, zbr,(1f)  #  excp hndl
	_DATA nip, call, return
1:
	_DATA drop, labelForVar        #  lbl
	_DATA ErrorUnhandled, puts
	_DATA WarningColour, colour, puts, NoColour, colour, error
end

# Default handler for EOF is to exit. This is over-ridden
# when reading from files passed on the commandline.
variable EndOfFile, exit0

string ErrorColour,   "[31m"
string WarningColour, "[33m"
string NoColour,      "[0m"

word error
	_DATA inChannel, get, isATTY, zbr,(1f)
	_DATA clearInputBuffer, reset
1:
_DATA one, exit


# Numeric Output #######################################

#: digit-to-char  dup 0 9 btw? ?[ '0' + ;] 'a' 10 - + ;
word digit_to_char, "digit-to-char" # n -- c
	_DATA dup 
	_DATA zero, nine, between, zbr,(1f)
	_DATA asc_0, add, return
1:
	_DATA asc_a, ten, sub, add
end

#: digit ( u -- c ) 9 over < 7  and  + 48 + ;
word digit
	_DATA nine, over, lt, seven,  and,  add, asc_0, add
end
#: extract ( n base -- n c ) 0 swap um/mod digit ;
word extract
	_DATA udivmod, digit
end
#: <# ( -- ) pad hld ! ;
word formatted, "<#"
	_DATA pad, hld, set
end
#: hold ( b -- ) hld @ 1 - dup hld ! c! ;
word hold
	_DATA hld, get, one, sub, dup, hld, set, setb
end
#: #  ( u -- u ) base @ extract hold ;
word holddigit, "#"
	_DATA base, get, extract, hold
end
#: #s ( u -- 0 ) # dup ?[ #s ;] ;
word holdint, "#s"
	_DATA holddigit, dup, zbr,(1f), tc, holdint
1:
end
#: sign ( n -- ) 0< ?[ '-' hold ] ;
word sign
	_DATA ltz, zbr,(1f), asc_minus, hold
1:
end
#: #> ( w -- str len ) drop hld @ pad over - ;
word unformatted "#>"
	_DATA drop, hld, get, pad, over, sub
end
#: str ( n -- str len ) dup push abs <# #s pop sign #> ;
word str
	_DATA dup, push, abs, formatted, holdint, pop, sign, unformatted
end

#: u.  ( u -- ) <# #s #> space type ;
word putu "u."
	_DATA formatted, holdint, unformatted, put
end
#: . ( w -- ) base @ 10 xor ?[ u. ;] str type ;
word putn "."
	_DATA base, get, ten, xor, zbr,(1f), tc, putu
1:	_DATA str, put
end
word putx "x."
	_DATA base, get, swap, hex, putn, base, set
end

word hex
	_DATA sixteen, base, set
end
word decimal
	_DATA ten, base, set
end
word binary
	_DATA two, base, set
end


# String output #########################################

word lens  # str -- int
	_DATA get
end

word warn  # zstr len -- 
	_DATA errChannel, get, write
end
word warns # nstr --
	_DATA stash, one, cell, add
	_DATA pop, get, warn
end

word put   # zstr len --
	_DATA outChannel, get, write
end
word putz # zstr --
	_DATA dup, lenz
	_DATA put
end
word puts #  nstr --  
	_DATA stash, one, cell, add
	_DATA pop, get, put
end

word putc  # c --
	_DATA spGet, one, put
	_DATA drop # drop on-stack buffer
end

word colour  #  colour -- 
	_DATA push
	_DATA outChannel, get, isATTY, zbr,(1f)
	_DATA peek, puts
1:
	_DATA trash
end


# File IO ###############################################
constant OpenPerms 0666
word zopen   # zstr mode -- fh
	# syscall3 requires arg order: perms mode zstr callid
	_DATA swap, push, push
	_DATA OpenPerms, pop, pop
	_DATA SysOpen, syscall3
	_DATA dup, zero, lt, zbr,(1f)
	_DATA drop, FileOpenFailed, raise
1:
end
word open  # str mode -- fh
	_DATA push
	_DATA one, cell, add
	_DATA pop, zopen
end

word zopenIn, "zopen-in"
	_DATA ReadOnly, zopen, inChannel, set
end
word openIn, "open-in"
	_DATA ReadOnly, open, inChannel, set
end
word openOut, "open-out"
	# TODO: doesn't check for errors!
	_DATA open, outChannel, set
end

word close  # fh -- err
	_DATA SysClose, syscall1
end
word closeOut, "close-out"
	_DATA outChannel, get, close
	_DATA stdout, outChannel, set
end
word closeIn, "close-in"
	_DATA inChannel, get, close
	_DATA stdin, inChannel, set
end

word write  # str len fh -- 
	_DATA push
	_DATA swap, pop
	_DATA SysWrite, syscall3
	_DATA drop # discard result
end
word read   # buf len fh -- n
	_DATA push, swap, pop
	_DATA SysRead, syscall3
end

variable FileOpenFailed
variable MmapFailed
variable FailedToMunmapFile
variable CouldNotStatFile

word statFD "stat-fd"
	_DATA here, stash, swap, SysStat, syscall2
	_DATA zero, lt, zbr,(1f)
	_DATA CouldNotStatFile, raise
1:
	_DATA pop
end

# Get the st_size field of the C stat struct
word st_size ".st_size"
	_DATA five, cell, add
end

word fileLength  "file-length" # fd -- len
	_DATA statFD, st_size, get
end


# Memory management ######################################

word setBrkAddr "set-brk-addr"  # addr -- addr
	_DATA SysBrk, syscall1
end
word getBrkAddr, "get-brk-addr"  #  -- addr
	_DATA zero, setBrkAddr
end
word getHeapSize "get-heap-size"  # -- n
	_DATA getBrkAddr, HeapBaseAddr, sub
end

# Todo: error handling on the following two functions
word setHeapSize "set-heap-size"  # n --
	_DATA HeapBaseAddr, add, setBrkAddr, drop
end
word growHeap "grow-heap"  # n --
	_DATA getBrkAddr, add, setBrkAddr, drop
end


# System interface ########################################

word exit0, "0-exit"
	_DATA zero, exit
end

word exit #  n -- 
	_DATA SysExit, syscall1
end

word bye
	_DATA byebye, puts, nl
	_DATA zero, exit
end

constant TCGETS, 0x00005401
word isATTY "is-a-tty?"  # fd -- bool
	_DATA push, scratchpadAddr, get, TCGETS, pop, SysIOCtl, syscall3
	_DATA zero, eq
end

# Memory mapping

constant MapShared,     MAP_SHARED
constant MapPrivate,    MAP_PRIVATE
constant MapAnonymous,  MAP_ANONYMOUS
constant MapStack,      MAP_STACK

constant ProtRead,      PROT_READ
constant ProtWrite,     PROT_WRITE
constant ProtExec,      PROT_EXEC
constant ProtGrowsDown, PROT_GROWSDOWN
constant ProtGrowsUp,   PROT_GROWSUP

word mmap  # fd flags prot len -- addr
	_DATA push, push, push, push
	#     offs  fd   flag prot len  addr
	_DATA zero, pop, pop, pop, pop, zero, SysMmap, syscall6
	_DATA dup, minus_two_hundred, minus_one, between, zbr,(1f)
	_DATA MmapFailed, raise
1:
end
word munmap  # len addr -- 
	_DATA SysMunmap, syscall2
	_DATA drop  # todo: error handling
end

# Create a mem-mapped buffer
word buffer  # len -- addr
	_DATA push
	_DATA minus_one                        # fd is ignored
	_DATA MapPrivate, MapAnonymous, or     # set map options
	_DATA ProtWrite, ProtRead, or          # set protections
	_DATA pop, mmap
end

word mmapFd "mmap-fd" # fd len -- addr
	_DATA push, MapShared, ProtRead, pop, mmap
end

word bufferZFile "buffer-zfile" # zstr -- addr len fd
	_DATA ReadOnly, zopen, stash
	_DATA dup, fileLength, stash, mmapFd
	_DATA pop, pop
end

word bufferFile "buffer-file"  # str -- addr len fd
	_DATA one, cell, add
	_DATA bufferZFile
end


# Dictionary lookup ###################################

.section .data
.align CELL_SIZE, 0
wordbuffer:
	_DATA 0
wordbuffer_text:
	.space WORD_BUFFER_SIZE
end_wordbuffer:
	_DATA 0 // space for padding

word notFoundHandler "not-found-handler"  # str
	_DATA WarningColour, colour
	_DATA puts, NoColour, colour, NotFound, puts, nl
_DATA error

	
# : find  @ dup ?[ 2dup label streq ?[ nip dup cfa swap behavior ;] find ;] ;
word find // str dict -- xt bh | str 0
	_DATA get, dup, zbr,(2f)
	_DATA over, over, label, strEq, zbr,(1f)
	_DATA nip, dup, cfa, swap, behaviour, return
1:	_DATA tc, find
2:
end

word lfa, ".lfa"  # entry -- addr
	_DATA LfaOffs, add
end
word cfa, ".cfa" // entry -- codeAddr
	_DATA CfaOffs, add
end
word bfa, ".bfa"
	_DATA BfaOffs, add
end
word pfa, ".pfa"
	_DATA PfaOffs, add
end

word label, ".label"  // entry -- str
	_DATA lfa, get
end
word behaviour, ".behaviour" 
	_DATA bfa, get
end
word cfaToLabel, ".cfa->.label"
	_DATA CfaOffs, sub
	_DATA label
end

word labelForVar, "label-for-var"
	_DATA one, cell, sub, cfaToLabel
end

word nl
	_DATA ten, putc
end

# Words that create words ############################

word header  # str --
	_DATA dpAlign
	_DATA here, push
	_DATA dictionary, get, storeinc  # compile link to current head of dict
	_DATA storeinc                   # compile label address
	_DATA quote, storeinc, storeinc  # store the default behaviour
	_DATA pop, dictionary, set       # store our new word in the dict
end

word define  #  str interp --
	_DATA swap, header, storeinc
end

word defdoes   # str --
	_DATA quote, dodoes, define, zero, storeinc  # behaviour field
end
word defword   # str -- 
	_DATA quote, do, define
end
word defconst  # val str -- 
	_DATA quote, doconst, define
end
word defvar    # val str --
	_DATA quote, dovar, define
end

word create
	_DATA word, keeps, defdoes
end
word does
	# This is subtle! pop gives us the address of the word after
	# does in the definition (and prevents subsequent code executing).
	# We put it in the link field of the word create has just made.
	_DATA pop, dictionary, get, pfa, set
end
word createConstant, "create-constant"  # val --
	_DATA word, keeps, defconst, storeinc
end
word createVariable, "create-variable"  # --
	_DATA word, keeps, defvar
	_DATA zero, storeinc
end
word createWord, "create-word"
	_DATA word, keeps, defword
end
word immed, "#immediate", call
	_DATA dictionary, get, bfa, quote, call, swap, set
end

word constantColon, "constant:"
	_DATA createConstant
end
word variableColon, "variable:"
	_DATA createVariable
end
word colon, ":"
	_DATA createWord
_DATA tc, compiler

#: iscol  ( xt -- bool )  @ DoAddr = ;
word iscol  # xt -- bool
	_DATA get, DoAddr, eq
end

#: ;  cp @  dup iscol ?[ ,  ' tc cp ! ;]   compile return  trash  ;
word semicolon, ";", call
	_DATA cp,get,get, dup, iscol, zbr,(1f), storeinc, quote,tc, cp, set, return
1:	_DATA drop, compile,return
	_DATA trash  # return to the interpreter loop that called compiler
end

word mark
	_DATA here, zero, storeinc
end
word resolve
	_DATA here, swap, set
end

word if, "?[", call
	_DATA compile,zbr, mark
end
word endif, "]", call
	_DATA resolve
end
word case, "=[", call
	_DATA compile,over,  compile,eq,  compile,zbr,  mark
end
word endcase, ";]", call
	_DATA compile,return,  resolve
end

word welcome
	_DATA inChannel, get, isATTY, zbr,(1f)
	_DATA WelcomeMessage, puts
1:
end
word prompt
	_DATA inChannel, get, isATTY, zbr,(1f)
	_DATA nl, spc, putc, depth, putn
	_DATA asc_comma, putc, rdepth, putn
	_DATA promptText, get, puts
1:
end

word compiled  # xt -- 
	_DATA here, cp, set
	_DATA storeinc
end

word compile
	# read from the instruction stream and compile a call to it
	_DATA pop, getStep, compiled, push
end

#: compiler ( -- ) word dictionary find dup ?[ call compiler ;]
#                  drop NotFoundException raise ;
word compiler
	_DATA word, dictionary, find
	_DATA dup, zbr,(1f), call, tc,compiler
1:	_DATA drop, NotFoundException,raise
end

#: interpreter ( -- ) prompt word dictionary 
#	find    ?[ call interpreter ;]
#	number  ?[ interpreter ;]
#	NotFoundException raise
word interpreter
	_DATA prompt, word, dictionary
	_DATA find,         zbr,(1f), call, tc,interpreter
1:	_DATA dup, number,  zbr,(2f), nip,  tc,interpreter
2:	_DATA drop, NotFoundException,raise
end


.section .rodata

constant DoAddr,      do
constant DoConstAddr, doconst
constant DoDoesAddr,  dodoes
constant WordBuffer, wordbuffer
constant CellShift CELL_SHIFT
constant CellSize, CELL_SIZE

#ifdef CANTILEVER_CHEAP_DATE
constant CheapDate, -1
#else
constant CheapDate, 0
#endif
constant Base4Year, BASE_4_YEAR
constant LilianCorrection, LILIAN_CORRECTION

variable argc
variable argv
variable argv0

variable ioBuffer, , "io-buffer"
variable bufpos
variable bufend
variable scratchpadAddr, , "scratchpad-addr"

variable ds0
variable rs0
variable dp0
variable dictPtr, ,"dict-ptr"
variable hld
variable base, 10
variable cp, 0     # compilation pointer

variable NotFoundException, notFoundHandler

string WelcomeMessage "Welcome to Cantilever\n\n\tType an expression in Reverse-Polish form \n\tterminated with [33m;[0m or [33m=[0m (to see a numeric result). \n\tIf you have rlwrap installed you can use tab-completion\n"
string byebye, "\n-- Toodle-pip!\n"
string TooLong, "Word too long: "
string NotFound, " is neither a dictionary word nor a recognised number\n"
string InvalidEsc, "Invalid escape char: "
string ErrorUnhandled, "Unhandled exception: "
string DefaultPrompt, " ok "

variable decimal_places, 0, "decimal-places"

variable promptText, str_DefaultPrompt, "prompt-text"
variable dictionary, link   # MUST BE LAST
