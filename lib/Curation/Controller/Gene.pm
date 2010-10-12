package Curation::Controller::Gene;

use warnings;
use strict;
use Bio::Graphics::Browser::Markup;
use Bio::Perl;
use Chado::AutoDBI;
use dicty::DB::AutoDBI;
use POSIX qw/strftime/;
use SOAP::Lite;
use Data::Dumper;
use Bio::DB::SeqFeature::Store;
use File::Spec::Functions;

# Other modules:
use base 'Mojolicious::Controller';

__PACKAGE__->attr('soap');

# Module implementation
#
sub index {
    my ($self) = @_;
}

sub show {
    my ($self) = @_;
    my $helper = $self->app->helper;

    my $gene = $self->get_gene( $self->stash('id') );
    $self->render(
        template => 'gene/show',
        %{ $self->app->config->{content} }
    );
}

## --- Display part
sub gbrowse {
    my ($self) = @_;

    my $helper = $self->app->helper;
    my $config = $self->app->config->{content}->{gbrowse};

    my $feature           = $self->get_gene( $self->stash('id') );
    my $species           = $helper->organism($feature)->species;
    my $reference_feature = $helper->reference_feature($feature);
    $self->exception( 'source_feature not found: ' . $self->stash('id') )
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
        . $helper->is_flipped($feature) . ';'
        . $tracks;

    my $gbrowse = '<a href="' . $link . '"><img src="' . $img_url . '"/></a>';
    $self->render_text($gbrowse);
}

sub blink {
    my ($self) = @_;

    my $output;
    my $helper  = $self->app->helper;
    my $feature = $self->get_gene( $self->stash('id') );
    my @predictions =
        $helper->subfeatures( $feature, 'mRNA', 'Sequencing Center' );

    foreach my $prediction (@predictions) {
        my ($genbank_id) =
            $helper->dbxrefs( $prediction, 'Protein Accession Number' );

        $output .=
            $genbank_id
            ? '<iframe' 
            . ' src="'
            . $self->app->config->{content}->{blink}->{url}
            . $genbank_id
            . '"></iframe>'
            : ''
            if $genbank_id;
    }
    $self->render_text($output);
}

sub fasta {
    my ($self) = @_;

    my $config = $self->app->config->{content}->{fasta};
    return if !$config;

    my $helper  = $self->app->helper;
    my $feature = $self->get_gene( $self->stash('id') );
    my $flip    = $helper->is_flipped($feature);
    my $frame   = $self->frame( $feature, $config->{padding} );

    ## get genomic sequence of a region ( make sure to address interbase coordinates )
    my $reference_feature  = $helper->reference_feature($feature);
    my $reference_sequence = $helper->sequence($reference_feature);

    my $sequence = lc substr $reference_sequence, $frame->{start} - 1,
        $frame->{length} + 1;
    $sequence = revcom_as_string($sequence) if $flip;

    ## get all features of type defined in config in region
    my @features =
        $helper->get_features( $reference_feature, $frame, $config );

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
        my @features = $helper->filter_by_type( \@features, $type );
        @features = $helper->filter_by_source( \@features, $source )
            if $source;

        ## grep subfeatures instead if defined in config
        @features =
            map { $helper->subfeatures( $_, $fasta->{subfeature} ) } @features
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
    $self->render_text( '<pre>' 
            . $header
            . $sequence . '<hr/>'
            . 'Color schema:'
            . $legend . '<br/>'
            . '</pre>' );
}

sub blast {
    my ($self) = @_;

    my $result = '';
    my $helper = $self->app->helper;
    my $config = $self->app->config->{content}->{blast};

    my $params = {};
    $params->{types}  = {};
    $params->{caller} = 'blast';
    $params->{order}  = [];

    foreach my $blast_params ( @{ $config->{parameters} } ) {
        my $database = $blast_params->{name};
        push @{ $params->{order} }, $database
            if !exists $params->{types}->{$database};

        push @{ $params->{types}->{$database}->{content} },
            $self->blast_database( $blast_params->{database} );
        $params->{types}->{$database}->{default} = 1
            if $blast_params->{default} && $blast_params->{default} == 1;
    }
    $self->render(
        template => 'gene/subtabs',
        %{$params}
    );
}

sub blast_database {
    my ( $self, $database ) = @_;

    my $result            = '';
    my $helper            = $self->app->helper;
    my $config            = $self->app->config->{content}->{blast};
    my $feature           = $self->get_gene( $self->stash('id') );
    my $frame             = $self->frame($feature);
    my $reference_feature = $helper->reference_feature($feature);

    my @features =
        $helper->get_features( $reference_feature, $frame, $config,
        $feature );

    my $default = $self->default( $config->{features} );
    my $params  = {};
    $params->{types}  = {};
    $params->{caller} = 'blast-' . $database;
    $params->{order}  = [];

    foreach my $blast_params ( @{ $config->{parameters} } ) {
        next if $blast_params->{database} ne $database;

        foreach my $feature (@features) {
            my $protein = $helper->protein($feature);
            $blast_params->{sequence} = $protein;

            my $report_tx =
                $self->client->async->post_form( $config->{report_url},
                $blast_params );
            my $report = $report_tx->res->body;
            $self->render_text('error retrieving BLAST results')
                if !$report || $report =~ m{Sorry}i;

            my $identifier = $self->identifier($feature);
            my $content =
                $report
                ? '<iframe src="'
                . $config->{format_report_url} . '/'
                . $report
                . '?noheader=1"></iframe>'
                : 'error retrieving BLAST results';

            push @{ $params->{order} }, $identifier
                if !exists $params->{types}->{$identifier};
            push @{ $params->{types}->{$identifier}->{content} }, $content;

            $params->{types}->{$identifier}->{default} = 1
                if $self->identifier($feature) eq $default;
        }
    }
    return $self->render_partial(
        template => 'gene/subtabs',
        %{$params}
    );
}

sub protein {
    my ($self) = @_;

    my $helper            = $self->app->helper;
    my $config            = $self->app->config->{content}->{protein};
    my $feature           = $self->get_gene( $self->stash('id') );
    my $frame             = $self->frame($feature);
    my $reference_feature = $helper->reference_feature($feature);

    my @features =
        $helper->get_features( $reference_feature, $frame, $config,
        $feature );

    my $default = $self->default( $config->{features} );
    my $params  = {};
    $params->{types}  = {};
    $params->{caller} = 'protein';
    $params->{order}  = [];

    foreach my $feature (@features) {
        ## group by type/source
        my $identifier = $self->identifier($feature);

        push @{ $params->{order} }, $identifier
            if !exists $params->{types}->{$identifier};
        push @{ $params->{types}->{$identifier}->{content} },
            '<pre>' . $helper->protein($feature) . '</pre>';

        $params->{types}->{$identifier}->{default} = 1
            if $identifier eq $default;
    }
    $self->render( template => 'gene/subtabs', %{$params} );
}

sub curation {
    my ($self) = @_;

    my $helper            = $self->app->helper;
    my $config            = $self->app->config->{content}->{curation};
    my $feature           = $self->get_gene( $self->stash('id') );
    my $frame             = $self->frame($feature);
    my $reference_feature = $helper->reference_feature($feature);

    my @features =
        $helper->get_features( $reference_feature, $frame, $config,
        $feature );

    my $params = $config;
    $params->{types} = {};

    my $default = $self->default( $config->{features} );
    $self->app->log->debug($default);

    foreach my $feature (@features) {
        my $identifier = $self->identifier($feature);
        my $id         = $helper->id($feature);
        $params->{types}->{$id}->{identifier} =
            $id . ' (' . $identifier . ')';
        $params->{types}->{$id}->{default} = 1 if $identifier eq $default;
    }
    $self->render(
        template => 'gene/curation',
        %{$params}
    );
}

## --- Curation part
sub skip {
    my ($self) = @_;

    my $dbh    = $self->app->dbh;
    my $helper = $self->app->helper;

    my $id               = $self->stash('id');
    my $gene             = $self->get_gene($id);
    my $curator_initials = $self->session('initials');
    my $note_date        = strftime "%d-%b-%Y", localtime;
    my $note =
        'This gene has been inspected by a curator but there is no adequate support to make a curated model at this time.';

    eval {

        my $fprop = Chado::Featureprop->create(
            {   feature_id => $gene->feature_id,
                type_id    => Chado::Cvterm->get_single_row(
                    { name => 'public note' }
                    )->cvterm_id,
                value => $note . ' ' . uc($note_date) . ' ' . $curator_initials
            }
        );
    };
    $self->failure( 'Error adding note: ' . $@ ) if $@;
    $dbh->commit;

    #$self->clean_cache($id);
}

sub update {
    my ($self) = @_;

    my $dbh    = $self->app->dbh;
    my $helper = $self->app->helper;

    my $id               = $self->stash('id');
    my $curator_initials = $self->session('initials');

    ## get curation parameters from request parameters
    ## this requires parameter name being formed in a particular way
    ## View forms id of each control element (checkboxes) as a composition
    ## of lowercased qualifier type and value (i.e. derived-from-gene-prediction, supported-by-est).
    ## JS sends request to service using those ids as request parameters for selected qualifiers
    ## Controller checks if request contains expected parameter.

    my $config     = $self->app->config->{content}->{curation};
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

    my @predictions =
        map { $helper->search_feature($_) }
        split( ' ', $self->req->param('feature') );

    $self->failure('No features selected') if !@predictions;

    my $part_of_cvterm = $self->get_cvterm( 'relationship', 'part_of' );
    my $derived_cvterm = $self->get_cvterm( 'relationship', 'derived_from' );
    my $mrna_cvterm    = $self->get_cvterm( 'sequence',     'mRNA' );

    my $organism = $helper->organism($gene);
    my $prefix =
        $self->app->config->{organism}->{ $organism->species }->{prefix};
    my $schema = 'cgm_ddb';    #dicty::DBH->schema;

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
            {   db_id =>
                    Chado::Db->get_single_row( name => 'DB:' . 'dictyBase' )
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

sub get_gene {
    my ( $self, $id ) = @_;
    my @features = $self->app->helper->search_feature($id);

    $self->exception( 'gene not found: ' . $id ) if !@features;
    $self->exception( 'more than one gene returned: ' . $id )
        if @features > 1;
    return $features[0];
}

sub exception {
    my ( $self, $message ) = @_;
    $self->res->code(404);
    $self->render(
        template => 'gene/404',
        message  => $message,
        error    => 1,
        header   => 'Error page',
    );
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

## --- Some helpers
sub default {
    my ( $self, $features ) = @_;
    my $default;
    foreach my $feature (@$features) {
        next if !$feature->{default};
        $default = $self->identifier($feature);
    }
    return $default;
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

    my $helper = $self->app->helper;
    my $start  = $helper->start($feature) - $padding;
    my $end    = $helper->end($feature) + $padding;

    return { start => $start, end => $end, length => $end - $start };
}

sub frame_coordinates {
    my ( $self, $feature, $frame, $flip ) = @_;

    my $helper        = $self->app->helper;
    my $feature_start = $helper->start($feature);
    my $feature_end   = $helper->end($feature);

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
