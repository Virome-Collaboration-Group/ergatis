#!/usr/local/bin/perl
use lib (@INC,$ENV{"PERL_MOD_DIR"});
no lib "$ENV{PERL_MOD_DIR}/i686-linux";
no lib ".";

=head1 NAME

ps_scan2bsml.pl - Formats prosite scan output into bsml format.

=head1 SYNOPSIS

USAGE: template.pl
            --input_file=/path/to/some/transterm.raw
            --output=/path/to/transterm.bsml
            --project=aa1
            --analysis_id=ps_scan
            --id_repository=/some/id_repository/dir
          [ --log=/path/to/file.log
            --debug=4
            --help
          ]

=head1 OPTIONS

B<--input_file,-i>
    The input file (should be prosite scan output)

B<--output,-o>
    Where the output bsml file should be

B<--project,-p>
    Used in id generation.  It's the first token in the id.  (Ex. project.class.number.version)

B<--analysis_id,-a>
    Analysis id.  Should most likely by ps_scan_analysis.

B<--id_repository,-r>
    Used to make the ids (See Workflow::IdGenerator for details)

B<--log,-l>
    In case you wanted a log file.

B<--debug,-d>
    There are no debug statements in this program.  Sorry.

B<--help,-h>
    Displays this message.

=head1  DESCRIPTION

    Reads ps_scan output file and turns it into BSML.  Generates BSML with Sequence Pair Alignment and 
    Sequence Pair Run elements with polypeptide and prosite_entry class elements.

=head1  INPUT

    The raw output of ps_scan.  That is, the default output without using the -o option
    for ps_scan.pl.

=head1  OUTPUT

    Generates a BSML document representing the ps_scan matches.

=head1  CONTACT

    Kevin Galens
    kgalens@tigr.org

=cut

use strict;
use warnings;
use Getopt::Long qw(:config no_ignore_case no_auto_abbrev pass_through);
use Pod::Usage;
use BSML::BsmlBuilder;
use Workflow::Logger;
use Workflow::IdGenerator;
use Data::Dumper;

####### GLOBALS AND CONSTANTS ###########
my $inputFile;
my $project;
my $output;
my $debug;
my $analysis_id;
my $idMaker;
my $fasta_file;
########################################

my %options = ();
my $results = GetOptions (\%options, 
                          'input_file|i=s',
                          'output|o=s',
                          'project|p=s',
                          'analysis_id|a=s',
                          'id_repository|r=s',
                          'fasta_file|f=s',
                          'log|l=s',
                          'debug=s',
                          'help|h') || &_pod;

#Setup the logger
my $logfile = $options{'log'} || Workflow::Logger::get_default_logfilename();
my $logger = new Workflow::Logger('LOG_FILE'=>$logfile,
				  'LOG_LEVEL'=>$options{'debug'});
$logger = $logger->get_logger();

# Check the options.
&check_parameters(\%options);

my $data = &parsePs_scanData($inputFile);
my $bsml = &generateBsml($data);
$bsml->write($output);

exit(0);

######################## SUB ROUTINES #######################################
sub parsePs_scanData {
    my $file = shift;
    my $retHash;
    my ($seq, $prosite);

    #Open the file (should be default output from ps_scan run).
    open(IN, "<$file") or 
        &_die("Unable to open ps_scan raw file input ($file) : $!");

    while(<IN>) {

        if(/^>(.*)\s:(.*)$/) {
            print $_;
            $seq = $1;
            $seq =~ s/\s+//g;
            $prosite = $2;

            &_die("prosite ($prosite) or seq ($seq) was not set\n") unless($prosite && $seq);
        } else {
            my @tmp = split(/[\s\t]+/);

            if($tmp[1] > $tmp[3]) {
                $tmp[0] = 1;
                ($tmp[1], $tmp[3]) = ($tmp[3], $tmp[1]);
            } else {
                $tmp[0] = 0;
            }

            my $match = { 'start'  => $tmp[1]-1,
                          'stop'   => $tmp[3]-1,
                          'strand' => $tmp[0],
                          'match'  => $tmp[4] };

            push(@{$retHash->{$seq}->{$prosite}}, $match);
        }

    }

    return $retHash;

}

sub generateBsml {
    my $data = shift;
    my $seqObj;

    my $doc = new BSML::BsmlBuilder();

    foreach my $seq(keys %{$data}) {
        
        #Create the seq object
        $seqObj = $doc->createAndAddSequence($seq, $seq, '', 'aa', 'polypeptide');
        $doc->createAndAddLink($seqObj, 'analysis', '#'.$analysis_id.'_analysis', 'input_of');
        $doc->createAndAddSeqDataImport($seqObj, 'fasta', $fasta_file, '', $seq);

        foreach my $proDomain(keys %{$data->{$seq}}) {

            #Create another seq object.
            my ($proId, $title) = ($1, $2) if($proDomain =~ /(\w+)\s(.*)/);
            &_die("Could not parse id and title from prosite domain id line in raw output")
                unless($proId && $title);
            my $proSeq = $doc->createAndAddSequence($proId, $title,  '', 'aa', 'prosite_entry');

            my %spaArgs = ( 'refseq'  => $seqObj->{'attr'}->{'id'},
                            'compseq' => $proSeq->{'attr'}->{'id'},
                            'restart' => 0,
                            'class'   => 'match' );

            my $spaObj = $doc->createAndAddSequencePairAlignment(%spaArgs);

            foreach my $match (@{$data->{$seq}->{$proDomain}}) {
                
                my %sprArgs = ( 'alignment_pair' => $spaObj,
                                'refpos'         => $match->{'start'},
                                'runlength'      => $match->{'stop'} - $match->{'start'},
                                'refcomplement'  => $match->{'strand'},
                                'comppos'        => 0,
                                'comprunlength'  => length($match->{'match'}),
                                'compcomplement' => 0,
                                'class'          => 'match_part'
                                );   

                my $sprObj = $doc->createAndAddSequencePairRun(%sprArgs);
            }


        }
        


    }
    $doc->createAndAddAnalysis( 'id' => $analysis_id,
                                'sourcename' => $output );

    return $doc;
}

sub check_parameters {
    my $options = shift;

    my $error = "";

    &_pod if($options{'help'});

  
    if($options{'input_file'}) {
        $error .= "Option input_file ($options{'input_file'}) does not exist\n" unless(-e $options{'input_file'});
        $inputFile = $options{'input_file'};
    } else { 
        $error .= "Option input_file is required\n";
    }

    unless($options{'output'}) {
        $error .= "Option output is required\n";
    } else {
        $output = $options{'output'};
    }

    unless($options{'project'}) {
        $error .= "Option project is required\n";
    } else {
        $project = $options{'project'};
    }

    unless($options{'analysis_id'}) {
        $error .= "Option analysis_id is required\n";
    } else {
        $analysis_id = $options{'analysis_id'};
    }
    
    unless($options{'id_repository'}) {
        $error .= "Option id_repository is required\n";
    } else {
        $idMaker = new Workflow::IdGenerator( 'id_repository' => $options{'id_repository'});
        #$idMaker->set_pool_size( 
    }

    unless($options{'fasta_file'}) {
        $error .= "Option fasta_file is required\n";
    } else {
        $fasta_file = $options{'fasta_file'};
    }
    
    if($options{'debug'}) {
        $debug = $options{'debug'};
    }
    
    unless($error eq "") {
        &_die($error);
    }
    
}

sub _pod {   
    pod2usage( {-exitval => 0, -verbose => 2, -output => \*STDERR} );
}

sub _die {
    my $msg = shift;
    $logger->logdie($msg);
}
