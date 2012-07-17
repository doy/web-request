package Web::Request::Upload;
use Moose;

use HTTP::Headers;

has headers => (
    is      => 'ro',
    isa     => 'HTTP::Headers',
    handles => ['content_type'],
);

has tempname => (
    is  => 'ro',
    isa => 'Str',
);

has size => (
    is  => 'ro',
    isa => 'Int',
);

has filename => (
    is  => 'ro',
    isa => 'Str',
);

sub basename {
    ...
}

__PACKAGE__->meta->make_immutable;
no Moose;

1;
