#!/usr/bin/env perl
#
# Module used to interact with the back-end submissions DB. The table
# classes are defined in the DB/ subdirectory.
#
# Tim Rayner 2006, ArrayExpress team, European Bioinformatics Institute
#
# $Id: DB.pm 2137 2008-11-20 16:25:19Z farne $
#

use strict;
use warnings;
use Class::DBI;

package ArrayExpress::AutoSubmission::DB;
use base 'Class::DBI';

use EBI::FGPT::Config qw($CONFIG);

# DUMMY used to fool our test scripts (connection requires a DSN).
ArrayExpress::AutoSubmission::DB->connection(
    ($CONFIG->get_AUTOSUBS_DSN() || 'DUMMY'),
    $CONFIG->get_AUTOSUBS_USERNAME(),
    $CONFIG->get_AUTOSUBS_PASSWORD(),
    $CONFIG->get_AUTOSUBS_DBPARAMS(),
);

=pod

=begin html

    <div><a name="top"></a>
      <table class="layout">
	  <tr>
	    <td class="whitetitle" width="100">
              <a href="../../../index.html">
                <img src="../../T2M_logo.png"
                     border="0" height="50" alt="Tab2MAGE logo"></td>
              </a>
	    <td class="pagetitle">Module detail: DB.pm</td>
	  </tr>
      </table>
    </div>

=end html

=head1 NAME

ArrayExpress::AutoSubmission::DB - Class::DBI based interface to the
autosubmissions tracking database.

=head1 SYNOPSIS

 use ArrayExpress::AutoSubmission::DB::Experiment;
 my $expt = ArrayExpress::AutoSubmission::DB::Experiment->retrieve( $id );

=head1 DESCRIPTION

This module is the abstract superclass for a set of Class::DBI - based
modules, which are used as an object-relational mapping to the
underlying submissions tracking database (currently implemented using
MySQL). You should not use this class directly; rather, you should use
the relevant table subclasses to query the database (see L</SYNOPSIS>
for an example). Please refer to the Class::DBI documentation for
information on query syntax.

=head1 TABLES

Included below are auto-generated descriptions of the MySQL
tables. This listing was generated using the
SQL::Translator::Producer::POD module.

=head2 array_designs

=head3 FIELDS

=head4 id

=over 4

=item * int(11)

=item * PRIMARY KEY

=item * Nullable 'No' 

=back

=head4 miamexpress_subid

=over 4

=item * int(11)

=item * Default 'NULL' 

=item * Nullable 'Yes' 

=back

=head4 accession

=over 4

=item * varchar(255)

=item * Default 'NULL' 

=item * Nullable 'Yes' 

=back

=head4 name

=over 4

=item * varchar(255)

=item * Default 'NULL' 

=item * Nullable 'Yes' 

=back

=head4 miamexpress_login

=over 4

=item * varchar(50)

=item * Default 'NULL' 

=item * Nullable 'Yes' 

=back

=head4 status

=over 4

=item * varchar(50)

=item * Default 'NULL' 

=item * Nullable 'Yes' 

=back

=head4 data_warehouse_ready

=over 4

=item * char(15)

=item * Default 'NULL' 

=item * Nullable 'Yes' 

=back

=head4 date_last_processed

=over 4

=item * datetime

=item * Default 'NULL' 

=item * Nullable 'Yes' 

=back

=head4 comment

=over 4

=item * text(65535)

=item * Nullable 'Yes' 

=back

=head4 is_deleted

=over 4

=item * int(11)

=item * Nullable 'No' 

=back

=head4 miame_score

=over 4

=item * int(11)

=item * Default 'NULL' 

=item * Nullable 'Yes' 

=back

=head4 in_data_warehouse

=over 4

=item * int(11)

=item * Default 'NULL' 

=item * Nullable 'Yes' 

=back

=head4 annotation_source

=over 4

=item * varchar(50)

=item * Default 'NULL' 

=item * Nullable 'Yes' 

=back

=head4 annotation_version

=over 4

=item * varchar(50)

=item * Default 'NULL' 

=item * Nullable 'Yes' 

=back

=head4 biomart_table_name

=over 4

=item * varchar(50)

=item * Default 'NULL' 

=item * Nullable 'Yes' 

=back

=head4 release_date

=over 4

=item * datetime

=item * Default 'NULL' 

=item * Nullable 'Yes' 

=back

=head4 is_released

=over 4

=item * int(11)

=item * Default 'NULL' 

=item * Nullable 'Yes' 

=back

=head3 CONSTRAINTS

=head4 PRIMARY KEY

=over 4

=item * Fields = id

=back

=head4 UNIQUE

=over 4

=item * Fields = miamexpress_subid

=back

=head2 array_designs_experiments

=head3 FIELDS

=head4 id

=over 4

=item * int(11)

=item * PRIMARY KEY

=item * Nullable 'No' 

=back

=head4 array_design_id

=over 4

=item * int(11)

=item * Nullable 'No' 

=back

=head4 experiment_id

=over 4

=item * int(11)

=item * Nullable 'No' 

=back

=head3 INDICES

=head4 NORMAL

=over 4

=item * Fields = array_design_id

=back

=head4 NORMAL

=over 4

=item * Fields = experiment_id

=back

=head3 CONSTRAINTS

=head4 PRIMARY KEY

=over 4

=item * Fields = id

=back

=head4 FOREIGN KEY

=over 4

=item * Fields = array_design_id

=item * Reference Table = L</array_designs>

=item * Reference Fields = L</id>

=item * On delete = CASCADE

=back

=head4 FOREIGN KEY

=over 4

=item * Fields = experiment_id

=item * Reference Table = L</experiments>

=item * Reference Fields = L</id>

=item * On delete = CASCADE

=back

=head2 array_designs_organisms

=head3 FIELDS

=head4 id

=over 4

=item * int(11)

=item * PRIMARY KEY

=item * Nullable 'No' 

=back

=head4 organism_id

=over 4

=item * int(11)

=item * Nullable 'No' 

=back

=head4 array_design_id

=over 4

=item * int(11)

=item * Nullable 'No' 

=back

=head3 INDICES

=head4 NORMAL

=over 4

=item * Fields = organism_id

=back

=head4 NORMAL

=over 4

=item * Fields = array_design_id

=back

=head3 CONSTRAINTS

=head4 PRIMARY KEY

=over 4

=item * Fields = id

=back

=head4 FOREIGN KEY

=over 4

=item * Fields = organism_id

=item * Reference Table = L</organisms>

=item * Reference Fields = L</id>

=item * On delete = CASCADE

=back

=head4 FOREIGN KEY

=over 4

=item * Fields = array_design_id

=item * Reference Table = L</array_designs>

=item * Reference Fields = L</id>

=item * On delete = CASCADE

=back

=head2 categories

=head3 FIELDS

=head4 id

=over 4

=item * int(11)

=item * PRIMARY KEY

=item * Nullable 'No' 

=back

=head4 ontology_term

=over 4

=item * varchar(50)

=item * Default 'NULL' 

=item * Nullable 'Yes' 

=back

=head4 display_label

=over 4

=item * varchar(50)

=item * Default 'NULL' 

=item * Nullable 'Yes' 

=back

=head4 is_common

=over 4

=item * int(11)

=item * Default 'NULL' 

=item * Nullable 'Yes' 

=back

=head4 is_bmc

=over 4

=item * int(11)

=item * Default 'NULL' 

=item * Nullable 'Yes' 

=back

=head4 is_fv

=over 4

=item * int(11)

=item * Default 'NULL' 

=item * Nullable 'Yes' 

=back

=head4 is_deleted

=over 4

=item * int(11)

=item * Nullable 'No' 

=back

=head3 CONSTRAINTS

=head4 PRIMARY KEY

=over 4

=item * Fields = id

=back

=head2 categories_designs

=head3 FIELDS

=head4 category_id

=over 4

=item * int(11)

=item * Nullable 'No' 

=back

=head4 design_id

=over 4

=item * int(11)

=item * Nullable 'No' 

=back

=head3 INDICES

=head4 NORMAL

=over 4

=item * Fields = category_id

=back

=head4 NORMAL

=over 4

=item * Fields = design_id

=back

=head3 CONSTRAINTS

=head4 FOREIGN KEY

=over 4

=item * Fields = category_id

=item * Reference Table = L</categories>

=item * Reference Fields = L</id>

=item * On delete = CASCADE

=back

=head4 FOREIGN KEY

=over 4

=item * Fields = design_id

=item * Reference Table = L</designs>

=item * Reference Fields = L</id>

=item * On delete = CASCADE

=back

=head2 categories_materials

=head3 FIELDS

=head4 category_id

=over 4

=item * int(11)

=item * Nullable 'No' 

=back

=head4 material_id

=over 4

=item * int(11)

=item * Nullable 'No' 

=back

=head3 INDICES

=head4 NORMAL

=over 4

=item * Fields = category_id

=back

=head4 NORMAL

=over 4

=item * Fields = material_id

=back

=head3 CONSTRAINTS

=head4 FOREIGN KEY

=over 4

=item * Fields = category_id

=item * Reference Table = L</categories>

=item * Reference Fields = L</id>

=item * On delete = CASCADE

=back

=head4 FOREIGN KEY

=over 4

=item * Fields = material_id

=item * Reference Table = L</materials>

=item * Reference Fields = L</id>

=item * On delete = CASCADE

=back

=head2 categories_taxons

=head3 FIELDS

=head4 category_id

=over 4

=item * int(11)

=item * Nullable 'No' 

=back

=head4 taxon_id

=over 4

=item * int(11)

=item * Nullable 'No' 

=back

=head3 INDICES

=head4 NORMAL

=over 4

=item * Fields = category_id

=back

=head4 NORMAL

=over 4

=item * Fields = taxon_id

=back

=head3 CONSTRAINTS

=head4 FOREIGN KEY

=over 4

=item * Fields = category_id

=item * Reference Table = L</categories>

=item * Reference Fields = L</id>

=item * On delete = CASCADE

=back

=head4 FOREIGN KEY

=over 4

=item * Fields = taxon_id

=item * Reference Table = L</taxons>

=item * Reference Fields = L</id>

=item * On delete = CASCADE

=back

=head2 data_files

=head3 FIELDS

=head4 id

=over 4

=item * int(11)

=item * PRIMARY KEY

=item * Nullable 'No' 

=back

=head4 experiment_id

=over 4

=item * int(11)

=item * Nullable 'No' 

=back

=head4 name

=over 4

=item * varchar(255)

=item * Default 'NULL' 

=item * Nullable 'Yes' 

=back

=head4 is_unpacked

=over 4

=item * int(11)

=item * Default 'NULL' 

=item * Nullable 'Yes' 

=back

=head4 is_deleted

=over 4

=item * int(11)

=item * Nullable 'No' 

=back

=head3 INDICES

=head4 NORMAL

=over 4

=item * Fields = experiment_id

=back

=head3 CONSTRAINTS

=head4 PRIMARY KEY

=over 4

=item * Fields = id

=back

=head4 FOREIGN KEY

=over 4

=item * Fields = experiment_id

=item * Reference Table = L</experiments>

=item * Reference Fields = L</id>

=back

=head2 data_formats

=head3 FIELDS

=head4 id

=over 4

=item * int(11)

=item * PRIMARY KEY

=item * Nullable 'No' 

=back

=head4 name

=over 4

=item * varchar(50)

=item * Nullable 'No' 

=back

=head3 CONSTRAINTS

=head4 PRIMARY KEY

=over 4

=item * Fields = id

=back

=head4 UNIQUE

=over 4

=item * Fields = name

=back

=head2 design_instances

=head3 FIELDS

=head4 id

=over 4

=item * int(11)

=item * PRIMARY KEY

=item * Nullable 'No' 

=back

=head4 design_id

=over 4

=item * int(11)

=item * Nullable 'No' 

=back

=head4 experiment_id

=over 4

=item * int(11)

=item * Nullable 'No' 

=back

=head3 INDICES

=head4 NORMAL

=over 4

=item * Fields = design_id

=back

=head4 NORMAL

=over 4

=item * Fields = experiment_id

=back

=head3 CONSTRAINTS

=head4 PRIMARY KEY

=over 4

=item * Fields = id

=back

=head4 FOREIGN KEY

=over 4

=item * Fields = design_id

=item * Reference Table = L</designs>

=item * Reference Fields = L</id>

=item * On delete = CASCADE

=back

=head4 FOREIGN KEY

=over 4

=item * Fields = experiment_id

=item * Reference Table = L</experiments>

=item * Reference Fields = L</id>

=item * On delete = CASCADE

=back

=head2 designs

=head3 FIELDS

=head4 id

=over 4

=item * int(11)

=item * PRIMARY KEY

=item * Nullable 'No' 

=back

=head4 display_label

=over 4

=item * varchar(50)

=item * Default 'NULL' 

=item * Nullable 'Yes' 

=back

=head4 ontology_category

=over 4

=item * varchar(50)

=item * Default 'NULL' 

=item * Nullable 'Yes' 

=back

=head4 ontology_value

=over 4

=item * varchar(50)

=item * Default 'NULL' 

=item * Nullable 'Yes' 

=back

=head4 design_type

=over 4

=item * char(15)

=item * Nullable 'No' 

=back

=head4 is_deleted

=over 4

=item * int(11)

=item * Nullable 'No' 

=back

=head3 CONSTRAINTS

=head4 PRIMARY KEY

=over 4

=item * Fields = id

=back

=head2 events

=head3 FIELDS

=head4 id

=over 4

=item * int(11)

=item * PRIMARY KEY

=item * Nullable 'No' 

=back

=head4 array_design_id

=over 4

=item * int(11)

=item * Default 'NULL' 

=item * Nullable 'Yes' 

=back

=head4 experiment_id

=over 4

=item * int(11)

=item * Default 'NULL' 

=item * Nullable 'Yes' 

=back

=head4 event_type

=over 4

=item * varchar(50)

=item * Nullable 'No' 

=back

=head4 was_successful

=over 4

=item * int(11)

=item * Default 'NULL' 

=item * Nullable 'Yes' 

=back

=head4 source_db

=over 4

=item * varchar(30)

=item * Default 'NULL' 

=item * Nullable 'Yes' 

=back

=head4 target_db

=over 4

=item * varchar(30)

=item * Default 'NULL' 

=item * Nullable 'Yes' 

=back

=head4 start_time

=over 4

=item * datetime

=item * Default 'NULL' 

=item * Nullable 'Yes' 

=back

=head4 end_time

=over 4

=item * datetime

=item * Default 'NULL' 

=item * Nullable 'Yes' 

=back

=head4 machine

=over 4

=item * varchar(50)

=item * Default 'NULL' 

=item * Nullable 'Yes' 

=back

=head4 operator

=over 4

=item * varchar(30)

=item * Default 'NULL' 

=item * Nullable 'Yes' 

=back

=head4 log_file

=over 4

=item * varchar(511)

=item * Default 'NULL' 

=item * Nullable 'Yes' 

=back

=head4 jobregister_dbid

=over 4

=item * int(15)

=item * Default 'NULL' 

=item * Nullable 'Yes' 

=back

=head4 comment

=over 4

=item * text(65535)

=item * Nullable 'Yes' 

=back

=head4 is_deleted

=over 4

=item * int(11)

=item * Nullable 'No' 

=back

=head3 INDICES

=head4 NORMAL

=over 4

=item * Fields = array_design_id

=back

=head4 NORMAL

=over 4

=item * Fields = experiment_id

=back

=head3 CONSTRAINTS

=head4 PRIMARY KEY

=over 4

=item * Fields = id

=back

=head4 FOREIGN KEY

=over 4

=item * Fields = array_design_id

=item * Reference Table = L</array_designs>

=item * Reference Fields = L</id>

=back

=head4 FOREIGN KEY

=over 4

=item * Fields = experiment_id

=item * Reference Table = L</experiments>

=item * Reference Fields = L</id>

=back

=head2 experiments

=head3 FIELDS

=head4 id

=over 4

=item * int(11)

=item * PRIMARY KEY

=item * Nullable 'No' 

=back

=head4 accession

=over 4

=item * varchar(255)

=item * Default 'NULL' 

=item * Nullable 'Yes' 

=back

=head4 name

=over 4

=item * varchar(255)

=item * Default 'NULL' 

=item * Nullable 'Yes' 

=back

=head4 user_id

=over 4

=item * int(11)

=item * Default 'NULL' 

=item * Nullable 'Yes' 

=back

=head4 checker_score

=over 4

=item * int(11)

=item * Default 'NULL' 

=item * Nullable 'Yes' 

=back

=head4 software

=over 4

=item * varchar(100)

=item * Default 'NULL' 

=item * Nullable 'Yes' 

=back

=head4 status

=over 4

=item * varchar(50)

=item * Default 'NULL' 

=item * Nullable 'Yes' 

=back

=head4 data_warehouse_ready

=over 4

=item * int(11)

=item * Default 'NULL' 

=item * Nullable 'Yes' 

=back

=head4 date_last_edited

=over 4

=item * datetime

=item * Default 'NULL' 

=item * Nullable 'Yes' 

=back

=head4 date_submitted

=over 4

=item * datetime

=item * Default 'NULL' 

=item * Nullable 'Yes' 

=back

=head4 date_last_processed

=over 4

=item * datetime

=item * Default 'NULL' 

=item * Nullable 'Yes' 

=back

=head4 in_curation

=over 4

=item * int(11)

=item * Default 'NULL' 

=item * Nullable 'Yes' 

=back

=head4 curator

=over 4

=item * char(30)

=item * Default 'NULL' 

=item * Nullable 'Yes' 

=back

=head4 comment

=over 4

=item * text(65535)

=item * Nullable 'Yes' 

=back

=head4 experiment_type

=over 4

=item * char(30)

=item * Default 'NULL' 

=item * Nullable 'Yes' 

=back

=head4 miamexpress_login

=over 4

=item * char(30)

=item * Default 'NULL' 

=item * Nullable 'Yes' 

=back

=head4 miamexpress_subid

=over 4

=item * int(11)

=item * Default 'NULL' 

=item * Nullable 'Yes' 

=back

=head4 is_affymetrix

=over 4

=item * int(11)

=item * Default 'NULL' 

=item * Nullable 'Yes' 

=back

=head4 is_mx_batchloader

=over 4

=item * int(11)

=item * Default 'NULL' 

=item * Nullable 'Yes' 

=back

=head4 is_deleted

=over 4

=item * int(11)

=item * Nullable 'No' 

=back

=head4 miame_score

=over 4

=item * int(11)

=item * Default 'NULL' 

=item * Nullable 'Yes' 

=back

=head4 in_data_warehouse

=over 4

=item * int(11)

=item * Default 'NULL' 

=item * Nullable 'Yes' 

=back

=head4 num_submissions

=over 4

=item * int(11)

=item * Default 'NULL' 

=item * Nullable 'Yes' 

=back

=head4 submitter_description

=over 4

=item * text(65535)

=item * Nullable 'Yes' 

=back

=head4 curated_name

=over 4

=item * varchar(255)

=item * Default 'NULL' 

=item * Nullable 'Yes' 

=back

=head4 num_samples

=over 4

=item * int(11)

=item * Default 'NULL' 

=item * Nullable 'Yes' 

=back

=head4 num_hybridizations

=over 4

=item * int(11)

=item * Default 'NULL' 

=item * Nullable 'Yes' 

=back

=head4 has_raw_data

=over 4

=item * int(11)

=item * Default 'NULL' 

=item * Nullable 'Yes' 

=back

=head4 has_processed_data

=over 4

=item * int(11)

=item * Default 'NULL' 

=item * Nullable 'Yes' 

=back

=head4 has_gds

=over 4

=item * bit(1)

=item * Default 'NULL' 

=item * Nullable 'Yes' 

=back

=head4 release_date

=over 4

=item * datetime

=item * Default 'NULL' 

=item * Nullable 'Yes' 

=back

=head4 is_released

=over 4

=item * int(11)

=item * Default 'NULL' 

=item * Nullable 'Yes' 

=back

=head4 ae_miame_score

=over 4

=item * int(11)

=item * Default 'NULL' 

=item * Nullable 'Yes' 

=back

=head4 ae_data_warehouse_score

=over 4

=item * int(11)

=item * Default 'NULL' 

=item * Nullable 'Yes' 

=back

=head3 INDICES

=head4 NORMAL

=over 4

=item * Fields = user_id

=back

=head3 CONSTRAINTS

=head4 PRIMARY KEY

=over 4

=item * Fields = id

=back

=head4 FOREIGN KEY

=over 4

=item * Fields = user_id

=item * Reference Table = L</users>

=item * Reference Fields = L</id>

=back

=head2 experiments_factors

=head3 FIELDS

=head4 id

=over 4

=item * int(11)

=item * PRIMARY KEY

=item * Nullable 'No' 

=back

=head4 experiment_id

=over 4

=item * int(11)

=item * Nullable 'No' 

=back

=head4 factor_id

=over 4

=item * int(11)

=item * Nullable 'No' 

=back

=head3 INDICES

=head4 NORMAL

=over 4

=item * Fields = experiment_id

=back

=head4 NORMAL

=over 4

=item * Fields = factor_id

=back

=head3 CONSTRAINTS

=head4 PRIMARY KEY

=over 4

=item * Fields = id

=back

=head4 FOREIGN KEY

=over 4

=item * Fields = factor_id

=item * Reference Table = L</factors>

=item * Reference Fields = L</id>

=item * On delete = CASCADE

=back

=head4 FOREIGN KEY

=over 4

=item * Fields = experiment_id

=item * Reference Table = L</experiments>

=item * Reference Fields = L</id>

=item * On delete = CASCADE

=back

=head2 experiments_loaded_data

=head3 FIELDS

=head4 experiment_id

=over 4

=item * int(11)

=item * Nullable 'No' 

=back

=head4 loaded_data_id

=over 4

=item * int(11)

=item * Nullable 'No' 

=back

=head3 INDICES

=head4 NORMAL

=over 4

=item * Fields = experiment_id

=back

=head4 NORMAL

=over 4

=item * Fields = loaded_data_id

=back

=head3 CONSTRAINTS

=head4 FOREIGN KEY

=over 4

=item * Fields = experiment_id

=item * Reference Table = L</experiments>

=item * Reference Fields = L</id>

=item * On delete = CASCADE

=back

=head4 FOREIGN KEY

=over 4

=item * Fields = loaded_data_id

=item * Reference Table = L</loaded_data>

=item * Reference Fields = L</id>

=item * On delete = CASCADE

=back

=head2 experiments_quantitation_types

=head3 FIELDS

=head4 id

=over 4

=item * int(11)

=item * PRIMARY KEY

=item * Nullable 'No' 

=back

=head4 quantitation_type_id

=over 4

=item * int(11)

=item * Nullable 'No' 

=back

=head4 experiment_id

=over 4

=item * int(11)

=item * Nullable 'No' 

=back

=head3 INDICES

=head4 NORMAL

=over 4

=item * Fields = quantitation_type_id

=back

=head4 NORMAL

=over 4

=item * Fields = experiment_id

=back

=head3 CONSTRAINTS

=head4 PRIMARY KEY

=over 4

=item * Fields = id

=back

=head4 FOREIGN KEY

=over 4

=item * Fields = quantitation_type_id

=item * Reference Table = L</quantitation_types>

=item * Reference Fields = L</id>

=item * On delete = CASCADE

=back

=head4 FOREIGN KEY

=over 4

=item * Fields = experiment_id

=item * Reference Table = L</experiments>

=item * Reference Fields = L</id>

=item * On delete = CASCADE

=back

=head2 factors

=head3 FIELDS

=head4 id

=over 4

=item * int(11)

=item * PRIMARY KEY

=item * Nullable 'No' 

=back

=head4 name

=over 4

=item * varchar(128)

=item * Nullable 'No' 

=back

=head4 is_deleted

=over 4

=item * int(11)

=item * Nullable 'No' 

=back

=head3 CONSTRAINTS

=head4 PRIMARY KEY

=over 4

=item * Fields = id

=back

=head2 loaded_data

=head3 FIELDS

=head4 id

=over 4

=item * int(11)

=item * PRIMARY KEY

=item * Nullable 'No' 

=back

=head4 identifier

=over 4

=item * varchar(255)

=item * Nullable 'No' 

=back

=head4 md5_hash

=over 4

=item * char(35)

=item * Nullable 'No' 

=back

=head4 data_format_id

=over 4

=item * int(11)

=item * Nullable 'No' 

=back

=head4 is_deleted

=over 4

=item * int(11)

=item * Nullable 'No' 

=back

=head4 platform_id

=over 4

=item * int(11)

=item * Default 'NULL' 

=item * Nullable 'Yes' 

=back

=head4 needs_metrics_calculation

=over 4

=item * int(11)

=item * Nullable 'No' 

=back

=head4 date_hashed

=over 4

=item * datetime

=item * Default 'NULL' 

=item * Nullable 'Yes' 

=back

=head3 INDICES

=head4 NORMAL

=over 4

=item * Fields = data_format_id

=back

=head4 NORMAL

=over 4

=item * Fields = platform_id

=back

=head3 CONSTRAINTS

=head4 PRIMARY KEY

=over 4

=item * Fields = id

=back

=head4 FOREIGN KEY

=over 4

=item * Fields = platform_id

=item * Reference Table = L</platforms>

=item * Reference Fields = L</id>

=back

=head4 FOREIGN KEY

=over 4

=item * Fields = data_format_id

=item * Reference Table = L</data_formats>

=item * Reference Fields = L</id>

=back

=head2 loaded_data_quality_metrics

=head3 FIELDS

=head4 id

=over 4

=item * int(11)

=item * PRIMARY KEY

=item * Nullable 'No' 

=back

=head4 value

=over 4

=item * decimal(12,5)

=item * Default 'NULL' 

=item * Nullable 'Yes' 

=back

=head4 quality_metric_id

=over 4

=item * int(11)

=item * Nullable 'No' 

=back

=head4 loaded_data_id

=over 4

=item * int(11)

=item * Nullable 'No' 

=back

=head4 date_calculated

=over 4

=item * datetime

=item * Default 'NULL' 

=item * Nullable 'Yes' 

=back

=head3 INDICES

=head4 NORMAL

=over 4

=item * Fields = quality_metric_id

=back

=head4 NORMAL

=over 4

=item * Fields = loaded_data_id

=back

=head3 CONSTRAINTS

=head4 PRIMARY KEY

=over 4

=item * Fields = id

=back

=head4 FOREIGN KEY

=over 4

=item * Fields = loaded_data_id

=item * Reference Table = L</loaded_data>

=item * Reference Fields = L</id>

=item * On delete = CASCADE

=back

=head4 FOREIGN KEY

=over 4

=item * Fields = quality_metric_id

=item * Reference Table = L</quality_metrics>

=item * Reference Fields = L</id>

=item * On delete = CASCADE

=back

=head2 material_instances

=head3 FIELDS

=head4 id

=over 4

=item * int(11)

=item * PRIMARY KEY

=item * Nullable 'No' 

=back

=head4 material_id

=over 4

=item * int(11)

=item * Nullable 'No' 

=back

=head4 experiment_id

=over 4

=item * int(11)

=item * Nullable 'No' 

=back

=head3 INDICES

=head4 NORMAL

=over 4

=item * Fields = material_id

=back

=head4 NORMAL

=over 4

=item * Fields = experiment_id

=back

=head3 CONSTRAINTS

=head4 PRIMARY KEY

=over 4

=item * Fields = id

=back

=head4 FOREIGN KEY

=over 4

=item * Fields = material_id

=item * Reference Table = L</materials>

=item * Reference Fields = L</id>

=item * On delete = CASCADE

=back

=head4 FOREIGN KEY

=over 4

=item * Fields = experiment_id

=item * Reference Table = L</experiments>

=item * Reference Fields = L</id>

=item * On delete = CASCADE

=back

=head2 materials

=head3 FIELDS

=head4 id

=over 4

=item * int(11)

=item * PRIMARY KEY

=item * Nullable 'No' 

=back

=head4 display_label

=over 4

=item * varchar(50)

=item * Default 'NULL' 

=item * Nullable 'Yes' 

=back

=head4 ontology_category

=over 4

=item * varchar(50)

=item * Default 'NULL' 

=item * Nullable 'Yes' 

=back

=head4 ontology_value

=over 4

=item * varchar(50)

=item * Default 'NULL' 

=item * Nullable 'Yes' 

=back

=head4 is_deleted

=over 4

=item * int(11)

=item * Nullable 'No' 

=back

=head3 CONSTRAINTS

=head4 PRIMARY KEY

=over 4

=item * Fields = id

=back

=head2 meta

=head3 FIELDS

=head4 name

=over 4

=item * varchar(128)

=item * PRIMARY KEY

=item * Default '' 

=item * Nullable 'No' 

=back

=head4 value

=over 4

=item * varchar(128)

=item * Default '' 

=item * Nullable 'No' 

=back

=head3 CONSTRAINTS

=head4 PRIMARY KEY

=over 4

=item * Fields = name

=back

=head2 organism_instances

=head3 FIELDS

=head4 id

=over 4

=item * int(11)

=item * PRIMARY KEY

=item * Nullable 'No' 

=back

=head4 organism_id

=over 4

=item * int(11)

=item * Nullable 'No' 

=back

=head4 experiment_id

=over 4

=item * int(11)

=item * Nullable 'No' 

=back

=head3 INDICES

=head4 NORMAL

=over 4

=item * Fields = organism_id

=back

=head4 NORMAL

=over 4

=item * Fields = experiment_id

=back

=head3 CONSTRAINTS

=head4 PRIMARY KEY

=over 4

=item * Fields = id

=back

=head4 FOREIGN KEY

=over 4

=item * Fields = organism_id

=item * Reference Table = L</organisms>

=item * Reference Fields = L</id>

=item * On delete = CASCADE

=back

=head4 FOREIGN KEY

=over 4

=item * Fields = experiment_id

=item * Reference Table = L</experiments>

=item * Reference Fields = L</id>

=item * On delete = CASCADE

=back

=head2 organisms

=head3 FIELDS

=head4 id

=over 4

=item * int(11)

=item * PRIMARY KEY

=item * Nullable 'No' 

=back

=head4 scientific_name

=over 4

=item * varchar(50)

=item * Default 'NULL' 

=item * Nullable 'Yes' 

=back

=head4 common_name

=over 4

=item * varchar(50)

=item * Default 'NULL' 

=item * Nullable 'Yes' 

=back

=head4 accession

=over 4

=item * int(11)

=item * Default 'NULL' 

=item * Nullable 'Yes' 

=back

=head4 taxon_id

=over 4

=item * int(11)

=item * Default 'NULL' 

=item * Nullable 'Yes' 

=back

=head4 is_deleted

=over 4

=item * int(11)

=item * Nullable 'No' 

=back

=head3 INDICES

=head4 NORMAL

=over 4

=item * Fields = taxon_id

=back

=head3 CONSTRAINTS

=head4 PRIMARY KEY

=over 4

=item * Fields = id

=back

=head4 FOREIGN KEY

=over 4

=item * Fields = taxon_id

=item * Reference Table = L</taxons>

=item * Reference Fields = L</id>

=back

=head2 permissions

=head3 FIELDS

=head4 id

=over 4

=item * int(11)

=item * PRIMARY KEY

=item * Nullable 'No' 

=back

=head4 name

=over 4

=item * varchar(40)

=item * Nullable 'No' 

=back

=head4 info

=over 4

=item * varchar(80)

=item * Default 'NULL' 

=item * Nullable 'Yes' 

=back

=head4 is_deleted

=over 4

=item * int(11)

=item * Nullable 'No' 

=back

=head3 CONSTRAINTS

=head4 PRIMARY KEY

=over 4

=item * Fields = id

=back

=head2 permissions_roles

=head3 FIELDS

=head4 role_id

=over 4

=item * int(11)

=item * Nullable 'No' 

=back

=head4 permission_id

=over 4

=item * int(11)

=item * Nullable 'No' 

=back

=head3 INDICES

=head4 NORMAL

=over 4

=item * Fields = role_id

=back

=head4 NORMAL

=over 4

=item * Fields = permission_id

=back

=head3 CONSTRAINTS

=head4 FOREIGN KEY

=over 4

=item * Fields = role_id

=item * Reference Table = L</roles>

=item * Reference Fields = L</id>

=item * On delete = CASCADE

=back

=head4 FOREIGN KEY

=over 4

=item * Fields = permission_id

=item * Reference Table = L</permissions>

=item * Reference Fields = L</id>

=item * On delete = CASCADE

=back

=head2 platforms

=head3 FIELDS

=head4 id

=over 4

=item * int(11)

=item * PRIMARY KEY

=item * Nullable 'No' 

=back

=head4 name

=over 4

=item * varchar(50)

=item * Nullable 'No' 

=back

=head3 CONSTRAINTS

=head4 PRIMARY KEY

=over 4

=item * Fields = id

=back

=head4 UNIQUE

=over 4

=item * Fields = name

=back

=head2 protocols

=head3 FIELDS

=head4 id

=over 4

=item * int(11)

=item * PRIMARY KEY

=item * Nullable 'No' 

=back

=head4 accession

=over 4

=item * char(15)

=item * Default 'NULL' 

=item * Nullable 'Yes' 

=back

=head4 user_accession

=over 4

=item * varchar(100)

=item * Default 'NULL' 

=item * Nullable 'Yes' 

=back

=head4 expt_accession

=over 4

=item * char(15)

=item * Default 'NULL' 

=item * Nullable 'Yes' 

=back

=head4 name

=over 4

=item * varchar(255)

=item * Default 'NULL' 

=item * Nullable 'Yes' 

=back

=head4 date_last_processed

=over 4

=item * datetime

=item * Default 'NULL' 

=item * Nullable 'Yes' 

=back

=head4 comment

=over 4

=item * text(65535)

=item * Nullable 'Yes' 

=back

=head4 is_deleted

=over 4

=item * int(11)

=item * Nullable 'No' 

=back

=head3 CONSTRAINTS

=head4 PRIMARY KEY

=over 4

=item * Fields = id

=back

=head4 UNIQUE

=over 4

=item * Fields = accession

=back

=head2 quality_metrics

=head3 FIELDS

=head4 id

=over 4

=item * int(11)

=item * PRIMARY KEY

=item * Nullable 'No' 

=back

=head4 type

=over 4

=item * varchar(50)

=item * Nullable 'No' 

=back

=head4 description

=over 4

=item * text(65535)

=item * Nullable 'Yes' 

=back

=head3 CONSTRAINTS

=head4 PRIMARY KEY

=over 4

=item * Fields = id

=back

=head4 UNIQUE

=over 4

=item * Fields = type

=back

=head2 quantitation_types

=head3 FIELDS

=head4 id

=over 4

=item * int(11)

=item * PRIMARY KEY

=item * Nullable 'No' 

=back

=head4 name

=over 4

=item * varchar(128)

=item * Nullable 'No' 

=back

=head4 is_deleted

=over 4

=item * int(11)

=item * Nullable 'No' 

=back

=head3 CONSTRAINTS

=head4 PRIMARY KEY

=over 4

=item * Fields = id

=back

=head2 roles

=head3 FIELDS

=head4 id

=over 4

=item * int(11)

=item * PRIMARY KEY

=item * Nullable 'No' 

=back

=head4 name

=over 4

=item * varchar(40)

=item * Nullable 'No' 

=back

=head4 info

=over 4

=item * varchar(80)

=item * Default 'NULL' 

=item * Nullable 'Yes' 

=back

=head4 is_deleted

=over 4

=item * int(11)

=item * Nullable 'No' 

=back

=head3 CONSTRAINTS

=head4 PRIMARY KEY

=over 4

=item * Fields = id

=back

=head2 roles_users

=head3 FIELDS

=head4 user_id

=over 4

=item * int(11)

=item * Nullable 'No' 

=back

=head4 role_id

=over 4

=item * int(11)

=item * Nullable 'No' 

=back

=head3 INDICES

=head4 NORMAL

=over 4

=item * Fields = user_id

=back

=head4 NORMAL

=over 4

=item * Fields = role_id

=back

=head3 CONSTRAINTS

=head4 FOREIGN KEY

=over 4

=item * Fields = user_id

=item * Reference Table = L</users>

=item * Reference Fields = L</id>

=item * On delete = CASCADE

=back

=head4 FOREIGN KEY

=over 4

=item * Fields = role_id

=item * Reference Table = L</roles>

=item * Reference Fields = L</id>

=item * On delete = CASCADE

=back

=head2 spreadsheets

=head3 FIELDS

=head4 id

=over 4

=item * int(11)

=item * PRIMARY KEY

=item * Nullable 'No' 

=back

=head4 experiment_id

=over 4

=item * int(11)

=item * Nullable 'No' 

=back

=head4 name

=over 4

=item * varchar(255)

=item * Default 'NULL' 

=item * Nullable 'Yes' 

=back

=head4 is_deleted

=over 4

=item * int(11)

=item * Nullable 'No' 

=back

=head3 INDICES

=head4 NORMAL

=over 4

=item * Fields = experiment_id

=back

=head3 CONSTRAINTS

=head4 PRIMARY KEY

=over 4

=item * Fields = id

=back

=head4 FOREIGN KEY

=over 4

=item * Fields = experiment_id

=item * Reference Table = L</experiments>

=item * Reference Fields = L</id>

=back

=head2 taxons

=head3 FIELDS

=head4 id

=over 4

=item * int(11)

=item * PRIMARY KEY

=item * Nullable 'No' 

=back

=head4 scientific_name

=over 4

=item * varchar(50)

=item * Default 'NULL' 

=item * Nullable 'Yes' 

=back

=head4 common_name

=over 4

=item * varchar(50)

=item * Default 'NULL' 

=item * Nullable 'Yes' 

=back

=head4 accession

=over 4

=item * int(11)

=item * Default 'NULL' 

=item * Nullable 'Yes' 

=back

=head4 is_deleted

=over 4

=item * int(11)

=item * Nullable 'No' 

=back

=head3 CONSTRAINTS

=head4 PRIMARY KEY

=over 4

=item * Fields = id

=back

=head2 users

=head3 FIELDS

=head4 id

=over 4

=item * int(11)

=item * PRIMARY KEY

=item * Nullable 'No' 

=back

=head4 login

=over 4

=item * varchar(40)

=item * Nullable 'No' 

=back

=head4 name

=over 4

=item * varchar(40)

=item * Default 'NULL' 

=item * Nullable 'Yes' 

=back

=head4 password

=over 4

=item * varchar(40)

=item * Nullable 'No' 

=back

=head4 email

=over 4

=item * varchar(100)

=item * Default 'NULL' 

=item * Nullable 'Yes' 

=back

=head4 modified_at

=over 4

=item * datetime

=item * Default 'NULL' 

=item * Nullable 'Yes' 

=back

=head4 created_at

=over 4

=item * datetime

=item * Default 'NULL' 

=item * Nullable 'Yes' 

=back

=head4 access

=over 4

=item * datetime

=item * Default 'NULL' 

=item * Nullable 'Yes' 

=back

=head4 is_deleted

=over 4

=item * int(11)

=item * Nullable 'No' 

=back

=head3 CONSTRAINTS

=head4 PRIMARY KEY

=over 4

=item * Fields = id

=back

=head4 UNIQUE

=over 4

=item * Fields = login

=back

=head1 PRODUCED BY

SQL::Translator::Producer::POD

=head1 AUTHOR

Tim Rayner (rayner@ebi.ac.uk), ArrayExpress team, EBI, 2004.

Acknowledgements go to the ArrayExpress curation team for feature
requests, bug reports and other valuable comments. 

=begin html

<hr>
<a href="http://sourceforge.net">
  <img src="http://sourceforge.net/sflogo.php?group_id=120325&amp;type=2" 
       width="125" 
       height="37" 
       border="0" 
       alt="SourceForge.net Logo" />
</a>

=end html

=cut

1;
