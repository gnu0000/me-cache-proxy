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
my $RequestDir  = "Requests";
my $ResponseDir = "Responses";
my $ReplayDir   = "Replays";

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

   opendir DIR, $RequestDir;
   my @names = sort readdir DIR;
   closedir DIR;

   for (@names)
      {
      next unless m/^\d{4}-\d{2}-\d{2}-\d{2}-\d{2}-\d{2}\.txt$/i;
      last unless $Request = LoadRequest ("$RequestDir/$_");
      print STDERR "Loaded request:\n". $Request->as_string() .".\n\n"; #debug stuff
      $Response = ForwardRequestAndGetResponse ($Request);
      print STDERR "response:\n". ($Response->is_success() ? "Success" : $Response->error_as_HTML()) ."\n"; #debug stuff
      SaveResponse ("$ReplayDir/$_", $Response);
      }
   print STDERR "Connection closed.\n"; #debug stuff
   }


# Load request from disk
#
sub LoadRequest
   {
   my ($RequestFile) = @_;
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


#sub DumpData
#   {
#   my ($FileName, @Stuff) = @_;
#
#   $Data::Dumper::Indent = 1;
#   $Data::Dumper::Terse  = 1;
#   open (FILE, "> $FileName") or die "Cannot open file $FileName.";
#   print FILE Dumper (@Stuff) . "\n";
#   close FILE;
#   }

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


my @Headers;

sub SaveResponse
   {
   my ($FileName, $Response) = @_;

   open FILE, ">$FileName" or die "Cannot open file $FileName.";

   print FILE "Status: " . $Response->status_line . "\n";
   @Headers = ();
   $Response->scan(\&record_header);
   foreach (sort @Headers)
      {print FILE $_, "\n";}
   print FILE "\n";

   my $Message = $Response->content;
   print FILE $Message, "\n";

   close FILE;
   }


sub record_header
   {
   my ($Name, $Value) = @_;
   push @Headers, "$Name: $Value";
   }