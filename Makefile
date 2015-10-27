.PHONY: install test dist

all: lint test dist

include version.mk

BRANCH:=$(shell git rev-parse --short HEAD)
BUILD:=$(shell whoami)-$(BRANCH)-$(shell date -u +%Y%m%d%H%M%S)
APP_VERSION=$(VERSION)-$(BUILD)

install:
	@ true

test:
	bundle exec rspec $(RSPEC_ARGS)

lint:
	bundle exec rubocop --fail-level=error

dist:
	./package.sh BRANCH=$(BRANCH) BUILD=$(BUILD) APP_VERSION=$(APP_VERSION)