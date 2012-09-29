#!/usr/bin/env perl
use strict;
use warnings;
use Test::More;

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

done_testing;
