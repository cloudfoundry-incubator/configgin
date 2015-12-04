#!/usr/bin/env make

.PHONY: install test dist

all: dependencies lint test dist

include version.mk

BRANCH:=$(shell git rev-parse --short HEAD)
BUILD:=$(shell whoami)-$(BRANCH)-$(shell date -u +%Y%m%d%H%M%S)
APP_VERSION=$(VERSION)+$(BUILD)

install:
	@ true

test: dependencies
	bundle exec rspec $(RSPEC_ARGS)

dependencies:
	bundle package

lint: dependencies
	bundle exec rubocop --fail-level=error

dist:
	/usr/bin/env BRANCH=$(BRANCH) BUILD=$(BUILD) APP_VERSION=$(APP_VERSION) ./package.sh
