package Curation::Controller::Usersession;

use warnings;
use strict;
use DBI;
use File::Spec::Functions;

# Other modules:
use base 'Mojolicious::Controller';

# Module implementation
#

sub login {
    my ($self) = @_;
}

sub logout {
    my ($self) = @_;
    $self->render(template => 'usersession/login');
}

sub validate {
    my ( $self, $c ) = @_;
    
    my $session = $self->req->cookie('session');
    my $value   = $session ? $session->value : undefined;
    
    if ( !$value ) {
    	$c->res->code(301);
        $c->res->headers->location('/curation/login'); 
        return;
    }
    return 1;
}

sub create {
    my ( $self, $c ) = @_;
    my $password = $self->req->param('password') || '';
    my $username = $self->req->param('username') || '';
    
    my $dbfile = catfile( $self->app->home->rel_dir('db'), $self->app->config->{database} );
    my $dbh = DBI->connect( "dbi:SQLite:dbname=$dbfile", '', '' );
    
    my $sql = 'SELECT id FROM users WHERE name like ? and password like ?;';
    my $sth = $dbh->prepare($sql);
    $sth->execute( $username, $password );
    
    my $id = $sth->fetchrow();
    
    $self->render(template => 'usersession/login') if !$id;
    
    $self->session(user => 'Bender');
    
    $self->res->cookies(
        Mojo::Cookie::Response->new(
            path  => '/session_cookie',
            name  => 'session',
            value => 'PF'
        )
    );
    $self->render(template => 'gene/index');
    #$c->res->code(301);
    #$c->res->headers->location('/curation');

}

1;