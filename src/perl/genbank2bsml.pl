#!/usr/local/packages/perl-5.8.5/bin/perl
 
eval 'exec /usr/local/packages/perl-5.8.5/bin/perl  -S $0 ${1+"$@"}'
    if 0; # not running under some shell
BEGIN{foreach (@INC) {s/\/usr\/local\/packages/\/local\/platform/}};
use lib (@INC,$ENV{"PERL_MOD_DIR"});
no lib "$ENV{PERL_MOD_DIR}/i686-linux";
no lib ".";

use strict;
use warnings;
use Getopt::Long qw(:config no_ignore_case no_auto_abbrev);
use File::Basename;
use Bio::SeqIO;
use BSML::BsmlBuilder;
umask(0000);

my %options = &parse_options();
# output options
my $ifile = $options{input_file};
my $odir = $options{output_dir};
my $ofile = $options{output_bsml};
my %fsa_files; # file names and handlers and for each fasta output file

my %TagCount; #NOTE: rename this or something
print "Parsing $ifile\n";
my %gbr = %{parse_genbank_file($ifile)};
my $doc = new BSML::BsmlBuilder();
print "Converting $ifile to bsml \n";
&to_bsml(\%gbr, $doc);

#output the BSML
#my $bsmlfile = "$odir/".$gbr{'gi'}.".bsml";
print "Outputting bsml to $ofile\n";
$doc->write($ofile);
chmod (0777, $ofile);

# close file handlers
foreach my $class (keys %fsa_files) {
  close($fsa_files{$class}{fh});  
}

%gbr = ();

#tag count info
print "\nTag Counts:\n";
foreach (sort { $TagCount{$b} <=> $TagCount{$a} } keys %TagCount) {
    print "  $_: ".$TagCount{$_}."\n";
}

#
# Subroutines follow
#
sub print_usage {
        my $byebye = shift;
        my $progname = $0;
        die << "END";
$byebye
usage: $progname --input_file|i <file> --output_bsml|b <file> --output_dir|o <dir>
END
}


sub parse_options {
    my %options = ();
    GetOptions( \%options,
		'input_file|i=s',
		'output_dir|o=s',
		'output_bsml|b=s'  #output bsml file
		) || &print_usage("Unprocessable option");

    # check for required parameters

    (defined($options{input_file})) || die "input_file is required parameter";
    # we may be passed a file name, but the .gz is what is actually there
    unless (-e $options{input_file}) {
	$options{input_file} .= ".gz";
    }
    (-r $options{input_file}) || die "input_file ($options{input_file}) not readable: $!";

    (-w $options{output_dir} && -d $options{output_dir}) 
	|| die "output_dir directory ($options{output_dir}) not writeable: $!";

    (defined($options{output_bsml})) || die "output_bsml is required options";

    print "Executing $0 with options\n";
    foreach (keys %options) { print "  $_: $options{$_}\n";}

    return %options;
}

# in: genbank/refseq file
#out: hashref of all the info
sub parse_genbank_file {
    my $gb_file = shift;
    my %gbr;

    # support for compressed input
    # example taken from http://bioperl.org/wiki/HOWTO:SeqIO
    my $seq_obj;
    if ($gb_file =~ /\.(gz|gzip)$/) {
	$seq_obj = Bio::SeqIO->new(-file   => "gunzip -c $gb_file |",
				   -format => 'genbank');
    }
    else {   
	$seq_obj = Bio::SeqIO->new(-file   => "<$gb_file",
				   -format => 'genbank');
    }

    while (my $seq = $seq_obj->next_seq) {
	$gbr{'component'} = 'chromosome'; #default;
	$gbr{'strain'} = '';

	$gbr{'accession'} = $seq->accession_number;
	$gbr{'taxon_id'} = $seq->species->ncbi_taxid();
	$gbr{'gi'} = $seq->primary_id();
	defined($gbr{'gi'}) || die "No gi in $gb_file";

	#first word is genus, all follows is species
	$gbr{'organism'} = $seq->species->common_name;
	$gbr{'organism'} =~ m/(\S+)\s+(.*)/;
	$gbr{'genus'} = $1;
	$gbr{'species'} = $2;

	$gbr{'sequence'} = $seq->seq();
	$gbr{'seq_len'} = $seq->length();

	# $gbr{'molecule'} = $seq->molecule();
	# Placed in Sequence@class
	if ($seq->molecule() =~ /dna/i) {
	    $gbr{'molecule'} = 'dna';
	}
	elsif ($seq->molecule() =~ /rna/i) {
	    $gbr{'molecule'} = 'rna';
	}
	elsif ($seq->molecule() =~ /aa/i) {
	    die "molecule=aa; dealing with an amino acid record is so vastly unsupported script is killing itself to preserve its dignity."
	}
	else {
	    die "Unknown molecule: ".$seq->molecule();
	}

	# Get expanded "polymer_type" as entered in ard.obo
	# cross reference this against $gbr{molecule} for consistency
	# see bug #3251: http://jorvis-lx:8080/bugzilla/show_bug.cgi?id=3251
	# taxonomy names taken from http://www.ncbi.nlm.nih.gov/genomes/VIRUSES/vifam.html
	$gbr{'polymer_type'} = "DNA"; #default
	my $classification = join(" ",$seq->species->classification);
	if ($classification =~ /dsDNA viruses/) {
	    # do nothing dsDNA = DNA
	}
	elsif ($classification =~ /dsRNA viruses/) {
	    $gbr{'polymer_type'} = "dsRNA";
	}
	elsif ($classification =~ /ssDNA viruses/) {
	    $gbr{'polymer_type'} = "ssDNA";
	}
	elsif ($classification =~ /ssRNA negative-strand viruses/) {
	    $gbr{'polymer_type'} = "ssRNA-";
	}
	elsif ($classification =~ /ssRNA positive-strand viruses/) {
	    $gbr{'polymer_type'} = "ssRNA+";
	}
	elsif ($classification =~ /RNA/) {
	    die "Unable to set polymer_type, unknown RNA in classification ($classification)";
	}
	elsif ($classification =~ /DNA/) {
	    die "Unable to set polymer_type, unknown DNA in classification ($classification)";
	}

	# check for potential misparse
	if ( ($gbr{'molecule'} eq 'dna') && !($gbr{'polymer_type'} =~ /DNA/) ) {
	    die "Mismatch between molecule ($gbr{molecule}) and polymer_type ($gbr{polymer_type})";
	}
	if ( ($gbr{'molecule'} eq 'rna') && !($gbr{'polymer_type'} =~ /RNA/) ) {
	    die "Mismatch between molecule ($gbr{molecule}) and polymer_type ($gbr{polymer_type})";
	}

	#currently unused
	#$gbr{'sub_species'} = $seq->species->sub_species();
	#$gbr{'variant'} = $seq->species->variant();	
	#$gbr{'genus'} = $seq->species->genus();   #changed to organism parsing
	#$gbr{'species'} = $seq->species->species(); #changed to organism parsing
	#$gbr{'strain'} = $seq->species->strain();
	#$gbr{'desc'} = $seq->desc();
	#$seq->moltype() will say dna if the sequence is dna, this is a problem for genbank records
	#where an rna sequence will be represented as dna


	
	my $anno_collection = $seq->annotation;
	my @annotations = $anno_collection->get_Annotations(); #or Annotations('comment')

	#search FEATURE.source for:
	#  -/plasmid
	#  -/strain
	my $ugc = 0; #unknown group count
	my %FeatureCount = ();
	my %transl_tables; #track of translation tables in CDSs
 	for my $feat_object ($seq->get_SeqFeatures()) {
	    my $primary_tag = $feat_object->primary_tag;
	    ++$FeatureCount{$primary_tag};
 	    if ($primary_tag eq 'source') {
 		for my $tag ($feat_object->get_all_tags) {
		    if ($tag eq 'plasmid') {
			$gbr{'component'} = "plasmid";
		    }
		    elsif ($tag eq 'strain') {
			$gbr{'strain'} = join(' ', $feat_object->get_tag_values($tag));
		    }
		    else {
			# record unknown tag
			++$TagCount{"unknown_source_tag_".$tag};
		    }
 		}
 	    }
	    else { #!= source but is something we care about

		#this test junk is examing the types of inexact locations
		#currently counting it on all features
		my $loc_thing = $feat_object->location->location_type()."_".
		    $feat_object->location->start_pos_type."_".
		    $feat_object->location->end_pos_type;
		
		++$TagCount{$loc_thing};
		unless ($loc_thing =~ /^EXACT/) {
		    print "\n$loc_thing: ".$gbr{'accession'};
		}
		#/test junk
		
		if ($primary_tag eq 'CDS'  ||
		    $primary_tag eq 'gene' || 
		    #$primary_tag eq 'misc_feature' ||  #not supported by chado (not in cvterm)
		    $primary_tag eq 'promoter' ||
		    $primary_tag eq 'exon' ||
		    #$primary_tag eq 'variation' ||  #this is an example of an IN-BETWEEN tag
		    $primary_tag eq 'intron'
		    ) {
		    
		    # obtain feature group
		    my $feature_group = '';
		    my $feature_tag = '';
		    my $feature_value = '';
		    if ($feat_object->has_tag("gene")) {
			$feature_tag = 'gene';
			$feature_value = join('_',$feat_object->get_tag_values("gene"));
		    }
		    elsif ($feat_object->has_tag("locus_tag")) {
			$feature_tag = 'locus_tag';
			$feature_value = join('_',$feat_object->get_tag_values("locus_tag"));
		    }
		    elsif ($feat_object->has_tag("protein_id")) {
			$feature_tag = 'protein_id';
			$feature_value = join('_',$feat_object->get_tag_values("protein_id"));
		    }
		    else {
			#no way to group feature, so put it in its own feature_group
			$feature_tag = 'unknown';
			$feature_value = $ugc;			    
			++$ugc;
		    }
		    $feature_group = $feature_tag."_".$feature_value;
		    
		    # id is unique across all bsml documents (use accession instead?  can't use taxon id)
		    # //Feature/@id has to begin with alpha character?
		    # old way: my $feature_id = "gi_".$gbr{'gi'}.".".$feature_group.".".$primary_tag."_".$FeatureCount{$primary_tag};
		    my $feature_id = "gi_".$gbr{'gi'}.".".$primary_tag."_".$FeatureCount{$primary_tag};
		    $feature_id =~ s/\///; #/'s in this will cause trouble down the road
		    if (exists $gbr{'Features'}->{$feature_group}->{$feature_id}) { die "feature id is not unique!  feature_id: $feature_id"; }
		    
		    my $is_complement;
		    if ($feat_object->strand == 1) {
			$is_complement = 0;
		    }
		    elsif ($feat_object->strand == -1) { 
			$is_complement = 1;
		    }
		    else {
			die "unknown feature strand in $feature_id: ".$feat_object->strand; 
		    }

		    #store information on the feature in the hashref
		    $gbr{'Features'}->{$feature_group}->{$feature_id} = {
									  class => $primary_tag,
									  is_complement => $is_complement,
									  start => $feat_object->start,
									  end => $feat_object->end,
									  location_type => $feat_object->location->location_type,
									  start_type => $feat_object->location->start_pos_type,
									  end_type => $feat_object->location->end_pos_type,
									  feature_tag => $feature_tag,
									  feature_value => $feature_value
									};
		    if ($primary_tag eq 'CDS') {
			#store (possibly joined) nucleotide sequence using spliced_seq()
			$gbr{'Features'}->{$feature_group}->{$feature_id}->{'spliced_seq'} = $feat_object->spliced_seq->seq();
			$gbr{'Features'}->{$feature_group}->{$feature_id}->{'feature_len'} = $feat_object->spliced_seq->length();
			$gbr{'Features'}->{$feature_group}->{$feature_id}->{'translation'} = 0; #default null value
			if ($feat_object->has_tag("translation")) { # in some cases its "psuedo"
			    $gbr{'Features'}->{$feature_group}->{$feature_id}->{'translation'}=join('',$feat_object->get_tag_values("translation"));
			}

			#See bug 2414
			#Can assume all CDSs have transl_table?  No.
			#Will a document have uniform transl_tables?  Dunno.
			#See http://www.ncbi.nlm.nih.gov/Taxonomy/Utils/wprintgc.cgi?mode=c#SG1
			#  By default all transl_table in GenBank flatfiles are equal to id 1, and this is not shown. 
			#  When transl_table is not equal to id 1, it is shown as a qualifier on the CDS feature.
			if ($feat_object->has_tag("transl_table")) {			    
			    ++$TagCount{join('',$feat_object->get_tag_values("transl_table"))};			    
			    ++$transl_tables{join('',$feat_object->get_tag_values("transl_table"))};
			}
		    }

		    # store all unknown secondary tags (check if its not one of the tags we check for)
		    foreach my $tag ($feat_object->get_all_tags() ) {
			unless ($tag eq "gene" || $tag eq "locus_tag" || $tag eq "protein_id" || $tag eq "translation" || $tag eq "transl_table") {
			    ++$TagCount{"unknown_feature_tag_".$tag};
			}
		    }


		} #if big || statement
		else {
		    # record unknown primary tag
		    ++$TagCount{"unknown_primary_tag_".$primary_tag};
		}
	    } #else != source
 	} #for all the SeqFeatures

	#Most likely no /transl_table so use default, 
	#otherwise check make sure only one non-standard transl_table appeared
	my @transl_tables = (keys %transl_tables);
	if (@transl_tables == 0) {
	    print "Normal transl_table: 1\n";
	    $gbr{'transl_table'} = 1;
	}
	elsif (@transl_tables == 1) {
	    print "Using a different transl_table: ".$transl_tables[0]."\n";
	    $gbr{'transl_table'} = $transl_tables[0];
	}
	else {
	    die "Conflicting /transl_table values for CDSs in $gb_file";
	}

	#if there wasn't a valid strain provided, see if one can be grabbed from organism name
	unless ($gbr{'strain'}) {
	    if ($gbr{'organism'} =~ m/((sp\.)|(str\.)|(subsp\.))\s*(.*)/) {
		$gbr{'strain'} = $+; #last match
	    }
	}

    }
    undef($seq_obj);
    return \%gbr;
}


sub to_bsml {
    my %gbr = %{$_[0]};
    my $doc = $_[1];
    my $genome = $doc->createAndAddGenome('id' => 99);
    my $genome_id = $genome->{attr}->{id}; # have to track the active genome and propagate through to Link Sequences

    my %xref;
    $xref{'taxon_id'} = $doc->createAndAddCrossReference(
						'parent'          => $genome, 
						'database'        => 'taxon',           # //Genome/Cross-reference/@database
						'identifier'      => $gbr{'taxon_id'},  # //Genome/Cross-reference/@identifier
						'identifier-type' => 'taxon_id'         # //Genome/Cross-reference/@identifier-type
						);

    #add genbank/refseq accession (distinguish between the two?)
    $xref{'accession'} = $doc->createAndAddCrossReference(
						'parent'          => $genome, 
						'database'        => 'NCBI_GenBank:'.$gbr{'accession'},  # //Genome/Cross-reference/@database
						'identifier'      => $gbr{'accession'},                  # //Genome/Cross-reference/@identifier
						'identifier-type' => 'genbank flat file'                 # //Genome/Cross-reference/@identifier-type
						);

    $xref{'gi'} = $doc->createAndAddCrossReference(
						'parent'          => $genome, 
						'database'        => 'GI:'.$gbr{'gi'},  # //Genome/Cross-reference/@database
						'identifier'      => $gbr{'gi'},        # //Genome/Cross-reference/@identifier
						'identifier-type' => 'gi'               # //Genome/Cross-reference/@identifier-type
						);

    my $organism = $doc->createAndAddOrganism( 
					       'genome'  => $genome,
					       'genus'   => $gbr{'genus'},   # //Genome/Organism/@genus
					       'species' => $gbr{'species'}, # //Genome/Organism/@species
					       );

    # add genetic code / translation table / transl_table
    # values of 2, 3, 4, 5, 9, 13, 14, 16, 21, 22, 23 are also mitochondrial codes
    # see http://www.ncbi.nlm.nih.gov/Taxonomy/Utils/wprintgc.cgi?mode=c#SG1
    # see bugzilla 2414
    my %mt_codes = (2 => 1, 3 => 1, 4 => 1, 5 => 1, 9 => 1, 13 => 1, 14 => 1, 16 => 1, 21 => 1, 22 => 1, 23 => 1);
    my $transl_table;
    if ($mt_codes{$gbr{'transl_table'}}) {
	$transl_table = $doc->createAndAddBsmlAttribute($organism, 'mt_genetic_code', $gbr{'transl_table'});
    }
    else {
	$transl_table = $doc->createAndAddBsmlAttribute($organism, 'genetic_code', $gbr{'transl_table'});
    }

    my $strain_elem = $doc->createAndAddStrain(
					       'name'     => $gbr{'strain'},
					       'organism' => $organism
					       );

    # class is always assembly
    # chromosome|plasmid will be denoted in the "secondary type" ie an Attribute-list
    # if seq->molcule (taken from LOCUS line) matches dna, molecule=dna
    # if it matches rna, molecule=rna
    # otherwise it dies
    my $sequence = $doc->createAndAddSequence(
					      $gbr{'accession'}, #id
					      undef,             #title
					      $gbr{'seq_len'},   #length
					      $gbr{'molecule'},  #molecule
					      'assembly'         #class
					      );

    # store the main genomic sequence
    # store everything in odir
    my $fastafile = "$odir/$gbr{'gi'}.assembly.fsa";
    my $fastaname = "gi|".$gbr{'gi'}."|ref|".$gbr{'accession'}."|".$gbr{'organism'};
    # in order for this to get parsed correctly by bsml2chado's BSML::Indexer::Fasta component, 
    # Seq-data-import/@identifier must equal the fasta header up to the first space
    # currently dealing with this by:
    $fastaname =~ s/\s+/_/g;

    my $seq_obj = $doc->createAndAddSeqDataImport(
						  $sequence,                     # Sequence element object reference
						  'fasta',                       # //Seq-data-import/@format
						  $fastafile,                    # //Seq-data-import/@source
						  undef,                         # //Seq-data-import/@id
						  $fastaname                     # //Seq-data-import/@identifier
						  );
    open (my $FFILE, ">$fastafile") || die "Unable to open for writing $fastafile";
    print {$FFILE} fasta_out($fastaname, $gbr{'sequence'});
    close($FFILE);
    chmod(0666, $fastafile);

    # add the "secondary types" as  //Attribute-list/Attribute[@name="SO", content=<class>]
    # presumably class is from SO (not really), content=chromosome|plasmid
    $sequence->addBsmlAttributeList([{name => 'SO', content=> $gbr{'component'}}]);

    # add expanded ard.obo polymer_type (or SO term, if DNA|RNA)
    # note that right now I don't know it *could* be RNA, but maybe it will be in the future?
    # see bug #3251 http://jorvis-lx:8080/bugzilla/show_bug.cgi?id=3251
    if ($gbr{polymer_type} eq "DNA" || $gbr{polymer_type} eq "RNA") {
	$doc->createAndAddBsmlAttribute($sequence, 'SO', $gbr{polymer_type});
    }
    else {
	$doc->createAndAddBsmlAttribute($sequence, 'ARD', $gbr{polymer_type});
    }

    my $link_elem = $doc->createAndAddLink(
					   $sequence,
					   'genome',        # rel
					   '#'.$genome_id    # href
					   );

    #
    # features, feature-groups
    #
    #create the feature table
    my $feature_table_elem = $doc->createAndAddFeatureTable($sequence);

    foreach my $feature_group (keys %{$gbr{'Features'}}) {
	my $feature_group_elem = $doc->createAndAddFeatureGroup(
								$sequence, #the <Sequence> element containing the feature group
								undef,                    # id
								"$feature_group"             # groupset
								);
	die ("Could not create <Feature-group> element for uniquename '$sequence'") if (!defined($feature_group_elem));

	foreach my $feature (keys %{$gbr{'Features'}->{$feature_group}}) {	    
	    $gbr{'Features'}->{$feature_group}->{$feature}->{id} = $feature;
	    &addFeature($gbr{'Features'}->{$feature_group}->{$feature}, $doc, $genome_id, $feature_table_elem, $feature_group_elem);
	} #foreach feature in feature_group
    } #foreach feature_group
} #/to_bsml

#this doesn't conflict w/ BSML namespace
sub addFeature {
    my $featref = shift;
    my $doc = shift;
    my $genome_id = shift;
    my $feature_table_elem = shift;
    my $feature_group_elem = shift;

    my $id = $featref->{'id'};
    my $class = $featref->{'class'};
    my $is_complement = $featref->{'is_complement'};
    my $start = $featref->{'start'} - 1; #convert to space based coords
    my $end = $featref->{'end'}; #this should NOT be +1, right?
    my $feature_tag = $featref->{'feature_tag'};
    my $feature_value = $featref->{'feature_value'};

    my $location_type = $featref->{'location_type'};
    my $start_type = $featref->{'start_type'};
    my $end_type = $featref->{'end_type'};

    #Add //Feature
    my $feature_elem = $doc->createAndAddFeature(
						 $feature_table_elem,  # <Feature-table> element object reference
						 "$id",                # id
						 undef,                # title
						 $class,               # class
						 undef,                # comment
						 undef,                # displayAuto
						 );
    if (!defined($feature_elem)) {
 	die("Could not create feature element ($id)");
    }

    #Add the location element
    if ($location_type eq "EXACT") {
	if ($start_type eq "EXACT" && $end_type eq "EXACT") {
	    my $loc_loc = $doc->createAndAddIntervalLoc($feature_elem, $start, $end, $is_complement);
	}
	elsif ($start_type eq "BEFORE" && $end_type eq "EXACT") {
	    my $loc_loc = $doc->createAndAddIntervalLoc($feature_elem, $start, $end, $is_complement, 1, 0);
	}
	elsif ($start_type eq "EXACT" && $end_type eq "AFTER") {
	    my $loc_loc = $doc->createAndAddIntervalLoc($feature_elem, $start, $end, $is_complement, 0, 1);
	}
	elsif ($start_type eq "BEFORE" && $end_type eq "AFTER") {
	    my $loc_loc = $doc->createAndAddIntervalLoc($feature_elem, $start, $end, $is_complement, 1, 1);
	}
	else {
	    die "Unsupported start_type ($start_type) or end_type ($end_type)";
	}
    }
    elsif ($location_type eq "IN-BETWEEN") {
	#Check that it's a reasonable conversion of base-coordinates into interval coordinates describing an interbase position
	($start == $end - 2) || die "Incongruous site-loc: start=$start, end=$end";
	print "Creating site: $start $end\n";
	#Add a Site-Loc (since in interbase coords, site is one before the end)
	my $site_loc = $doc->createAndAddSiteLoc($feature_elem, $end-1,$is_complement, $class );
    }
    else {
	die "Unsupported location_type: $location_type";
    }

    #Add a reference to the new feature to the //Feature-group
    my $feature_group_member_elem = $doc->createAndAddFeatureGroupMember( $feature_group_elem,  # <Feature-group> element object reference
									  $id,                  # featref
									  $class,               # feattype
									  undef,                # grouptype
									  undef,                # cdata
									); 
    if (!defined($feature_group_member_elem)){
	die("Could not create <Feature-group-member> element object reference for gene model subfeature '$id'");
    }

    # add Attribute for which tag was used to create feature-group
    # See http://jorvis-lx:8080/bugzilla/show_bug.cgi?id=2506#c3 for discussion
    if (my $attribute_feature_value = $feature_group_elem->returnBsmlAttr($feature_tag)) {
	unless ($feature_value eq $attribute_feature_value->[0]) {  #check it's the same
	    die("conflict in feature_tag '$feature_tag', existing value '$attribute_feature_value->[0]' conflicts with '$feature_value'");
	}
    }
    else {
	my $attribute_feature = $doc->createAndAddBsmlAttribute($feature_group_elem, $feature_tag, $feature_value);
	if (!defined($attribute_feature)){
	    die("Could not create <Attribute> element ");
	}
    }

    # if the feature type is CDS
    # - add dna sequence (*or* rna)
    # - add polypeptide feature
    # - add aa sequence for polypeptide
    if ($class eq 'CDS') {
	&addSeqToFeature($featref, $doc, $genome_id, $feature_table_elem, $feature_group_elem, $feature_elem, $gbr{'molecule'});
	if ($featref->{'translation'}) {
	    # create dummy featref for polypeptide
	    my $poly_featref = {
				 'id' => $featref->{'id'},
				 'class' => 'polypeptide',
				 'is_complement' => $featref->{'is_complement'},
				 'start' => $featref->{'start'} - 1, #convert to space based coords
				 'end' => $featref->{'end'}, #this should NOT be +1, right?
				 'feature_tag' => $featref->{'feature_tag'},
				 'feature_value' => $featref->{'feature_value'},				 
				 'location_type' => $featref->{'location_type'},
				 'start_type' => $featref->{'start_type'},
				 'end_type' => $featref->{'end_type'},
				 'feature_len' => length($featref->{'translation'}),
				 'spliced_seq' => $featref->{'translation'}
				 };
	    $poly_featref->{id} =~ s/CDS/polypeptide/; # change id
	    my $poly_feat_elem = &addFeature($poly_featref, $doc, $genome_id, $feature_table_elem, $feature_group_elem);
	    &addSeqToFeature($poly_featref, $doc, $genome_id, $feature_table_elem, $feature_group_elem, $poly_feat_elem, 'aa');
	} # if translation
    }# if CDS

    # return the feature that was created
    return $feature_elem;

} #end addFeature



sub addSeqToFeature {
    # add Sequence object
    # link sequence to genome
    # add sequence link to feature
    my $featref = shift;
    my $doc = shift;
    my $genome_id = shift;
    my $feature_table_elem = shift;
    my $feature_group_elem = shift;
    my $feature_elem = shift;
    my $molecule_type= shift;

    my $id = $featref->{'id'};
    my $class = $featref->{'class'};
    my $feature_len = $featref->{'feature_len'};
    my $spliced_seq = $featref->{'spliced_seq'};

    my $seq_name = $id."_seq";

    # create sequence object
    my $feature_seq = $doc->createAndAddSequence(
						 $seq_name,    # id
						 undef,        # title
						 $feature_len, # $gbr{'seq_len'},   #length
						 $molecule_type,        # molecule
						 $class  #class
						 );
    # write sequence object to file
    unless (defined($fsa_files{$class})) {
	$fsa_files{$class}{name} = "$odir/$gbr{gi}.$class.fsa";
	open($fsa_files{$class}{fh}, ">".$fsa_files{$class}{name});
    }

#    my $fastafile = "$odir/$id.fsa"; 
    my $fastaname = $id;
    #Seq-data-import/@identifier must equal the fasta header up to the first space	
    my $feature_seq_obj = $doc->createAndAddSeqDataImport(
							  $feature_seq,                  # Sequence element object reference
							  'fasta',                       # //Seq-data-import/@format
#							  $fastafile,                    # //Seq-data-import/@source
							  $fsa_files{$class}{name},      # //Seq-data-import/@source
							  undef,                         # //Seq-data-import/@id
							  $fastaname                     # //Seq-data-import/@identifier
							  );

#    open (my $FFILE, ">$fastafile") || die "Unable to open for writing $fastafile: $!";
#    print {$FFILE} fasta_out($fastaname, $spliced_seq);
    print {$fsa_files{$class}{fh}} fasta_out($fastaname, $spliced_seq);

#    close($FFILE);
    #chmod(0666, $fastafile);

    # link sequence to genome
    # I am reasonably certain that not including the genome@id value for the href is okay
    # the line above is a ***lie***
    my $feature_link_elem = $doc->createAndAddLink(
						   $feature_seq,
						   'genome',        # rel
#						   '#'.$genome->{'attr'}->{'id'}    # href
						   '#'.$genome_id
						   );


    # link feature to sequence
    my $feature_seq_link = $doc->createAndAddLink(
						  $feature_elem,
						  'sequence',      # rel
						  '#'.$seq_name    # href (same as Sequence@id)
						  );
    return $feature_seq;
}


#-------------------------------------------------------------------------
# fasta_out()
# taken without remorse from legacy2bsml.pl
#-------------------------------------------------------------------------
sub fasta_out {
    #This subroutine takes a sequence name and its sequence and
    #outputs a correctly formatted single fasta entry (including newlines).  

    #$logger->debug("Entered fasta_out") if $logger->is_debug;

    my ($seq_name, $seq) = @_;

    my $fasta=">"."$seq_name"."\n";
    $seq =~ s/\s+//g;
    for(my $i=0; $i < length($seq); $i+=60){
	my $seq_fragment = substr($seq, $i, 60);
	$fasta .= "$seq_fragment"."\n";
    }
    return $fasta;

}

#
# unused
#
sub parse_genbank_file_regexp {
    my $gb_file = shift;

    my %gbr;
    open(File,"<$gb_file") || die "can't open file ($gb_file): $!\n";
    while (my $line = <File>) {
	chomp;
	if($line =~ /\AACCESSION/) {
	    # We have found the ACCESSION, grab that info and store it in gbr:
	    my ($check1,$check2,$check3)=split(/\s+/,$line);
	    $gbr{'accession'} = $check2;
	}
	elsif($line =~ /\A\s+ORGANISM/) {
	    # We have found the ORGANISM, grab that info and store it in gbr:
	    $gbr{'organism'} = $line;
	    $gbr{'organism'} =~ s/\A\s+ORGANISM\s+//;
	    chomp $gbr{'organism'};
	}
	elsif ($line =~ /^FEATURES/) {
	    my $next_line = <File>;
	    if ($next_line =~ /^\s*source/) {
		$gbr{'feature'} = 1;
	    }
	}
	elsif($line =~ /\A\s+\/strain/) {
	    # We have found the strain, grab that info and store it in gbr:
	    $gbr{'strain'} = $line;
	    $gbr{'strain'} =~ s/\A\s+\/strain\=//;
	    $gbr{'strain'} =~ s/\"//g;
	    $gbr{'strain'} =~ s/\n//g;
	    chomp $gbr{'strain'};
	}
	elsif ($line =~ /\/db_xref=\"taxon\:(\d+)\"/) {
	    $gbr{'taxon_id'} = $1;
	}
	elsif ($line =~ /\/isolate=\"(.+)\"/) {
	    $gbr{'isolate'} = $1;
	}
	elsif ($line =~ /\/serovar=\"(.+)\"/) {
	    $gbr{'serovar'} = $1;
	}
	elsif ($line =~ /\/specific_host=\"(.+)\"/) {
	    $gbr{'specific_host'} = $1;
	}
	elsif ($line =~ /\/note=(.+)/) {
	    $gbr{'note'} = $1;
	}
    } #while $line
    close(File);

    #Clean up parsed data

    #remove strain information from organism name
    #sp. and str. are sometimes present in organism previous to strain
    if (defined $gbr{'strain'} && defined $gbr{'organism'}) {
	$gbr{'organism'} =~ s/((sp\.)|(str\.))?\s*\Q$gbr{'strain'}\E//;
    }

    #If two words in organism, split to genus species
    #(first word is genus, everything else is species)
    if (defined $gbr{'organism'}) {
	my @words = split (/\s/, $gbr{'organism'});
	$gbr{'words'} = @words;
	if ($gbr{'words'} == 1) { #one word is probably genus
	    $gbr{'genus'} = $words[0];
	    $gbr{'species'} = "";
	}
	else { #else, throw it all in species
	    $gbr{'genus'} = shift @words;
	    $gbr{'species'} = "@words";
	}
    }
    return \%gbr;
}
