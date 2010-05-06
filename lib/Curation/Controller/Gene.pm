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

# Other modules:
use base 'Mojolicious::Controller';

__PACKAGE__->attr('soap');

# Module implementation
#
sub index {
    my ( $self ) = @_;
}

sub show {
    my ($self) = @_;
    my $helper = $self->app->helper;

    my $gene = $self->get_gene( $self->stash('id') );
    
    my $params;
    $params->{ $_ } = 1 foreach keys %{$self->app->config->{content}};

    $self->render( template => 'gene/show', %$params );
}

## --- Display part
sub gbrowse {
    my ($self) = @_;

    my $helper = $self->app->helper;

    my $feature           = $self->get_gene( $self->stash('id') );
    my $reference_feature = $helper->reference_feature($feature);
    $self->exception( 'source_feature not found: ' . $self->stash('id') )
        if !$reference_feature;

    my $frame = $self->frame($feature);
    my $name =
          $reference_feature->name . ':'
        . $frame->{start} . '..'
        . $frame->{end};

    my $config  = $self->app->config->{content}->{gbrowse};
    my $species = $helper->organism($feature)->species;
    my $tracks  = join( ';', map { 't=' . $_ } @{ $config->{tracks} } );
    my $link    = $config->{link_url} . '?name=' . $name;
    
    my $config_name =
          $config->{version} != 2
        ? $self->app->config->{organism}->{$species}->{site_name}
        : $species;

    my $img_url =
          $config->{img_url} . '/' 
        . $config_name . '/?name=' 
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

    my $helper = $self->app->helper;
    my @links;

    my $feature = $self->get_gene( $self->stash('id') );

    my @predictions =
        $helper->subfeatures( $feature, 'mRNA', 'Sequencing Center' );
    foreach my $prediction (@predictions) {
        my ($genbank_id) =
            $helper->dbxrefs( $prediction, 'Protein Accession Number' );

        my $blink =
            $genbank_id
            ? '<iframe' 
            . ' src="'
            . $self->app->config->{content}->{blink}->{url}
            . $genbank_id
            . '"></iframe>'
            : '';

        push @links, $blink;
    }
    $self->render_text( join( '<br/>', @links ) );
}

sub fasta {
    my ($self) = @_;

    my $config = $self->app->config->{content}->{fasta};
    return if !$config;

    my $helper = $self->app->helper;
    my $markup = Bio::Graphics::Browser::Markup->new;
    $markup->add_style( br => '<br>' );

    my $feature = $self->get_gene( $self->stash('id') );
    my $flip    = $helper->is_flipped($feature);

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
    my $legend = '';
    my @legend_coordinates;

    foreach my $fasta ( @{ $config } ) {
        my $type = $fasta->{type};
        my $source = $fasta->{source} || undef;

        $self->app->log->error('feature type is not defined') if !$type;

        ## add track markup to legend
        my $name = $source ? $type . '-' . $source : $type;
        $markup->add_style( $name => $fasta->{style} );

        push @legend_coordinates,
            [ $name, length($legend), length($legend) + length($name) ];
        $legend .= $name;
        push @legend_coordinates, [ 'br', length($legend), length($legend) ];

        ## grep features with defined type and source from set
        my @features = $helper->filter_by_type( \@features, $type );
        @features = $helper->filter_by_source( \@features, $source )
            if $source;
        
#        if (!@features && $fasta->{sourcedb}){
#            # Open the feature database
#            my $db      = Bio::DB::SeqFeature::Store->new( 
#                -adaptor => 'DBI::mysql',
#                -dsn     => 'dbi:mysql:test',
#            );
#        }
        foreach my $feature (@features) {
            my $frame_coordinates;
            if ( $fasta->{subfeature} ) {
                foreach my $subfeature ( $helper->subfeatures( $feature, $fasta->{subfeature} ) ) {
                    $frame_coordinates = $self->frame_coordinates( $subfeature, $frame, $flip );
                    push @coordinates,
                        [
                        $name,
                        $frame_coordinates->{start},
                        $frame_coordinates->{end}
                        ]
                        if $frame_coordinates;
                }
            }
            else {
                $frame_coordinates = $self->frame_coordinates( $feature, $frame, $flip );
                push @coordinates,
                    [
                    $name, 
                    $frame_coordinates->{start},
                    $frame_coordinates->{end}
                    ];
            }
        }
    }

    ## fix breaks
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
    $self->render_text( '<pre>Color schema:<br/>' 
            . $legend . '<br/>' 
            . $header
            . $sequence
            . '</pre>' );
}

sub blast {
    my ($self) = @_;
    
    my $result = '';
    
    my $helper = $self->app->helper;
    my $config = $self->app->config->{content}->{blast};
    
    my $feature = $self->get_gene( $self->stash('id') );
        
    my $reference_feature  = $helper->reference_feature($feature);
    my @features =
        $helper->splice_features( $reference_feature, $helper->start($feature) - 1,
        $helper->end($feature) );
    
    my @filtered_features;
    foreach my $fasta ( @{ $config->{features} } ) {
        my $type = $fasta->{type};
        my $source = $fasta->{source} || undef;
        
        my @features = $helper->filter_by_type( \@features, $type );
        @features = $helper->filter_by_source( \@features, $source )
            if $source; 
        push @filtered_features, @features;
    }

    foreach my $feature (@filtered_features){
        my $protein = $helper->protein($feature);
        
        my $params = $config->{parameters};
        $params->{sequence} = $protein;
        
        my $report_tx = $self->client->post_form(
            $config->{report_url},
            $params
            );
        my $report = $report_tx->res->body; 
        if (!$report){
             $self->render_text('error retrieving BLAST results');
        }
        my $out = '<iframe src="'. $config->{format_report_url} . '/'. $report .'?noheader=1"></iframe>';
        $self->render_text( $out );
    }
}

sub protein {
    my ($self) = @_;
    my $output = '';
    my $feature = $self->get_gene( $self->stash('id') );
    
    my $helper = $self->app->helper;
    my $config = $self->app->config->{content}->{protein};

    my $reference_feature  = $helper->reference_feature($feature);
    my @features =
        $helper->splice_features( $reference_feature, $helper->start($feature) - 1,
        $helper->end($feature) );
    
    my @filtered_features;
    foreach my $fasta ( @{ $config->{features} } ) {
        my $type = $fasta->{type};
        my $source = $fasta->{source} || undef;
        
        my @features = $helper->filter_by_type( \@features, $type );
        @features = $helper->filter_by_source( \@features, $source )
            if $source; 
        push @filtered_features, @features;
    }

    foreach my $feature (@filtered_features){
        $output .= '<pre>'. $helper->protein($feature) . '</pre><br/>';
    }
    $self->render_text($output);
}

### TODO
sub interpro {
    my ( $self, $feature ) = @_;
    
    my $output = '';
    
    my $config = $self->app->config->{interpro};
    my $helper = $self->app->helper;
    
    my $soap = SOAP::Lite->service($config->{wdsl});
    $soap->proxy( $config->{proxy}, timeout => $config->{timeout} );
    $soap->on_fault(
        sub {
            my ( $soap, $res ) = @_;
            # Throw an exception for all faults
            $self->app->log->error($res) if ref($res) eq '';
            $self->app->log->error( $res->faultstring );
            return new SOAP::SOM;
        }
    );
    $self->soap($soap);
    
    my $params = {    # Parameters to pass to service
        'app'       => join(' ', @{$config->{apps}}),
        'seqtype'   => 'p',
        'async'     => 1,    # Use InterproScan in async mode, simulate sync mode in client
        'email'     => 'y-bushmanova@northwestern.edu'
    };

    my $async = 1;
    
    my $reference_feature  = $helper->reference_feature($feature);
    my @features =
        $helper->splice_features( $reference_feature, $helper->start($feature) - 1,
        $helper->end($feature) );
    
    foreach my $feature ( @{ $self->app->config->{interpro}->{features} } ) {
        my $type = $feature->{type};
        my $source = $feature->{source} || undef;
        
        my @features = $helper->filter_by_type( \@features, $type );
        @features = $helper->filter_by_source( \@features, $source )
            if $source;
        
        my @proteins = map { $helper->protein($_) } @features;
        return 'No protein data available' if !@proteins;
        
        foreach my $protein (@proteins){
            my $contents = [ { type => 'sequence', content => $protein } ];
            my $job_id = $self->submit_job( $contents, $params, $async );
            $self->app->log->error('Error submitting job') if !$job_id;
            
            $output .= '<span class=interpro pending>' . $job_id . '</span><br/>';
        }
    }
    return $output;
#    $self->client_poll($job_id);
#    my $results = $self->get_results($job_id);
#    return $self->format_results($results);
}

## --- Some helpers

sub frame {
    my ( $self, $feature ) = @_;

    my $helper = $self->app->helper;

    my $window_ext = $self->app->config->{content}->{gbrowse}->{padding};

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

sub submit_job {
    my ($self, $contents, $params, $async ) = @_;
    
    my $soap = $self->soap;
    my $job_id;

    # Check application list is right format
    if ( defined( $params->{'app'} ) ) {
        $params->{'app'} =~ s/,/ /g;     # Change commas to spaces for service
        $params->{'app'} =~ s/ +/ /g;    # Squash spaces
    }

    # Submit the job
    my $params_data = SOAP::Data->name('params')->type( map => $params );
    my $content_data = SOAP::Data->name('content')->value($contents);

    # For SOAP::Lite 0.60 and earlier parameters are passed directly
    if ( $SOAP::Lite::VERSION eq '0.60' || $SOAP::Lite::VERSION =~ /0\.[1-5]/ ) {
        $job_id = $soap->runInterProScan( $params_data, $content_data );
    }

    # For SOAP::Lite 0.69 and later parameter handling is different, so pass
    # undef's for templated params, and then pass the formatted args.
    else {
        $job_id =
            $soap->runInterProScan( undef, undef, $params_data,
            $content_data );
    }
    $self->app->log->debug("job started: $job_id");
    return $job_id;
}

sub client_poll {
    my ( $self, $job_id ) = @_;
    my $completed = 0;
    
    while ( $completed ne 1 ) {
        my $status = $self->soap->checkStatus($job_id);
        $completed++ if $status !~ m{running|pending}i;
        sleep $self->app->config->{interpro}->{check_interval};
    }
}

sub get_results {
    my ( $self, $job_id ) = @_;
    my $result;
    my $result_types = $self->soap->getResults($job_id);
    my $outformat    = 'txt';
    foreach my $type (@$result_types) {
        next
            if $type->{ext} !~ m{$outformat}
                && $type->{type} !~ m{$outformat};

        $result = $self->soap->poll( $job_id, $type->{type} );
        next if !$result;
    }

    $self->app->log->debug("retrieved results: $job_id") if $result;

    return $result;
}

sub format_results {
    my ( $self, $results ) = @_;
    return $results;
}

## --- Curation part
sub update {
    my ($self) = @_;

    my $dbh    = $self->app->dbh;
    my $helper = $self->app->helper;

    my $id               = $self->stash('id');
    my $curator_initials = $self->session('initials');

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
    $self->exception( 'gene not found: ' . $id ) if !@features;
    $self->exception( 'more than one gene returned: ' . $id )
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

1;
