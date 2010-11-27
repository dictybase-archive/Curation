package Curation::Controller::Reference;

use warnings;
use strict;
use Bio::DB::EUtilities;
use Bio::Biblio::IO;
use dicty::Search::Gene;
use Modware::Publication::DictyBase;
use Modware::Publication::Author;
use JSON;

# Other modules:
use base 'Mojolicious::Controller';

sub show {
    my ($self)   = @_;
    my $config   = $self->app->config->{reference};
    my $ref      = $self->get_reference;
    my $genes_rs = $self->get_linked_genes($ref);

    my $sub_rs = $genes_rs->search(
        { 'cv.name' => 'dictyBase_literature_topic' },
        {   join => [
                'dbxref',
                {   'feature_pubs' =>
                        { 'feature_pubprops' => { 'type' => 'cv' } }
                }
            ],
        }
    );
    my $not_curated_rs = $genes_rs->search(
        {   feature_id =>
                { 'NOT IN' => $sub_rs->get_column('feature_id')->as_query },
        },
        { order_by => { -asc => 'me.name' } }
    );
    my $curated_rs = $genes_rs->search(
        {   feature_id =>
                { 'IN' => $sub_rs->get_column('feature_id')->as_query },
        },
        { order_by => { -asc => 'me.name' } }
    );
    

    my @linked;
    map { push @linked, $_ }
        map {
        { id => $_->dbxref->accession, name => $_->name, curated => 1 }
        } $curated_rs->all;

    map { push @linked, $_ }
        map {
        { id => $_->dbxref->accession, name => $_->name, curated => 0 }
        } $not_curated_rs->all;

    my $author_count = $ref->total_authors;
    my $author_str;
    if ( $author_count == 1 ) {
        $author_str = $ref->get_from_authors(0)->last_name;
    }
    elsif ( $author_count == 2 ) {
        $author_str =
              $ref->get_from_authors(0)->last_name . ' & '
            . $ref->get_from_authors(1)->last_name;
    }
    else {
        my $penultimate = $author_count - 2;
        for my $i ( 0 .. $penultimate ) {
            if ( $i == $penultimate ) {
                $author_str .= $ref->get_from_authors($i)->last_name . ' & ';
                next;
            }
            $author_str .= $ref->get_from_authors($i)->last_name . ', ';
        }
        $author_str .= $ref->get_from_authors(-1)->last_name;
    }

    my $year = $ref->year;
    $year =~ s{-}{ }g if $year;

    $self->stash( linkout  => $config->{linkout} );
    $self->stash( abstract => $ref->abstract ) if $ref->has_abstract;
    $self->stash( year     => $year ) if $year;
    $self->stash( authors  => $author_str );
    $self->stash( pages    => $ref->pages ) if $ref->has_pages;
    $self->stash( title    => $ref->title ) if $ref->has_title;
    $self->stash( volume   => $ref->volume ) if $ref->has_volume;
    $self->stash( issue    => $ref->issue ) if $ref->has_issue;
    $self->stash( pubmed   => $ref->pubmed_id ) if $ref->pubmed_id;
    $self->stash( journal  => $ref->journal )
        if $ref->has_journal;
    $self->stash( linked => \@linked );
}

sub delete {
    my ($self) = @_;
    my $ref = $self->get_reference;
    eval { $ref->delete; };
    $self->render(
        text   => 'error deleting reference' . $self->stash('id') . $@,
        status => 500
    ) if $@;
    $self->render( text => 'deleted reference ' . $self->stash('id') );
}

sub get_reference {
    my ($self) = @_;
    my $ref;
    eval {
        $ref = Modware::Publication::DictyBase->find_by_pub_id(
            $self->stash('id') );
    };
    return $ref
        || $self->render_exception(
        'Reference not found: ' . $self->stash('id') );
}

sub get_pubmed {
    my ($self) = @_;
    my $ref;
    eval {
        $ref = Modware::Publication::DictyBase->find_by_pubmed_id(
            $self->stash('pubmed_id') );
    };
    $self->render_exception(
        'reference with pubmed ' . $self->stash('pubmed_id') 
        . 'not found' )
        if !$ref;
    $self->redirect_to( '/curation/reference/' . $ref->pub_id );
}

sub create_pubmed {
    my ($self) = @_;
    my $citation;
    my $url;

    $self->render_exception('pubmed id is not provided')
        if !$self->stash('pubmed_id');

    eval {
        my $eutils = Bio::DB::EUtilities->new(
            -eutil => 'efetch',
            -db    => 'pubmed',
            -id    => $self->stash('pubmed_id')
        );

        my $in = Bio::Biblio::IO->new(
            -data   => $eutils->get_Response->content,
            -format => 'medlinexml'
        );
        $citation = $in->next_bibref;

        $eutils->reset_parameters(
            -eutil  => 'elink',
            -dbfrom => 'pubmed',
            -cmd    => 'prlinks',
            -id     => $self->stash('pubmed_id')
        );

        my $ls      = $eutils->next_LinkSet;
        my $linkout = $ls->next_UrlLink;
        $url = $linkout->get_url if $linkout;
    };
    $self->render(
        text => 'error retrieving pubmed '
            . $self->stash('pubmed_id') . ": $@",
        status => 500
    ) if $@ || !$citation;

    my $source = 'PUBMED';
    my $type   = 'journal article';

    my $ref =
        Modware::Publication::DictyBase->new(
        id => $self->stash('pubmed_id') );

    $ref->source($source);
    $ref->type($type);
    $ref->year( $citation->date ) if $citation->date;
    $ref->title( $citation->title );
    $ref->volume( $citation->volume );
    $ref->status( $citation->status );

    $ref->issue( $citation->issue ) if $citation->issue;
    $ref->journal( $citation->journal->abbreviation )
        if $citation->journal && $citation->journal->abbreviation;
    $ref->pages( $citation->medline_page )
        if $citation->medline_page;
    $ref->abstract( $citation->abstract ) if $citation->abstract;
    $ref->full_text_url($url) if $url;

    my $count = 1;
    for my $person ( @{ $citation->authors } ) {
        $ref->add_author(
            Modware::Publication::Author->new(
                last_name  => $person->lastname,
                suffix     => $person->suffix,
                given_name => $person->initials . ' ' . $person->forename,
                rank       => $count++
            )
        );

    }
    my $new_ref = $ref->create;
    $self->redirect_to( '/curation/reference/' . $new_ref->pub_id );
}

sub get_linked_genes {
    my ( $self, $ref ) = @_;

    my $schema = $self->app->schema;

    return $schema->resultset('Sequence::Feature')->search(
        {   'pub.uniquename' => $ref->id,
            'type.name'      => 'gene',
            'me.is_deleted'  => 0
        },
        { join => [ 'type', { 'feature_pubs' => 'pub' } ] }
    );
}

sub get_gene {
    my ($self) = @_;
    my $gene_id = $self->stash('gene_id');

    return if !$gene_id;
    my ($gene) = dicty::Search::Gene->find(
        -name       => $gene_id,
        -id         => $gene_id,
        -clause     => 'OR',
        -is_deleted => 'false'
    );
    $self->render(
        text   => 'no gene with name or id ' . $gene_id . ' found',
        status => 500
    ) if !$gene;
    return $gene;
}

sub link_gene {
    my ($self) = @_;
    my $ref    = $self->get_reference;
    my $gene   = $self->get_gene;

    eval { $gene->add_reference($ref); $gene->_update_reference_links; };

    $self->render(
        text => 'error linking reference '
            . $self->stash('id')
            . " with gene "
            . $gene->name . " : $@",
        status => 500
    ) if $@;

    $self->render( text => 'successfully linked '
            . $self->stash('id')
            . " with gene "
            . $gene->name );
}

sub unlink_gene {
    my ($self) = @_;
    my $ref    = $self->get_reference;
    my $gene   = $self->get_gene;

    eval {
        $gene->remove_reference($ref);
        $gene->_update_reference_links;
    };

    $self->render(
        text => 'error unlinking reference '
            . $self->stash('id')
            . " with gene "
            . $gene->name . " : $@",
        status => 500
    ) if $@;
    $self->render( text => 'successfully unlinked '
            . $self->stash('id')
            . " with gene "
            . $gene->name );
}

sub get_topics {
    my ($self) = @_;
    my $ref    = $self->get_reference;
    my $gene   = $self->get_gene;

    my $topics = $gene->topics_by_reference($ref);
    $self->render( json => $topics );
}

sub update_topics {
    my ($self) = @_;
    my $ref    = $self->get_reference;
    my $gene   = $self->get_gene;
    my $topics = $self->req->content->asset->slurp;

    $self->app->log->debug($topics);
    $self->render_exception('no topics provided') if !$topics;

    my %existng_topics;
    my %updated_topics;

    %existng_topics =
        map { $_ => 1 } @{ $gene->topics_by_reference($ref) }
        if $gene->topics_by_reference($ref);
    %updated_topics = map { $_ => 1 } @{ jsonToObj($topics) }
        if $topics ne '[]';

    foreach my $topic ( keys %updated_topics ) {
        if ( exists $existng_topics{key} ) {
            delete $existng_topics{key};
            delete $updated_topics{key};
        }
    }

    eval {
        $gene->add_topic_by_reference( $ref,    [ keys %updated_topics ] );
        $gene->remove_topic_by_reference( $ref, [ keys %existng_topics ] );
        $gene->update;
    };
    $self->render(
        text => 'error updating topics' 
            . $topics
            . ' for gene '
            . $gene->name . " : $@",
        status => 500
    ) if $@;

    $self->render( text => 'successfully updated topics ' 
            . $topics
            . ' for gene '
            . $gene->name );
}

## not used any more, moved to bulk update from one-by-one
sub add_topic {
    my ($self) = @_;
    my $ref    = $self->get_reference;
    my $gene   = $self->get_gene;
    my $topic  = uri_unescape( $self->req->params('topic') );
    $topic =~ s{\+}{ }g;

    eval {
        $gene->add_topic_by_reference( $ref, [$topic] );
        $gene->update;
    };
    $self->render(
        text => 'error adding topic' 
            . $topic
            . ' for gene '
            . $gene->name . " : $@",
        status => 500
    ) if $@;

    $self->render( text => 'successfully added topic ' 
            . $topic
            . ' for gene '
            . $gene->name );
}

sub delete_topic {
    my ($self) = @_;
    my $ref    = $self->get_reference;
    my $gene   = $self->get_gene;
    my $topic  = $self->req->params('topic');

    eval {
        $gene->remove_topic_by_reference( $ref, [$topic] );
        $gene->update;
    };
    $self->render(
        text => 'error removing topic' 
            . $topic
            . ' for gene '
            . $gene->name . " : $@",
        status => 500
    ) if $@;

    $self->render( text => 'successfully removed topic ' 
            . $topic
            . ' for gene '
            . $gene->name );
}

1;
