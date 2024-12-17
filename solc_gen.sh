# This file is called internally by the Makefile command, do not use this file directly.
# Refer to the comments in the Makefile.
for d in contracts/$1/*; do
  solc @openzeppelin/=$2/@openzeppelin/ --pretty-json --combined-json abi $d -o contract_abi/$(basename $d) --overwrite ..=..
  solc @openzeppelin/=$2/@openzeppelin/ --abi $d -o contract_abi/$(basename $d) --overwrite ..=..
done
