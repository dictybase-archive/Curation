package curationBuilder;
use File::Spec::Functions;
use Carp;
use Archive::Extract;
use File::Path;
use Path::Class;
use Try::Tiny;
use TAP::Harness;
use base qw/Module::Build/;

sub ACTION_deploy {
    my ($self) = @_;
    $self->depends_on('dist');
    my $file = catfile( $self->base_dir, $self->dist_dir . '.tar.gz' );
    my $archive = Archive::Extract->new( archive => $file );
    my $path = $self->prompt( 'Extract archive to:', $ENV{HOME} );
    my $fullpath = catdir( $path, $self->dist_dir );
    if ( -e $fullpath ) {
        rmtree( $fullpath, { verbose => 1 } );
    }
    $archive->extract( to => $path ) or confess $archive->error;
    my $logpath  = catdir( $fullpath, 'log' );
    my $datapath = catdir( $fullpath, 'data' );
    my $dbpath   = catdir( $fullpath, 'db' );

    mkpath( $logpath, { verbose => 1, mode => 0777 } );
    chmod 0777, $logpath;

    #now make the conf files readable
    my @conf = map { $_->stringify } dir( $fullpath, 'conf' )->children();
    chmod 0644, $_ foreach @conf;
}

sub ACTION_test {
    my ( $self, @arg ) = @_;
    $self->SUPER::ACTION_test(@arg);
}

1;
