#!/usr/bin/env perl
# Copyright [1999-2015] Wellcome Trust Sanger Institute and the EMBL-European Bioinformatics Institute
# 
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
# 
#      http://www.apache.org/licenses/LICENSE-2.0
# 
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.


use strict;
use warnings;

=head1 NAME

update_msater_db.pl

=head1 CONTACT

Please email comments or questions to the public Ensembl
developers list at <http://lists.ensembl.org/mailman/listinfo/dev>.

Questions may also be sent to the Ensembl help desk at
<http://www.ensembl.org/Help/Contact>.

=head1 DESCRIPTION

This script will check that all the species found in the Registry are
in the compara database, and with up-to-date meta-information (such as
the genebuild, etc).
In dry-run mode, the script only does the comparison. In default mode,
it will update the master database to make it match the core databases.

=head1 SYNOPSIS

  perl update_master_db.pl --help

  perl update_master_db.pl
    --reg_conf registry_configuration_file
    --compara compara_db_name_or_alias
    [--[no]dry-run]

=head1 OPTIONS

=head2 GETTING HELP

=over

=item B<[--help]>

Prints help message and exits.

=back

=head2 GENERAL CONFIGURATION

=over

=item B<[--reg_conf registry_configuration_file]>

The Bio::EnsEMBL::Registry configuration file. If none given,
the one set in ENSEMBL_REGISTRY will be used if defined, if not
~/.ensembl_init will be used.

=item B<--compara compara_db_name_or_alias>

The compara database to update. You can use either the original name or any of the
aliases given in the registry_configuration_file

=item B<[--[no]dry-run]>

In dry-run mode, the script does not write into the master
database, and would be happy with a read-only connection.

=back

=head1 INTERNAL METHODS

=cut


use Getopt::Long;

use Bio::EnsEMBL::Registry;

my $help;
my $reg_conf;
my $compara;
my $force = 0;
my $dry_run = 0;

GetOptions(
    "help" => \$help,
    "reg_conf=s" => \$reg_conf,
    "compara=s" => \$compara,
    "dry_run|dry-run" => \$dry_run,
  );

$| = 0;

# Print Help and exit if help is requested
if ($help or !$reg_conf or !$compara) {
    use Pod::Usage;
    pod2usage({-exitvalue => 0, -verbose => 2});
}

Bio::EnsEMBL::Registry->load_all($reg_conf);

my $compara_db = Bio::EnsEMBL::Registry->get_DBAdaptor($compara, "compara");
my $genome_db_adaptor = $compara_db->get_GenomeDBAdaptor();

foreach my $db_adaptor (@{Bio::EnsEMBL::Registry->get_all_DBAdaptors(-GROUP => 'core')}) {

    # Get the production name and assembly to fetch our GenomeDBs
    my $mc = $db_adaptor->get_MetaContainer();
    my $that_species = $mc->get_production_name();
    my $that_assembly = $db_adaptor->assembly_name();
    unless ($that_species) {
        warn sprintf("Skipping %s (no species name found.\n", $db_adaptor->dbc->locator);
        next;
    }
    my $master_genome_db = $genome_db_adaptor->fetch_by_name_assembly($that_species, $that_assembly);

    # Time to test !
    if ($master_genome_db) {
        # Make a new one with the core db information
        my $proper_genome_db = Bio::EnsEMBL::Compara::GenomeDB->new( -DB_ADAPTOR => $db_adaptor );
        my $diffs = $proper_genome_db->_check_equals($master_genome_db);
        if ($diffs) {
            warn "> Differences for '$that_species' (assembly '$that_assembly')\n\t".($proper_genome_db->toString)."\n\t".($master_genome_db->toString)."\n$diffs\n";
            $proper_genome_db->dbID($master_genome_db->dbID);
            unless ($dry_run) {
                $genome_db_adaptor->update($proper_genome_db);
                warn "\t> Successfully the master database\n";
            }
        } else {
            print "> '$that_species' (assembly '$that_assembly') OK\n";
        }
    } else {
        warn "> Could not find the species '$that_species' (assembly '$that_assembly') in the genome_db table. You should probably add it.\n";
    }
    
    # Don't keep all the connections open
    $db_adaptor->dbc->disconnect_if_idle();
}

