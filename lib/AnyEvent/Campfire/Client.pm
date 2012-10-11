package AnyEvent::Campfire::Client;
{
  $AnyEvent::Campfire::Client::VERSION = '0.0.1';
}

# Abstract: Campfire API in an event loop
use Moose;
use namespace::autoclean;

use AnyEvent;
use AnyEvent::HTTP::ScopedClient;
use AnyEvent::Campfire::Stream;
use URI;
use MIME::Base64;
use JSON::XS;
use Try::Tiny;

extends 'AnyEvent::Campfire';

has 'account' => (
    is  => 'ro',
    isa => 'Str',
);

sub BUILD {
    my $self = shift;

    if ( !$self->authorization || !scalar @{ $self->rooms } || !$self->account )
    {
        print STDERR
          "Not enough parameters provided. I Need a token, rooms and account\n";
        exit(1);
    }

    for my $room ( @{ $self->rooms } ) {
        my $uri = sprintf "https://%s.campfirenow.com/room/$room/join",
          $self->account;
        my $scope = AnyEvent::HTTP::ScopedClient->new($uri);
        $scope->header(
            {
                Authorization => $self->authorization,
                Accept        => '*/*',
            }
          )->post(
            sub {
                my ( $body, $hdr ) = @_;
                if ( $hdr->{Status} !~ m/^2/ ) {
                    $self->emit( 'error', "$hdr->{Status}: $hdr->{Reason}" );
                    return;
                }

                $self->emit( 'join', $room );

                my $stream = AnyEvent::Campfire::Stream->new(
                    token => $self->token,
                    rooms => join( ',', @{ $self->rooms } ),
                );

                $stream->on( 'stream', $self->_events->{message}[0] );
                $stream->on( 'error',  $self->_events->{error}[0] );
            }
          );
    }
}

sub speak {
    my ( $self, $room, $text ) = @_;

    my $scope = AnyEvent::HTTP::ScopedClient->new(
        sprintf "https://%s.campfirenow.com/room/$room/speak",
        $self->account );
    $scope->header(
        {
            Authorization  => $self->authorization,
            Accept         => '*/*',
            'Content-Type' => 'application/json',
        }
      )->post(
        encode_json( { message => { body => $text } } ),
        sub {
            my ( $body, $hdr ) = @_;
            if ( !$body || $hdr->{Status} !~ m/^2/ ) {
                $self->emit( 'error', $hdr->{Reason} );
                return;
            }
        }
      );
}

sub leave {
    my ( $self, $room ) = @_;
    my $scope = AnyEvent::HTTP::ScopedClient->new(
        sprintf "https://%s.campfirenow.com/room/$room/leave",
        $self->account );
    $scope->header(
        {
            Authorization  => $self->authorization,
            Accept         => '*/*',
            'Content-Type' => 'application/json',
        }
      )->post(
        sub {
            my ( $body, $hdr ) = @_;
            if ( !$body || $hdr->{Status} !~ m/^2/ ) {
                $self->emit( 'error', $hdr->{Reason} );
                return;
            }

            my $data;
            try {
                $data = decode_json($body);
            }
            catch {
                $self->emit( 'error', $_ );
                return;
            };

            $self->emit( 'leave', $data );
        }
      );
}

sub exit {
    my $self = shift;
    for my $room ( @{ $self->rooms } ) {
        $self->leave($room);
    }
}

__PACKAGE__->meta->make_immutable;

1;


1;

__END__

=pod

=encoding utf-8

=head1 NAME

AnyEvent::Campfire::Client

=head1 VERSION

version 0.0.1

=head1 SYNOPSIS

    use AnyEvent::Campfire::Client;
    my $client = AnyEvent::Campfire::Client->new(
        token => 'xxxx',
        rooms => '1234',
        account => 'p5-hubot',
    );

    $client->on(
        'join',
        sub {
            my ($e, $data) = @_; # $e is event emitter. please ignore it.
            $client->speak($data->{room}, "hi");
        }
    );

    $client->on(
        'message',
        sub {
            my ($e, $data) = @_;
            # ...
        }
    );

    ## want to exit?
    $client->exit;

=head1 AUTHOR

Hyungsuk Hong <hshong@perl.kr>

=head1 COPYRIGHT AND LICENSE

This software is copyright (c) 2012 by Hyungsuk Hong.

This is free software; you can redistribute it and/or modify it under
the same terms as the Perl 5 programming language system itself.

=cut
