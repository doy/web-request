package Web::Request::Upload;
use Moose;

use HTTP::Headers;

use Web::Response::Types;

has headers => (
    is      => 'ro',
    isa     => 'Web::Response::Types::HTTP::Headers',
    coerce  => 1,
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

# XXX Path::Class, and just make this a delegation?
# would that work at all on win32?
has basename => (
    is  => 'ro',
    isa => 'Str',
    lazy => 1,
    default => sub {
        my $self = shift;

        require File::Spec::Unix;

        my $basename = $self->{filename};
        $basename =~ s{\\}{/}g;
        $basename = (File::Spec::Unix->splitpath($basename))[2];
        $basename =~ s{[^\w\.-]+}{_}g;

        return $basename;
    },
);

__PACKAGE__->meta->make_immutable;
no Moose;

1;
