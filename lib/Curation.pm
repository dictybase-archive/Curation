package Curation;

use strict;
use warnings;
use YAML;
use File::Spec::Functions;
use Curation::Renderer::TT;
use Curation::Helper;
use dicty::DBH;
use base 'Mojolicious';

__PACKAGE__->attr('config');
__PACKAGE__->attr('template_path');
__PACKAGE__->attr( 'has_config', default => 0 );
__PACKAGE__->attr('helper');
__PACKAGE__->attr('dbh');

# This method will run once at server start
sub startup {
    my ($self) = @_;

    #default log level
    $self->log->level('debug');

    #config file setup
    $self->set_config;

    #set helper
    $self->helper( Curation::Helper->new() );
    $self->helper->app($self);

    #set up various renderer
    $self->set_renderer;
    
    ## set dbh
    $self->dbh(dicty::DBH->new());
    # Routes
    my $router = $self->routes;
    
    my $base = $router->namespace();
    $router->namespace( $base . '::Controller' );
    
    $self->session->cookie_domain('.dictybase.org');

    my $bridge = $router->bridge('/curation')->to(
        controller => 'usersession',
        action     => 'validate'
    );

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

    $bridge->route('/')
        ->to( controller => 'curation', action => 'index', format => 'html' );

    $bridge->route('/genes')
        ->to( controller => 'gene', action => 'index', format => 'html' );

    $bridge->route('/gene/:id')
        ->to( controller => 'gene', action => 'show', format => 'html' );

    $bridge->route('/gene/:id/update')
        ->to( controller => 'gene', action => 'update', format => 'html' );

}

sub set_renderer {
    my ($self) = @_;

    #try to set the default template path for TT
    #keep in mind this setup is separate from the Mojo's default template path
    #if something not specifically is not set it defaults to Mojo's default
    use Data::Dumper;
    $self->log->debug( Dumper $self->config );

    $self->template_path( $self->renderer->root );
    if ( $self->has_config and $self->config->{default}->{template_path} ) {
        $self->template_path( $self->config->{default}->{template_path} );
    }

    my $tpath = $self->template_path;

    $self->log->debug(qq/default template path for TT $tpath/);

    my $mode        = $self->mode;
    my $compile_dir = $self->home->rel_dir('tmp');
    if ( $mode eq 'production' or $mode eq 'test' ) {
        $compile_dir = $self->home->rel_dir('webtmp');
    }
    $self->log->debug(qq/default compile path for TT $compile_dir/);
    if ( !-e $compile_dir ) {
        $self->log->error("folder for template compilation is absent");
    }

    my $tt = Curation::Renderer::TT->new(
        path        => $tpath,
        compile_dir => $compile_dir,
        option      => {
            PRE_PROCESS => $self->config ? $self->config->{page}->{header}
                || ''
            : '',
            POST_PROCESS => $self->config ? $self->config->{page}->{footer}
                || ''
            : '',
        },
    );

    $self->renderer->add_handler( tt => $tt->build );

    #$self->renderer->default_handler('tt');
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
#    $self->log->debug(qq/got config file $file/);
    $self->config( YAML::LoadFile($file) );
    $self->has_config(1);
}

1;
