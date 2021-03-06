package Curation::Controller::Gene;

use warnings;
use strict;
use Bio::Graphics::Browser::Markup;
use Bio::Perl;
use Chado::AutoDBI;
use dicty::DB::AutoDBI;
use POSIX qw/strftime/;
use Bio::DB::SeqFeature::Store;
use File::Spec::Functions;
use Modware::Publication::DictyBase;

# Other modules:
use base 'Mojolicious::Controller';

__PACKAGE__->attr('soap');

# Module implementation
#

sub show {
    my ($self) = @_;
    my $config = $self->app->config->{gene};
    my $gene = $self->get_gene( $self->stash('id') );
    map { $self->stash( $_ => 1 ) } keys %{ $self->app->config->{gene} };
    $self->stash( linkout => $config->{linkout} )
}

## --- Display part
sub gbrowse {
    my ($self) = @_;

    my $utils  = $self->app->utils;
    my $config = $self->app->config->{gene}->{gbrowse};

    $self->render_exception('no configuration found for gbrowse')
        if !$config;

    my $feature           = $self->get_gene( $self->stash('id') );
    my $species           = $utils->organism($feature)->species;
    my $reference_feature = $utils->reference_feature($feature);

    $self->render_exception(
        'source_feature not found: ' . $self->stash('id') )
        if !$reference_feature;

    my $frame = $self->frame( $feature, $config->{padding} );
    my $name =
          $reference_feature->name . ':'
        . $frame->{start} . '..'
        . $frame->{end};

    my $tracks = join( ';', map { 't=' . $_ } @{ $config->{tracks} } );
    my $link = $config->{link_url} . '?name=' . $name;

    my $config_name =
          $config->{version} != 2
        ? $self->app->config->{organism}->{$species}->{site_name}
        : $species;

    my $img_url =
          $config->{img_url} . '/'
        . $config_name
        . '/?name='
        . $name
        . ';width='
        . $config->{width}
        . ';keystyle=between;abs=1;flip='
        . $utils->is_flipped($feature) . ';'
        . $tracks;

    my $gbrowse = '<a href="' . $link . '"><img src="' . $img_url . '"/></a>';
    $self->render( data => $gbrowse );
}

sub blink {
    my ($self) = @_;

    my $config = $self->app->config->{gene}->{blink};

    $self->render_exception('no configuration found for blink')
        if !$config;

    my $output;
    my $utils   = $self->app->utils;
    my $feature = $self->get_gene( $self->stash('id') );

    my @curated =
        $utils->subfeatures( $feature, 'mRNA', 'dictyBase Curator' );
    my @predictions =
        $utils->subfeatures( $feature, 'mRNA', 'Sequencing Center' );

    foreach my $model ( @curated, @predictions ) {
        my ($genbank_id) =
            $utils->dbxrefs( $model, 'Protein Accession Number' );

        next if !$genbank_id;

        $output .=
            '<iframe src="' . $config->{url} . $genbank_id . '"></iframe>';
    }
    $output ||= "No data available for " . $self->stash('id');
    $self->render( data => $output );
}

sub fasta {
    my ($self) = @_;

    my $config = $self->app->config->{gene}->{fasta};
    $self->render_exception('no configuration found for gbrowse')
        if !$config;

    my $utils   = $self->app->utils;
    my $feature = $self->get_gene( $self->stash('id') );
    my $flip    = $utils->is_flipped($feature);
    my $frame   = $self->frame( $feature, $config->{padding} );

    ## get genomic sequence of a region ( make sure to address interbase coordinates )
    my $reference_feature  = $utils->reference_feature($feature);
    my $reference_sequence = $utils->sequence($reference_feature);

    my $sequence = lc substr $reference_sequence, $frame->{start} - 1,
        $frame->{length} + 1;
    $sequence = revcom_as_string($sequence) if $flip;

    ## get all features of type defined in config in region
    my @features =
        $utils->get_features( $reference_feature, $frame, $config );

    ## store legend and relative start and stop positions for each type defined in config
    my @coordinates;
    my $legend = '';
    my @legend_coordinates;

    my $markup = Bio::Graphics::Browser::Markup->new;
    $markup->add_style( br => '<br>' );

    foreach my $fasta ( @{ $config->{features} } ) {
        my $type = $fasta->{type};
        my $source = $fasta->{source} || undef;

        $self->app->log->error('feature type is not defined') if !$type;

        ## add track markup to legend
        my $name = $source ? $type . '-' . $source : $type;
        $markup->add_style( $name, $fasta->{style} );

        my $length = length($legend);
        push @legend_coordinates, [ $name, $length, $length + length($name) ];
        push @legend_coordinates, [ 'br', $length, $length ];
        $legend .= $name;

        ## grep features with defined type and source from set
        my @features = $utils->filter_by_type( \@features, $type );
        @features = $utils->filter_by_source( \@features, $source )
            if $source;

        ## grep subfeatures instead if defined in config
        @features =
            map { $utils->subfeatures( $_, $fasta->{subfeature} ) } @features
            if ( $fasta->{subfeature} );

        ## if feature have not been found but config contains source database, try to search there
        if ( !@features && $fasta->{sourcedb} ) {
            my $db = Bio::DB::SeqFeature::Store->new(
                -adaptor => $fasta->{sourcedb}->{adaptor},
                -dsn     => $fasta->{sourcedb}->{dsn},
                -user    => $fasta->{sourcedb}->{user},
                -pass    => $fasta->{sourcedb}->{pass}
            );
            @features = $db->get_features_by_location(
                -seqid => $reference_feature->name,
                -start => $frame->{start} - 1,
                -end   => $frame->{end}
            );
        }

        foreach my $feature (@features) {
            my $frame_coordinates =
                $self->frame_coordinates( $feature, $frame, $flip );
            push @coordinates,
                [
                $name, $frame_coordinates->{start},
                $frame_coordinates->{end}
                ]
                if $frame_coordinates;
        }
    }

    ## add line breaks
    my $n = 60;
    for ( my $i = 0; $i <= length($sequence) / $n; $i++ ) {
        push @coordinates, [ 'br', $i * $n, $i * $n ];
    }

    ## put makeup
    $markup->markup( \$sequence, \@coordinates );
    $markup->markup( \$legend,   \@legend_coordinates );

    my $header = '>'
        . $reference_feature->name . ':'
        . $frame->{start} . ','
        . $frame->{end};
    $header .= ' (reverse complemented)' if $flip;

    ## get the party started
    $self->render( data => '<pre>' 
            . $header
            . $sequence . '<hr/>'
            . 'Color schema:'
            . $legend . '<br/>'
            . '</pre>' );
}

sub blast {
    my ($self) = @_;

    my $config = $self->app->config->{gene}->{blast};
    $self->render_exception('no configuration found for blast')
        if !$config;

    my $result = '';
    my $utils  = $self->app->utils;

    my $params = {};
    $params->{types} = {};
    $params->{order} = [];

    foreach my $blast_params ( @{ $config->{parameters} } ) {
        my $db_name = $blast_params->{name};
        push @{ $params->{order} }, $db_name
            if !exists $params->{types}->{$db_name};

        $params->{types}->{$db_name}->{default} = 1
            if $blast_params->{default} && $blast_params->{default} == 1;
        $params->{types}->{$db_name}->{auto} = 1;
        
        push @{ $params->{types}->{$db_name}->{content} },
            $self->blast_by_database($db_name);
    }
    $self->stash( caller => 'blast' );
    $self->render( template => 'subtabs', %{$params} );
}

sub blast_by_database {
    my ( $self, $db_name ) = @_;

    my $result            = '';
    my $utils             = $self->app->utils;
    my $config            = $self->app->config->{gene}->{blast};
    my $feature           = $self->get_gene( $self->stash('id') );
    my $frame             = $self->frame($feature);
    my $reference_feature = $utils->reference_feature($feature);

    my @features =
        $utils->get_features( $reference_feature, $frame, $config, $feature );

    my @default = $self->default( $config->{features} );
    my $params  = {};
    $params->{types} = {};
    $params->{order} = [];

    foreach my $blast_params ( @{ $config->{parameters} } ) {
        next if $blast_params->{name} ne $db_name;

        foreach my $feature (@features) {
            my $protein    = $utils->protein($feature);
            my $identifier = $self->identifier($feature);

            $blast_params->{sequence} = $protein;
            push @{ $params->{order} }, $identifier
                if !exists $params->{types}->{$identifier};
                
            $params->{types}->{$identifier}->{default} = 1
               if grep { $_ eq $self->identifier($feature) } @default;
            
            $self->client->post_form(
                $config->{report_url},
                $blast_params,
                sub {
                    my $client = shift;
                    my $report = $client->res->body;

                    my $error = 'error retrieving BLAST results'
                        if !$report || $report =~ m{Sorry}i;

                    my $content =
                          $error
                        ? $error
                        : '<iframe src="'
                        . $config->{format_report_url} . '/'
                        . $report
                        . '?noheader=1"></iframe>';
                    push @{ $params->{types}->{$identifier}->{content} },
                        $content;
                }
            )->process;
        }
    }
    $self->stash( caller => 'blast/' . $db_name );
    return $self->render_partial( template => 'subtabs', %{$params} );
}

sub blast_report {
    my ( $self, $tx ) = @_;
    my $config = $self->app->config->{content}->{blast};
    my $report = $tx->res->body;
    
    my $error  = 'error retrieving BLAST results'
        if !$report || $report =~ m{Sorry}i;

    my $content =
          $error
        ? $error
        : '<iframe src="'
        . $config->{format_report_url} . '/'
        . $report
        . '?noheader=1"></iframe>';

    
    return $content;
}

sub protein {
    my ($self) = @_;

    my $utils             = $self->app->utils;
    my $config            = $self->app->config->{gene}->{protein};
    my $feature           = $self->get_gene( $self->stash('id') );
    my $frame             = $self->frame($feature);
    my $reference_feature = $utils->reference_feature($feature);

    my @features =
        $utils->get_features( $reference_feature, $frame, $config, $feature );

    my @default = $self->default( $config->{features} );
    my $params  = {};
    $params->{types} = {};
    $params->{order} = [];

    foreach my $feature (@features) {
        ## group by type/source
        my $identifier = $self->identifier($feature);

        push @{ $params->{order} }, $identifier
            if !exists $params->{types}->{$identifier};
        push @{ $params->{types}->{$identifier}->{content} },
            '<pre>' . $utils->protein($feature) . '</pre>';

        $params->{types}->{$identifier}->{default} = 1
            if grep { $_ eq $identifier } @default;
    }
    $self->stash( caller => 'protein' );
    $self->render( template => 'subtabs', %{$params} );
}

sub curation {
    my ($self) = @_;

    my $config            = $self->app->config->{gene}->{curation};
    my $feature           = $self->get_gene( $self->stash('id') );
    my $frame             = $self->frame($feature);
    my $utils             = $self->app->utils;
    my $reference_feature = $utils->reference_feature($feature);

    my @features =
        $utils->get_features( $reference_feature, $frame, $config, $feature );
    my @default = $self->default( $config->{features} );

    my $types;
    foreach my $feature (@features) {
        my $identifier = $self->identifier($feature);
        my $id         = $utils->id($feature);
        $types->{$id}->{id} = $id;
        $types->{$id}->{name} = $id . ' (' . $identifier . ')';
        $types->{$id}->{default} = 1 if grep {$_ eq $identifier} @default;
    }
    my @notes = map { $_->value . ' [public]' } Chado::Featureprop->search(
        {   feature_id => $feature->feature_id,
            type_id =>
                Chado::Cvterm->get_single_row( { name => 'public note' } )
                ->cvterm_id,
        }
    );
    push @notes, map { $_->value . ' [private]' } Chado::Featureprop->search(
        {   feature_id => $feature->feature_id,
            type_id =>
                Chado::Cvterm->get_single_row( { name => 'private note' } )
                ->cvterm_id,
        }
    );

    $self->stash( types      => $types );
    $self->stash( qualifiers => $config->{qualifiers} );
    $self->stash( notes => \@notes ) if @notes;
}

## --- Curation part
sub skip {
    my ($self) = @_;

    my $dbh   = $self->app->dbh;
    my $utils = $self->app->utils;

    my $id               = $self->stash('id');
    my $gene             = $self->get_gene($id);
    my $curator_initials = $self->session('initials');
    my $note_date        = strftime "%d-%b-%Y", localtime;
    my $note =
        'This gene has been inspected by a curator, but there is currently inadequate support to make a curated model.';

    eval {
        my ($fprop) = Chado::Featureprop->search(
            {   feature_id => $gene->feature_id,
                type_id    => Chado::Cvterm->get_single_row(
                    { name => 'public note' }
                    )->cvterm_id,
            }
        );
        $self->failure(
            'Error adding note: public note already exists for the gene')
            if $fprop;

        $fprop = Chado::Featureprop->create(
            {   feature_id => $gene->feature_id,
                type_id    => Chado::Cvterm->get_single_row(
                    { name => 'public note' }
                    )->cvterm_id,
                value => $note . ' '
                    . uc($note_date) . ' '
                    . $curator_initials
            }
        );
    };
    $self->failure( 'Error adding note: ' . $@ ) if $@;
    $dbh->commit;

    #$self->clean_cache($id);
}

sub update {
    my ($self) = @_;

    my $dbh   = $self->app->dbh;
    my $utils = $self->app->utils;

    my $id               = $self->stash('id');
    my $curator_initials = $self->session('initials');

    ## get curation parameters from request parameters
    ## this requires parameter name being formed in a particular way
    ## View forms id of each control element (checkboxes) as a composition
    ## of lowercased qualifier type and value (i.e. derived-from-gene-prediction, supported-by-est).
    ## JS sends request to service using those ids as request parameters for selected qualifiers
    ## Controller checks if request contains expected parameter.

    my $config     = $self->app->config->{gene}->{curation};
    my $qualifiers = {};

    foreach my $qualifier ( @{ $config->{qualifiers} } ) {
        foreach my $value ( @{ $qualifier->{values} } ) {
            my $id = lc( $qualifier->{type} . ' ' . $value );
            $id =~ s/ /-/g;
            push @{ $qualifiers->{ $qualifier->{type} } }, $value
                if $self->req->param($id);
        }
    }

    my $gene = $self->get_gene($id);
    $self->prune_models($gene);

    my ($prediction) = $utils->search_feature( $self->req->param('feature') );
    $self->failure('No features selected') if !$prediction;

    my $part_of_cvterm = $self->get_cvterm( 'relationship', 'part_of' );
    my $derived_cvterm = $self->get_cvterm( 'relationship', 'derived_from' );
    my $mrna_cvterm    = $self->get_cvterm( 'sequence',     'mRNA' );
    
    my $organism = $utils->organism($gene); 
    my $prefix =
        $self->app->config->{organism}->{ $organism->species }->{prefix};
    my $schema = 'cgm_ddb';    #dicty::DBH->schema;

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

    my $old_floc = Chado::Featureloc->get_single_row(
        { feature_id => $gene->feature_id } );
    my $new_floc = Chado::Featureloc->get_single_row(
        { feature_id => $curated->feature_id } );
    eval {
        $old_floc->strand($new_floc->strand);
        $old_floc->fmin($new_floc->fmin);
        $old_floc->fmax($new_floc->fmax);
        $old_floc->update();
    };
    $self->failure( 'Error updating gene location: ' . $@ ) if $@;
    
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
                            ->{ $organism->species }->{site_name} . ' Curator'
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
        {   db_id => Chado::Db->get_single_row( name => 'DB:' . 'dictyBase' )
                ->db_id,
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

    ## add qualifiers
    foreach my $qualifier ( keys %$qualifiers ) {
        $self->add_featureprop( $curated, $qualifier,
            @{ $qualifiers->{$qualifier} } );
    }

    ## create paragraph for gene
    my $paragraph;
    my $note_date = strftime "%d-%b-%Y", localtime;
    eval {
        $paragraph = dicty::DB::Paragraph->create(
            {   paragraph_text => '<summary><curation_status>'
                    . 'A curated model has been added, '
                    . uc($note_date) . ' '
                    . $curator_initials
                    . '</curation_status></summary>',
                created_by => $self->session('username')
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

    ## add "Curated model" reference
    my ($reference) = Modware::Publication::DictyBase->search(
        title => 'Curated model' );
    
    eval {
        my $sth = $dbh->prepare(
            "INSERT INTO feature_pub (feature_id, pub_id) values(?,?)"
        );
        $sth->execute( $curated->feature_id, $reference->pub_id );
    };
    $self->failure( 'Error adding reference: ' . $@ ) if $@;
    $dbh->commit;
    #$self->clean_cache($id);
}

sub prune_models {
    my ( $self, $gene ) = @_;
    eval {
        my $part_of_cvterm = $self->get_cvterm( 'relationship', 'part_of' );
        my $derived_cvterm =
            $self->get_cvterm( 'relationship', 'derived_from' );

        my @models = grep {
            Chado::Feature_Dbxref->search(
                {   feature_id => $_->feature_id,
                    dbxref_id  => Chado::Dbxref->get_single_row(
                        { accession => 'dictyBase Curator' }
                        )->dbxref_id
                }
                )
            }
            grep {
            $_->type == $self->get_cvterm( 'sequence', 'mRNA' )->cvterm_id
            }
            map {
            Chado::Feature->get_single_row( { feature_id => $_->subject_id } )
            }
            grep { $_->type == $part_of_cvterm->cvterm_id }
            Chado::Feature_Relationship->search(
            { object_id => $gene->feature_id } );

        return if !@models;

        foreach my $model (@models) {
            my ($protein) = map {
                Chado::Feature->get_single_row(
                    { feature_id => $_->subject_id } )
                } Chado::Feature_Relationship->search(
                {   type_id   => $derived_cvterm->cvterm_id,
                    object_id => $model->feature_id
                }
                );
            $protein->is_deleted(1);
            $protein->update;

            my @exons = map {
                Chado::Feature->get_single_row(
                    { feature_id => $_->subject_id } )
                } Chado::Feature_Relationship->search(
                {   type_id   => $part_of_cvterm->cvterm_id,
                    object_id => $model->feature_id,
                }
                );
            map { $_->is_deleted(1); $_->update } @exons;
        }
        map { $_->is_deleted(1); $_->update } @models;
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
                uniquename  => $uniquename,
                created_by  => $self->session('username'),
                modified_by => $self->session('username'),
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

sub add_featureprop {
    my ( $self, $feature, $type, @values ) = @_;
    my $i = 0;
    eval {
        foreach my $value (@values) {
            Chado::Featureprop->create(
                {   feature_id => $feature->feature_id,
                    type_id    => Chado::Cvterm->get_single_row(
                        {   name  => $type,
                            cv_id => Chado::Cv->get_single_row(
                                { name => 'autocreated' }
                                )->cv_id
                        }
                        )->cvterm_id,
                    value => $value,
                    rank  => $i
                }
            );
            $i++;
        }
    };
    $self->failure("Error adding $type: $@") if $@;
}

sub get_gene {
    my ( $self, $id ) = @_;
    my @features = $self->app->utils->search_feature($id);

    $self->render_exception( 'gene not found: ' . $id ) if !@features;
    $self->render_exception( 'more than one gene returned: ' . $id )
        if @features > 1;
    return $features[0];
}

sub failure {
    my ( $self, $message ) = @_;
    $self->app->dbh->rollback;
    $self->render(
        template => 'gene/update',
        message  => $message,
        class    => 'error-warning'
    );
}

sub clean_cache {
    my ( $self, $id ) = @_;
    my $config = $self->app->config;

 #    my $tx = $self->client->delete( $config->{cache}->{cleanup_url} . $id );
 #    my $report = $tx->res->message;
 #    $self->app->log->debug($report);
}

## --- Some utilss
sub default {
    my ( $self, $features ) = @_;
    my @default;
    foreach my $feature (@$features) {
        next if !$feature->{default};
        push @default, $self->identifier($feature);
    }
    return @default;
}

sub identifier {
    my ( $self, $feature ) = @_;
    my $identifier;

    return $feature->{title} if $feature->{title};

    $identifier = $feature->{type};
    $identifier .= '-' . $feature->{source} if $feature->{source};
    return $identifier;
}

sub frame {
    my ( $self, $feature, $padding ) = @_;

    $padding ||= 0;
    my $utils = $self->app->utils;
    my $start = $utils->start($feature) - $padding;
    my $end   = $utils->end($feature) + $padding;

    return { start => $start, end => $end, length => $end - $start };
}

sub frame_coordinates {
    my ( $self, $feature, $frame, $flip ) = @_;

    my $utils         = $self->app->utils;
    my $feature_start = $utils->start($feature);
    my $feature_end   = $utils->end($feature);

    return
        if $feature_start > $frame->{end} || $feature_end < $frame->{start};

    my $start = $feature_start - $frame->{start} + 1;
    $start = 0 if $start < 0;

    my $end = $feature_end - $frame->{start} + 1;
    $end = $frame->{length} + 1 if $end > $frame->{length};

    my ( $f_start, $f_end );
    if ($flip) {
        $f_start = $frame->{length} - $end + 1;
        $f_start = 0 if $f_start < 0;
        $f_end   = $frame->{length} - $start + 1;
        return { start => $f_start, end => $f_end };
    }

    return if $start && $end == 0;
    return { start => $start, end => $end };
}

1;
