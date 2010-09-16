package Curation::Helper;

use strict;
use Chado::AutoDBI;
use Data::Dumper;
use dicty::DB::AutoDBI;

use base 'Mojo::Base';
use version; our $VERSION = qv('1.0.0');

__PACKAGE__->attr('app');

sub search_feature {
    my ( $self, $id ) = @_;

    my @dbxref = Chado::Dbxref->search( { accession => $id } );
    return if !@dbxref;

    my @features =
        map { Chado::Feature->search( { dbxref_id => $_->dbxref_id, is_deleted => 0 } ) }
        @dbxref;

    return @features;
}

sub reference_feature {
    my ( $self, $feature ) = @_;

    my $floc = Chado::Featureloc->get_single_row(
        { feature_id => $feature->feature_id } );
    return if !$floc;

    my $reference_feature = Chado::Feature->get_single_row(
        { feature_id => $floc->srcfeature_id } );

    return $reference_feature;
}

sub start {
    my ( $self, $feature ) = @_;
    
    my $start;
    
    eval {
        $start = $feature->start -1;
    };
    return $start if $start;
    
    my $floc = Chado::Featureloc->get_single_row(
        { feature_id => $feature->feature_id } );

    my $start = $floc->fmin < $floc->fmax ? $floc->fmin : $floc->fmax;
    return $start;
}

sub end {
    my ( $self, $feature ) = @_;

    my $end;
    eval {
        $end = $feature->stop;
    };
    return $end if $end;
    
    my $floc = Chado::Featureloc->get_single_row(
        { feature_id => $feature->feature_id } );

    my $end = $floc->fmin > $floc->fmax ? $floc->fmin : $floc->fmax;
    return $end;
}

sub organism {
    my ( $self, $feature ) = @_;

    my $organism = Chado::Organism->get_single_row(
        { organism_id => $feature->organism_id } );

    return $organism;
}

sub id {
    my ( $self, $feature ) = @_;

    my $id =
        Chado::Dbxref->get_single_row( { dbxref_id => $feature->dbxref_id } )
        ->accession;
    return $id;
}

sub subfeatures {
    my ( $self, $feature, $type, $source ) = @_;

    my $part_of_cvterm = Chado::Cvterm->get_single_row(
        {   name  => 'part_of',
            cv_id => Chado::Cv->get_single_row( { name => 'relationship' } )
        }
    );

    ## get all subfeatures
    my @subfeatures = map {
        Chado::Feature->get_single_row( { feature_id => $_->subject_id } )
        }
        grep { $_->type == $part_of_cvterm->cvterm_id }
        Chado::Feature_Relationship->search(
        { object_id => $feature->feature_id } );

    ## filter by type if requested
    @subfeatures = $self->filter_by_type( \@subfeatures, $type ) if $type;

    ## filter by source if requested
    @subfeatures = $self->filter_by_source( \@subfeatures, $source )
        if $source;

    return @subfeatures;
}

sub dbxrefs {
    my ( $self, $feature, $source ) = @_;

    my @dbxref = map {
        Chado::Dbxref->get_single_row( { dbxref_id => $_->dbxref_id } )
        } Chado::Feature_Dbxref->search(
        { feature_id => $feature->feature_id } );

    my $db = Chado::Db->get_single_row( { name => 'DB:' . $source } );

    return map { $_->accession } grep { $_->db_id == $db->db_id } @dbxref;
}

sub sequence {
    my ( $self, $feature ) = @_;
    return $feature->residues;
}

sub splice_features {
    my ( $self, $feature, $start, $end ) = @_;
    my @features;
    ## too slow
#    my @features =
#        map  { Chado::Feature->get_single_row({ feature_id => $_->feature_id }) }
#        grep { $_->fmin <= $end && $_->fmax >= $start }
#        Chado::Featureloc->search({ srcfeature_id => $feature->feature_id });

    my $sql = qq{
        SELECT f.feature_id
        FROM feature f
        INNER JOIN featureloc fl
        ON f.feature_id     = fl.feature_id
        WHERE srcfeature_id = ?
        AND fmax           >= ?
        AND fmin           <= ? 
        AND f.is_deleted   = 0
    };
    my $sth = $self->app->dbh->prepare($sql);
    $sth->execute( $feature->feature_id, $start, $end );
    while ( my $row = $sth->fetchrow_hashref("NAME_lc") ) {
        push @features,
            Chado::Feature->get_single_row(
            { feature_id => $row->{feature_id} } );
    }
    return @features;
}

sub filter_by_source {
    my ( $self, $features, $source ) = @_;

    my $dbxref = Chado::Dbxref->get_single_row( { accession => $source } );
    $self->app->log->debug("$source dbxref not found") if !$dbxref;
    return if !$dbxref;
    
    return grep {
        Chado::Feature_Dbxref->get_single_row(
            {   feature_id => $_->feature_id,
                dbxref_id  => $dbxref->dbxref_id
            }
            )
    } @$features;
}

sub filter_by_type {
    my ( $self, $features, $type ) = @_;

    my $type_cvterm = Chado::Cvterm->get_single_row(
        {   name  => $type,
            cv_id => Chado::Cv->get_single_row( { name => 'sequence' } )
        }
    );
    return if !$type_cvterm;
    return grep { $_->type == $type_cvterm->cvterm_id } @$features;
}

sub is_flipped {
    my ( $self, $feature ) = @_;
    
    ## check feature floc first
    my $floc = Chado::Featureloc->get_single_row(
        { feature_id => $feature->feature_id } );
        return 1 if $floc->strand == -1;
    
    ## check subfeatures (just in case)
    foreach my $subfeature ($self->subfeatures($feature)){
        my $floc = Chado::Featureloc->get_single_row(
        { feature_id => $subfeature->feature_id } );
        return 1 if $floc->strand == -1;
    }
    return 0;
}

sub protein {
    my ($self, $feature) = @_;
    my $protein = '';
    my $count = 0;

    while ($protein eq '' && $count < 3 ){
        my $tx = $self->app->client->async->post_form(
            $self->app->config->{content}->{protein}->{url},
            {   id       => $self->app->helper->id($feature),
                organism => $self->app->helper->organism($feature)->species,
                type     => 'Protein'
            }
        );
        $protein = $tx->res->body;
        $count++;
        $self->app->log->debug('could not get sequence: '. Dumper $tx) if !$protein;
    }
   return $protein;
}

sub get_features {
    my ( $self, $reference_feature, $frame, $config ) = @_;

    my @filtered_features;
    my @all_features =
        $self->splice_features( $reference_feature, $frame->{start} - 1,
        $frame->{end} );

    foreach my $feature ( @{ $config->{features} } ) {
        my $type   = $feature->{type};
        my $source = $feature->{source} || undef;
        my $title  = $feature->{title} || undef;

        my @features = $self->filter_by_type( \@all_features, $type );
        @features = $self->filter_by_source( \@features, $source )
            if $source;
        map { $_->{type} = $type } @features;
        map { $_->{source} = $source } @features if $source;
        map { $_->{title} = $title } @features if $title;
        push @filtered_features, @features;
    }
    return @filtered_features;
}


1;
