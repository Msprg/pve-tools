# SPDX-License-Identifier: GPL-3.0-or-later
PACKAGES := $(notdir $(wildcard packages/*))
DIST     := dist

.PHONY: all build test lint repo-smoke clean
all: lint test build

build:
	@for p in $(PACKAGES); do scripts/build-deb.sh packages/$$p $(DIST) || exit 1; done

test:
	@status=0; for p in $(PACKAGES); do scripts/run-tests.sh packages/$$p || status=1; done; exit $$status

lint:
	@scripts/lint.sh

# needs root: runs apt-get update against a throwaway signed repo (isolated apt state)
repo-smoke: build
	@scripts/repo-smoke-test.sh $(DIST)

clean:
	rm -rf $(DIST)
