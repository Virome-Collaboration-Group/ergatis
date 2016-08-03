#!/usr/bin/perl

=head1 NAME

run_cmsearch.pl - Takes hmmpfam files as input and runs the hits against
    cmsearch.  Optimization for cmsearch.

=head1 SYNOPSIS

USAGE: run_cmsearch.pl 
              --input_list=/path/hmmpfam/results.raw.list
              --input_file=/path/hmmpfam/result.raw
              --tmp_dir=/path/to/tmpdir/
              --output_file=/path/to/infernal.raw
              --flanking_seq=50
              --hmm_cm_table=/path/to/some/file.table
              --cmsearch_bin=/path/to/cmsearch
          [   --other_opts=cmsearch options
              --log=/path/to/some/file.log
              --debug= > 2 for verbose
          ]

=head1 OPTIONS

B<--input_list,-l>
    A list of hmmpfam raw output files to be formatted and run with cmsearch

B<--input_file,-i>
	With --hmm_processing enabled:
    An input file (hmmpfam) raw output
	With --hmm_processing_disbled:
	A polypeptide fasta file

B<--tmp_dir,-t>
    Directory to write temporary files.  Will be cleaned up if --clean_up is enabled.
	Is required if --hmm_preprocessing is enabled

B<--output_file,-o>
    The output file for cmsearch results to go into.  Will concate all results to this file.

B<--flanking_seq,-f>
    The number of nucleotides on either side of the hmmpfam hit to parse out of database for 
    cmsearch run. Default: 50.  Only works with the --hmm_preprocessing flag set

B<--hmm_cm_table,-c>
    File containing a lookup for covariance models given an hmm model.  See input section of perldoc
    more specific details on this file.  Can only be used with HMM preprocessing

B<--hmm_preprocessing, -h>
	If flag is enabled, will accept HMM raw results as input, process the results in order to 
	obtain subsequences from --sequence_list to run cm_search on

B<--cmsearch_bin,-b>
    Path to the cmsearch binary. If not it will be assumed that the binary is in the PATH.

B<--cm_file, -C>
	Instead of mapping the HMMs or passing in a directory of CMs, just pass in a single CM file.
	Best use case is if you are unsure what to compare against and just want to compare against
	all available RFams.  Can be used with or without HMM_preprocessing

B<--sequence_list,-s>
    A list of absolute paths to files which contain the input fasta sequence from the HMMER search.
    In most cases will be the chromosome/assembly sequence used as input. Used to grab extra flanking
    sequence. If not running with HMM preprocessing, just pass a single file as --input_file

B<--other_opts,-e>
    Other options to be passed into the cmsearch program.  
    *Note: The -W option is used by this script and therefore will be parsed out of the other_opts
    string prior to running cmsearch.  This program uses the length of the sequence found by the
    hmmpfam run (plus extraSeq) as the window size.

B<--clean_up>
	Remove temp files and the temp directory

B<--debug> 
    Debug level.  Use a large number to turn on verbose debugging. 

B<--log> 
    Log file

B<--help,>
    This help message

=head1  DESCRIPTION

The program infernal is used to search covariance models against biological sequences
(see infernal userguide: oryx.ulb.ac.be/infernal.pdf).  More specifically infernal uses
profiles of RNA secondary structure for sequence analysis.  The program is computationally
intensive when used with large genomic sequences.  

At its most basic form, run_cmsearch.pl will simply take a polypeptide fasta sequence and a CM file and 
run Infernal's 'cmsearch' script.

Optionally, run_cmsearch.pl will take in a set of hmmpfam results as an initial screening to infernal.  
RNA HMMs can quickly identify regions where RNA is located, and these sections can then be further
refined by running this section through cmsearch (infernal).  With a set of HMMs and CMs created from
the same alignments, infernal can be used in a high-throughput manner.

=head1  INPUT

=head2 HMM_preprocessing flag on

The main input for run_cmsearch is either a list of hmmpfam raw results or one hmmpfam raw result.
The sequences are then parsed from these hmmpfam results and the database queryed.  The sequence
identifier is taken from the name of the file (which is reliable in the ergatis naming scheme, but
probably could be made more general in the future).  The name of the HMMs are also parsed from these
files.  Important to note that the HMM names are not the same as the file names (since hmmpfam can
use a multi-hmm file for searching).  This becomes important in the creation of the hmm_cm_table.

If a hit was found with an HMM file, the related CM file will be used to search that portion of the
sequence.  To do this, the program must know which HMMs relate to which CMs.  There are two ways
to provide this information.  This by providing a tab-delimited file with HMM name (not file name,
but the name found in the HMM header and the one used in hmmpfam output) and CM (actual path to file)
on each line.  For example:

    RF00001.HMM     /usr/local/db/RFAM/CMs/RF00001.cm
    RF00002.HMM     /usr/local/db/RFAM/CMs/RF00002.cm
    ...

The other option is to provide the program with the directory where all the covariance models are
stored.  The program will then look in that directory for a covariance model that contains the first
word of the HMM name (not file name, but actual id name found in hmmpfam results).  

=head2 HMM_preprocessing flag off

The --input_file instead will be replaced by a fasta sequence file.  All that is required is this
fasta file and the covariance matrix (CM) file path marked by --cm_file.  

=head1  OUTPUT

The program will create individual fasta files for each hmmpfam hit provided in the input and is 
cleaned up later.  All the cmsearch results (all the stdout from the program run) is written to
output_file.  See infernal userguide: oryx.ulb.ac.be/infernal.pdf for more information on output format.

=head1  CONTACT

    Kevin Galens
    kgalens@tigr.org

=cut

use strict;
use warnings;
use Getopt::Long qw(:config no_ignore_case no_auto_abbrev pass_through);
use Pod::Usage;
use Ergatis::Logger;
use HmmTools;
use Data::Dumper;
use IPC::Open3;
use POSIX ":sys_wait_h";

my %options = ();
my $results = GetOptions (\%options, 
                          'input_list|l=s',
                          'input_file|i=s',
                          'tmp_dir|t=s',
                          'output_file|o=s',
                          'sequence_list|s=s',
                          'flanking_seq|f=i',
                          'hmm_cm_table|c=s',
						  'hmm_preprocessing|h=i',
						  'cm_file|C=s',
                          'cmsearch_bin|b=s',
                          'other_opts|e=s',
						  'clean_up=i',
                          'log=s',
                          'debug=s',
                          'help') || &_pod();

## display documentation
&_pod if( $options{'help'} );

my $logfile = $options{'log'} || Ergatis::Logger::get_default_logfilename();
my $logger = new Ergatis::Logger('LOG_FILE'=>$logfile,
				  'LOG_LEVEL'=>$options{'debug'});
$logger = $logger->get_logger();


############ GLOBALS AND CONSTANTS #############
my $PROG_NAME = 'cmsearch';

my @files;
my $fasta_in;
my $hmmCmTable;
my %hmmCmLookup;
my $cmDir;
my $cmFile;
my $outputDir;
my $outputFile;
my @seqList;
my $extraSeqLen = 50;
my $other_opts = "";
my @dirsMade;
my $debug = 0;
################################################

## make sure everything passed was peachy
&check_parameters(\%options);

################## MAIN #########################
if ($options{'hmm_preprocessing'} ){
	print "HMM preprocessing has been enabled\n" if ($debug > 2);
	&createHmmCmLookup($hmmCmTable) if(defined($hmmCmTable));

	#All the input files if it's a list.
	foreach my $file(@files) {
    	my $stats = &processHmmpfamFile($file);
    	$stats = &getSequencesAndPrint($stats);

    	#Make sure that we make an output file even if there aren't any results to read in.
    	if( (scalar(keys %{$stats})) == 0 ) {
			$logger->debug("No sequences parsed from query seq file.");
    	    system("touch $outputFile");
    	}
    
    	#Okay this may seem to be overkill, but I'm almost sure it has to be this way (almost).
    	#It allows for the case where one HMM can have a hit against the same sequence twice.  
    	#Therefore one cmsearch run should be identified not only by the hmm/cm and query sequence, 
    	#but also where the hit has occured on the query sequence.
    	foreach my $querySeq(keys %{$stats}) {
				$logger->debug("Query = $querySeq");
        	foreach my $hmm(keys %{$stats->{$querySeq}}) {
				$logger->debug("HMM = $hmm");
            	foreach my $boundaries(keys %{$stats->{$querySeq}->{$hmm}}) {
						$logger->debug("Boundaries = $boundaries");
                	my $fileName = $stats->{$querySeq}->{$hmm}->{$boundaries};
                	unless($fileName) {
                	    print Dumper($stats->{$querySeq}->{$hmm});
                	    &_die("Could not find file name");
                	}
					my $cm = selectCM($hmm, $cmFile);
					validateFasta($fileName);
                	my $exitVal = &runProg($fileName, $cm, $other_opts, $outputFile);
                	handleExitVal($exitVal);
            	}
        	}
    	}
	}
	&cleanUp if ($options{'clean_up'});
} else {
	# Strictly fasta file and pass in CM file
	my $exitVal = runProg($fasta_in, $cmFile, $other_opts, $outputFile);
	handleExitVal($exitVal);
}

exit(0);
################## END MAIN #####################


##################################### SUB ROUTINES ############################################

#Name: check_parameters
#Desc: checks the input parameters of the program
#Args: Hash Ref - holding the options (from GetOptions routine)
#Rets: Nothing.
sub check_parameters {
    my $options = shift;

    #I wish this function could be uglier.  So I'm not commenting it.
    if($options->{input_list} && $options->{input_list} ne "") {
        &_die("input_list [$options->{input_list}] does not exist") unless( -e $options->{input_list});
        open(IN, "< $options->{input_list}") or &_die("Unable to open $options->{input_list}");
        while(<IN>) {
            push(@files, $_);
        }
        close(IN);
    } elsif($options->{input_file} && $options->{input_file} ne "") {
        &_die("input_file [$options->{input_file}] does not exist") unless( -e $options->{input_file});
        if ($options->{hmm_preprocessing}){
			push(@files,$options->{input_file});
		} else {
			$fasta_in = $options->{input_file};
		}
    } else {
        &_die("Either input_list or input_file must be provided");
    }

	if ($options->{hmm_preprocessing}){
    	if($options->{tmp_dir}) {
    	    &_die("$options->{tmp_dir} (tmp_dir) does not exist") unless( -d $options{tmp_dir});
    	} else {
    	    &_die("Option tmp_dir must be provided if HMM preprocessing is enabled");
    	}
    	$outputDir = $options->{tmp_dir};
    	$outputDir =~ s|/$||;
   
		if($options->{sequence_list}) {
        	&_die("sequence_list $options->{sequence_list} does not exist") unless(-e $options->{sequence_list});
    	} else {
        	&_die("Option sequence_list must be provided if HMM preprocessing is enabled.  If not running with HMM results, just pass single fasta file as --input_file");
    	}   
    	open(IN, "<$options->{sequence_list}") or &_die("Unable to open $options->{sequence_list}");
    	@seqList = <IN>;
    	close(IN);
	}

    &_die("output_file option is required") unless($options->{output_file});
    $outputFile = $options->{output_file};
    system("rm -f $outputFile") if(-e $options->{output_file});

    $debug = $options->{debug} if($options->{debug});

    if($options->{hmm_cm_table} && $options->{hmm_cm_table}  ne "" && $options->{hmm_preprocessing}) {
        if(-f $options->{hmm_cm_table}) {
            $hmmCmTable = $options->{hmm_cm_table};
        } elsif (-d $options->{hmm_cm_table}) {
            $cmDir = $options->{hmm_cm_table};
		} else {
            &_die("Option --hmm_cm_table file or directory path $options->{hmm_cm_table} does not exist");
        }
    } elsif (-f $options->{cm_file}) {
		$cmFile = $options->{cm_file};
	} else {
        &_die("Options --hmm_cm_table or --cm_file are required");
    }

    $other_opts = $options->{other_opts} if($options->{other_opts});
    $extraSeqLen = $options->{flanking_seq} if($options->{flanking_seq});
    
    if($options->{cmsearch_bin} && $options->{cmsearch_bin} ne "") {
        &_die("Could not locate cmsearch binary at $options->{cmsearch_bin}") unless(-e $options{cmsearch_bin});
        $PROG_NAME = $options->{cmsearch_bin};
    }
}

#Name: cleanUp
#Desc: Will remove tmp files and directories made.
#Args: None (Uses @dirsMade array)
#Rets: Nothing
sub cleanUp {
    foreach my $dir(@dirsMade) {
        print STDERR "DEBUG: removing $dir and contents\n";
		unlink glob "$dir/*.fsa";
		rmdir($dir);
    }
}

#Name: createHmmCmLookup
#Desc: Will create a hash lookup from a file that coordinates hmm -> cmm files from the 
#      supplied table file. (Tab delimited matching an hmm with a cm).
#Args: String: File name of the table
#Rets: Nothing
sub createHmmCmLookup {
    my $lookupInput = shift;
    print "In createHmmCmLookup\n" if($debug > 2);
    open(IN, "< $lookupInput") or 
        &_die("Unable to open $lookupInput for reading");
    while(<IN>) {
        my @tmpList = split(/\s/);
        $hmmCmLookup{$tmpList[0]} = $tmpList[1];
        &_die("Check the format of the HMM->CM lookup file.  The HMM should be the HMM name, ".
              "and the CM should be a full path to the CM file.  See perldoc for more details.")
            unless(-e $tmpList[1]);
    }
    close(IN);
  
}

#Name: findFile
#Desc: Given a sequence, will search for the file name in the @seqList array
#Args: Part of the name of the file
#Rets: The sequence in that file.
sub findFile {
    my $seqID = shift;
    my ($retval,$fileFound);
    my $fileFlag = 0; 
	my $multiFlag = 0;	# If sequence is grepped, had to come from multifasta input
    $seqID =~ s/\|/\_/g;
    print "Searching with $seqID\n";
    foreach my $file (@seqList) {
        if($file =~ /$seqID\./) {
            $fileFound = $file;
            print $fileFound."\n";
            $fileFlag++;
        }
    }

    if($fileFlag > 1) {
        &_die("Found $fileFlag possible files");
    } elsif($fileFlag == 0) {
		my $grepFile = grepFile($seqID);
        &_die("Didn't find a match for $seqID in the sequence_list") if (!$grepFile);
		$fileFound = $grepFile;
		$multiFlag = 1;
    }

    open(IN, "< $fileFound") or &_die("Unable to open $fileFound to get sequence information");
    
    my $header = "";
    my %sequence;
    while (<IN>) {
        my $line = $_;
        chomp($line);
		
		if ($multiFlag && $line =~ />($seqID.*)\n*$/) {
			$header = $1;
			$sequence{$header} = "";
		} elsif ($line =~ />(.*)\n*$/) {
            $header = $1;
            $sequence{$header} = "";
        } else {
            $sequence{$header}.=$line;
        }
    }

	# If file was grepped, return sequence directly
	if ($multiFlag && defined $sequence{$seqID}) {
		return $sequence{$seqID};
	} else {
		&_die("Sequence $seqID was not found within the grepped file.  That's odd.");
	}
	# If sequence ID was in file name (single-seq input), return only sequence
    if (scalar(keys %sequence) > 1)  {
        &_die("More than one sequence found in file $fileFound.  ".
              "Assuming this was a single-seq input.");
    } elsif ($header eq "") {
        &_die("Couldn't find sequence in file $fileFound.  Perhaps it's not fasta format?");
    }
    
    return $sequence{$header};
}

sub grepFile {
	my $seqID = shift;
	my $noFile = 0;	# Flag in case sequence cannot be grepped from files
	foreach my $file (@seqList) {
	  open my $fh, $file || &_die("Cannot open $file for reading (for grep check): $!");
	  while (my $line = <$fh>){
		if ($line =~ /^>/){
			my $i = index $line, $seqID;
			if ($i > -1) {	# -1 means index position was not found for sequence
				close $fh;
				return $file;
			}
		}
	  }
	  close $fh;
	}
	return $noFile;
}

#Name: getInputFiles
#Desc: Opens the passed in file name and makes an array of all the listed files
#Args: String: the file name fo the input list
#Rets: List: An array of the contained files.
sub getInputFiles {
    my $fileName = shift;
    my @retval;
    my $inH;

    open($inH, "< $fileName") or &_die("Could not open $fileName for reading");

    while(<$inH>) {
        push(@retval,$_);
    }
    close($inH);
    
    chomp(@retval);

    return \@retval;

}

#Name: getSequenceAndPrint
#Desc: Retrieves sequence from the database (by looking up id's stored in a hash ref created by
#      processHmmpfamFile.
#Args: Hash Ref: Stats returned from processHmmpfamFile
#Rets: Hash Ref: The same hash ref, just with sequences included.
sub getSequencesAndPrint {
    my $seqHash = shift;

    #Loop through sequences
    foreach my $querySeq (keys %{$seqHash}) {
        my $tmpSeq = "";
        $tmpSeq = &findFile($querySeq);
        &_die("Couldn't find file matching $querySeq") unless($tmpSeq ne "");

        #Loop through all the hits for a query sequence
        # (one hit is defined by a unique combination of query sequence,
        # hmm file, start and stop locations).
        foreach my $hmm (keys %{$seqHash->{$querySeq}}) {

            foreach my $startEnd (keys %{$seqHash->{$querySeq}->{$hmm}}) {

                #Since the start and end coordinates are going to change, remove the old entry.
                delete($seqHash->{$querySeq}->{$hmm}->{$startEnd});
                
				#Get the start and end of the hit
                my ($start, $end) = split(/::/, $startEnd);
                #Parse sequence information
				my $tmpSection;
                ($tmpSection, $start, $end) = &parseSeqAndExtra($tmpSeq, $start, $end);
                
                #Store file name information and print sequence
                $seqHash->{$querySeq}->{$hmm}->{"${start}::$end"} = &printSeqToFile($querySeq, $hmm, $start, 
                                                                                  $end, $tmpSection);
            }
        }
    }
    #Return the result
    return $seqHash;
}

#Name: handleExitVal
#Desc: Will die with a correct message depending on the exit value of runProg 
#Args: Hash Ref :: Run information (returned from run prog)
#Rets: Nothing
sub handleExitVal {
    my $exitVal = shift;
    &_die("command:\n$exitVal->{cmd}\nError: @{$exitVal->{err}}") 
        unless(@{$exitVal->{err}} == 0);
}

#Name: lookupCM
#Desc: Looks up a certain cm file from an $hmm name.
#Args: Scalar: HMM name.  Must be in the HMM->CM table.
#Rets: Scalar: The CM related to the HMM.
sub lookupCM {
    my $hmm = shift;
    my $retval;
    
    if($cmDir) {
        $hmm = $1 if($hmm =~ /([^_]+)/);
        opendir(IN,$cmDir) or &_die("Could not open directory cm_dir: [$cmDir] ($!)");
        print "Opening $cmDir\n" if($debug > 2);
        my @posCM = grep { /$hmm/ && -f "$cmDir/$_" } readdir(IN);
        closedir(IN);

        if(@posCM == 0) {
            &_die("Could not find a match for hmm $hmm in $cmDir");
        } elsif(@posCM > 1) {
            $" = ", ";
            &_die("Found more than one possible match for $hmm in $cmDir:\n@posCM");
            $" = " ";
        } else {
            $retval = "$cmDir/$posCM[0]";
        }
    } else {
        
        $retval = $hmmCmLookup{$hmm};
    }

    return $retval;
}

#Name: parseSeqAndExtra
#Desc: Parses the sequence information out of the database.  Will take $extraSeqLen nucleotides
#      on either side of the boudaries provided
#Args: Scalar: Full sequence
#      Scalar: The start boundary to be parsed
#      Scalar: The end boundary
#Rets: Returns the new start and end coordinates (after $extraSeqLen) and the newly parsed
#      sequence
sub parseSeqAndExtra {
    my ($seq, $start, $end) = @_;

    if($start < $extraSeqLen) {
        $start = 0;
    } else {
        $start -= $extraSeqLen;
    }

    #A little sloppy here.  If it's over the length, it will just
    #take it all, so doesn't matter if $end > length($seq)
    $end += $extraSeqLen;

    my $retval = substr($seq, $start, $end-$start);
    return ($retval, $start, $end);
}

#Name: printSeqToFile
#Desc: Will print a sequence to file in the output directory in fasta format
#Args: Scalarx5: QuerySequence ID, the hmm file used in the analysis, the start and end boudnaries
#                and the sequence.
#Rets: Nothing
sub printSeqToFile {
    my ($querySeq, $hmm, $start, $end, $tmpSeq) = @_;
    my $outFileName;
    $querySeq =~ s/\|/\_/g;
    unless(-d "$outputDir/$querySeq") {
        system("mkdir $outputDir/$querySeq");
        push(@dirsMade, "$outputDir/$querySeq");
    }

    my $tmpHmm = $1 if($hmm =~ /.*::(.*)/);

    $outFileName = "$outputDir/$querySeq/$tmpHmm.$start.$end.fsa";
    open(OUT, "> $outFileName") 
        or &_die("Unable to open output file $outFileName ($!)");
    print OUT ">${querySeq}::$start-$end\n$tmpSeq";
	close(OUT);

    return $outFileName;
}

#Name: processHmmpfamFile
#Desc: Takes in an hmmpfam output file and returns a hash of full of the hits (summarized)
#Args: Scalar: Hmmpfam name
#Rets: Hash Ref: $hashRef->{seqId}->{hmmFile::hmmName}->{start::end}
sub processHmmpfamFile {
    my $fileName = shift;
    my $hmmpfamStats;  #Hash Ref
    my ($inH,$querySeq);
    my $alignmentFlag = 0;

	#my $in = Bio::SearchIO->new(-format => 'hmmer',
	#							-version => 3,
	#							-file => $fileName); 

	#open($inH, "<$fileName") or &_die("Unable to open $fileName ($!)");
	print "Parsing $fileName\n" if($debug > 2);
	
	# Parse HMM data using HMMTools module
	my $data = &read_hmmer3_output($fileName);
	
	my $hmmFile 	= $data->{'info'}->{'hmm_file'};
	foreach my $querySeq (keys %{$data->{'queries'}}) {
		foreach my $hit (keys %{$data->{'queries'}->{$querySeq}->{'hits'}}){
			my $h = $data->{'queries'}->{$querySeq}->{'hits'}->{$hit};
			my $hit_name = $h->{'accession'};
			foreach my $domain (keys %{$h->{'domains'}}){
				my $dh = $h->{'domains'}->{$domain};
				my $start = $dh->{'seq_f'};
				my $end = $dh->{'seq_t'};
				print $querySeq, "\t", $hmmFile, "\t", $hit_name, "\t", $start, "\t", $end, "\n" if ($debug > 2);
				$hmmpfamStats->{$querySeq}->{"${hmmFile}::$hit_name"}->{"${start}::$end"} = "";
			}
		}
	}
    return $hmmpfamStats;
}

#Name: selectCM
#Desc: Selects CM to use in 'cmsearch'
#Args: Scalar :: HMM Covariance model path
#	   Scalar :: Single CM file (if exists)
#Rets: Scalar :: CM file path

sub selectCM {
	my ($hmm, $cmFile) = @_;
    my $cm = &lookupCM($1) if($hmm =~ /.*::(.*)/);
    $cm = $cmFile if (defined $cmFile);
    &_die("Could not parse HMM name from line $hmm") unless($cm);
	return $cm;
}

#Name validateFasta
#Desc Ensure Fasta file seqs aren't 0 length
#Args: Scalar :: Fasta file
#Rets: void

sub validateFasta {
	my ($fsaFile) = shift;
    #Get the length of the fasta file
    my $length;
    open(IN, "< $fsaFile") or &_die("Unable to open $fsaFile to determine length ($!)");
    while(<IN>) {
        if(/^[^>]/) {
            $length = length($_);
        }   
    }   
    &_die("Could not determine length of sequence in file $fsaFile") unless($length);
}

#Name: runProg
#Desc: Runs the cmsearch program
#Args: Scalar :: Fasta file path
#      Scalar :: CM file
#      Scalar :: Other options
#	   Scalar :: Output file
#Rets: Hash Ref :: std - stdout of program
#                  err - stderr of program
#                  exitVal - the exitVal
#                  cmd - the command that was run
sub runProg {
    my ($fsaFile, $cm, $oOpts, $outputFile) = @_;
    my $retval;

    #Make sure the -W option isn't used in the other opts.  
    $oOpts =~ s/--window\s\S+//;
	$oOpts .= " --tblout $outputFile.tbl ";

    #set up the cmsearch command
    my $cmd = $PROG_NAME." $oOpts $cm $fsaFile";
    print " running [$cmd]\n" if($debug > 2);

    #Run the command and store it's std out and err and exitval.
    my $pid = open3(undef, \*STD, \*ERR, $cmd);
    my $exitVal = $? << 8;
    $retval->{exitVal} = $exitVal;
    $retval->{std} = [<STD>];
    $retval->{err} = [<ERR>];
    $retval->{cmd} = $cmd;
    waitpid($pid, 0);
    
    #Print the std out to a file.  The output file.  If it exists, concatenate, otherwise
    #just make it.
    my $openOut = "> $outputFile";
    $openOut = ">".$openOut if(-e $outputFile);
    open(OUT, $openOut) or &_die("Unable to open output file $outputFile ($!) [$openOut]");
    print OUT "$cmd\n";
    print OUT "@{$retval->{std}}\n";
    close(OUT);

    #Return the info about the cmsearch run
    return $retval;
}


#Name: _pod
#Desc: Because I'm too lazy to put this line twice.
#Args: none
#Rets: none
sub _pod {
    pod2usage( {-exitval => 0, -verbose => 2, -output => \*STDERR} );
}

#Name: _die
#Desc: Because I'm too lazy to write $logger->logdie(blah) everywhere
#Args: Scalar: The program's last words
#Rets: Nothing, this function will never exit successfully. Shame...
sub _die {
    my $msg = shift;
    &cleanUp;
    $logger->logdie($msg);
}
##EOF
