use strict;
use warnings;
package AnyEvent::CurrentCost;

# ABSTRACT: AnyEvent module for reading from Current Cost energy meters

=head1 SYNOPSIS

  # Create simple Current Cost reader with logging callback
  AnyEvent::CurrentCost->new(callback => sub { print $_[0]->summary },
                             device => '/dev/ttyUSB0');

  # start event loop
  AnyEvent->condvar->recv;

=head1 DESCRIPTION

AnyEvent module for reading from Current Cost energy meters.

B<IMPORTANT:> This is an early release and the API is still subject to
change.

=cut

use constant DEBUG => $ENV{ANYEVENT_CURRENT_COST_DEBUG};
use base qw/Device::CurrentCost/;
use AnyEvent;
use AnyEvent::Handle;
use Carp qw/croak/;

=method C<new(%params)>

Constructs a new C<AnyEvent::CurrentCost> object.  The supported
parameters are:

=over

=item device

The name of the device to connect to.  The value should be a tty device
name.  The default is C</dev/ttyUSB0>.

=item callback

The callback to execute when a message is received.

=back

=cut

sub new {
  my ($pkg, %p) = @_;
  croak $pkg.q{->new: 'callback' parameter is required} unless ($p{callback});
  my $self = $pkg->SUPER::new(%p);
  $self;
}

sub DESTROY { shift->cleanup }

=method C<cleanup()>

This method attempts to destroy any resources in the event of a
disconnection or fatal error.

=cut

sub cleanup {
  my $self = shift;
  print STDERR "cleanup\n" if DEBUG;
  delete $self->{handle};
  close $self->filehandle;
}

sub _error {
  my ($self, $fatal, $message) = @_;
  $self->cleanup($message);
  $self->{on_error}->($fatal, $message) if ($self->{on_error});
}

=method C<open()>

This method opens the serial port and configures it.

=cut

sub open {
  my $self = shift;
  my $fh = $self->SUPER::open;
  my $handle; $handle =
    AnyEvent::Handle->new(
                          fh => $fh,
                          on_error => sub {
                            my ($handle, $fatal, $msg) = @_;
                            print STDERR $handle.": error $msg\n" if DEBUG;
                            $handle->destroy;
                            $self->_error($fatal, 'Error: '.$msg);
                          },
                          on_rtimeout => sub {
                            my $rbuf = \$handle->{rbuf};
                            print STDERR $handle, ": discarding '",
                              (unpack 'H*', $$rbuf), "'\n" if DEBUG;
                            $$rbuf = '';
                            $handle->rtimeout(0);
                          },
                         );
  $self->{handle} = $handle;
  $handle->push_read(ref $self => $self,
                     sub {
                       $self->{callback}->(@_);
                       return;
                     });
}

sub _time_now {
  AnyEvent->now;
}

=method C<anyevent_read_type()>

This method is used to register an L<AnyEvent::Handle> read type
method to read Current Cost messages.

=cut

sub anyevent_read_type {
  my ($handle, $cb, $self) = @_;
  sub {
    my $rbuf = \$handle->{rbuf};
    $handle->rtimeout($self->{discard_timeout});
    while (1) { # read all message from the buffer
      print STDERR "Before: ", (unpack 'H*', $$rbuf||''), "\n" if DEBUG;
      my $res = $self->read_one($rbuf);
      return unless ($res);
      print STDERR "After: ", (unpack 'H*', $$rbuf), "\n" if DEBUG;
      $res = $cb->($res) and return $res;
    }
  }
}

1;
