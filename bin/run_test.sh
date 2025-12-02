#!/bin/bash
ruby bin/test_prism_merge.rb > tmp/test_output.txt 2>&1
echo "Exit code: $?" >> tmp/test_output.txt

