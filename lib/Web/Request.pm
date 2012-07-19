package Web::Request;
use Moose;

use Class::Load ();
use Encode ();
use HTTP::Body ();
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
        address         => [ get => 'REMOTE_ADDR' ],
        remote_host     => [ get => 'REMOTE_HOST' ],
        protocol        => [ get => 'SERVER_PROTOCOL' ],
        method          => [ get => 'REQUEST_METHOD' ],
        port            => [ get => 'SERVER_PORT' ],
        user            => [ get => 'REMOTE_USER' ],
        request_uri     => [ get => 'REQUEST_URI' ],
        path_info       => [ get => 'PATH_INFO' ],
        script_name     => [ get => 'SCRIPT_NAME' ],
        scheme          => [ get => 'psgi.url_scheme' ],
        _input          => [ get => 'psgi.input' ],
        content_length  => [ get => 'CONTENT_LENGTH' ],
        content_type    => [ get => 'CONTENT_TYPE' ],
        session         => [ get => 'psgix.session' ],
        session_options => [ get => 'psgix.session.options' ],
        logger          => [ get => 'psgix.logger' ],
    },
);

has _base_uri => (
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

has base_uri => (
    is      => 'ro',
    isa     => 'URI',
    lazy    => 1,
    default => sub { URI->new(shift->_base_uri)->canonical },
);

has uri => (
    is      => 'ro',
    isa     => 'URI',
    lazy    => 1,
    default => sub {
        my $self = shift;

        my $base = $self->_base_uri;

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

has _http_body => (
    is  => 'rw',
    isa => 'HTTP::Body',
);

has _parsed_body => (
    traits  => ['Hash'],
    is      => 'ro',
    isa     => 'HashRef',
    lazy    => 1,
    default => sub {
        my $self = shift;

        my $ct = $self->content_type;
        my $cl = $self->content_length;
        if (!$ct && !$cl) {
            return {
                content => '',
                body    => {},
                uploads => {},
            };
        }

        my $body = HTTP::Body->new($ct, $cl);
        # automatically clean up, but wait until the request object is gone
        $body->cleanup(1);
        $self->_http_body($body);

        my $input = $self->_input;

        if ($self->env->{'psgix.input.buffered'}) {
            $input->seek(0, 0);
        }

        my $content = '';
        my $spin = 0;
        while ($cl) {
            $input->read(my $chunk, $cl < 8192 ? $cl : 8192);
            my $read = length($chunk);
            $cl -= $read;
            $body->add($chunk);
            $content .= $chunk;

            if ($read == 0 && $spin++ > 2000) {
                confess "Bad Content-Length ($cl bytes remaining)";
            }
        }

        if ($self->env->{'psgix.input.buffered'}) {
            $input->seek(0, 0);
        }
        else {
            open my $fh, '<', \$content;
            $self->env->{'psgix.input'} = $fh;
            $self->env->{'psgix.input.buffered'} = 1;
        }

        return {
            content => $content,
            body    => $body->param,
            uploads => $body->upload,
        }
    },
    handles => {
        _content => [ get => 'content' ],
        _body    => [ get => 'body' ],
        _uploads => [ get => 'uploads' ],
    },
);

has content => (
    is      => 'ro',
    isa     => 'Str',
    lazy    => 1,
    default => sub {
        my $self = shift;

        # XXX get Plack::TempBuffer onto CPAN separately, so that this doesn't
        # always have to be sitting in memory
        return $self->decode($self->_parsed_body->{content});
    },
);

has query_parameters => (
    is      => 'ro',
    isa     => 'HashRef[Str]',
    lazy    => 1,
    default => sub {
        my $self = shift;

        my %params = (
            $self->uri->query_form,
            (map { $_ => '' } $self->uri->query_keywords),
        );
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
        my $ret = {};

        while (my ($k, $v) = splice @params, 0, 2) {
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
        my $self = shift;

        my $body = $self->_body;

        my $ret = {};
        for my $key (keys %$body) {
            my $val = $body->{$key};
            $ret->{$key} = $self->decode(ref($val) ? $val->[-1] : $val);
        }

        return $ret;
    },
);

has all_body_parameters => (
    is      => 'ro',
    isa     => 'HashRef[ArrayRef[Str]]',
    lazy    => 1,
    default => sub {
        my $self = shift;

        my $body = $self->_body;

        my $ret = {};
        for my $key (keys %$body) {
            my $val = $body->{$key};
            $ret->{$key} = ref($val)
                ? [ map { $self->decode($_) } @$val ]
                : [ $self->decode($val) ];
        }

        return $ret;
    },
);

has uploads => (
    is      => 'ro',
    isa     => 'HashRef[Web::Request::Upload]',
    lazy    => 1,
    default => sub {
        my $self = shift;

        my $uploads = $self->_uploads;

        my $ret = {};
        for my $key (keys %$uploads) {
            my $val = $uploads->{$key};
            $ret->{$key} = ref($val) eq 'ARRAY'
                ? $self->_new_upload($val->[-1])
                : $self->_new_upload($val);
        }

        return $ret;
    },
);

has all_uploads => (
    is      => 'ro',
    isa     => 'HashRef[ArrayRef[Web::Request::Upload]]',
    lazy    => 1,
    default => sub {
        my $self = shift;

        my $uploads = $self->_uploads;

        my $ret = {};
        for my $key (keys %$uploads) {
            my $val = $uploads->{$key};
            $ret->{$key} = ref($val) eq 'ARRAY'
                ? [ map { $self->_new_upload($_) } @$val ]
                : [ $self->_new_upload($val) ];
        }

        return $ret;
    },
);

has encoding => (
    is      => 'ro',
    isa     => 'Str',
    default => 'iso-8859-1',
);

has _encoding_obj => (
    is      => 'ro',
    isa     => 'Object', # no idea what this should be
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

sub new_response {
    my $self = shift;

    Class::Load::load_class($self->response_class);
    $self->response_class->new(@_);
}

sub _new_upload {
    my $self = shift;

    Class::Load::load_class($self->upload_class);
    $self->upload_class->new(@_);
}

sub path {
    my $self = shift;

    my $path = $self->path_info;
    return $path if length($path);
    return '/';
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
