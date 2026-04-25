#!/usr/bin/env bats

load test_helper

setup() {
	load_lib command_call
}

@test "matches bare /cmd" {
	run command_called "/foo" foo
	[ "$status" -eq 0 ]
}

@test "matches /cmd with trailing args" {
	run command_called "/foo bar baz" foo
	[ "$status" -eq 0 ]
}

@test "matches /cmd followed by newline" {
	run command_called $'/foo\nmore stuff' foo
	[ "$status" -eq 0 ]
}

@test "matches /cmd with leading whitespace" {
	run command_called $'   \n  /foo' foo
	[ "$status" -eq 0 ]
}

@test "matches harness command-name wrapper" {
	run command_called "before <command-name>/foo</command-name> after" foo
	[ "$status" -eq 0 ]
}

@test "matches custom marker substring" {
	run command_called "ignore <!-- foo-marker --> rest" foo "<!-- foo-marker -->"
	[ "$status" -eq 0 ]
}

@test "does not match different command" {
	run command_called "/bar" foo
	[ "$status" -eq 1 ]
}

@test "does not match /foo embedded inside another word" {
	run command_called "say /foobar" foo
	[ "$status" -eq 1 ]
}

@test "does not match marker-less prompt when marker required and absent" {
	run command_called "no marker here" foo "<!-- foo-marker -->"
	[ "$status" -eq 1 ]
}

@test "does not match /cmd inside arbitrary middle text without wrapper" {
	run command_called "the user said /foo earlier" foo
	[ "$status" -eq 1 ]
}
