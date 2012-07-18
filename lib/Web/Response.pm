package Web::Response;
use Moose;

use HTTP::Headers ();
use URI::Escape ();

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
    is      => 'rw',
    isa     => 'HashRef[Str|HashRef[Str]]',
    lazy    => 1,
    default => sub { +{} },
);

sub redirect {
    my $self = shift;
    my ($url, $status) = @_;

    $self->status($status || 302);
    $self->location($url);
}

sub finalize {
    my $self = shift;

    $self->_finalize_cookies;

    return [
        $self->status,
        [
            map {
                my $k = $_;
                map {
                    my $v = $_;
                    # replace LWS with a single SP
                    $v =~ s/\015\012[\040|\011]+/chr(32)/ge;
                    # remove CR and LF since the char is invalid here
                    $v =~ s/\015|\012//g;
                    ( $k => $v )
                } $self->header($k);
            } $self->headers->header_field_names
        ],
        $self->body
    ];
}

sub _finalize_cookies {
    my $self = shift;

    my $cookies = $self->cookies;
    for my $name (keys %$cookies) {
        $self->headers->push_header(
            'Set-Cookie' => $self->_bake_cookie($name, $cookies->{name}),
        );
    }

    $self->cookies({});
}

sub _bake_cookie {
    my $self = shift;
    my ($name, $val) = @_;

    return '' unless defined $val;
    $val = { value => $val }
        unless ref($val) eq 'HASH';

    my @cookie = (
        URI::Escape::uri_escape($name)
      . '='
      . URI::Escape::uri_escape($val->{value})
    );

    push @cookie, 'domain='  . $val->{domain}
        if defined($val->{domain});
    push @cookie, 'path='    . $val->{path}
        if defined($val->{path});
    push @cookie, 'expires=' . $self->_date($val->{expires})
        if defined($val->{expires});
    push @cookie, 'secure'
        if $val->{secure};
    push @cookie, 'HttpOnly'
        if $val->{httponly};

    return join '; ', @cookie;
}

# XXX DateTime?
my @MON  = qw( Jan Feb Mar Apr May Jun Jul Aug Sep Oct Nov Dec );
my @WDAY = qw( Sun Mon Tue Wed Thu Fri Sat );

sub _date {
    my $self = shift;
    my ($expires) = @_;

    return $expires unless $expires =~ /^\d+$/;

    my ($sec, $min, $hour, $mday, $mon, $year, $wday) = gmtime($expires);
    $year += 1900;

    return sprintf("%s, %02d-%s-%04d %02d:%02d:%02d GMT",
                   $WDAY[$wday], $mday, $MON[$mon], $year, $hour, $min, $sec);
}

__PACKAGE__->meta->make_immutable;
no Moose;

1;
