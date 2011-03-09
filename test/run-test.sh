#!/usr/bin/env sh

ghc --make -fforce-recomp -fhpc -isrc -outputdir /tmp  test/Test.hs 

echo "---------------"
echo "program output:"
echo "---------------"
./test/Test

echo "---------------"
hpc markup --destdir=test/coverage Test.tix

echo "----------------"
echo "coverage report:"
echo "----------------"
hpc report Test.tix

# cleanup
rm test/Test
rm Test.tix
rm -r .hpc
