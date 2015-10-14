.PHONY: test

install:
	@ true

test:
	bundle exec rspec $(RSPEC_ARGS)

lint:
	rubocop
