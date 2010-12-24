package Curation::Controller::Usersession;

use warnings;
use strict;
use File::Spec::Functions;
use Digest::MD5 qw/md5_hex/;

# Other modules:
use base 'Mojolicious::Controller';

# Module implementation

sub login {
    my ($self) = @_;
    my $config = $self->app->config;
    $self->redirect_to('home') if $self->session('initials'); 
    $self->stash( signup => $config->{signup} ) if $config->{signup};
}

sub logout {
    my ($self) = @_;
    $self->session(expires => 1);
    $self->flash( message => 'Logged out');
    $self->redirect_to('login');
}

sub sign {
    my ($self) = @_;
    if ( !$self->app->config->{signup} ) {
        $self->flash( message => 'Signup is disabled' );
        $self->redirect_to('login');
    }
}

sub validate {
    my ($self) = @_;
    if (!$self->session('initials')) {
        $self->flash( message => 'Please log in');
        $self->redirect_to('login') ;       
    }
    return 1;
}

sub create {
    my ($self) = @_;

    my $password = $self->req->param('password');
    my $username = $self->req->param('username');

    if ( $password !~ m{\w} || $username !~ m{\w} ){
        $self->flash( message => 'Both password and username must be provided');  
        $self->redirect_to('login');        
    };
    use Data::Dumper;
    $password =~ m{(\w)};
    $self->app->log->debug(Dumper $1);
    
    my $dbfile = catfile( $self->app->home->rel_dir('db'),
        $self->app->config->{database}->{login} );
    my $dbh = DBI->connect( "dbi:SQLite:dbname=$dbfile", '', '' );

    my $sql =
        'SELECT initials FROM users WHERE name like ? and password like ?;';
    my $sth = $dbh->prepare($sql);
    $sth->execute( $username, $password );

    my $initials = $sth->fetchrow();
    if (!$initials){
        $self->flash( message => 'Provided username and password cobination not found');  
        $self->redirect_to('login');
    };

    $self->app->log->info( 'login: ' . $initials );
    
    $self->session( initials => $initials, username => $username );
    $self->redirect_to('home');
}

sub create_user {
    my ($self) = @_;

    my $username         = $self->req->param('username');
    my $initials         = $self->req->param('initials');
    my $password         = $self->req->param('password');
    my $password_confirm = $self->req->param('password_confirm');

    $self->render_exception('entered password does not match')
        if $password ne $password_confirm;

    my $schema = $self->app->schema;
    my $rs     = $schema->resultset('Curator');

    my $user = $rs->search(
        {   name     => $username,
            password => $password
        }
    )->first;
    if ($user) {
        $self->flash( message => "User $username already exists" );
        $self->redirect_to('login');
    }
    $schema->txn_do(
        sub {
            $user = $rs->create(
                {   name     => $username,
                    initials => $initials,
                    password => md5_hex($password)
                }
            );
        }
    );
    $self->flash( message => 'User created, try to log in' );
    $self->redirect_to('login');
}


1;