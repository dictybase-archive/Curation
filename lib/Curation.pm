package Curation;

use strict;
use warnings;
use YAML;
use dicty::DBH;
use File::Spec::Functions;
use Curation::Utils;
use Modware::DataSource::Chado;
use base 'Mojolicious';
use ModConfig;

use version;
our $VERSION = qv('2.0.0');

__PACKAGE__->attr('config');
__PACKAGE__->attr('has_config');
__PACKAGE__->attr('utils');
__PACKAGE__->attr('dbh');       ## dicty legacy model connection
__PACKAGE__->attr('schema');    ## Modware::DataSource::Chado model connection

# This method will run once at server start
sub startup {
    my ($self) = @_;

    # default log level
    $self->log->level('debug');

# Note that you should use a custom secret to make signed cookies really secure.
    $self->secret('dicty4ever');
    $self->session->cookie_path('/curation');
    $self->session->cookie_name('dictybasecuration');
    $self->session->default_expiration(18000);

    # Routes
    my $router = $self->routes;

    # Controlles namespace
    my $base = $router->namespace;
    $router = $router->namespace( $base . '::Controller' );

    $router->route('curation/login')
        ->to( 'usersession#login', format => 'html' );
    $router->route('curation/logout')
        ->to( 'usersession#logout', format => 'html' );

    $router->route('curation/usersession')->via('post')
        ->to('usersession#create');

    my $bridge = $router->bridge('curation')->to('usersession#validate');

    $bridge->route('')->to( 'curation#index', format => 'html' );
    $bridge->route('genes')->to( 'gene#index', format => 'html' );
    $bridge->route('gene/:id')->to( 'gene#show', format => 'html' );
    $bridge->route('gene/:id/fasta')->via('get')
        ->to( 'gene#fasta', format => 'html' );
    $bridge->route('gene/:id/gbrowse')->via('get')
        ->to( 'gene#gbrowse', format => 'html' );
    $bridge->route('gene/:id/protein')->via('get')
        ->to( 'gene#protein', format => 'html' );
    $bridge->route('gene/:id/blink')->via('get')
        ->to( 'gene#blink', format => 'html' );
    $bridge->route('gene/:id/blast')->via('get')
        ->to( 'gene#blast', format => 'html' );
    $bridge->route('gene/:id/blast/database')->via('get')
        ->to( 'gene#blast_by_database', format => 'html' );
    $bridge->route('gene/:id/curation')->via('get')
        ->to( 'gene#curation', format => 'html' );
    $bridge->route('gene/:id/update')
        ->to( 'gene#update', format => 'html' );
    $bridge->route('gene/:id/skip')
        ->to( 'gene#skip', format => 'html' );

    $bridge->route('reference/:id/')->via('get')
        ->to( 'reference#show', format => 'html' );
    $bridge->route('reference/:id/')->via('delete')
        ->to('reference#delete');

    $bridge->route('reference/:id/gene/:gene_id/')->via('post')
        ->to('reference#link_gene');
    $bridge->route('reference/:id/gene/:gene_id/')->via('delete')
        ->to('reference#unlink_gene');

    $bridge->route('reference/:id/gene/:gene_id/topics/')->via('get')
        ->to( 'reference#get_topics', format => 'json' );
    $bridge->route('reference/:id/gene/:gene_id/topics/')->via('put')
        ->to('reference#update_topics');

    ## not used any more, moved to bulk update from one-by-one
    $bridge->route('reference/:id/gene/:gene_id/topics/')->via('post')
        ->to('reference#add_topic');
    $bridge->route('reference/:id/gene/:gene_id/topics/:topic')->via('delete')
        ->to('reference#delete_topic');

    # config file setup
    $self->set_config;

    # set helper
    $self->utils( Curation::Utils->new() );
    $self->utils->app($self);

    # set dbh
    $self->set_dbh;
}

sub set_config {
    my ($self) = @_;

    my $folder = $self->home->rel_dir('conf');
    return if !-e $folder;

    my $file = catfile( $folder, $self->mode . '.yml' );

    $self->config( YAML::LoadFile($file) );
    $self->has_config(1);
}

sub set_dbh {
    my ($self) = @_;

    $self->dbh( dicty::DBH->new() );
    my $config = $self->config->{database};

    Modware::DataSource::Chado->connect(
        dsn      => $config->{dsn},
        user     => $config->{user},
        password => $config->{pwd},
        attr     => $config->{attr}
    );
    $self->schema( Modware::DataSource::Chado->handler );
}
1;
