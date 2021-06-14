#!/perl/bin/perl -w
#
# TrnsPort TestSuite Replay prototype
#  ver  0.01  01/29/03
#  Charles Engelke
#  Craig Fitzgerald
#
#

use LWP::UserAgent;
use HTTP::Daemon;
use HTTP::Status;
use URI;
use URI::http;
#use Storable qw(store retrieve);
use Data::Dumper;
use strict;

# used as constants
my $RequestFilePrefix  = "Request_";
my $ResponseFilePrefix = "Replay_";

my $Agent;

# Main
#########################
MAIN:
   $|++;

   Play ();
   exit (0);
#########################
# END of main


# do the actual work
# 
sub Play
   {
   my ($Request, $Response, $RequestIdx);

   # This needs to be done before data load because of side effects
   $Agent = LWP::UserAgent->new() unless $Agent;

   for ($RequestIdx=1; ; $RequestIdx++)
      {
      last unless $Request = LoadRequest ($RequestIdx);
      print STDERR "Loaded request:\n". $Request->as_string() .".\n\n"; #debug stuff
      $Response = ForwardRequestAndGetResponse ($Request);
      print STDERR "response:\n". ($Response->is_success() ? "Success" : $Response->error_as_HTML()) ."\n"; #debug stuff
      StoreResponse ($Response, $RequestIdx);
      }
   print STDERR "Connection closed.\n"; #debug stuff
   }


# Load request from disk
#
sub LoadRequest
   {
   my ($RequestIdx) = @_;
   my $RequestFile = sprintf ("$RequestFilePrefix%3.3d.dat", $RequestIdx);
   return if !-e $RequestFile;
   my $Request = LoadData ($RequestFile);
   return $Request;
   }

# Forward request to server
# Get response from server
sub ForwardRequestAndGetResponse
   {
   my ($Request) = @_;
   my $Response = $Agent->send_request($Request);
   }

# Store response to disk
#
sub StoreResponse
   {
   my ($Response, $RequestIdx) = @_;
   my $ResponseFile = sprintf ("$ResponseFilePrefix%3.3d.dat", $RequestIdx);
   DumpData ($ResponseFile, $Response);
   return $ResponseFile;
   }


sub DumpData
   {
   my ($FileName, @Stuff) = @_;

   $Data::Dumper::Indent = 1;
   $Data::Dumper::Terse  = 1;
   open (FILE, "> $FileName") or die "Cannot open file $FileName.";
   print FILE Dumper (@Stuff) . "\n";
   close FILE;
   }

sub LoadData
   {
   my ($FileName) = @_;
   local ($/);
   undef $/;
   open (FILE, "< $FileName") or die "Cannot open file $FileName.";
   my $Data = <FILE>;
   close FILE;
   my $Stuff = eval $Data;
   return $Stuff;
   }