package Web::Response;
use Moose;

use HTTP::Headers;

use Web::Response::Types ();

has status => (
    is      => 'rw',
    isa     => 'Web::Response::Types::HTTPStatus',
    lazy    => 1,
    default => sub { confess "Status was not supplied" },
);

has headers => (
    is      => 'rw',
    isa     => 'Web::Response::Types::HTTP::Headers',
    lazy    => 1,
    coerce  => 1,
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
    isa     => 'Web::Response::Types::PSGIBody',
    lazy    => 1,
    coerce  => 1,
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
