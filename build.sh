#!/bin/sh

arch=$1
os=$2
stem="cantilever-$arch-$os"

usage () {
	echo -e '\tUsage: $0 <arch> <os>'
}
fail () {
	echo -e '\tError:' $1
	usage
	exit 1
}
[ -f $arch/core.S ] || fail "Unrecognised arch '$arch'"
# [ -f $os/system.S ] || fail "Unsupported OS '$os'"

cat $arch/$os.S $arch/core.S $arch/extra.S cantilever.S > $stem.S

# gcc -g -nostdlib -Wl,--nopie -o $stem $stem.S
gcc -g -m32 -static -nostdlib -o $stem $stem.S

