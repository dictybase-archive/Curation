# Copyright (C) 2008-2009, Sebastian Riedel.

package Curation::Controller;

use strict;
use warnings;

use base 'Mojolicious::Controller';

# Well, at least here you'll be treated with dignity.
# Now strip naked and get on the probulator.

sub render { shift->ctx->render(@_) }

sub req { shift->ctx->req }

sub res { shift->ctx->res }

sub stash { shift->ctx->stash(@_) }

sub redirect_to {
    my $self   = shift;
    my $target = shift;

    # Prepare location
    my $base     = $self->req->url->base->clone;
    my $location = Mojo::URL->new->base($base);

    # Path
    if ($target =~ /^\//) { $location->path($target) }

    # URL
    elsif ($target =~ /^\w+\:\/\//) { $location = $target }

    # Named
    else { $location = $self->url_for($target, @_) }

    # Code
    $self->res->code(302);

    # Location header
    $self->res->headers->location($location);

    return $self;
}


1;
__END__

=head1 NAME

dictyTools::Controller - Controller Base Class

=head1 SYNOPSIS

    use base 'dictyTools::Controller';

=head1 DESCRIPTION

L<Mojolicous::Controller> is a controller base class.

=head1 METHODS

L<dictyTools::Controller> inherits all methods from
L<MojoX::Dispatcher::Routes::Controller> and implements the following new
ones.

=head2 C<render>

    $controller->render;
    $controller->render(action => 'foo');

=head2 C<req>

    my $req = $controller->req;

=head2 C<res>

    my $res = $controller->res;

=head2 C<stash>

    my $stash   = $controller->stash;
    my $foo     = $controller->stash('foo');
    $controller = $controller->stash({foo => 'bar'});
    $controller = $controller->stash(foo => 'bar');

=cut
