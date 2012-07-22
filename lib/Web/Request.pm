package Web::Request;
use Moose;
# ABSTRACT: common request class for web frameworks

use Class::Load ();
use Encode ();
use HTTP::Body ();
use HTTP::Headers ();
use HTTP::Message::PSGI ();
use URI ();
use URI::Escape ();

=head1 SYNOPSIS

  use Web::Request;

  my $app = sub {
      my ($env) = @_;
      my $req = Web::Request->new_from_env($env);
      # ...
  };

=head1 DESCRIPTION

=cut

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
            # XXX $self->decode too?
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
    clearer => '_clear_content',
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
    clearer => '_clear_query_parameters',
    default => sub {
        my $self = shift;

        my %params = (
            $self->uri->query_form,
            (map { $_ => '' } $self->uri->query_keywords),
        );
        return {
            map { $self->decode($_) } map { $_ => $params{$_} } keys %params
        };
    },
);

has all_query_parameters => (
    is      => 'ro',
    isa     => 'HashRef[ArrayRef[Str]]',
    lazy    => 1,
    clearer => '_clear_all_query_parameters',
    default => sub {
        my $self = shift;

        my @params = $self->uri->query_form;
        my $ret = {};

        while (my ($k, $v) = splice @params, 0, 2) {
            $k = $self->decode($k);
            push @{ $ret->{$k} ||= [] }, $self->decode($v);
        }

        return $ret;
    },
);

has body_parameters => (
    is      => 'ro',
    isa     => 'HashRef[Str]',
    lazy    => 1,
    clearer => '_clear_body_parameters',
    default => sub {
        my $self = shift;

        my $body = $self->_body;

        my $ret = {};
        for my $key (keys %$body) {
            my $val = $body->{$key};
            $key = $self->decode($key);
            $ret->{$key} = $self->decode(ref($val) ? $val->[-1] : $val);
        }

        return $ret;
    },
);

has all_body_parameters => (
    is      => 'ro',
    isa     => 'HashRef[ArrayRef[Str]]',
    lazy    => 1,
    clearer => '_clear_all_body_parameters',
    default => sub {
        my $self = shift;

        my $body = $self->_body;

        my $ret = {};
        for my $key (keys %$body) {
            my $val = $body->{$key};
            $key = $self->decode($key);
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
    is      => 'rw',
    isa     => 'Str',
    builder => 'default_encoding',
    trigger => sub {
        my $self = shift;
        $self->_clear_encoding_obj;
        $self->_clear_content;
        $self->_clear_query_parameters;
        $self->_clear_all_query_parameters;
        $self->_clear_body_parameters;
        $self->_clear_all_body_parameters;
    },
);

has _encoding_obj => (
    is      => 'ro',
    isa     => 'Object', # no idea what this should be
    lazy    => 1,
    clearer => '_clear_encoding_obj',
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

sub response_class   { 'Web::Response'        }
sub upload_class     { 'Web::Request::Upload' }
sub default_encoding { 'iso8859-1'            }

__PACKAGE__->meta->make_immutable;
no Moose;

=head1 CONSTRUCTORS

=head2 new_from_env($env)

Create a new Web::Request object from a L<PSGI> environment hashref.

=head2 new_from_request($request)

Create a new Web::Request object from a L<HTTP::Request> object.

=head2 new(%params)

Create a new Web::Request object with named parameters. Valid parameters are:

=over 4

=item env

A L<PSGI> environment hashref.

=item encoding

The encoding to use for decoding all input in the request. Defaults to
the value of C<default_encoding>.

=back

=cut

=method address

Returns the IP address of the remote client.

=method remote_host

Returns the hostname of the remote client. May be empty.

=method protocol

Returns the protocol (HTTP/1.0, HTTP/1.1, etc.) used in the current request.

=method method

Returns the HTTP method (GET, POST, etc.) used in the current request.

=method port

Returns the local port that this request was made on.

=method path

Returns the request path for the current request. Unlike C<path_info>, this
will never be empty, it will always start with C</>. This is most likely what
you want to use to dispatch on.

=method path_info

Returns the request path for the current request. This can be C<''> if
C<script_name> ends in a C</>. This can be appended to C<script_name> to get
the full (absolute) path that was requested from the server.

=method script_name

Returns the absolute path where your application is mounted. It may be C<''>
(in which case, C<path_info> will start with a C</>).

=method request_uri

Returns the raw, undecoded URI path (the literal path provided in the request,
so C</foo%20bar> in C<GET /foo%20bar HTTP/1.1>). You most likely want to use
C<path>, C<path_info>, or C<script_name> instead.

=method scheme

Returns C<http> or C<https> depending on the scheme used in the request.

=method session

Returns the session object, if a middleware is used which provides one. See
L<PSGI::Extensions>.

=method session_options

Returns the session options hashref, if a middleware is used which provides
one. See L<PSGI::Extensions>.

=method logger

Returns the logger object, if a middleware is used which provides one. See
L<PSGI::Extensions>.

=method uri

Returns the full URI used in the current request, as a L<URI> object.

=method base_uri

Returns the base URI for the current request (only the components up through
C<script_name>) as a L<URI> object.

=method headers

Returns a L<HTTP::Headers> object containing the headers for the current
request.

=method content_length

The length of the content, in bytes. Corresponds to the C<Content-Length>
header.

=method content_type

The MIME type of the content. Corresponds to the C<Content-Type> header.

=method content_encoding

The encoding of the content. Corresponds to the C<Content-Encoding> header.

=method referer

Returns the value of the C<Referer> header.

=method user_agent

Returns the value of the C<User-Agent> header.

=method header($name)

Shortcut for C<< $req->headers->header($name) >>.

=method cookies

Returns a hashref of cookies received in this request. The values are URI
decoded.

=method content

Returns the content received in this request, decoded based on the value of
C<encoding>.

=method param($param)

Returns the parameter value for the parameter named C<$param>. Returns the last
parameter given if more than one are passed.

=method parameters

Returns a hashref of parameter names to values. If a name is given more than
once, the last value is provided.

=method all_parameters

Returns a hashref where the keys are parameter names and the values are
arrayrefs holding every value given for that parameter name. All parameters are
stored in an arrayref, even if there is only a single value.

=method query_parameters

Like C<parameters>, but only return the parameters that were given in the query
string.

=method all_query_parameters

Like C<all_parameters>, but only return the parameters that were given in the
query string.

=method body_parameters

Like C<parameters>, but only return the parameters that were given in the
request body.

=method all_body_parameters

Like C<all_parameters>, but only return the parameters that were given in the
request body.

=method uploads

Returns a hashref of upload objects (instances of C<upload_class>). If more
than one upload is provided with a given name, returns the last one given.

=method all_uploads

Returns a hashref where the keys are upload names and the values are arrayrefs
holding an upload object (instance of C<upload_class>) for every upload given
for that name. All uploads are stored in an arrayref, even if there is only a
single value.

=method new_response(@params)

Returns a new response object, passing C<@params> to its constructor.

=method env

Returns the L<PSGI> environment that was provided in the constructor (or
generated from the L<HTTP::Request>, if C<new_from_request> was used).

=method encoding

Returns the encoding that was provided in the constructor.

=method response_class

Returns the name of the class to use when creating a new response object via
C<new_response>. Defaults to L<Web::Response>. This can be overridden in
a subclass.

=method upload_class

Returns the name of the class to use when creating a new upload object for
C<uploads> or C<all_uploads>. Defaults to L<Web::Request::Upload>. This can be
overridden in a subclass.

=method default_encoding

Returns the name of the default encoding to use for C<encode> and C<decode>.
Defaults to iso8859-1. This can be overridden in a subclass.

=head1 BUGS

No known bugs.

Please report any bugs through RT: email
C<bug-web-request at rt.cpan.org>, or browse to
L<http://rt.cpan.org/NoAuth/ReportBug.html?Queue=Web-Request>.

=head1 SEE ALSO

L<Plack::Request>

=head1 SUPPORT

You can find this documentation for this module with the perldoc command.

    perldoc Web::Request

You can also look for information at:

=over 4

=item * AnnoCPAN: Annotated CPAN documentation

L<http://annocpan.org/dist/Web-Request>

=item * CPAN Ratings

L<http://cpanratings.perl.org/d/Web-Request>

=item * RT: CPAN's request tracker

L<http://rt.cpan.org/NoAuth/Bugs.html?Dist=Web-Request>

=item * Search CPAN

L<http://search.cpan.org/dist/Web-Request>

=back

=cut

1;
