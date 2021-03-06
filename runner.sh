#!/bin/bash

# Simple script for running tests and measure their time
# with some basic statistics (i.g. mean, std, confidence interval).
# This script uses multitime tool (https://github.com/ltratt/multitime)
# and assumes that it is installed.
# Also one should compile the tests before running the script: `make test`.

BF=$(mktemp)
trap 'rm -f -- "$BF"' INT TERM HUP EXIT
./TestMain.native -list-test | while read -r line ; do
    echo "./TestMain.native -runner sequential -only-test $line" >> $BF
    fi
done

multitime -c 95 -n 10 -b $BF 2>results.txt
