#!/usr/bin/perl

eval 'exec /local/packages/perl-5.8.8/bin/perl  -S $0 ${1+"$@"}'
    if 0; # not running under some shell
BEGIN{foreach (@INC) {s/\/usr\/local\/packages/\/local\/platform/}};
use lib (@INC,$ENV{"PERL_MOD_DIR"});
no lib "$ENV{PERL_MOD_DIR}/i686-linux";
no lib ".";

=head1  NAME 

rename_signalp_graphics_output.pl - renames gif, eps, ps, and gnu output files

=head1 SYNOPSIS

USAGE: signalp_graphics_rename.pl 
        --input_path=/path/to/signalp/output_dir 
        --output_path=/path/to/output/destination
        --output_prefix=OUTPUT_FILE_PREFIX
        --log=/path/to/some.log
        --debug=4

=head1 OPTIONS

B<--input_path,-p> 
    The path to directory containing signalp created graphics files.

B<--output_prefix,-o>
    Desired file prefix of the set of signalp graphics files.
    
B<--debug,-d> 
    Debug level.  Use a large number to turn on verbose debugging. 

B<--log,-l> 
    Log file

B<--help,-h> 
    This help message

=head1   DESCRIPTION

This script is used by the signalp workflow component to rename signalp graphics output files (gnu, gif, eps, ps) so that they do not overwrite each other, and to make them conform with naming standards.

=head1 INPUT

The script should be provided an input directory with the --path flag.
This directory should be equivalent to whatever directory was passed to
signalp with *signalp's* -d/-destination flag.

The output file prefix should be provided with the --output_prefix flag.
Omitting this flag would serve no conceivable purpose, but will not kill
the script.

=head1 OUTPUT

The script will modify and/or rename the following graphics-related files
that are produced by signalp if they are found in the directory specified
with the --path flag:

plot.gnu    --> SPECIFIED_PREFIX.gnu
plot.ps     --> SPECIFIED_PREFIX.ps
plot.hmm.X.eps  --> SPECIFIED_PREFIX.hmm.SEQUENCE_ID.eps
plot.hmm.X.gif  --> SPECIFIED_PREFIX.hmm.SEQUENCE_ID.gif
plot.nn.X.eps   --> SPECIFIED_PREFIX.nn.SEQUENCE_ID.eps
plot.nn.X.gif   --> SPECIFIED_PREFIX.nn.SEQUENCE_ID.gif

Where X is an integer from 1 to N representing the number of the input sequence
within a multi-sequence FASTA file provided to signalp as input.

All original eps/gif/ps files are generated by signalp from the plot.gnu file.
SPECIFIED_PREFIX.gnu is modified by this script so that it will generate output
files with the new names generated by this script.

=head1 CONTACT

    Brett Whitty
    bwhitty@tigr.org

=cut    

## MODIFIED on 12/07/2005
## Added END block to prevent problems when script is killed and rerun.
## If script is interrupted, we will delete any output files that
## were created, leaving the input files untouched.
## Otherwise, if it runs to completion we will remove the input files.
## *** THIS MAY CAUSE A PROBLEM *** if for some reason output from two 
## concurrent signalp runs are written to the same directory in the
## meantime.

use strict;
use Getopt::Long qw(:config no_ignore_case no_auto_abbrev);
use Pod::Usage;
use File::Copy;
use Ergatis::Logger;

my %options = ();
my $results = GetOptions (\%options,
              'input_path|p=s',
              'output_path=s',
              'output_prefix|o=s',
              'log|l=s',
              'debug=s',
              'help|h') || pod2usage();

my $logfile = $options{'log'} || Ergatis::Logger::get_default_logfilename();
my $logger = new Ergatis::Logger('LOG_FILE'=>$logfile,
				  'LOG_LEVEL'=>$options{'debug'});
$logger = Ergatis::Logger::get_logger();

## display documentation
if( $options{'help'} ){
    pod2usage( {-exitval=>0, -verbose => 2, -output => \*STDERR} );
}

&check_parameters(\%options);

my $inprefix = 'plot';
my $insuffix = 'gnu';
my $infile = $inprefix.'.'.$insuffix;
my $path_to_files = $options{'input_path'};
my $path_to_output = $options{'output_path'};
my $outprefix = $options{'output_prefix'};

my @input_files;
my @output_files;

unless ($path_to_files =~ /\/$/) {
    $path_to_files .= '/';
}
unless ($path_to_output =~ /\/$/) {
    $path_to_output .= '/';
}

open (my $in, $path_to_files.$infile) || $logger->logdie("failed opening '$infile'");
push(@input_files, $path_to_files.$infile);
open (my $out, ">".$path_to_output.$outprefix.".gnu") || $logger->logdie("failed opening $path_to_output.$outprefix.gnu for writing");
push(@output_files, $path_to_output.$outprefix.".gnu"); 

my $counter = 0;
my $sequence_id = '';

while (<$in>) {
    my $line = $_;
    if (/^set title.*: ([^"]+)/) {
        $sequence_id = $1;
            $logger->debug("recognized a plot for a sequence called '$sequence_id' in $infile") if ($logger->is_debug);
    }
    if (/^set output.*$inprefix.ps"/) {
            $logger->debug("found reference to '$inprefix.ps' in $infile") if ($logger->is_debug);
#}
        $line =~ s/$inprefix.ps/$outprefix.ps/;
        print $out $line;
        if (-e $path_to_files."$inprefix.ps") {
                $logger->debug("$inprefix.ps exists") if ($logger->is_debug);
            open (my $psin, $path_to_files."$inprefix.ps") || die "couldn't open \"$inprefix.ps\" for reading\n";
            push(@input_files, $path_to_files."$inprefix.ps");
                $logger->debug("$inprefix.ps was opened for reading") if ($logger->is_debug);
            open (my $psout, ">".$path_to_output.$outprefix.".ps") || $logger->logdie("couldn't open '$path_to_output$outprefix.ps' for writing");
            push(@output_files, $path_to_output.$outprefix.".ps");
                $logger->debug("$path_to_output$outprefix.ps was opened for writing") if ($logger->is_debug);
            while (my $ps_line = <$psin>) {
                if ($ps_line =~ /$inprefix.ps/) {
                    $ps_line =~ s/$inprefix.ps/$outprefix.ps/;
                        $logger->debug("found reference to '$inprefix.ps' within $inprefix.ps and modified in $outprefix.ps") if ($logger->is_debug);
                }
                print $psout $ps_line;
            }
            close $psin;
            close $psout;
        } else {
                $logger->debug("'$inprefix.ps' is missing. probably wasn't created; not gonna get upset about it.") if ($logger->is_debug);
        }
    }
    if (/^set output.*plot.([^\.]+).(\d+).([a-z]+)/) {
        my $analysis = $1;
        $counter = $2;
        my $extension = $3;
            $logger->debug("'plot.$analysis.$counter.$extension' will be renamed to '$outprefix.$analysis.$counter.$extension'") if ($logger->is_debug);
        $line =~ s/plot.$analysis.$counter.$extension/$outprefix.$analysis.$counter.$extension/;
        print $out $line;
        if ($extension eq 'eps' && -e $path_to_files."plot.$analysis.$counter.$extension") {
                $logger->debug("'plot.$analysis.$counter.$extension' exists") if ($logger->is_debug);
            open (my $epsin, $path_to_files."plot.$analysis.$counter.$extension") || $logger->logdie("couldn't open 'plot.$analysis.$counter.$extension' for reading");
            push(@input_files, $path_to_files."plot.$analysis.$counter.$extension"); 
                $logger->debug("'plot.$analysis.$counter.$extension' was opened for reading") if ($logger->is_debug);
                open (my $epsout, ">".$path_to_output."$outprefix.$analysis.$counter.$extension") || $logger->logdie("couldn't open '$outprefix.$analysis.$counter.$extension' for writing");
            push(@output_files, $path_to_output."$outprefix.$analysis.$counter.$extension");
                $logger->debug("'$outprefix.$analysis.$counter.$extension' was opened for writing") if ($logger->is_debug);
            while (my $eps_line = <$epsin>) {
                if ($eps_line =~ /plot.$analysis.$counter.$extension/) {
                    $eps_line =~ s/plot.$analysis.$counter.$extension/$outprefix.$analysis.$counter.$extension/;
                        $logger->debug("found self-reference in 'plot.$analysis.$counter.$extension' and modified to '$outprefix.$analysis.$counter.$extension'") if ($logger->is_debug);
                }
                print $epsout $eps_line;
            }
            close $epsin;
            close $epsout;
                $logger->debug("'$outprefix.$analysis.$counter.$extension' wrote successfully") if ($logger->is_debug);
        } elsif (-e $path_to_files."plot.$analysis.$counter.$extension") {
            copy($path_to_files."plot.$analysis.$counter.$extension",$path_to_output."$outprefix.$analysis.$counter.$extension") || $logger->logdie("couldn't rename 'plot.$analysis.$counter.$extension' to '$outprefix.$analysis.$counter.$extension'");
            push(@input_files, $path_to_files."plot.$analysis.$counter.$extension");
            push(@output_files, $path_to_output."$outprefix.$analysis.$counter.$extension");
                $logger->debug("renamed 'plot.$analysis.$counter.$extension' to '$outprefix.$analysis.$counter.$extension'") if ($logger->is_debug);
        } else {
            $logger->logdie("'plot.$analysis.$counter.$extension' is referenced in '".$path_to_files."$infile' but does not exist");
        }
    } else {
        print $out $line;
    }
}
close $in;
close $out;
$logger->debug("processing of '$infile' completed without error") if ($logger->is_debug);
$logger->debug("'$infile' referenced a total of *$counter* distinct sequences") if ($logger->is_debug);
$logger->debug("'$infile' has been renamed to '$outprefix.$insuffix'") if ($logger->is_debug);

if ($counter > 1) {
    $logger->debug("'$infile' contains more than 1 fasta record") if ($logger->is_debug);
}

my $run_complete = 1;
exit(0);

sub check_parameters{
    my ($options) = @_;
    
    if ($options{'input_path'} eq ""){
        pod2usage({-exitval => 2,  -message => "--input_path option missing", -verbose => 1, -output => \*STDERR});    
    }
    if ($options{'output_path'} eq ""){
        pod2usage({-exitval => 2,  -message => "--output_path option missing", -verbose => 1, -output => \*STDERR});    
    }
    
    if ($options{'output_prefix'} eq ""){
        pod2usage({-exitval => 2,  -message => "--output_prefix option missing", -verbose => 1, -output => \*STDERR});    
    }
    
    ## make sure the input path exists
    if (! -d $options{'input_path'}){
        $logger->logdie("input path $options{input_path} doesn't exist");
    }
    

    ## make sure the input path exists
    if (! -d $options{'output_path'}){
        $logger->logdie("output path $options{output_path} doesn't exist");
    }
    
}

END {

    ## Clean up input files if the run completed successfully
    if ($run_complete) {
#        foreach my $infile(@input_files) {
#            unlink($infile);    
#        }
    } else {
    ## Otherwise, remove whatever output files were created.
#        foreach my $outfile(@output_files) {
#            unlink($outfile);
#        }
    }   
}
