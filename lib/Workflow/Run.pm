package Workflow::Run;

# $Id$

# Copyright (c) 2002, The Institute for Genomic Research. All rights reserved.

=head1 NAME

Run.pm - A module for building workflow instances

=head1 VERSION

This document refers to version $Name$ of frontend.cgi, $Revision$. 
Last modified on $Date$

=head1 SYNOPSIS



=head1 DESCRIPTION

=head2 Overview


=over 4

=cut


use strict;
use Workflow::Logger;
use Data::Dumper;

=item new

B<Description:> The module constructor.

B<Parameters:> %arg, a hash containing attribute-value pairs to
initialize the object with. Initialization actually occurs in the
private _init method.

my $builder = new Workflow::Builder('NAME'=>'blastp', #verbose debugging
				    'REPOSITORY_ROOT'=>'/usr/local/annotation',
				    'DATABASE'=>'tryp'
				    );

B<Returns:> $self (A Workflow::Builder object).

=cut

sub new {
    my ($class) = shift;
    my $self = bless {}, ref($class) || $class;
    $self->{_logger} = Workflow::Logger::get_logger(__PACKAGE__);
    $self->_init(@_);
    return $self;
}


=item $obj->_init([%arg])

B<Description:> Tests the Perl syntax of script names passed to it. When
testing the syntax of the script, the correct directories are included in
in the search path by the use of Perl "-I" command line flag.

B<Parameters:> %arg, a hash containing attributes to initialize the testing
object with. Keys in %arg will create object attributes with the same name,
but with a prepended underscore.

B<Returns:> None.

=cut

sub _init {
    my $self = shift;
    $self->{_WORKFLOW_EXEC_DIR} = "$ENV{'WORKFLOW_WRAPPERS_DIR'}" || ".";
    $self->{_WORKFLOW_CREATE_EXEC} = "CreateWorkflow.sh";
    $self->{_WORKFLOW_RUN_EXEC} = "RunWorkflow.sh";
    $self->{_nodistrib} = 0;

    my %arg = @_;
    foreach my $key (keys %arg) {
        $self->{"_$key"} = $arg{$key}
    }
}

sub CreateWorkflow{
    my($self,$instance, $ini, $template, $log, $outfile) = @_;
    if($self->{_nodistrib} == 1){
	$template = $self->_replacedistrib($template,"$outfile.template.nodistrib");
    }
    my $execstr = "$self->{_WORKFLOW_EXEC_DIR}/$self->{_WORKFLOW_CREATE_EXEC} -t $template -c $ini -i $instance -l $log -o $outfile > $outfile";
    $self->{_logger}->debug("Exec via system: $execstr") if ($self->{_logger}->is_debug());
    my $debugstr = "";
    if($self->{_logger}->is_debug()){
	$debugstr = "-v 6";
    }
    my $ret = system("$execstr $debugstr");
    $ret >>= 8;
    return $ret;
}

sub RunWorkflow{
    my($self,$instance, $log, $outfile) = @_;
    my $execstr = "$self->{_WORKFLOW_EXEC_DIR}/$self->{_WORKFLOW_RUN_EXEC} -i $instance -l $log -o $outfile > $outfile";
    $self->{_logger}->debug("Exec via system: $execstr") if ($self->{_logger}->is_debug());
    my $debugstr = "";
    if($self->{_logger}->is_debug()){
	$debugstr = "-v 6";
    }
    my $ret = system("$execstr $debugstr");
    $ret >>= 8;
    return $ret;
}

sub _replacedistrib{
    my($self,$file,$outputfile) = @_;
    open( FILEIN, "$file" ) or $self->{_logger}->logdie("Could not open file $file");
    open( FILEOUT, "+>$outputfile") or $self->{_logger}->logdie("Could not open output file $outputfile");
    
    while( my $line = <FILEIN> ){
	$line =~ s/Distributed/Unix/g;
	print FILEOUT $line;
    }
    close FILEIN;
    close FILEOUT;
    return $outputfile;
}

1;
