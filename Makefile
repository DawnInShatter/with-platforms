# Usage: make solc_gen_by_dir dirname=vims node_modules=./node_modules
# The dirname parameter indicates the directory where the .sol file you modified is located,
# which is a subdirectory of ethcontracts
# The node_modules parameter represents the path to your node_modules directory
solc_gen_by_dir:
	sh solc_gen.sh $(dirname) $(node_modules)