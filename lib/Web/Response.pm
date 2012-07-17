package Web::Response;
use Moose;

use HTTP::Headers;

has status => (
    is      => 'rw',
    isa     => 'Int', # XXX restrict to /^[1-5][0-9][0-9]$/
    lazy    => 1,
    default => sub { confess "Status was not supplied" },
);

has headers => (
    is      => 'rw',
    isa     => 'HTTP::Headers', # XXX coerce from array/hashref
    lazy    => 1,
    default => sub { HTTP::Headers->new },
    handles => {
        header           => 'header',
        content_length   => 'content_length',
        content_type     => 'content_type',
        content_encoding => 'content_encoding',
        location         => [ header => 'Location' ],
    },
);

has body => (
    is      => 'rw',
    lazy    => 1,
    default => sub { [] },
);

has cookies => (
    is      => 'ro',
    isa     => 'HashRef',
    lazy    => 1,
    default => sub { +{} },
);

sub redirect {
    ...
}

sub finalize {
    ...
}

__PACKAGE__->meta->make_immutable;
no Moose;

1;
