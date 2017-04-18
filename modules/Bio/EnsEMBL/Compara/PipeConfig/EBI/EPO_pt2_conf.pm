=head1 LICENSE

Copyright [1999-2015] Wellcome Trust Sanger Institute and the EMBL-European Bioinformatics Institute
Copyright [2016-2017] EMBL-European Bioinformatics Institute

Licensed under the Apache License, Version 2.0 (the "License");
you may not use this file except in compliance with the License.
You may obtain a copy of the License at

     http://www.apache.org/licenses/LICENSE-2.0

Unless required by applicable law or agreed to in writing, software
distributed under the License is distributed on an "AS IS" BASIS,
WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
See the License for the specific language governing permissions and
limitations under the License.

=cut

=head1 NAME

Bio::EnsEMBL::Compara::PipeConfig::EBI::EPO_pt2_conf

=head1 SYNOPSIS

    EBI-specific configuration of EPO_pt2 pipeline (anchor mapping). Options that
    may need to be checked include:

       'species_set_name'  - used in the naming of the database
	   'compara_anchor_db' - database containing the anchor sequences (entered in the anchor_sequence table)

    #4. Run init_pipeline.pl script:
        Using command line arguments:
        init_pipeline.pl Bio::EnsEMBL::Compara::PipeConfig::EPO_pt2_conf.pm

    #5. Run the "beekeeper.pl ... -sync" and then " -loop" command suggested by init_pipeline.pl

    #6. Fix the code when it crashes
=head1 DESCRIPTION  

    This configuaration file gives defaults for mapping (using exonerate at the moment) anchors to a set of target genomes (dumped text files)

=head1 CONTACT

Please email comments or questions to the public Ensembl
developers list at <http://lists.ensembl.org/mailman/listinfo/dev>.

Questions may also be sent to the Ensembl help desk at
<http://www.ensembl.org/Help/Contact>.

=cut

package Bio::EnsEMBL::Compara::PipeConfig::EBI::EPO_pt2_conf;

use strict;
use warnings;

use Bio::EnsEMBL::Hive::Version 2.4;

use base ('Bio::EnsEMBL::Compara::PipeConfig::EPO_pt2_conf');

sub default_options {
    my ($self) = @_;

    return {
	%{$self->SUPER::default_options},

    'species_set_name' => '17mammals_reuse',

    # Where the pipeline lives
    'host' => 'mysql-ens-compara-prod-2.ebi.ac.uk',
    'port' => 4522,

	# database containing the anchors for mapping
    # !!!!!!! CANNOT FIND A DUMP OF THIS ANYWHERE !!!!!!
    # !!! add when run of EPO pt1 completes !!!
	'compara_anchor_db' => 'mysql://ensro@compara3/sf5_TEST_gen_anchors_mammals_cat_100',

	'mapping_exe' => $self->o('ensembl_cellar') . 'exonerate22/2.2.0/bin/exonerate',
    'ortheus_c_exe' => $self->o('ensembl_cellar') . 'ortheus/0.5.0/bin/ortheus_core',

	 # place to dump the genome sequences
    'seq_dump_loc' => '/hps/nobackup/production/ensembl/' . $ENV{USER} . '/epo_anchor_mapping/release_' . $self->o('rel_with_suffix'),
    'compara_master' => 'mysql://ensro@mysql-ens-compara-prod-1.ebi.ac.uk:4485/ensembl_compara_master',
     };
}

1;