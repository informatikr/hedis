#!/usr/bin/env sh

echo "---------------"
echo "program output:"
echo "---------------"
./dist/build/hedis-test/hedis-test

echo "---------------"
hpc markup --destdir=test/coverage hedis-test.tix

echo "----------------"
echo "coverage report:"
echo "----------------"
hpc report hedis-test.tix

echo "------------------"
echo "hlint suggestions:"
echo "------------------"
find src ! -name 'Commands.hs' ! -type d | xargs hlint

# cleanup
rm hedis-test.tix
