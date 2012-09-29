#!/usr/bin/env perl
use strict;
use warnings;
use Test::More;

use Web::Request;
use Web::Response;

{
    my $res = Web::Response->new(sub {
        my $responder = shift;
        $responder->([200, [], ["Hello world"]]);
    });
    my $psgi_res = $res->finalize;
    ok(ref($psgi_res) eq 'CODE', "got a coderef");

    my $complete_response;
    my $responder = sub { $complete_response = $_[0] };
    $psgi_res->($responder);
    is_deeply(
        $complete_response,
        [ 200, [], ["Hello world"] ],
        "got the right response"
    );
}

{
    use utf8;

    my $req = Web::Request->new_from_env({});

    my $res = $req->new_response(sub {
        my $responder = shift;
        $responder->([200, [], ["café"]]);
    });
    my $psgi_res = $res->finalize;
    ok(ref($psgi_res) eq 'CODE', "got a coderef");

    my $complete_response;
    my $responder = sub { $complete_response = $_[0] };
    $psgi_res->($responder);
    is_deeply(
        $complete_response,
        [ 200, [], ["caf\xe9"] ],
        "got the right response"
    );
}

{
    use utf8;

    my $req = Web::Request->new_from_env({});
    $req->encoding('UTF-8');

    my $res = $req->new_response(sub {
        my $responder = shift;
        $responder->([200, [], ["café"]]);
    });
    my $psgi_res = $res->finalize;
    ok(ref($psgi_res) eq 'CODE', "got a coderef");

    my $complete_response;
    my $responder = sub { $complete_response = $_[0] };
    $psgi_res->($responder);
    is_deeply(
        $complete_response,
        [ 200, [], ["caf\xc3\xa9"] ],
        "got the right response"
    );
}

done_testing;
