#!/perl/bin/perl -w

use LWP::UserAgent;
use Storable qw(store retrieve);
use strict;

#########################
MAIN:
	my %Data;
	$Data{a} = 'a';
	$Data{b} = 'b';
	my $A	= \%Data;
	my $File = "a.o";
   store $A, $File;
   my $B = retrieve ($File);
   
   print "B->{a} = $B->{a}\n";
   print "B->{b} = $B->{b}\n";

   exit (0);
#########################
