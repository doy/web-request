package Web::Response::Types;
use strict;
use warnings;

use Moose::Util::TypeConstraints;

class_type('HTTP::Headers');

subtype 'Web::Response::Types::StringLike',
    as 'Object',
    where {
        return unless overload::Method($_, '""');
        my $tc = find_type_constraint('Web::Response::Types::PSGIBodyObject');
        return !$tc->check($_);
    };

duck_type 'Web::Response::Types::PSGIBodyObject' => ['getline', 'close'];

subtype 'Web::Response::Types::PSGIBody',
    as 'ArrayRef[Str]|FileHandle|Web::Response::Types::PSGIBodyObject';

subtype 'Web::Response::Types::HTTPStatus',
    as 'Int',
    where { /^[1-5][0-9][0-9]$/ };

subtype 'Web::Response::Types::HTTP::Headers',
    as 'HTTP::Headers';
coerce 'Web::Response::Types::HTTP::Headers',
    from 'ArrayRef',
    via { HTTP::Headers->new(@$_) },
    from 'HashRef',
    via { HTTP::Headers->new(%$_) };

coerce 'Web::Response::Types::PSGIBody',
    from 'Str|Web::Response::Types::StringLike',
    via { [ $_ ] };

1;
