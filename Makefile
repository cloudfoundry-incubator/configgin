.PHONY: install test dist

all: lint test dist

include version.mk

NAME=configgin
BRANCH:=$(shell git rev-parse --abbrev-ref HEAD)
COMMIT:=$(shell git describe --tags --long | sed -r 's/[0-9.]+-([0-9]+)-(g[a-f0-9]+)/$(VERSION)+\1.\2/')
APP_VERSION=$(NAME)-$(COMMIT).$(BRANCH)

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
