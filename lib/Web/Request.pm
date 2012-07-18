package Web::Request;
use Moose;

use Encode ();
use List::MoreUtils ();
use HTTP::Headers ();
use HTTP::Message::PSGI ();
use URI ();
use URI::Escape ();

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

has _uri_base => (
    is      => 'ro',
    isa     => 'Str',
    lazy    => 1,
    default => sub {
        my $self = shift;

        my $env = $self->env;

        my $scheme = $self->scheme || "http";
        my $server = $env->{HTTP_HOST};
        $server = ($env->{SERVER_NAME} || '') . ':'
                . ($env->{SERVER_PORT} || 80)
            unless defined $server;
        my $path = $self->script_name || '/';

        return "${scheme}://${server}${path}";
    },
);

has uri_base => (
    is      => 'ro',
    isa     => 'URI',
    lazy    => 1,
    default => sub { URI->new(shift->_uri_base)->canonical },
);

has uri => (
    is      => 'ro',
    isa     => 'URI',
    lazy    => 1,
    default => sub {
        my $self = shift;

        my $base = $self->_uri_base;

        # We have to escape back PATH_INFO in case they include stuff
        # like ? or # so that the URI parser won't be tricked. However
        # we should preserve '/' since encoding them into %2f doesn't
        # make sense. This means when a request like /foo%2fbar comes
        # in, we recognize it as /foo/bar which is not ideal, but that's
        # how the PSGI PATH_INFO spec goes and we can't do anything
        # about it. See PSGI::FAQ for details.
        # http://github.com/miyagawa/Plack/issues#issue/118
        my $path_escape_class = '^A-Za-z0-9\-\._~/';

        my $path = URI::Escape::uri_escape(
            $self->path_info || '',
            $path_escape_class
        );
        $path .= '?' . $self->env->{QUERY_STRING}
            if defined $self->env->{QUERY_STRING}
            && $self->env->{QUERY_STRING} ne '';

        $base =~ s!/$!! if $path =~ m!^/!;

        return URI->new($base . $path)->canonical;
    },
);

has headers => (
    is      => 'ro',
    isa     => 'HTTP::Headers',
    lazy    => 1,
    default => sub {
        my $self = shift;
        my $env = $self->env;
        return HTTP::Headers->new(
            map {
                (my $field = $_) =~ s/^HTTPS?_//;
                $field => $env->{$_}
            } grep {
                /^(?:HTTP|CONTENT)/i
            } keys %$env
        );
    },
    handles => ['header', 'content_encoding', 'referer', 'user_agent'],
);

has cookies => (
    is      => 'ro',
    isa     => 'HashRef',
    lazy    => 1,
    default => sub {
        my $self = shift;

        my $cookie_str = $self->env->{HTTP_COOKIE};
        return {} unless defined $cookie_str;

        my %results;
        for my $pair (grep { /=/ } split /[;,] ?/, $cookie_str) {
            $pair =~ s/^\s+|\s+$//g;
            my ($key, $value) = map {
                URI::Escape::uri_unescape($_)
            } split(/=/, $pair, 2);
            $results{$key} = $value unless exists $results{$key};
        }

        return \%results;
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
        my $it = List::MoreUtils::natatime 2, @params;
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

    return $class->new_from_env(HTTP::Message::PSGI::req_to_psgi($req));
}

sub response_class { 'Web::Response' }
sub upload_class   { 'Web::Request::Upload' }

sub path {
    my $self = shift;

    my $path = $self->path_info;
    return $path if length($path);
    return '/';
}

sub uri_base { URI->new(shift->_uri_base)->canonical; }

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
