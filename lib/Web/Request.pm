package Web::Request;
use Moose;

use Encode ();
use HTTP::Headers;
use URI;

has env => (
    traits  => ['Hash'],
    is      => 'ro',
    isa     => 'HashRef',
    lazy    => 1,
    default => sub {
        confess "Can't get the env if it wasn't provided during construction";
    },
    handles => {
        address         => 'REMOTE_ADDR',
        remote_host     => 'REMOTE_HOST',
        protocol        => 'SERVER_PROTOCOL',
        method          => 'REQUEST_METHOD',
        port            => 'SERVER_PORT',
        user            => 'REMOTE_USER',
        request_uri     => 'REQUEST_URI',
        path_info       => 'PATH_INFO',
        script_name     => 'SCRIPT_NAME',
        scheme          => 'psgi.url_scheme',
        _input          => 'psgi.input',
        content_length  => 'CONTENT_LENGTH',
        content_type    => 'CONTENT_TYPE',
        session         => 'psgix.session',
        session_options => 'psgix.session.options',
        logger          => 'psgix.logger',
    },
);

has uri => (
    is      => 'ro',
    isa     => 'URI',
    lazy    => 1,
    default => sub {
        ...
    },
);

has headers => (
    is      => 'ro',
    isa     => 'HTTP::Headers',
    lazy    => 1,
    default => sub {
        ...
    },
    handles => ['header', 'content_encoding', 'referer', 'user_agent'],
);

has cookies => (
    is      => 'ro',
    isa     => 'HashRef',
    lazy    => 1,
    default => sub {
        ...
    },
);

has content => (
    is      => 'ro',
    isa     => 'Str',
    lazy    => 1,
    default => sub {
        ...
    },
);

has query_parameters => (
    is      => 'ro',
    isa     => 'HashRef[Str]',
    lazy    => 1,
    default => sub {
        my $self = shift;

        my %params = $self->uri->query_form;
        return {
            map { $_ => $self->decode($params{$_}) } keys %params
        };
    },
);

has all_query_parameters => (
    is      => 'ro',
    isa     => 'HashRef[ArrayRef[Str]]',
    lazy    => 1,
    default => sub {
        my $self = shift;

        my @params = $self->uri->query_form;
        my $it = natatime 2, @params;
        my $ret = {};

        while (my ($k, $v) = $it->()) {
            push @{ $ret->{$k} ||= [] }, $self->decode($v);
        }

        return $ret;
    },
);

has body_parameters => (
    is      => 'ro',
    isa     => 'HashRef[Str]',
    lazy    => 1,
    default => sub {
        ...
    },
);

has all_body_parameters => (
    is      => 'ro',
    isa     => 'HashRef[ArrayRef[Str]]',
    lazy    => 1,
    default => sub {
        ...
    },
);

has uploads => (
    is      => 'ro',
    isa     => 'ArrayRef[Web::Request::Upload]',
    lazy    => 1,
    default => sub {
        ...
    },
);

has encoding => (
    is      => 'ro',
    isa     => 'Str',
    default => 'iso-8859-1',
);

has _encoding_obj => (
    is      => 'ro',
    isa     => 'Encode::Encoding',
    lazy    => 1,
    default => sub { Encode::find_encoding(shift->encoding) },
    handles => ['decode', 'encode'],
);

sub new_from_env {
    my $class = shift;
    my ($env) = @_;

    return $class->new(env => $env);
}

sub new_from_request {
    my $class = shift;
    my ($req) = @_;

    return $class->new_from_env(req_to_psgi($req));
}

sub response_class { 'Web::Response' }

sub path {
    my $self = shift;

    my $path = $self->path_info;
    return $path if length($path);
    return '/';
}

sub uri_base {
    ...
}

sub new_response {
    my $self = shift;

    $self->response_class->new(@_);
}

sub parameters {
    my $self = shift;

    return {
        %{ $self->query_parameters },
        %{ $self->body_parameters },
    };
}

sub all_parameters {
    my $self = shift;

    my $ret = { %{ $self->all_query_parameters } };
    my $body_parameters = $self->all_body_parameters;

    for my $key (keys %$body_parameters) {
        push @{ $ret->{$key} ||= [] }, @{ $body_parameters->{key} };
    }

    return $ret;
}

sub param {
    my $self = shift;
    my ($key) = @_;

    $self->parameters->{$key};
}

__PACKAGE__->meta->make_immutable;
no Moose;

1;
