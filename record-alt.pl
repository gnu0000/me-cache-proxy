#!/perl/bin/perl -w
#
# TrnsPort TestSuite Relay prototype
#  ver  0.01  01/29/03
#  Charles Engelke
#  Craig Fitzgerald
#
# This program records conversations between HTTP clent and Server
# Point client to this daemon, config this daemon to forward to server
# requests and responses are streamed to disk as 
#    Storable::fd_retrieve readable, HTTP::Request and HTTP::Response objects
# This sample currently emits debug output to stderr
#

use LWP::UserAgent;
use HTTP::Daemon;
use HTTP::Status;
use URI;
use strict;
use Data::Dumper;

# used as constants
my $RequestFilePrefix  = "Requests/";
my $ResponseFilePrefix = "Responses/";

# Main
#########################
MAIN:
   $|++;

   mkdir "requests", 777 unless -d "requests";
   mkdir "responses", 777 unless -d "responses";
   mkdir "replays", 777 unless -d "replays";

   my $DaemonPort = 80;
   my $ServerHost = "w2kdb.infotechfl.com";
   my $ServerPort = 8889;
   Monitor ($DaemonPort, $ServerHost, $ServerPort);
   exit (0);
#########################
# END of main


# do the actual work
# loop forever:
#  block-wait on a connection from a client
#  loop until connection is done
#   get client request, store it, forward to server
#   get server response, store it, forward to client
sub Monitor 
   {
   my ($DaemonPort, $ServerHost, $ServerPort) = @_;
   my ($Request, $Response);
   my $Daemon = HTTP::Daemon->new (LocalPort => $DaemonPort) or die "Couldn't create daemon on port $DaemonPort.";

   for (my $RequestIdx=1; ; ) # loop forever on connections
      {
      print STDERR "Accepted new connection.\n"; #debug stuff
      for (my $Connection=$Daemon->accept(); $Request=GetRequest ($Connection); $RequestIdx++)
         {
         my ($sec, $min, $hr, $mday, $mon, $year) = localtime time;
         my $filename = sprintf "%04d-%02d-%02d-%02d-%02d-%02d.txt", $year, $mon+1, $mday, $hr, $min, $sec;
         print STDERR "Accepted request:\n". $Request->as_string() .".\n\n"; #debug stuff

         ModifyRequest ($Request, $ServerHost, $ServerPort);
         print STDERR "Modified request:\n". $Request->as_string() .".\n\n"; #debug stuff

         DumpData ("$RequestFilePrefix$filename", $Request); # Store request to disk

         $Response = ForwardRequestAndGetResponse ($Request);
         print STDERR "response:\n". ($Response->is_success() ? "Success\n" : $Response->error_as_HTML()) ."\n"; #debug stuff

         SaveResponse ("$ResponseFilePrefix$filename", $Response); # Store response to disk

         ForwardResponse ($Connection, $Response);
         $Connection->shutdown(2);   # Fixes IE keep-alive bug?  YES!

         sleep(1);
         }
      print STDERR "Connection closed.\n"; #debug stuff
      }
   }

# Get request from client
#
sub GetRequest
   {
   my ($Connection) = @_;
   my $Request = $Connection->get_request();
   return $Request;
   }

# change headers so we can forward the request
#
sub ModifyRequest
   {
   my ($Request, $ServerHost, $ServerPort) = @_;
   $Request->header (Host => $ServerHost . ":" . $ServerPort);
   $Request->header (User_Agent => "TrnsPort TestSuite-Relay/1.0");
   $Request->remove_header ("If-Modified-Since");
   $Request->remove_header ("If-None-Match");
   $Request->remove_header ("Connection");   # Try to avoid IE keep-alive bug.  No joy.
   my $URI = $Request->uri();
   $URI->scheme("http");
   $URI->host($ServerHost);
   $URI->port($ServerPort);
   }


# Forward request to server
# Get response from server
my $Agent;
sub ForwardRequestAndGetResponse
   {
   my ($Request) = @_;
   $Agent = LWP::UserAgent->new() unless $Agent;
   my $Response = $Agent->send_request($Request);
   }


# Forward response to client
#
sub ForwardResponse
   {
   my ($Connection, $Response) = @_;
   $Connection->send_response($Response);
   }

# 
#
sub DumpData
   {
   my ($FileName, @Stuff) = @_;

   $Data::Dumper::Indent = 1;
   $Data::Dumper::Terse  = 1;
   open (FILE, "> $FileName") or die "Cannot open file $FileName.";
   print STDERR "Writing file $FileName\n";
   print FILE Dumper (@Stuff) . "\n";
   close FILE;
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
