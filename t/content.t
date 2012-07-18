#!/usr/bin/env perl
use strict;
use warnings;
use Test::More;
use Plack::Test;

use Web::Request;

my $app = sub {
    my $req = Web::Request->new_from_env(shift);
    is $req->content, 'body';
    $req->new_response(status => 200)->finalize;
};

test_psgi $app, sub {
    my $cb = shift;

    my $req = HTTP::Request->new(POST => "/");
    $req->content("body");
    $req->content_type('text/plain');
    $req->content_length(4);
    $cb->($req);
};

done_testing;

