#!/usr/bin/env sh

echo "---------------"
echo "program output:"
echo "---------------"
# The -M argument limits heap size for 'testConstantSpacePipelining'.
./dist/build/hedis-test/hedis-test +RTS -M1m

echo "---------------"
hpc markup --destdir=test/coverage hedis-test.tix

echo "----------------"
echo "coverage report:"
echo "----------------"
hpc report hedis-test.tix

echo "------------------"
echo "hlint suggestions:"
echo "------------------"
find src ! -name 'Commands.hs' ! -type d \
	| xargs -J % hlint % --ignore="Use import/export shortcut"

# cleanup
rm hedis-test.tix
