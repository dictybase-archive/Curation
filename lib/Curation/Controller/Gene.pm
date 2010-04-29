package Curation::Controller::Gene;

use warnings;
use strict;
use Bio::Graphics::Browser::Markup;
use Bio::Perl;
use Chado::AutoDBI;
use dicty::DB::AutoDBI;
use POSIX qw/strftime/;

# Other modules:
use base 'Curation::Controller';


# Module implementation
#
sub index {
    my ( $self, $c ) = @_;
}

sub show {
    my ( $self, $c ) = @_;
    my $helper = $self->app->helper;

    my $id = $c->stash('id');

    my @features = $helper->search_feature($id);
    $self->exception( 'gene not found: ' . $id, $c ) if !@features;
    $self->exception( 'more than one gene returned: ' . $id, $c )
        if @features > 1;

    my $gene = $features[0];

    $self->render(
        template => 'gene/show',
        gbrowse  => $self->gbrowse_link( $gene, $c ),
        blink    => $self->blink_link( $gene, $c ),
        fasta    => $self->fasta( $gene, $c ),
        #curation => $self->curation( $gene, $c ),
    );
}

sub exception {
    my ( $self, $message, $c ) = @_;
    $c->res->code(404);
    $self->render(
        template => 'gene/404',
        message  => $message,
        error    => 1,
        header   => 'Error page',
    );
}

sub gbrowse_link {
    my ( $self, $feature, $c ) = @_;

    my $helper = $self->app->helper;

    my $id                = $helper->id($feature);
    my $reference_feature = $helper->reference_feature($feature);
    $self->exception( 'source_feature not found: ' . $id, $c )
        if !$reference_feature;

    my $frame = $self->frame($feature);

    my $name =
          $reference_feature->name . ':'
        . $frame->{start} . '..'
        . $frame->{end};
    my $track = join( '+', @{ $self->app->config->{gbrowse}->{tracks} } );
    
    my $gbrowse =
          '<a href="/db/cgi-bin/ggb/gbrowse/'
        . $helper->organism($feature)->species
        . '?name='
        . $name
        . '"><img src="'
        . '/db/cgi-bin/ggb/gbrowse_img/'
        . $helper->organism($feature)->species
        . '?name='
        . $name
        . '&width=450&type='
        . $track
        . '&keystyle=between&abs=1&flip='
        . $helper->is_flipped($feature)
        . '"/></a>';
    return $gbrowse;
}

sub blink_link {
    my ( $self, $feature, $c ) = @_;

    my $helper = $self->app->helper;
    my @links;

    my @predictions =
        $helper->subfeatures( $feature, 'mRNA', 'Sequencing Center' );
    foreach my $prediction (@predictions) {
        my ($genbank_id) =
            $helper->dbxrefs( $prediction, 'Protein Accession Number' );
        my $blink =
              '<iframe'
            . ' src="http://www.ncbi.nlm.nih.gov/sutils/blink.cgi?pid='
            . $genbank_id
            . '"></iframe>';

        return $blink;
    }
    return join( '<br/>', @links );
}

sub fasta {
    my ( $self, $feature, $c ) = @_;

    return if !$self->app->config->{fasta};

    my $helper = $self->app->helper;
    my $markup = Bio::Graphics::Browser::Markup->new;
    $markup->add_style( br    => '<br>' );
    
    my $flip = $helper->is_flipped($feature);

    ## get genomic sequence of a region ( make sure to address interbase coordinates )
    my $reference_feature  = $helper->reference_feature($feature);
    my $reference_sequence = $helper->sequence($reference_feature);

    my $frame = $self->frame($feature);

    my $sequence = lc substr $reference_sequence, $frame->{start} - 1,
        $frame->{length} + 1;
    $sequence = revcom_as_string($sequence) if $flip;

    ## get all features in region
    my @features =
        $helper->splice_features( $reference_feature, $frame->{start} - 1,
        $frame->{end} );

    ## store relative start and stop positions for each type defined in config
    my @coordinates;
    my $schema;
    my @schema_coordinates;
    
    foreach my $fasta ( @{ $self->app->config->{fasta} } ) {
        my $type = $fasta->{type};
        my $source = $fasta->{source} || undef;

        $self->app->log->error('feature type is not defined') if !$type;

        my $name = $source ? $type . '-' . $source : $type;
        $markup->add_style( $name => $fasta->{style} );
        
        push @schema_coordinates, [ $name, length($schema), length($schema) + length($name) ];
        $schema .= $name;
        push @schema_coordinates, [ 'br', length($schema), length($schema) ];
                
        my @features = $helper->filter_by_type( \@features, $type );
        @features = $helper->filter_by_source( \@features, $source )
            if $source;

        foreach my $feature (@features) {
            my $frame_coordinates;
            if ( $fasta->{subfeature} ) {
                foreach my $subfeature (
                    $helper->subfeatures( $feature, $fasta->{subfeature} ) ) {
                    $frame_coordinates =
                        $self->frame_coordinates( $subfeature, $frame, $flip );
                    push @coordinates,
                        [
                        $name,
                        $frame_coordinates->{start},
                        $frame_coordinates->{end}
                        ] if $frame_coordinates;
                }
            }
            else {
                $frame_coordinates =
                    $self->frame_coordinates( $feature, $frame, $flip );
                push @coordinates,
                    [
                    $name, $frame_coordinates->{start},
                    $frame_coordinates->{end}
                    ];
            }
        }
    }

    ## add breaks
    my $n = 60;
    for ( my $i = 0; $i <= length($sequence) / $n; $i++ ) {
        push @coordinates, [ 'br', $i * $n, $i * $n ];
    }
    
    ## put some makeup
    $markup->markup( \$sequence, \@coordinates );
    $markup->markup( \$schema, \@schema_coordinates );
    
    my $header = '>'
        . $reference_feature->name . ':'
        . $frame->{start} . ','
        . $frame->{end};
    $header .= ' (reverse complemented)' if $flip;
    
    return 'Color schema:<br/>'.$schema.'<br/>'.$header.$sequence;
}

sub frame {
    my ( $self, $feature, $c ) = @_;

    my $helper = $self->app->helper;

    my $window_ext = $self->app->config->{gbrowse}->{padding};

    my $start = $helper->start($feature) - $window_ext;
    my $end   = $helper->end($feature) + $window_ext;

    return { start => $start, end => $end, length => $end - $start };
}

sub frame_coordinates {
    my ( $self, $feature, $frame, $flip ) = @_;

    my $helper = $self->app->helper;
    
    return if $helper->start($feature) > $frame->{end} || $helper->end($feature) < $frame->{start};
    
    my $start = $helper->start($feature) - $frame->{start} + 1;
    $start = 0 if $start < 0;

    my $end = $helper->end($feature) - $frame->{start} + 1;
    $end = $frame->{length} + 1 if $end > $frame->{length};
    
    my ($f_start, $f_end);
    if ($flip){
        $f_start = $frame->{length} - $end + 1;
        $f_start = 0 if $f_start < 0;
        
        $f_end = $frame->{length} - $start + 1;
    }

    return if $start && $end == 0;
    return { start => $f_start, end => $f_end } if $flip;
    return { start => $start, end => $end };

}

sub update {
    my ( $self, $c ) = @_;

    my $dbh    = $self->app->dbh;
    my $helper = $self->app->helper;

    my $id               = $c->stash('id');
    my $curator_initials = 'YB';

    my @derived;
    push @derived, 'Gene prediction'
        if $self->req->param('gpDerived') eq 'true';

    my @support;
    push @support, 'EST' if $self->req->param('estSupport') eq 'true';
    push @support, 'Sequence similarity'
        if $self->req->param('ssSupport') eq 'true';
    push @support, 'Genomic context'
        if $self->req->param('gcSupport') eq 'true';
    push @support, 'Unpublished transcript sequence'
        if $self->req->param('utsSupport') eq 'true';

    my @incomplete;
    push @incomplete, 'Incomplete support'
        if $self->req->param('incomplete') eq 'true';
    push @incomplete, 'Conflicting evidence'
        if $self->req->param('conflict') eq 'true';

    my $part_of_cvterm = $self->get_cvterm( 'relationship', 'part_of' );
    my $derived_cvterm = $self->get_cvterm( 'relationship', 'derived_from' );
    my $mrna_cvterm    = $self->get_cvterm( 'sequence',     'mRNA' );

    my @features = $helper->search_feature($id);
    $self->exception( 'gene not found: ' . $id, $c ) if !@features;
    $self->exception( 'more than one gene returned: ' . $id, $c )
        if @features > 1;

    my $gene = $features[0];
    $self->prune_models($gene);

    ## get predictions
    my @predictions =
        grep {
        Chado::Feature_Dbxref->search(
            {   feature_id => $_->feature_id,
                dbxref_id  => Chado::Dbxref->get_single_row(
                    { accession => 'Sequencing Center' }
                    )->dbxref_id
            }
            )
        }
        grep { $_->type == $mrna_cvterm->cvterm_id }
        map {
        Chado::Feature->get_single_row( { feature_id => $_->subject_id } )
        }
        grep { $_->type == $part_of_cvterm->cvterm_id }
        Chado::Feature_Relationship->search(
        { object_id => $gene->feature_id } );
    $self->exception("no predictions found for $id") if !@predictions;

    my $organism = $helper->organism($gene);
    my $prefix =
        $self->app->config->{organism}->{ $organism->species }->{prefix};
    my $schema = dicty::DBH->schema;

    foreach my $prediction (@predictions) {
        my $number = $dbh->selectcol_arrayref(
            "SELECT $schema.DICTYBASEidno_seq.NEXTVAL FROM DUAL")->[0];
        $number = sprintf( "%07d", $number );
        my $new_id = $prefix . $number;

        # create the dbxref record
        my $id_dbxref = Chado::Dbxref->find_or_create(
            db_id => Chado::Db->get_single_row(
                name => 'DB:'
                    . $self->app->config->{organism}->{ $organism->species }
                    ->{site_name}
                )->db_id,
            accession => $new_id
        );

        ## create curated model
        my $curated = $self->clone(
            $prediction,           $id_dbxref->accession,
            $id_dbxref->accession, $id_dbxref->dbxref_id
        );

        ##  feature relationship
        my $frel;
        eval {
            $frel = Chado::Feature_Relationship->create(
                {   object_id  => $gene->feature_id,
                    type_id    => $part_of_cvterm->cvterm_id,
                    subject_id => $curated->feature_id,
                }
            );
        };
        $self->failure( 'Error duplicating relationship: ' . $@ ) if $@;

        ## link source
        eval {
            Chado::Feature_Dbxref->create(
                {   feature_id => $curated->feature_id,
                    dbxref_id  => Chado::Dbxref->get_single_row(
                        {   accession => $self->app->config->{organism}
                                ->{ $organism->species }->{site_name}
                                . ' Curator'
                        }
                        )->dbxref_id
                }
            );
        };
        $self->failure( 'Error linking source to model: ' . $@ ) if $@;

        my @prediction_exons = map {
            Chado::Feature->get_single_row( { feature_id => $_->subject_id } )
            } Chado::Feature_Relationship->search(
            {   type_id   => $part_of_cvterm->cvterm_id,
                object_id => $prediction->feature_id,
            }
        );
        $self->failure("No exons found for $id") if !@prediction_exons;

        foreach my $prediction_exon (@prediction_exons) {
            my $exon_floc = Chado::Featureloc->get_single_row(
                { feature_id => $prediction_exon->feature_id } );

            my $chromosome_dbxref = Chado::Dbxref->get_single_row(
                {   dbxref_id => Chado::Feature->get_single_row(
                        { feature_id => $exon_floc->srcfeature_id }
                        )->dbxref_id
                }
            );
            my $name = '_'
                . $id_dbxref->accession
                . '_exon_'
                . $chromosome_dbxref->accession . ':'
                . $exon_floc->fmin . '..'
                . $exon_floc->fmax;

            my $curated_exon = $self->clone( $prediction_exon, $name );

            ##  feature relationship
            my $frel;
            eval {
                $frel = Chado::Feature_Relationship->create(
                    {   object_id  => $curated->feature_id,
                        type_id    => $part_of_cvterm->cvterm_id,
                        subject_id => $curated_exon->feature_id,
                    }
                );
            };
            $self->failure( 'Error duplicating relationship: ' . $@ ) if $@;
        }

        ## create polypeptide
        my ($predicted_protein) = map {
            Chado::Feature->get_single_row( { feature_id => $_->subject_id } )
            } Chado::Feature_Relationship->search(
            {   type_id   => $derived_cvterm->cvterm_id,
                object_id => $prediction->feature_id
            }
            );
        my $protein_id_dbxref = Chado::Dbxref->create(
            {   db_id => Chado::Db->get_single_row(
                    name => 'DB:' . $ENV{'SITE_NAME'}
                    )->db_id,
                accession => $new_id . ".P"
            }
        );
        eval {
            my $protein = Chado::Feature->create(
                {   organism_id => $predicted_protein->organism_id,
                    dbxref_id   => $protein_id_dbxref->dbxref_id,
                    name        => $protein_id_dbxref->accession,
                    uniquename  => $protein_id_dbxref->accession,
                    residues    => $predicted_protein->residues,
                    seqlen      => $predicted_protein->seqlen,
                    type_id     => $predicted_protein->type_id,
                    md5checksum => $predicted_protein->md5checksum,
                }
            );
            Chado::Feature_Relationship->create(
                {   type_id    => $derived_cvterm->cvterm_id(),
                    subject_id => $protein->feature_id,
                    object_id  => $curated->feature_id
                }
            );
        };
        $self->failure( 'Error adding protein: ' . $@ ) if $@;

        ## add derived from (gene prediction)
        $self->add_featureprop( $curated, 'derived from', @derived );

        ## add supported by
        $self->add_featureprop( $curated, 'supported by', @support );

        ## add 'incomplete support qualifier' if applicable
        $self->add_featureprop( $curated, 'qualifier', @incomplete );
    }
    ## create paragraph for gene
    my $paragraph;
    my $note_date = strftime "%d-%b-%Y", localtime;
    eval {
        $paragraph = dicty::DB::Paragraph->create(
            {         paragraph_text => '<summary><curation_status>'
                    . 'A curated model has been added, '
                    . uc($note_date) . ' '
                    . $curator_initials
                    . '</curation_status></summary>',
            }
        );
        my $fprop = Chado::Featureprop->get_single_row(
            {   feature_id => $gene->feature_id,
                type_id    => Chado::Cvterm->get_single_row(
                    { name => 'paragraph_no' }
                    )->cvterm_id,
            }
        );
        $fprop->value( $paragraph->paragraph_no );
        $fprop->update();
    };
    $self->failure( 'Error adding paragraph: ' . $@ ) if $@;
    $dbh->commit;
}

sub prune_models {
    my ($self, $gene) = @_;
    eval {
        my $part_of_cvterm = $self->get_cvterm('relationship','part_of');
        
        my @models = grep {
            Chado::Feature_Dbxref->search(
                {   feature_id => $_->feature_id,
                    dbxref_id  => Chado::Dbxref->get_single_row(
                        { accession => 'dictyBase Curator' }
                        )->dbxref_id
                }
                )
            }
            grep { $_->type == $self->get_cvterm('sequence','mRNA')->cvterm_id }
            map {
            Chado::Feature->get_single_row( { feature_id => $_->subject_id } )
            }
            grep { $_->type == $part_of_cvterm->cvterm_id }
            Chado::Feature_Relationship->search(
            { object_id => $gene->feature_id } );

        return if !@models;

        foreach my $model (@models) {
            my @exons = map {
                Chado::Feature->get_single_row(
                    { feature_id => $_->subject_id } )
                } Chado::Feature_Relationship->search(
                {   type_id   => $part_of_cvterm->cvterm_id,
                    object_id => $model->feature_id,
                }
                );
            map { $_->delete } @exons;
        }
        map { $_->delete } @models;
    };
    $self->failure("error removing gene models: $@") if $@;
    $self->app->dbh->commit;
}

sub get_cvterm {
    my ( $self, $namespace, $name ) = @_;
    return Chado::Cvterm->get_single_row(
        {   name  => $name,
            cv_id => Chado::Cv->get_single_row( { name => $namespace } )
        }
    );
}

sub clone {
    my ( $self, $source_feature, $uniquename, $name, $dbxref_id ) = @_;
    my $new_feature;

    eval {
        $new_feature = Chado::Feature->create(
            {   organism_id => $source_feature->organism_id,
                type_id     => $source_feature->type_id,
                uniquename  => $uniquename
            }
        );
        $new_feature->dbxref_id($dbxref_id) if $dbxref_id;
        $new_feature->name($name)           if $name;
        $new_feature->update();
    };
    $self->failure( 'Error duplicating feature: ' . $@ ) if $@;

    ## location graph
    my $floc;
    my $source_floc = Chado::Featureloc->get_single_row(
        { feature_id => $source_feature->feature_id } );
    eval {
        $floc = Chado::Featureloc->create(
            {   feature_id    => $new_feature->feature_id,
                srcfeature_id => $source_floc->srcfeature_id,
                strand        => $source_floc->strand,
                fmin          => $source_floc->fmin,
                fmax          => $source_floc->fmax,
            }
        );
    };
    $self->failure( 'Error duplicating location: ' . $@ ) if $@;
    return $new_feature;
}

sub failure {
    my ($self, $message) = @_;
    $self->app->dbh->rollback;
    $self->render(
        template => 'gene/update',
        message  => $message,
        class    => 'error-warning'
    );
}

sub add_featureprop {
    my ( $self, $feature, $type, @values ) = @_;
    my $i = 0;
    eval {
        foreach my $value (@values) {
            Chado::Featureprop->create(
                {   feature_id => $feature->feature_id,
                    type_id =>
                        Chado::Cvterm->get_single_row( { name => $type } )
                        ->cvterm_id,
                    value => $value,
                    rank  => $i
                }
            );
            $i++;
        }
    };
    $self->failure("Error adding $type: $@") if $@;
}

1;
