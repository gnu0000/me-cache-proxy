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
my $RequestFilePrefix  = "Request_";
my $ResponseFilePrefix = "Response_";

# Main
#########################
MAIN:
   $|++;

   my $DaemonPort = 8889;
   my $ServerHost = "demo3.infotechfl.com";
   my $ServerPort = 80;
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
         print STDERR "Accepted request:\n". $Request->as_string() .".\n\n"; #debug stuff

         ModifyRequest ($Request, $ServerHost, $ServerPort);
         print STDERR "Modified request:\n". $Request->as_string() .".\n\n"; #debug stuff

         DumpData (sprintf ("$RequestFilePrefix%3.3d.dat", $RequestIdx), $Request); # Store request to disk

         $Response = ForwardRequestAndGetResponse ($Request);
         print STDERR "response:\n". ($Response->is_success() ? "Success\n" : $Response->error_as_HTML()) ."\n"; #debug stuff

         DumpData (sprintf ("$ResponseFilePrefix%3.3d.dat", $RequestIdx), $Response); # Store response to disk

         ForwardResponse ($Connection, $Response);
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
