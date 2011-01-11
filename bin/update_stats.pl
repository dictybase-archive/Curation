#!/usr/bin/perl 

use strict;
use DBI;
use IO::File;
use Getopt::Long;
use File::Spec::Functions;
use dicty::DBH;

my ( $help, $dbfile );

GetOptions(
    'h|help'       => \$help,
    'd|database=s' => \$dbfile,
);
pod2usage( -verbose => 2 ) if $help;
die 'no database filename provided' if !$dbfile;

my $dbh = DBI->connect( "dbi:SQLite:dbname=$dbfile", '', '' );
$dbh->{AutoCommit} = 1;

my $legacy_dbh = dicty::DBH->new();

my $tables = [
    {   name    => 'stats',
        columns => [
            {   curated => qq{
                SELECT COUNT(*) AS c FROM cgm_chado.v_verified_gene_features v
            }
            },
            {   curated_incomplete_support => qq{
                SELECT COUNT(*) AS c FROM cgm_chado.v_verified_gene_features v
                INNER JOIN cgm_chado.featureprop p ON p.feature_id=v.feature_id
                WHERE p.value LIKE 'genomic context' OR p.value LIKE 'Incomplete support' 
            }
            },
            {   pseudogenes => qq{
                SELECT COUNT(*) AS c FROM cgm_chado.v_notdeleted_feature f
                INNER JOIN cgm_chado.cvterm ct ON ct.cvterm_id = f.type_id
                WHERE ct.name   = 'pseudogene'
            }
            },
            {   alternate_transcripts => qq{
                SELECT COUNT(*) AS c
                FROM
                  (SELECT g.feature_id FROM cgm_chado.v_gene_features g
                  INNER JOIN cgm_chado.feature_relationship fr ON g.feature_id = fr.object_id
                  INNER JOIN v_verified_gene_features m ON m.feature_id = fr.subject_id
                  GROUP BY g.feature_id HAVING COUNT(m.feature_id) > 1
                  )                
            }
            },
            {   comprehensively_annotated => qq{
                SELECT COUNT (fp.feature_id) AS c FROM cgm_chado.featureprop fp
                INNER JOIN cgm_ddb.paragraph p ON TO_NCHAR(fp.value)= p.paragraph_no
                INNER JOIN cgm_chado.cvterm ct ON fp.type_id     = ct.cvterm_id
                WHERE ct.name = 'paragraph_no' AND p.paragraph_text LIKE '\%comprehensively annotated\%'                
            }
            },
            {   basic_annotations => qq{
                SELECT COUNT (fp.feature_id) AS c FROM cgm_chado.featureprop fp
                INNER JOIN cgm_ddb.paragraph p ON TO_NCHAR(fp.value)= p.paragraph_no
                INNER JOIN cgm_chado.cvterm ct ON fp.type_id     = ct.cvterm_id
                WHERE ct.name = 'paragraph_no' AND p.paragraph_text LIKE '\%Basic annotations\%'
            }
            },
            {   genes_descriptions => qq{
                SELECT COUNT(*) AS c FROM cgm_chado.featureprop p
                INNER JOIN cgm_chado.v_gene_features l ON l.feature_id=p.feature_id
                INNER JOIN cgm_chado.cvterm ct ON ct.cvterm_id = p.type_id
                WHERE ct.name   = 'description'
            }
            },
            {   gene_name_descriptions => qq{
                SELECT COUNT(*) AS c FROM cgm_chado.featureprop p
                INNER JOIN cgm_chado.v_gene_features l ON l.feature_id=p.feature_id 
                INNER JOIN cvterm ON cvterm.cvterm_id = p.type_id
                WHERE cvterm.name = 'name description'
            }
            },
            {   summary => qq{
                SELECT count(*) AS c FROM cgm_chado.v_gene_features g
                WHERE EXISTS
                  (SELECT 'a' FROM cgm_chado.featureprop fp
                  INNER JOIN cgm_chado.cvterm ct ON fp.type_id = ct.cvterm_id
                  INNER JOIN cgm_ddb.paragraph p  ON TO_NCHAR(fp.value)= p.paragraph_no
                  WHERE fp.feature_id  = g.feature_id AND ct.name          = 'paragraph_no'
                  AND NOT REGEXP_LIKE(p.paragraph_text, '<summary( paragraph_no="[[:digit:]]*")*>(<curation_status|\\[Curation Status)')
                  )
            }
            },
            {   gene_prodicts => qq{
                SELECT COUNT (DISTINCT feature_id) AS c FROM cgm_chado.v_gene_features
                WHERE feature_id IN
                  (SELECT feature_id FROM cgm_chado.v_gene_features l
                  INNER JOIN cgm_ddb.locus_gp gp       ON gp.locus_no=l.feature_id
                  INNER JOIN cgm_ddb.gene_product g ON g.gene_product_no=gp.gene_product_no
                  INNER JOIN cgm_chado.organism o     ON o.organism_id = l.organism_id 
                  WHERE o.common_name LIKE 'dicty'
                  )                
            }
            },
            {   manual_gene_products => qq{
                SELECT COUNT (DISTINCT feature_id) AS c FROM cgm_chado.v_gene_features
                WHERE feature_id IN
                  (SELECT feature_id FROM cgm_chado.v_gene_features l
                  INNER JOIN cgm_ddb.locus_gp gp ON gp.locus_no=l.feature_id
                  INNER JOIN cgm_ddb.gene_product g ON g.gene_product_no=gp.gene_product_no
                  INNER JOIN cgm_chado.organism o ON o.organism_id = l.organism_id
                  WHERE o.common_name LIKE 'dicty' AND ( NOT g.is_automated=1
                  OR g.is_automated      IS NULL)
                  )
            }
            },
            {   unknown_gene_product => qq{
                SELECT COUNT (DISTINCT feature_id) AS c FROM cgm_chado.v_gene_features
                WHERE feature_id IN
                  (SELECT feature_id FROM cgm_chado.v_gene_features l
                  INNER JOIN cgm_ddb.locus_gp gp ON gp.locus_no=l.feature_id
                  INNER JOIN cgm_ddb.gene_product g ON g.gene_product_no=gp.gene_product_no
                  INNER JOIN cgm_chado.organism o ON o.organism_id = l.organism_id
                  WHERE o.common_name LIKE 'dicty' AND g.gene_product='unknown'
                  )
            }
            },
            {   go_annotations => qq{
                SELECT COUNT(*) AS c FROM cgm_chado.feature_cvterm fc
                INNER JOIN cgm_chado.cvterm ct ON fc.cvterm_id = ct.cvterm_id
                INNER JOIN cgm_chado.cv ON ct.cv_id = cv.cv_id
                INNER JOIN cgm_chado.v_gene_features g ON g.feature_id = fc.feature_id
                WHERE cv.name  IN ('molecular_function', 'biological_process', 'cellular_component')
            }
            },
            {   non_iea_go => qq{
                SELECT COUNT(*) AS c FROM cgm_chado.feature_cvterm fc
                INNER JOIN cgm_chado.cvterm ct ON fc.cvterm_id = ct.cvterm_id
                INNER JOIN cgm_chado.cv ON ct.cv_id = cv.cv_id
                INNER JOIN cgm_chado.v_gene_features g ON g.feature_id = fc.feature_id
                WHERE cv.name  IN ('molecular_function', 'biological_process', 'cellular_component')
                AND NOT EXISTS
                  (SELECT 'a' FROM cgm_chado.feature_cvtermprop fcp
                  INNER JOIN cgm_chado.cvterm fcpc ON fcp.type_id = fcpc.cvterm_id
                  INNER JOIN cgm_chado.cv fcv ON fcpc.cv_id = fcv.cv_id
                  INNER JOIN cgm_chado.cvtermsynonym cs ON fcpc.cvterm_id = cs.cvterm_id
                  INNER JOIN cgm_chado.cvterm cst ON cs.type_id  = cst.cvterm_id
                  WHERE   fcp.feature_cvterm_id = fc.feature_cvterm_id AND fcv.name LIKE 'evidence_code%' AND cs.synonym_ = 'IEA'
                  ) 
            }
            },
            {   genes_with_go => qq{
                SELECT COUNT( DISTINCT fc.feature_id ) AS c FROM cgm_chado.feature_cvterm fc
                INNER JOIN cgm_chado.cvterm ct ON fc.cvterm_id = ct.cvterm_id
                INNER JOIN cgm_chado.cv ON ct.cv_id = cv.cv_id
                INNER JOIN cgm_chado.v_gene_features g ON g.feature_id = fc.feature_id
                WHERE cv.name  IN ('molecular_function', 'biological_process', 'cellular_component')
            }
            },
            {   genes_with_exp => qq{
                SELECT COUNT( DISTINCT fc.feature_id ) AS c FROM cgm_chado.feature_cvterm fc
                INNER JOIN cgm_chado.cvterm ct ON fc.cvterm_id = ct.cvterm_id
                INNER JOIN cgm_chado.cv ON ct.cv_id = cv.cv_id
                INNER JOIN cgm_chado.v_gene_features g ON g.feature_id = fc.feature_id
                WHERE cv.name  IN ('molecular_function', 'biological_process', 'cellular_component')
                AND EXISTS
                  (SELECT 'a' FROM cgm_chado.feature_cvtermprop fcp
                  INNER JOIN cgm_chado.cvterm fcpc ON fcp.type_id = fcpc.cvterm_id
                  INNER JOIN cgm_chado.cv fcv ON fcpc.cv_id = fcv.cv_id
                  INNER JOIN cgm_chado.cvtermsynonym cs  ON fcpc.cvterm_id = cs.cvterm_id
                  INNER JOIN cgm_chado.cvterm cst ON cs.type_id               = cst.cvterm_id
                  WHERE fcp.feature_cvterm_id = fc.feature_cvterm_id and fcv.name LIKE 'evidence_code%'
                  AND cs.synonym_            IN ('IMP', 'IGI', 'IPI', 'IDA')
                  )
            }
            },
            {   fully_go_annotated_genes => qq{
                SELECT COUNT( DISTINCT g.feature_id ) AS c FROM cgm_chado.v_gene_features g
                WHERE EXISTS
                  (SELECT 'a' FROM cgm_chado.feature_cvterm fc
                  INNER JOIN cgm_chado.cvterm ct ON fc.cvterm_id = ct.cvterm_id
                  INNER JOIN cgm_chado.cv ON ct.cv_id         = cv.cv_id
                  WHERE fc.feature_id = g.feature_id  AND cv.name         = 'molecular_function'
                  )
                AND EXISTS
                  (SELECT 'a' FROM cgm_chado.feature_cvterm fc
                  INNER JOIN cgm_chado.cvterm ct ON fc.cvterm_id = ct.cvterm_id
                  INNER JOIN cgm_chado.cv ON ct.cv_id         = cv.cv_id
                  WHERE fc.feature_id = g.feature_id  AND cv.name         = 'biological_process'
                  )
                AND EXISTS
                  (SELECT 'a' FROM cgm_chado.feature_cvterm fc
                  INNER JOIN cgm_chado.cvterm ct ON fc.cvterm_id = ct.cvterm_id
                  INNER JOIN cgm_chado.cv ON ct.cv_id         = cv.cv_id
                  WHERE fc.feature_id = g.feature_id AND cv.name         = 'cellular_component'
                  )
                AND NOT EXISTS
                  (SELECT 'a' FROM cgm_chado.feature_cvterm fc
                  INNER JOIN cgm_chado.feature_cvtermprop fcp ON fc.feature_cvterm_id = fcp.feature_cvterm_id
                  INNER JOIN cgm_chado.cvterm fcpc ON fcp.type_id = fcpc.cvterm_id
                  INNER JOIN cgm_chado.cv fcv ON fcpc.cv_id = fcv.cv_id
                  INNER JOIN cgm_chado.cvtermsynonym cs ON fcpc.cvterm_id = cs.cvterm_id
                  INNER JOIN cgm_chado.cvterm cst ON cs.type_id       = cst.cvterm_id
                  WHERE fc.feature_id = g.feature_id  AND fcv.name LIKE 'evidence_code%'  AND cs.synonym_ = 'IEA'
                  ) 
            }
            },
            {   fully_go_annotated_genes_iea => qq{
                SELECT COUNT( DISTINCT g.feature_id ) AS c FROM cgm_chado.v_gene_features g
                WHERE EXISTS
                  (SELECT 'a' FROM cgm_chado.feature_cvterm fc
                  INNER JOIN cgm_chado.cvterm ct ON fc.cvterm_id = ct.cvterm_id
                  INNER JOIN cgm_chado.cv ON ct.cv_id         = cv.cv_id
                  WHERE fc.feature_id = g.feature_id AND cv.name         = 'molecular_function'
                  )
                AND EXISTS
                  (SELECT 'a' FROM cgm_chado.feature_cvterm fc
                  INNER JOIN cgm_chado.cvterm ct ON fc.cvterm_id = ct.cvterm_id
                  INNER JOIN cgm_chado.cv ON ct.cv_id         = cv.cv_id
                  WHERE fc.feature_id = g.feature_id AND cv.name         = 'biological_process'
                  )
                AND EXISTS
                  (SELECT 'a' FROM cgm_chado.feature_cvterm fc
                  INNER JOIN cgm_chado.cvterm ct ON fc.cvterm_id = ct.cvterm_id
                  INNER JOIN cgm_chado.cv ON ct.cv_id         = cv.cv_id
                  WHERE fc.feature_id = g.feature_id AND cv.name         = 'cellular_component'
                  )
            }
            },
            {   strains => qq{
                SELECT count(*) as c FROM cgm_ddb.stock_center
            }
            },
            {   genes_wth_strains => qq{
                SELECT count (distinct feature_id) as c FROM cgm_chado.feature_genotype
            }
            },
            {   strains_with_genes => qq{
                SELECT count (distinct genotype_id) as c FROM cgm_chado.feature_genotype 
            }
            },
            {   phenotypes => qq{
                SELECT count(*) FROM cgm_chado.phenotype p
            }
            },
            {   genes_with_phenotypes => qq{
                SELECT COUNT(DISTINCT f.name) AS c FROM cgm_chado.feature f
                INNER JOIN cgm_chado.feature_genotype fg ON f.feature_id = fg.feature_id
                INNER JOIN cgm_chado.phenstatement ph ON ph.genotype_id = fg.genotype_id
            }
            },
            {   papers_curated => qq{
                SELECT COUNT( DISTINCT p.pub_id ) as c FROM cgm_chado.pub p
                WHERE EXISTS
                  (SELECT 'a' FROM cgm_chado.feature_pub fp
                  INNER JOIN cgm_chado.feature_pubprop fpp ON fp.feature_pub_id = fpp.feature_pub_id
                  INNER JOIN cgm_chado.cvterm ct ON fpp.type_id = ct.cvterm_id
                  INNER JOIN cgm_chado.cv ON ct.cv_id    = cv.cv_id
                  WHERE p.pub_id = fp.pub_id
                  AND cv.name    ='dictyBase_literature_topic'
                  )
            }
            },
            {   papers_not_curated => qq{
                SELECT COUNT( DISTINCT p.pub_id ) AS c FROM cgm_chado.pub p
                WHERE NOT EXISTS
                  (SELECT 'a' FROM cgm_chado.feature_pub fp
                  INNER JOIN cgm_chado.feature_pubprop fpp ON fp.feature_pub_id = fpp.feature_pub_id
                  INNER JOIN cgm_chado.cvterm ct  ON fpp.type_id = ct.cvterm_id
                  INNER JOIN cgm_chado.cv ON ct.cv_id    = cv.cv_id
                  WHERE p.pub_id = fp.pub_id AND cv.name    ='dictyBase_literature_topic'
                  )
                AND NOT (p.pubplace = 'GENBANK' OR p.pubplace = 'Curator' 
                OR p.pubplace = 'Stinky source')                
            }
            },
            {   community_annotations => qq{
                SELECT COUNT(*) AS c FROM cgm_chado.featureprop fp
                WHERE fp.value LIKE 'Has Wiki Page'
            }
            },
        ],
    },
    {   name    => 'curation_stats',
        columns => [
            {   curated => qq{
                SELECT COUNT(*) AS c,  f.created_by as curator
                FROM cgm_chado.v_verified_gene_features f
                GROUP BY f.created_by
            }
            },
            {   pseudogenes => qq{
                SELECT COUNT(*) AS c, f.created_by as curator
                FROM cgm_chado.v_notdeleted_feature f
                INNER JOIN cgm_chado.cvterm ct ON ct.cvterm_id = f.type_id
                WHERE ct.name   = 'pseudogene'
                GROUP BY f.created_by
            }
            },

            #            { go_annotations        => 'Total GO annotations' },
            #            { genes_with_go         => 'Genes with GO' },
            {   phenotypes => qq{
                SELECT count(*) as c, p.created_by as curator
                FROM cgm_chado.phenotype p GROUP BY p.created_by
            }
            },
            {   genes_with_phenotypes => qq{
                SELECT COUNT(*) AS c, p.created_by as curator
                FROM cgm_chado.feature f
                INNER JOIN cgm_chado.feature_genotype fg ON f.feature_id = fg.feature_id
                INNER JOIN cgm_chado.phenstatement ph ON ph.genotype_id = fg.genotype_id
                INNER JOIN cgm_chado.phenotype p ON p.phenotype_id=ph.phenotype_id
                GROUP BY p.created_by
            }
            },
            {   strains => qq{
                SELECT COUNT(*) AS c, sc.created_by as curator
                FROM cgm_ddb.stock_center sc
                GROUP BY sc.created_by
            }
            },

            #            { genes_wth_strains     => 'Genes with strain(s)' },
            {   papers_curated => qq{
                SELECT COUNT(DISTINCT fp.pub_id) as c, cr.name as curator
                FROM cgm_chado.feature_pub fp
                INNER JOIN cgm_chado.feature_pubprop fpp ON fp.feature_pub_id = fpp.feature_pub_id
                INNER JOIN cgm_chado.curator_feature_pubprop cfp ON cfp.feature_pubprop_id = fpp.feature_pubprop_id
                INNER JOIN cgm_chado.curator cr ON cr.curator_id = cfp.curator_id
                INNER JOIN cgm_chado.cvterm ct ON fpp.type_id = ct.cvterm_id
                INNER JOIN cgm_chado.cv ON ct.cv_id   = cv.cv_id
                WHERE cv.name ='dictyBase_literature_topic'
                GROUP BY cr.name
            }
            },
            {   summary => qq{
                SELECT COUNT(*)  AS c ,
                  'CGM_DDB_PFEY' AS curator
                FROM cgm_ddb.paragraph p
                WHERE NOT REGEXP_LIKE(p.paragraph_text, '<summary( paragraph_no="[[:digit:]]*")*>(<curation_status|\\[Curation Status)')
                AND REGEXP_LIKE(p.paragraph_text, '[[:digit:]]{2}-[[:alpha:]]{3}-[[:digit:]]{4} PF')
                AND EXISTS
                  (SELECT 'a'
                  FROM cgm_chado.featureprop fp
                  INNER JOIN cgm_chado.cvterm ct
                  ON fp.type_id           = ct.cvterm_id
                  WHERE TO_NCHAR(fp.value)= p.paragraph_no
                  AND ct.name             = 'paragraph_no'
                  )

                UNION

                SELECT COUNT(*)  AS c ,
                  'CGM_DDB_PASC' AS curator
                FROM cgm_ddb.paragraph p
                WHERE NOT REGEXP_LIKE(p.paragraph_text, '<summary( paragraph_no="[[:digit:]]*")*>(<curation_status|\\[Curation Status)')
                AND REGEXP_LIKE(p.paragraph_text, '[[:digit:]]{2}-[[:alpha:]]{3}-[[:digit:]]{4} PG')
                AND EXISTS
                  (SELECT 'a'
                  FROM cgm_chado.featureprop fp
                  INNER JOIN cgm_chado.cvterm ct
                  ON fp.type_id           = ct.cvterm_id
                  WHERE TO_NCHAR(fp.value)= p.paragraph_no
                  AND ct.name             = 'paragraph_no'
                  )

                UNION

                SELECT COUNT(*)   AS c ,
                  'CGM_DDB_KERRY' AS curator
                FROM cgm_ddb.paragraph p
                WHERE NOT REGEXP_LIKE(p.paragraph_text, '<summary( paragraph_no="[[:digit:]]*")*>(<curation_status|\\[Curation Status)')
                AND REGEXP_LIKE(p.paragraph_text, '[[:digit:]]{2}-[[:alpha:]]{3}-[[:digit:]]{4} KS')
                AND EXISTS
                  (SELECT 'a'
                  FROM cgm_chado.featureprop fp
                  INNER JOIN cgm_chado.cvterm ct
                  ON fp.type_id           = ct.cvterm_id
                  WHERE TO_NCHAR(fp.value)= p.paragraph_no
                  AND ct.name             = 'paragraph_no'
                  )

                UNION

                SELECT COUNT(*)  AS c ,
                  'CGM_DDB_BOBD' AS curator
                FROM cgm_ddb.paragraph p
                WHERE NOT REGEXP_LIKE(p.paragraph_text, '<summary( paragraph_no="[[:digit:]]*")*>(<curation_status|\\[Curation Status)')
                AND REGEXP_LIKE(p.paragraph_text, '[[:digit:]]{2}-[[:alpha:]]{3}-[[:digit:]]{4} RD')
                AND EXISTS
                  (SELECT 'a'
                  FROM cgm_chado.featureprop fp
                  INNER JOIN cgm_chado.cvterm ct
                  ON fp.type_id           = ct.cvterm_id
                  WHERE TO_NCHAR(fp.value)= p.paragraph_no
                  AND ct.name             = 'paragraph_no'
                  )
            }
            },
            {   comprehensively_annotated => qq{
                    SELECT COUNT (fp.feature_id) AS c, 'CGM_DDB_BOBD' AS curator
                    FROM cgm_chado.featureprop fp
                    INNER JOIN cgm_ddb.paragraph p ON TO_NCHAR(fp.value)= p.paragraph_no
                    INNER JOIN cgm_chado.cvterm ct ON fp.type_id = ct.cvterm_id
                    WHERE ct.name = 'paragraph_no'
                    AND p.paragraph_text LIKE '\%comprehensively annotated%'
                    AND REGEXP_LIKE(p.paragraph_text, '[[:digit:]]{2}-[[:alpha:]]{3}-[[:digit:]]{4} RD')

                    UNION

                    SELECT COUNT (fp.feature_id) AS c, 'CGM_DDB_PFEY' AS curator
                    FROM cgm_chado.featureprop fp
                    INNER JOIN cgm_ddb.paragraph p ON TO_NCHAR(fp.value)= p.paragraph_no
                    INNER JOIN cgm_chado.cvterm ct ON fp.type_id = ct.cvterm_id
                    WHERE ct.name = 'paragraph_no'
                    AND p.paragraph_text LIKE '\%comprehensively annotated%'
                    AND REGEXP_LIKE(p.paragraph_text, '[[:digit:]]{2}-[[:alpha:]]{3}-[[:digit:]]{4} PF')

                    UNION

                    SELECT COUNT (fp.feature_id) AS c, 'CGM_DDB_PASC' AS curator
                    FROM cgm_chado.featureprop fp
                    INNER JOIN cgm_ddb.paragraph p ON TO_NCHAR(fp.value)= p.paragraph_no
                    INNER JOIN cgm_chado.cvterm ct ON fp.type_id = ct.cvterm_id
                    WHERE ct.name = 'paragraph_no'
                    AND p.paragraph_text LIKE '\%comprehensively annotated%'
                    AND REGEXP_LIKE(p.paragraph_text, '[[:digit:]]{2}-[[:alpha:]]{3}-[[:digit:]]{4} PG')

                    UNION

                    SELECT COUNT (fp.feature_id) AS c, 'CGM_DDB_KERRY' AS curator
                    FROM cgm_chado.featureprop fp
                    INNER JOIN cgm_ddb.paragraph p ON TO_NCHAR(fp.value)= p.paragraph_no
                    INNER JOIN cgm_chado.cvterm ct ON fp.type_id = ct.cvterm_id
                    WHERE ct.name = 'paragraph_no'
                    AND p.paragraph_text LIKE '\%comprehensively annotated%'
                    AND REGEXP_LIKE(p.paragraph_text, '[[:digit:]]{2}-[[:alpha:]]{3}-[[:digit:]]{4} KS')
            }
            },
            {   basic_annotations => qq{
                SELECT COUNT (fp.feature_id) AS c, 'CGM_DDB_BOBD' AS curator
                FROM cgm_chado.featureprop fp
                INNER JOIN cgm_ddb.paragraph p ON TO_NCHAR(fp.value)= p.paragraph_no
                INNER JOIN cgm_chado.cvterm ct ON fp.type_id = ct.cvterm_id
                WHERE ct.name = 'paragraph_no'
                AND p.paragraph_text LIKE '\%Basic annotations%'
                AND REGEXP_LIKE(p.paragraph_text, '[[:digit:]]{2}-[[:alpha:]]{3}-[[:digit:]]{4} RD')

                UNION

                SELECT COUNT (fp.feature_id) AS c, 'CGM_DDB_PFEY' AS curator
                FROM cgm_chado.featureprop fp
                INNER JOIN cgm_ddb.paragraph p ON TO_NCHAR(fp.value)= p.paragraph_no
                INNER JOIN cgm_chado.cvterm ct ON fp.type_id = ct.cvterm_id
                WHERE ct.name = 'paragraph_no'
                AND p.paragraph_text LIKE '\%Basic annotations%'
                AND REGEXP_LIKE(p.paragraph_text, '[[:digit:]]{2}-[[:alpha:]]{3}-[[:digit:]]{4} PF')

                UNION

                SELECT COUNT (fp.feature_id) AS c, 'CGM_DDB_PASC' AS curator
                FROM cgm_chado.featureprop fp
                INNER JOIN cgm_ddb.paragraph p ON TO_NCHAR(fp.value)= p.paragraph_no
                INNER JOIN cgm_chado.cvterm ct ON fp.type_id = ct.cvterm_id
                WHERE ct.name = 'paragraph_no' AND p.paragraph_text LIKE '\%Basic annotations%'
                AND REGEXP_LIKE(p.paragraph_text, '[[:digit:]]{2}-[[:alpha:]]{3}-[[:digit:]]{4} PG')

                UNION

                SELECT COUNT (fp.feature_id) AS c, 'CGM_DDB_KERRY' AS curator
                FROM cgm_chado.featureprop fp
                INNER JOIN cgm_ddb.paragraph p ON TO_NCHAR(fp.value)= p.paragraph_no
                INNER JOIN cgm_chado.cvterm ct ON fp.type_id = ct.cvterm_id
                WHERE ct.name = 'paragraph_no'
                AND p.paragraph_text LIKE '\%Basic annotations%'
                AND REGEXP_LIKE(p.paragraph_text, '[[:digit:]]{2}-[[:alpha:]]{3}-[[:digit:]]{4} KS')
            }
            },
        ],
        group_by => 'curator',

    }
];

foreach my $table (@$tables) {
    my @columns = @{ $table->{columns} };
    my $group   = $table->{group_by};

    my $insert_hash;

    foreach my $column (@columns) {
        my ($query) = values %$column;
        my ($name)  = keys %$column;

        my $sth = $legacy_dbh->prepare($query);
        $sth->execute;

        if ($group) {
            while ( my $row = $sth->fetchrow_hashref ) {
                $insert_hash->{ $row->{$group} }->{$name}  = $row->{'c'};
                $insert_hash->{ $row->{$group} }->{$group} = $row->{$group};
            }
        }
        else {
            my $row = $sth->fetchrow_hashref;
            $insert_hash->{'dummy'}->{$name} = $row->{'c'};
            $sth->finish;
        }
    }

    foreach my $key ( sort keys %$insert_hash ) {
        my $rowset  = $insert_hash->{$key};
        my @columns = keys %$rowset;
        my @values  = map { $rowset->{$_} } @columns;
        
        next
            if $rowset->{'curator'}
                && $rowset->{'curator'} !~ m{BOBD|PFEY|PASC|KERRY};

        my $placeholders = join ',', map {'?'} @values;
        my $insert_sql =
              'insert into '
            . $table->{name} . ' ('
            . join( ',', @columns )
            . ") values ($placeholders)";

        my $sth = $dbh->prepare($insert_sql);
        $sth->execute(@values);
    }
}

