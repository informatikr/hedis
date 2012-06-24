#!/usr/bin/env sh

# The -M argument limits heap size for 'testConstantSpacePipelining'.
cabal-dev test --test-option=+RTS --test-option=-M3m

echo "------------------"
echo "hlint suggestions:"
echo "------------------"
find src ! -name 'Commands.hs' ! -type d \
	| xargs -J % hlint % --ignore="Use import/export shortcut"
