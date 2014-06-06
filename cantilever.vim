" Vim syntax file
" Language:	Cantilever

"syn spell toplevel
"syn case ignore
"syn sync linebreaks=1

"syn match ref /$\S*/


" syn match isWord   /\S*/
"syn match isQuote  /'\s\+\S\+/
"syn match isImmed  /#\s*\S\+/
"syn match isImmed  /if\|endif\|;/
"syn match isDefn   /:\s\+\S\+/ " contains=isTag

syn match isTag    /['#:]/ contained

syn region String  start="\"" end="\""
syn region String  start="s: " end="\n"
syn region Comment start="(" end=")"
syn region Comment start="--" end="\n"
" syn region String  start="\"\n" end="\""
" syn region String  start="\"\t" end="\""

syn match isQuote  /\S\+'/ "contains=isTag
syn match isImmed  /\S\+#/ "contains=isTag
syn match isImmed  /;/
syn match isDefn   /\S\+:/ contains=isTag

hi link isQuote Type
hi link isImmed Identifier
hi link isDefn  Constant
hi link isTag   Macro
hi link isLeadSpace Todo

"hi hasPriW ctermfg=darkgrey cterm=bold guifg=darkgrey



