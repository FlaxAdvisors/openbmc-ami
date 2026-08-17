# Native (build-host) test for the flax-hi-inventory mapping layer.
#
#   make test          # build and run against samples/collections
#   DUMP=1 make test   # also print the full property table
#
# nlohmann/json.hpp is header-only; it is symlinked out of a Yocto sysroot into
# .deps/ so only that one header is pulled in (adding the whole ARM sysroot
# include path to a host build breaks on 32-bit uintptr_t).  Override
# NLOHMANN_DIR if the bmcweb work directory has been cleaned.

SRC_DIR := ../../meta-flax/recipes-phosphor/hi-inventory/flax-hi-inventory
NLOHMANN_DIR ?= $(firstword $(wildcard \
	/usr/include/nlohmann \
	../../build/tiogapass/tmp/work/*/bmcweb/*/recipe-sysroot/usr/include/nlohmann \
	../../build/tiogapass/tmp/sysroots-components/*/nlohmann-json/usr/include/nlohmann))

CXXFLAGS := -std=c++17 -Wall -Wextra -O1 -I$(SRC_DIR) -I.deps

test: test_map
	./test_map samples/collections

.deps/nlohmann:
	@if [ -z "$(NLOHMANN_DIR)" ]; then \
		echo "nlohmann/json.hpp not found; set NLOHMANN_DIR=<dir containing json.hpp>"; \
		exit 1; \
	fi
	@mkdir -p .deps
	@ln -sfn $(abspath $(NLOHMANN_DIR)) .deps/nlohmann

test_map: test_map.cpp $(SRC_DIR)/inventory_map.cpp $(SRC_DIR)/inventory_map.hpp .deps/nlohmann
	$(CXX) $(CXXFLAGS) -o $@ test_map.cpp $(SRC_DIR)/inventory_map.cpp

clean:
	rm -rf test_map .deps

.PHONY: test clean
