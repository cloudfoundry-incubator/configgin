#!/usr/bin/env make

GIT_ROOT:=$(shell git rev-parse --show-toplevel)

.PHONY: lint test dist

all: lint test dist

test:
	${GIT_ROOT}/make/test

lint:
	${GIT_ROOT}/make/lint

dist:
	${GIT_ROOT}/make/package
