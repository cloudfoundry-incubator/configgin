#!/usr/bin/env make

# GNU make 3.81 or later required:
ROOT_DIR:=$(dir $(realpath $(lastword $(MAKEFILE_LIST))))

.PHONY: lint test dist

all: lint test dist

test:
	${ROOT_DIR}make/test

lint:
	${ROOT_DIR}make/lint

dist:
	${ROOT_DIR}make/package

clean:
	rm -rf output
