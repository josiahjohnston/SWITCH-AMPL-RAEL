#!/usr/bin/perl
#
# This script executes a command from a list of files based on the current MPI id.

# call getid to get the MPI id number
use strict;

my ($worker_id, $numprocs, $jobs_file );
if ( scalar(@ARGV) == 3 ) {
  ($jobs_file, $worker_id, $numprocs) = @ARGV;
} else {
  $jobs_file = $ARGV[0];
  ($worker_id, $numprocs) = split(/\s+/,`getid`);
}

my $hostname = `hostname`;
chomp $hostname;

# open file and execute appropriate command
open (INPUT_FILE, $jobs_file) or &showhelp;

my $job_commands;
my $line_num = 0;
while( $job_commands = <INPUT_FILE> ) {
	chomp $job_commands;
	$line_num++;
	if( ( $line_num % $numprocs ) == $worker_id ) {
		print "executing job # $line_num with worker $worker_id of $numprocs running on $hostname.\n\t$job_commands\n";
		system($job_commands);
	}
}

close INPUT_FILE;


sub showhelp
{
	print "\nUsage: execute_jobs.pl <filename>\n\n";
	print "<filename> should contain a list of executables, one-per-line, including the path.\n\n";
}

system("ampl_lic stop;");
