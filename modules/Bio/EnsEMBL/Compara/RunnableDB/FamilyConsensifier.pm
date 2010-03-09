package Bio::EnsEMBL::Compara::RunnableDB::FamilyConsensifier;

# RunnableDB to assemble the consensus annotations on the fly
# (remake of 'consensifier.pl' and 'assemble-consensus.pl' originally written by Abel Ureta-Vidal)

use POSIX;
use strict;
use Algorithm::Diff qw(LCS);

use base ('Bio::EnsEMBL::Hive::ProcessWithParams');

sub fetch_input {
    my $self = shift @_;

    my $family_id = $self->param('family_id') || die "'family_id' is an obligatory parameter, please set it in the input_id hashref";

        # get all Uniprot members that would belong to the given family if redundant elements were added:
    my $sql = qq {
        SELECT m2.source_name, m2.description
          FROM family_member fm, member m1, member m2
         WHERE fm.family_id = ?
           AND fm.member_id=m1.member_id
           AND m1.sequence_id=m2.sequence_id
           AND m1.source_name IN ('Uniprot/SWISSPROT', 'Uniprot/SPTREMBL')
           AND m2.source_name IN ('Uniprot/SWISSPROT', 'Uniprot/SPTREMBL')
    };

    my $sth = $self->dbc->prepare( $sql );
    $sth->execute( $family_id );

    my %dbname2descs = (
        'Uniprot/SWISSPROT' => [],
        'Uniprot/SPTREMBL'  => [],
    );
    while( my ($source_name, $description) = $sth->fetchrow() ) {
        $description =~ tr/\(\)\.-/    /;
        push @{ $dbname2descs{$source_name} }, apply_edits(uc $description);
    }
    $sth->finish();
    $self->dbc->disconnect_when_inactive(1);

    $self->param('dbname2descs', \%dbname2descs);

    return 1;
}

sub run {
    my $self = shift @_;

    my $family_id    = $self->param('family_id');
    my $dbname2descs = $self->param('dbname2descs');

    my $source_name = scalar(@{ $dbname2descs->{'Uniprot/SWISSPROT'}})
        ? 'Uniprot/SWISSPROT'
        : 'Uniprot/SPTREMBL';

    my ($description, $percentage) = consensify($dbname2descs->{$source_name});

    my ($assembled_consensus, $score, $discarded_flag, $uselessness_output) = assemble_consensus($description, int($percentage));

    $self->param('description',         $assembled_consensus);
    $self->param('description_score',   $score);

    return 1;
}

sub write_output {
    my $self = shift @_;

    my $sql = "UPDATE family SET description = ?, description_score = ? WHERE family_id = ?";

    my $sth = $self->dbc->prepare( $sql );

    $sth->execute( $self->param('description'), $self->param('description_score'), $self->param('family_id') );
    $sth->finish();

    return 1;
}


# -------------------------- functional subroutines ----------------------------------

sub as_words { 
    #add ^ and $ to regexp
    my (@words) = @_;
    my @newwords=();

    foreach my $word (@words) { 
      push @newwords, "(^|\\s+)$word(\\s+|\$)"; 
    }
    return @newwords;
}

sub apply_edits  { 
  local($_) = @_;
  
  my @deletes = (qw(FOR\$
		    SIMILAR\s+TO\$
		    SIMILAR\s+TO\s+PROTEIN\$
		    RIKEN.*FULL.*LENGTH.*ENRICHED.*LIBRARY
		    CLONE:[0-9A-Z]+ FULL\s+INSERT\s+SEQUENCE
		    \w*\d{4,} HYPOTHETICAL\s+PROTEIN
		    IN\s+CHROMOSOME\s+[0-9IVX]+ [A-Z]\d+[A-Z]\d+\.{0,1}\d*),
		 &as_words(qw(NOVEL PUTATIVE PREDICTED 
			      UNNAMED UNNMAED ORF CLONE MRNA 
			      CDNA EST RIKEN FIS KIAA\d+ \S+RIK IMAGE HSPC\d+
			      FOR HYPOTETICAL HYPOTHETICAL PROTEIN ISOFORM)));
 
  foreach my $re ( @deletes ) { 
    s/$re/ /g; #space just for the the as_words regexs, to put back the spaces.
  }
  
  #Apply some fixes to the annotation:
  s/EC (\d+) (\d+) (\d+) (\d+)/EC_$1.$2.$3.$4/;
  s/EC (\d+) (\d+) (\d+)/EC_$1.$2.$3.-/;
  s/EC (\d+) (\d+)/EC_$1.$2.-.-/;
  s/(\d+) (\d+) KDA/$1.$2 KDA/;
  s/\s*,\s*/ /g;
  s/\s+/ /g;
  
  $_;
}

sub consensify {
  my($original_descriptions) = @_;

  my $best_annotation = '';

  my $total_members = scalar(@$original_descriptions);
  my $total_members_with_desc = grep(/\S+/, @$original_descriptions);

  ### OK, first a list of hacks:
  if ( $total_members_with_desc ==0 )  { # truly unknown
    return ('UNKNOWN', 0);
  }
  
  if ($total_members == 1) {
    $best_annotation = $original_descriptions->[0];
    $best_annotation =~ s/^\s+//; 
    $best_annotation =~ s/\s+$//; 
    $best_annotation =~ s/\s+/ /;
    if ($best_annotation eq '' || length($best_annotation) == 1) {
      return ('UNKNOWN', 0);
    } else { 
      return ($best_annotation, 100);
    }
  }

  if ($total_members_with_desc == 1)  { # nearly unknown
    ($best_annotation) = grep(/\S+/, @$original_descriptions);
    my $perc= int($total_members_with_desc/$total_members*100);
    $best_annotation =~ s/^\s+//;
    $best_annotation =~ s/\s+$//;
    $best_annotation =~ s/\s+/ /;
    if ($best_annotation eq '' || length($best_annotation) == 1) { 
      return ('UNKNOWN', 0);
    } else {  
      return ($best_annotation, $perc);
    } 
  }

  # all same desc:
  my %desc = undef;
  foreach my $desc (@$original_descriptions) {
    $desc{$desc}++;     
  }
  if  ( (keys %desc) == 1 ) {
    ($best_annotation) = keys %desc;
    my $n = grep($_ eq $best_annotation, @$original_descriptions);
    my $perc= int($n/$total_members*100);
    $best_annotation =~ s/^\s+//;
    $best_annotation =~ s/\s+$//;
    $best_annotation =~ s/\s+/ /;
    if ($best_annotation eq '' || length($best_annotation) == 1) {  
      return ('UNKNOWN', 0);
    } else {   
      return ($best_annotation, $perc);
    }  
  }
  # this should speed things up a bit as well 
  
  my %lcshash = undef;
  my %lcnext  = undef;
  my @array   = @$original_descriptions;
  while (@array) {
    # do an all-against-all LCS (longest commong substring) of the
    # descriptions of all members; take the resulting strings, and
    # again do an all-against-all LCS on them, until we have nothing
    # left. The LCS's found along the way are in lcshash.
    #
    # Incidentally, longest common substring is a misnomer, since it
    # is not guaranteed to occur in either of the original strings. It
    # is more like the common parts of a Unix diff ... 
    for (my $i=0;$i<@array;$i++) {
      for (my $j=$i+1;$j<@array;$j++){
	my @list1=split /\s+/,$array[$i];
	my @list2=split /\s+/,$array[$j];
	my @lcs=LCS(\@list1,\@list2);
	my $lcs=join(" ",@lcs);
	$lcs =~ s/^\s+//;
	$lcs =~ s/\s+$//;
	$lcs =~ s/\s+/ /;
	$lcshash{$lcs}=1;
	$lcnext{$lcs}=1;
      }
    }
    @array=keys(%lcnext);
    undef %lcnext;
  }

  my ($best_score, $best_perc)=(0, 0);
  my @all_cands=sort { length($b) <=> length($a) } keys %lcshash ;
  foreach my $candidate_consensus (@all_cands) {
    next unless (length($candidate_consensus) > 1);
    my @temp=split /\s+/,$candidate_consensus;
    my $length=@temp;               # num of words in annotation
    
    # see how many members of cluster contain this LCS:
    
    my ($lcs_count)=0;
    foreach my $orig_desc (@$original_descriptions) {
      my @list1=split /\s+/,$candidate_consensus;
      my @list2=split /\s+/,$orig_desc;
      my @lcs=LCS(\@list1,\@list2);
      my $lcs=join(" ",@lcs);  
      
      if ($lcs eq $candidate_consensus
	  || index($orig_desc,$candidate_consensus) != -1 # addition;
	  # many good (single word) annotations fall out otherwise
	 ) {
	$lcs_count++;
	
	# Following is occurs frequently, as LCS is _not_ the longest
	# common substring ... so we can't use the shortcut either
	
	# if ( index($orig_desc,$candidate_consensus) == -1 ) {
	#   warn "lcs:'$lcs' eq cons:'$candidate_consensus' and
	# orig:'$orig_desc', but index == -1\n" 
	# }
      }
    }	
    
    my $perc_with_desc=($lcs_count/$total_members_with_desc)*100;
    my $perc= $lcs_count/$total_members*100; 
    my $score=$perc + ($length*14); # take length into account as well
    $score = 0 if $length==0;
    if (($perc_with_desc >= 40) && ($length >= 1)) {
      if ($score > $best_score) {
	$best_score=$score;
	$best_perc=$perc;
	$best_annotation=$candidate_consensus;
      }
    }
  }                                   # foreach $candidate_consensus
  
  if  ($best_annotation eq  "" || $best_perc < 40)  {
    $best_annotation = 'AMBIGUOUS';
    $best_perc = 0;
  }
  $best_annotation =~ s/^\s+//;
  $best_annotation =~ s/\s+$//;
  $best_annotation =~ s/\s+/ /;
  
  return ($best_annotation, $best_perc);
}

sub assemble_consensus {
  my ($pre_description, $pre_score) = @_;

            ### deletes to be applied to correct some howlers
            my @deletes = ('FOR\s*$', 'SIMILAR\s*TO\s*$', 'SIMILAR\s*TO\s*PROTEIN\s*$',
                    'SIMILAR\s*TO\s*GENE\s*$','SIMILAR\s*TO\s*GENE\s*PRODUCT\s*$',
                    '\s*\bEC\s*$', 'RIKEN CDNA [A_Z]\d+\s*$', 'NOVEL\s*PROTEIN\s*$',
                    'NOVEL\s*$','C\d+ORF\d+','LIKE'); 

            ### any complete annotation that matches one of the following, gets
            ### ticked off completely
            my @useless_annots = 
              qw( ^.$  
                  ^\d+$ 
                  .*RIKEN.*FULL.*LENGTH.*ENRICHED.*LIBRARY.*
                );

            ### regexp to split the annotations into separate words for scoring:
            my $word_splitter='[\/ \t,:]+';

            ### words that get scored off; the balance of useful/useless words
            ### determines whether they make it through.
            ### (these regexps are surrounded by ^ and $ before they're used)

            my @useless_words =  # and misspellings, that is
              qw( BG EG BCDNA PROTEIN UNKNOWN FRAGMENT HYPOTHETICAL HYPOTETICAL 
                  NOVEL PUTATIVE PREDICTED UNNAMED UNNMAED
                  PEPTIDE KDA ORF CLONE MRNA CDNA FOR
                  EST
                  RIKEN FIS KIAA\d+ \S+RIK IMAGE HSPC\d+ _*\d+ 5\' 3\'
                  .*\d\d\d+.*
                );

            # sanity check on the words:
            foreach my $w (@useless_words) {
              if ( $w =~ /$word_splitter/) {
                die "word '$w' to be matched matches ".
                  "the word_splitter regexp '$word_splitter', so will never match";
              }
            }

  my $annotation='UNKNOWN';
  my $score=0;

  if (defined $pre_description) {
    $annotation=$pre_description;
    $score=$pre_score;
    if ($score < 40) {
      $annotation = 'AMBIGUOUS';
      $score = 0;
    }
  }
  # apply the deletes:
  foreach my $re (@deletes) { 
    $annotation =~ s/$re//g; 
  }

  my $useless=0;	
  my $total= 1;

  $_=$annotation;

  # see if the annotation as a whole is useless:
  if (grep($annotation =~ /$_/, @useless_annots)) {
    $useless=1000;
  } else {
    # word based checking: what is balance of useful/less words:
    my @words=split(/$word_splitter/,$annotation);
    $total= scalar @words;
    foreach my $word (@words) {
      if ( grep( $word =~ /^$_$/, @useless_words ) ) {
	$useless++;
      }
    }
    $useless += 1 if $annotation =~ /\bKDA\b/;
    # (because the kiloDaltons come with at least one meaningless number)
  }
  
  my $discarded_flag = 0;
  my $uselessness_output = '';

  if ( $annotation eq ''
       || ($useless >= 1 && $total == 1)
       || $useless > ($total+1)/2 ) {
    $uselessness_output = "$useless/$total;\t$annotation\t$score";
    $discarded_flag++;
    $annotation='UNKNOWN'; 
    $score=0;
  }

  $_=$annotation;
  
  #Apply some fixes to the annotation:
  s/EC (\d+) (\d+) (\d+) (\d+)/EC $1\.$2\.$3\.$4/;
  s/EC (\d+) (\d+) (\d+)/EC $1\.$2\.$3\.-/;
  s/EC (\d+) (\d+)/EC $1\.$2\.-\.-/;
  s/(\d+) (\d+) KDA/$1.$2 KDA/;
  
  s/\s+$//;
  s/^\s+//;

  if (/^BG:.*$/ || /^EG:.*$/ || length($_) <= 2 || /^\w{1}\s\d+\w*$/) {
    $_='UNKNOWN';
    $score = 0;
  }
  
  return ($_, $score, $discarded_flag, $uselessness_output);
}

1;
