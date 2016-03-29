#!/usr/bin/env make

GIT_ROOT:=$(shell git rev-parse --show-toplevel)

.PHONY: install test dist

all: lint test dist

NAME=configgin
VERSION:=$(shell cat VERSION)
VERSION_OFFSET := $(shell git describe --tags --long | sed -r 's/[0-9.]+-([0-9]+)-(g[a-f0-9]+)/\1.\2/')
BRANCH:=$(shell (git describe --all --exact-match HEAD 2>/dev/null || echo HEAD) | sed 's@.*/@@')
APP_VERSION=$(NAME)-$(VERSION)+$(VERSION_OFFSET).$(BRANCH)

install:
	@ true

vendor/sentinel: Gemfile Gemfile.lock
	bundle package
	touch $@

test: vendor/sentinel
	bundle exec rspec $(RSPEC_ARGS)

lint: vendor/sentinel
	bundle exec rubocop --fail-level=error

dist:
	/usr/bin/env APP_VERSION=$(APP_VERSION) ./package.sh
