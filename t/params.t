#!/usr/bin/env perl
use strict;
use warnings;
use Test::More;

use Web::Request;

my $req = Web::Request->new_from_env({ QUERY_STRING => "foo=bar" });
is_deeply $req->parameters, { foo => "bar" };
is $req->param('foo'), "bar";
is_deeply [ keys %{ $req->parameters } ], [ 'foo' ];

$req = Web::Request->new_from_env({ QUERY_STRING => "foo=bar&foo=baz" });
is_deeply $req->parameters, { foo => "baz" };
is $req->param('foo'), "baz";
is_deeply $req->all_parameters->{foo}, [ qw(bar baz) ];
is_deeply [ keys %{ $req->parameters } ], [ 'foo' ];

$req = Web::Request->new_from_env({ QUERY_STRING => "foo=bar&foo=baz&bar=baz" });
is_deeply $req->parameters, { foo => "baz", bar => "baz" };
is_deeply $req->query_parameters, { foo => "baz", bar => "baz" };
is $req->param('foo'), "baz";
is_deeply $req->all_parameters->{foo}, [ qw(bar baz) ];
is_deeply [ sort keys %{ $req->parameters } ], [ 'bar', 'foo' ];

done_testing;
