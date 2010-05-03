package Curation::Controller::Curation;

use warnings;
use strict;

# Other modules:
use base 'Mojolicious::Controller';

# Module implementation
#
sub index {
    my ($self, $c) = @_;
    $self->redirect_to('/curation/genes');
}

1;