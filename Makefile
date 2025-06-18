.PHONY: deploy install cleanup start yarn migrate format test coverage versions standalone-tests

ROOT_DIR:=$(shell dirname $(realpath $(firstword $(MAKEFILE_LIST))))
SHELL := /bin/bash

evn e:
	export ERL_AFLAGS="-kernel shell_history enabled"

install i:
	mix deps.get

cleanup c:
	-pkill -SIGTERM -f 'beam'

start server s:
	make cleanup
	MIX_ENV=dev iex -S mix phx.server

format f:
	mix format --migrate

test t:
	mix test

coverage cover co:
	mix test --cover

unit-tests ut:
	@echo "Running unit tests..."
	@find test/unit -name "*.exs" -exec elixir {} \;
	@echo "All unit tests completed."

versions v:
	@echo "Tool Versions"
	@cat .tool-versions
	@cat Aptfile
	@echo

