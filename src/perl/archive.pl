#!/usr/local/bin/perl

=head1  NAME 

dummy.pl - do nothing

=head1 SYNOPSIS

USAGE:  dummy.pl --debug debug_level --log log_file

=head1 OPTIONS

=item *

B<--debug,-d> Debug level.  Use a large number to turn on verbose debugging. 

=item *

B<--log,-l> Log file

=item *

B<--help,-h> This help message

=back

=head1   DESCRIPTION

=cut


use strict;
use Getopt::Long qw(:config no_ignore_case no_auto_abbrev);
use Pod::Usage;
use Workflow::Logger;

my %options = ();
my $results = GetOptions (\%options,
			  'file|f=s',
			  'directory|d=s',
			  'nodelete|n',
			  'log|l=s',
			  'debug=s',
			  'help|h') || pod2usage();

my $logfile = $options{'log'} || Workflow::Logger::get_default_logfilename();
my $logger = new Workflow::Logger('LOG_FILE'=>$logfile,
				  'LOG_LEVEL'=>$options{'debug'});
$logger = Workflow::Logger::get_logger();

# display documentation
if( $options{'help'} ){
    pod2usage( {-exitval=>0, -verbose => 2, -output => \*STDERR} );
}

&check_parameters(\%options);

print `tar cvzf $options{'file'} $options{'directory'}`;


sub check_parameters{
    my ($options) = @_;
    
    if($options{'directory'} eq ""){
	pod2usage({-exitval => 2,  -message => "--directory option missing", -verbose => 1, -output => \*STDERR});    
    }
    if($options{'file'} eq ""){
	pod2usage({-exitval => 2,  -message => "--file option missing", -verbose => 1, -output => \*STDERR});    
    }
    if(! (-d $options{'directory'})){
	$logger->warn("Invalid directory $options{'directory'}. Skipping execution");
	exit;
    }
}
