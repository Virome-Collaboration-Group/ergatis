#!/usr/bin/env perl
=head1 NAME

sam2lca.pl - Wrapper script to generate Lowest Common Ancestors from a BAM/SAM file

=head1 SYNOPSIS

 USAGE: sam2lca.pl
       --input_file=/path/to/some/input.bam
	   --original_bam=?path/to/some/original.bam
       --output_file=/path/to/transterm.txt
	   --tmp_dir=/tmp 
	   --tax_id_file=/path/to/tax_ids.txt
	   --nodes_file=/path/to/nodes.txt
	   --names_file\/path/to/names.txt
	 [
	   --host=revan.igs.umaryland.edu
	   --db=gi2taxon
	   --collection=gi2taxonnuc
	   --samtools_path=/path/to/samtools
	   --log=/path/to/file.log
       --debug=3
       --help
     ]

=head1 OPTIONS

B<--input_file,-i>
	A BAM file that has gone through BWA alignment

B<--original_bam, -b>
	A BAM file that was used as input for BWA alignment (resulting in the arg for --input_file.

B<--original_bam_list, -l>
	A list containing the BAm file as described above.  Should only be one BAM file.  Useful in Ergatis when the component may have both lists for the original BAM and the post-BWA bam 

B<--output_file,-o>
	Path name to LCA output. This can be any extension, but a simple .txt one will suffice

B<--tmp_dir,-t>
	Directory to store temporary files

B<--tax_id_file>

B<--nodes_file>
	Dump file containing information about NCBI Taxonomy ID nodes and their parent/children relationships

B<--names_file>
	Dump file containing information about organism names for given NCBI Taxonomy IDs

B<--tax_id_file>
	Dump file mapping nucleotide GI accessions to NCBI Taxonomy IDs

B<--host>
	MongoDB host server

B<--db>
	The GI-to-taxon database name (default 'gi2taxon')

B<--collection>
	The table that houses the GI-to-taxon information (default 'gi2taxonnuc')

B<--samtools_path,-s>
	Path to the directory of samtools executables

B<--log,-l>
    Logfile.

B<--debug,-d>
    1,2 or 3. Higher values more verbose.

B<--help,-h>
    Print this message

=head1  DESCRIPTION

 DESCRIPTION
 
=head1  INPUT

    Describe the input

=head1 OUTPUT

    Two LCA output files.

=head1  CONTACT

    Shaun Adkins
    sadkins@som.umaryland.edu

=cut

use strict;
use warnings;
use Getopt::Long qw(:config no_ignore_case no_auto_abbrev pass_through);
use Pod::Usage;
use LGT::LGTsam2lca;
use GiTaxon;

############# GLOBALS AND CONSTANTS ################
my $debug = 1;
my ($ERROR, $WARN, $DEBUG) = (1,2,3);
my $logfh;

my $HOST = 'revan.igs.umaryland.edu:10001';
my $DB = 'gi2taxon';
my $COLL = 'gi2taxonnuc';
my $SAMTOOLS_BIN = '/usr/local/bin/samtools';

my $original_bam;
####################################################

my %options;

my $results = GetOptions (\%options,
                         "input_file|i=s",
						 "original_bam|b=s",
						 "original_baml_list|l=s",
                         "output_file|o=s",
						 'tmp_dir|T=s',
						 'tax_id_file=s',
						 'nodes_file=s',
						 'names_file=s',
						 'host|h=s',
						 'db|d=s',
						 'collection|c=s',
						 'samtools_path|s=s',
                         "log|l=s",
                         "debug|d=s",
                         "help|h"
                          );

&check_options(\%options);

$options{host} = $HOST if (! $options{host});
$options{db} = $DB if (! $options{db});
$options{collection} = $COLL if (! $options{collection});

my $samtools = $options{samtools_path} ? $options{samtools_path} : $SAMTOOLS_BIN;

if ($options{input_file} !~ /.bam$/){
	&_log($ERROR, $options{input_file} . " must be a BAM file with a .bam extension");
}

my $gi_tax_obj = GiTaxon->new({
		'nodes' 		=> $options{nodes_file},
		'names' 		=> $options{names_file},
		'gi2tax'		=> $options{tax_id_file},
		'host'			=> $options{host},
		'gi_db'			=> $options{db},
		'gi_coll'		=> $options{collection},
		'taxonomy_dir'	=> $options{tmp_dir},
		'verbose'		=> 1
	});
my $sam2lca_obj = LGT::LGTsam2lca->new({
		'gi2tax'		=> $gi_tax_obj,
		'out_file'		=> $options{output_file},
		'samtools_bin'	=> $samtools,
		'complete_bam'	=> $original_bam
	});

$sam2lca_obj->process_file({
		'file'		=> $options{input_file},
});

my $files = $sam2lca_obj->writeOutput();

exit(0);

sub check_options {
   my $opts = shift;
   if( $opts->{'help'} ) {
       &_pod;
   }

   if( $opts->{'log'} ) {
       open( $logfh, "> $opts->{'log'}") or die("Can't open log file ($!)");
   }

   $debug = $opts->{'debug'} if( $opts->{'debug'} );

   foreach my $req ( qw(input_file output_file nodes_file names_file tax_id_file) ) {
       &_log($ERROR, "Option $req is required") unless( $opts->{$req} );
   }

   unless ($opts->{original_bam} || $opts->{original_bam_list}){
		&_log($ERROR, "Either --original_bam or --original_bam_list is required");
	}

	if ($opts->{original_bam}) {
		$original_bam  = $opts->{original_bam};
	} else {
		open LIST, $opts->{original_bam} || &_log($ERROR, "Cannot open $opts->{original_bam_list} for reading");
		my @files = <LIST>;
		&_log($ERROR, "List file must contain exactly one BAM file") unless (scalar(@files) == 1);
		$original_bam = shift @files;
		chomp $original_bam;
		close LIST;
	}
}

sub _log {
   my ($level, $msg) = @_;
   if( $level <= $debug ) {
      print STDOUT "$msg\n";
   }
   print $logfh "$msg\n" if( defined( $logfh ) );
   exit(1) if( $level == $ERROR );
}

sub _pod {
    pod2usage( {-exitval => 0, -verbose => 2, -output => \*STDERR} );
}
