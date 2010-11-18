package Curation::Controller::Usersession;

use warnings;
use strict;
use DBI;
use File::Spec::Functions;

# Other modules:
use base 'Mojolicious::Controller';

# Module implementation

sub login {
    my ($self) = @_;
    $self->redirect_to('/curation/') if $self->session('initials'); 
}

sub logout {
    my ($self) = @_;
    $self->session(expires => 1);
    $self->redirect_to('/curation/login');
}

sub validate {
    my ($self) = @_;
    $self->redirect_to('/curation/login') if !$self->session('initials');
    return 1;
}

sub create {
    my ($self) = @_;

    my $password = $self->req->param('password');
    my $username = $self->req->param('username');

    $self->redirect_to('/curation/login') if !( $password & $username );

    my $dbfile = catfile( $self->app->home->rel_dir('db'),
        $self->app->config->{database}->{login} );
    my $dbh = DBI->connect( "dbi:SQLite:dbname=$dbfile", '', '' );

    my $sql =
        'SELECT initials FROM users WHERE name like ? and password like ?;';
    my $sth = $dbh->prepare($sql);
    $sth->execute( $username, $password );

    my $initials = $sth->fetchrow();

    $self->app->log->debug( 'login: ' . $initials );

    $self->redirect_to('/curation/login') if !$initials;

    $self->session( initials => $initials, username => $username );
    $self->redirect_to('/curation/');
}

1;