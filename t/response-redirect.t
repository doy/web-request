#!/usr/bin/env perl
use strict;
use warnings;
use Test::More;

use Web::Response;

{
    my $res = Web::Response->new;
    $res->redirect('http://www.google.com/');
    is $res->location, 'http://www.google.com/';
    is $res->status, 302;

    is_deeply $res->finalize, [ 302, [ 'Location' => 'http://www.google.com/' ], [] ];
}

{
    my $res = Web::Response->new;
    $res->redirect('http://www.google.com/', 301);
    is_deeply $res->finalize, [ 301, [ 'Location' => 'http://www.google.com/' ], [] ];
}

{
    my $uri_invalid = "http://www.google.com/\r\nX-Injection: true\r\n\r\nHello World";

    my $res = Web::Response->new;
    $res->redirect($uri_invalid, 301);
    my $psgi_res = $res->finalize;
    ok $psgi_res->[1][1] !~ /\n/;
}

done_testing;
