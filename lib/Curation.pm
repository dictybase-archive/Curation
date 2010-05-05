package Curation;

use strict;
use warnings;
use YAML;
use dicty::DBH;
use File::Spec::Functions;

#use local::lib '/home/ubuntu/dictyBase/Libs/modernperl';

use Curation::Renderer::TT;
use Curation::Helper;

use Mojolicious::Plugin::DefaultHelpers;

use base 'Mojolicious';

__PACKAGE__->attr('config');
__PACKAGE__->attr( 'has_config' => 0);
__PACKAGE__->attr('helper');
__PACKAGE__->attr('dbh');

# This method will run once at server start
sub startup {
    my ($self) = @_;

    # default log level
    $self->log->level('debug');

    #my $plugins = $self->plugins(Mojolicious::Plugin::DefaultHelpers->new);

    ##### does not work?
    #Note that you should use a custom secret to make signed cookies really secure.
    $self->secret('My secret passphrase here!');
    
    # Routes
    my $router = $self->routes;
    
    # Controlles namespace
    my $base = $router->namespace;
    $router   = $router->namespace($base. '::Controller');
    
    $router->route('/curation/login')->to(
        controller => 'usersession',
        action     => 'login',
        format     => 'html'
    );
    $router->route('/curation/logout')->to(
        controller => 'usersession',
        action     => 'logout',
        format     => 'html'
    );
    
    $router->route('/curation/usersession')->via('post')->to(
        controller => 'usersession',
        action     => 'create',
    );

    my $bridge = $router->bridge('/curation')->to(
        controller => 'usersession',
        action     => 'validate'
    );

    $bridge->route('/')
        ->to( controller => 'curation', action => 'index', format => 'html' );

    $bridge->route('/genes')
        ->to( controller => 'gene', action => 'index', format => 'html' );

    $bridge->route('/gene/:id')
        ->to( controller => 'gene', action => 'show', format => 'html' );

    $bridge->route('/gene/:id/fasta')->via('get')
        ->to( controller => 'gene', action => 'fasta', format => 'html' );

    $bridge->route('/gene/:id/gbrowse')->via('get')
        ->to( controller => 'gene', action => 'gbrowse', format => 'html' );

    $bridge->route('/gene/:id/blink')->via('get')
        ->to( controller => 'gene', action => 'blink', format => 'html' );
    
    $bridge->route('/gene/:id/blast')->via('get')
        ->to( controller => 'gene', action => 'blast', format => 'html' );

    $bridge->route('/gene/:id/update')
        ->to( controller => 'gene', action => 'update', format => 'html' );
        
    # config file setup
    $self->set_config;

    # set helper
    $self->helper( Curation::Helper->new() );
    $self->helper->app($self);
        
    # set dbh
    $self->dbh(dicty::DBH->new());

}

sub set_config {
    my ( $self, $c ) = @_;

    #set up config file usually look under conf folder
    #supports similar profile as log file

    my $folder = $self->home->rel_dir('conf');
    if ( !-e $folder ) {
        return;
    }

    my $mode   = $self->mode();
    my $suffix = '.yml';

    my $file = catfile( $folder, $mode . $suffix );

    $self->config( YAML::LoadFile($file) );
    $self->has_config(1);
}


1;
