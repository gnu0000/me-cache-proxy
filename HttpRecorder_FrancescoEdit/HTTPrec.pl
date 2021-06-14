#!/usr/bin/perl -w
#^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
# HTTPrec.pl
# HTTP Record tool
# v.0.30, 22-FEB-2k3
#^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
#
# History:
# v.0.10	
#		First Prototype, by Charles Engelke and Craig Fitzgerald.
#
# v.020	20-FEB-2k3
#		Intermediary version.
#
# v.0.30	22-FEB-2k3
#		Second Prototype, by Frank Rizzi.
#		The HTTPrec tool now behaves as follows:
#		The tool is started and runs as a Daemon; it check the
#		content of the configuration file (the name of the file
#		is stored in the $CFG_FN file-scoped variable) for the
#		following parameters:
#		HTTPREC_HOST:the name of the machine where the HTTPrec
#				 tool is running;
#		CLIENT_PORT: the port for communications with the client
#				 machine running the baseline test;
#		SERVER_HOST: the name of the baseline server;
#		SERVER_PORT: the port for communications with the baseline
#				 server;
#		HTTPREC_CMD_PREFIX: the prefix common to all of the
#				 commands that the HTTPrec tool should
#				 recognize (Note: it is recommended that
#				 this prefix is unique, and it should NOT
#				 include a final '?').
#		(all of the parameters should be in the name=value
#		format in the configuration file).
#		The configuration file is assmued to be avilable in the
#		same directory where the HTTPrec tool is running;
#		alternatively, the $CFG_FN variable can include the
#		relative path to reach the configuration file from this
#		location.
#		Once started, the HTTPrec tool listens for communications
#		over the CLIENT_PORT port. It recognizes any incoming
#		communication directed to
#		http://<HTTPREC_HOST>:<CLIENT_PORT>/<HTTREC_CMD_PREFIX>
#		as command directed to the HTTPrec tool. The list of
#		legal commands includes (the common prefix is not listed
#		below):
#
#		~ cmd=menu
#		A request to access the menu page for the HTTPrec tool;
#
#		~ cmd=start&file=<filename>
#		A request to start a new recording, using file <filename>
#		to save the recorded events;
#
#		~ cmd=stop&file=<filename>
#		A request to stop the ongoing recording that is using
#		file <filename>;
#
#		~ cmd=list
#		A request tolist all of the available recoding files;
#
#		~ cmd=fetch&file=<filename>
#		A request to fetch the content of the recording file
#		<filename>
#
#		Any communication detected with the common prefix
#		http://<HTTPREC_HOST>:<CLIENT_PORT>/<HTTREC_CMD_PREFIX>
#		not matching one of these commands is considered an
#		un-recognized command, and will prompt the HTTPrec tool
#		to diaply its menu page (with an appropriate error message).
#		Any communication detected on the CLIENT_PORT without the
#		common prefix (in particular, lacking the
#		<HTTREC_CMD_PREFIX> portion) will be considered as a simple
#		communication from the Client machine. These communications
#		will be recorded, and redirected to the server machine if
#		the HTTPrec tool is currently in recording mode.
#		Other erroneous conditions will be detected and reported
#		to the client machine (such as a command lacking the
#		required parameteres, a request to start a recording while
#		the tool is already recording, a request to fetch a non
#		existing file, a request to stop a recording while the tool
#		is not recording, or a request to stop a recording with the
#		file parameter not matching the name of the file currently
#		in use for an ongoing recording).
#
#		While recording, the HTTPrec tool will record to the named
#		file all of the requests received by the client (commands to
#		the HTTPrec tool itself will NOT be recorded to that file),
#		in binary mode. While recording, the tool will also forward
#		each such communication received by the client to the
#		baseline server (SERVER_HOST), over the appropriate port
#		(SERVER_PORT), after having modified them so that the
#		baseline server will respond to the HTTPrec tool itself.
#		The responses received from the baseline server will also
#		by logged to the recording file, and then forwarded to the
#		client. Each of these requests and responses, saved to the
#		recording file, will be preceeded by a header line formatted
#		as follows:
#		Type=<Type> Size=<Size>
#		Where <Type> can be either the string "Request", or the
#		string "Response", and <Size> is the number of characters
#		(bytes) included in the saved message after the header line.
#
#		All of the recording files are saved by the HTTPrec tool to
#		a directory (whose named is stored in the file-scoped
#		$STORAGE variable).
#
#		The HTTPrec logs most events, in short form, to its log file,
#		named "HTTPrec.log", which is never cleared but appended to.
#
#^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^

#	Modules and Pragmas:
#^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
use HTTP::Daemon;
use HTTP::Status;
use strict;

#	File Scope:
#^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^

# Parameters from the configuration file:
#----------------------------------------
my $HTTPREC_HOST;
my $CLIENT_PORT;
my $SERVER_HOST;
my $SERVER_PORT;
my $HTTPREC_CMD_PREFIX;

# Attempts to access the configuration file, and read the
# required parameters; stops if any is missing.
#--------------------------------------------------------
my $CFG_FN = "HTTPrec.cfg";
if(!open(CFG, $CFG_FN))
{ die "#> Could not open Configuration File $CFG_FN.\n\n"; }

while(<CFG>)
{
  chomp;	# chomp \n
  s/#.*//;	# skip comments (starting with # character)
  s/^\s+//;	# skip leading whites
  s/\s+$//;	# skip trailing whites

  next unless length;	# If anything is left
					# split on the '=' character:
  my ($var, $val) = split(/\s*=\s*/, $_, 2);
  if($var eq "HTTPREC_HOST")		{ $HTTPREC_HOST = $val; }
  elsif($var eq "CLIENT_PORT")	{ $CLIENT_PORT = $val; }
  elsif($var eq "SERVER_PORT")	{ $SERVER_PORT = $val; }
  elsif($var eq "SERVER_HOST")	{ $SERVER_HOST = $val; }
  elsif($var eq "HTTPREC_CMD_PREFIX"){$HTTPREC_CMD_PREFIX = $val; }
}#WEND
close CFG;
my $cfgError = "Missing Parameter(s):\n";
my $nocfg = 0;
if(!$HTTPREC_HOST) { $cfgError.="  HTTPREC_HOST\n"; $nocfg=1; }
if(!$CLIENT_PORT) { $cfgError.="  CLIENT_PORT\n"; $nocfg=1; }
if(!$SERVER_HOST) { $cfgError.="  SERVER_HOST\n"; $nocfg=1; }
if(!$SERVER_PORT) { $cfgError.="  SERVER_PORT\n"; $nocfg=1; }
if(!$HTTPREC_CMD_PREFIX ) { $cfgError.="  HTTPREC_CMD_PREFIX \n"; $nocfg=1; }
if($nocfg)
{ die "#> Missing parameter(s) in Configuration File $CFG_FN\n".$cfgError; }

# Complete Command prefix:
#-------------------------
#my $CMD_PREFIX = "http://$HTTPREC_HOST:$CLIENT_PORT/$HTTPREC_CMD_PREFIX?";
my $CMD_PREFIX = "/$HTTPREC_CMD_PREFIX?";
my $CMD_PREFIX_S = length($CMD_PREFIX);

# Int-codes for Requests and Responses and associated strings:
#-------------------------------------------------------------
my $REQUEST = 0;			# i.e. "This is a request"
my $RESPONSE= 1;			# i.e. "This is a response"
my $ReqTypeString = "Request";
my $ResTypeString = "Response";

# $daemon: The HTTPrec daemon
#----------------------------
my $daemon = HTTP::Daemon->new(LocalPort => $CLIENT_PORT);
if(!$daemon)
{ die "#> Could not instanciate HTTPrec daemon.\n\n"; }

# StorageArea:
# If it doesn't exist, the program creates the HTTPstorage directory.
#--------------------------------------------------------------------
my $STORAGE = "HTTPstorage";
if(!-d $STORAGE)
{ mkdir $STORAGE, 777 or die "#> Could not create the $STORAGE directory.\n\n"; }

# Log-file:
# The log file is always preserved.
# When the HTTPrec tool is started, it logs the time to the LOG file.
#--------------------------------------------------------------------
my $LOGFN = "HTTPrec.log";
open(LOG, ">> $LOGFN") or die "#> Could not open $LOGFN file.\n\n";
my ($Dsec, $Dmin, $Dhr, $Dmday, $Dmon, $Dyear) = localtime time;
my $Dtime = sprintf "%04d-%02d-%02d-%02d-%02d-%02d", $Dyear+1900, $Dmon+1, $Dmday, $Dhr, $Dmin, $Dsec;
print LOG "**> HTTPrec started at $Dtime\n";
my $LOGLN = 1;

# $RECFN:
# filename for the REC filehandle, used when in recording mode.
# The REC filehandle is opened in ProcessCommand.
#--------------------------------------------------------------
my $RECFN;

# @headers array:
# used by the RecHeaders callback called by scan.
#------------------------------------------------
my @headers = ();

# Name of parameters to recognized commands:
# cmd=(start|stop|fetch|list) indicates which command is requested
# file=<file> is used by start, stop, and fetch commands to
#	indicate a recording-name (i.e. a filename).
#-----------------------------------------------------------------
my $PARN_CMD = "cmd";
my $PARN_FILE = "file";

# Recognized commands (i.e. values for the $PARN_CMD parameter),
# and equivalent codes:
#---------------------------------------------------------------
my $CMD_START = "start";	my $START_CODE = 1;
my $CMD_STOP = "stop";		my $STOP_CODE = 2;
my $CMD_LIST = "list";		my $LIST_CODE = 3;
my $CMD_FETCH = "fetch";	my $FETCH_CODE = 4;
my $CMD_MENU = "menu";		my $MENU_CODE = 5;
					my $UNREC_CODE = 10;

# Possible states for the HTTPrec tool:
#--------------------------------------
my $D_IDLE = 0;
my $D_REC = 1;

# Status of the HTTPrec tool:
# Initializes to $D_IDLE
#----------------------------
my $D_STATE = $D_IDLE;

# RecognizeCommand:
# Procedure to analyze an incoming HTT::Request and detect any
# of the HTTPrec commands. If an HTTPrec command is detected,
# the procedure returns the equivalent int-codes; otherwise, the
# procedure returns 0 (zero; false).
#^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
sub RecognizeCommand
{
  my ($request) = @_;
  my $uri = $request->uri;

printf ("DEBUG: RecognizeCommand: URI = $uri \n");
printf ("DEBUG: RecognizeCommand: CMD_PREFIX = $CMD_PREFIX \n");


  if($uri !~ /$CMD_PREFIX/i)
  { return 0; }

printf ("DEBUG: RecognizeCommand: passed test1 \n");


  my $post = substr($uri, $CMD_PREFIX_S);

  my @pairs = split(/&/,$post);
  my %parameters = ();
  foreach(@pairs)
  {
	my ($name, $val) = split/=/;
	$parameters{$name} = $val;
  }

  if (!exists $parameters{$PARN_CMD})		{ return $UNREC_CODE; }
  if ($parameters{$PARN_CMD} eq $CMD_START)	{ return $START_CODE; }
  if ($parameters{$PARN_CMD} eq $CMD_STOP)	{ return $STOP_CODE; }
  if ($parameters{$PARN_CMD} eq $CMD_FETCH)	{ return $FETCH_CODE; }
  if ($parameters{$PARN_CMD} eq $CMD_LIST)	{ return $LIST_CODE; }
  if ($parameters{$PARN_CMD} eq $CMD_MENU)	{ return $MENU_CODE; }
  return $UNREC_CODE;
}
# End of RecognizeCommand
#^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^

# SimpleResponse:
# Procedure producing a simple HTTP::Response for HTTP::Requests that
# are NOT recognized as HTTPrec commands. This version of HTTPrec
# uses these responses to reply to the client when a non-command
# request is received while the HTTPrec daemon is NOT recoding.
#^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
sub SimpleResponse
{
  my ($request) = @_;
  my $reqString = $request->as_string;

  my $responseCode = RC_OK;
  my $responseMsg = status_message($responseCode);
  my $responseHeader = $request->headers();

  my $responseContent = "<html><head><title>";
  my ($sec, $min, $hr, $mday, $mon, $year) = localtime time;
  my $time = sprintf "%04d-%02d-%02d-%02d-%02d-%02d", $year+1900, $mon+1, $mday, $hr, $min, $sec;
  $responseContent.="Response Generated at $time</title></head>\n";
  $responseContent.="<body>\n";
  $responseContent.="<b>Request Received:</b><br/>\n";
  $responseContent.=$reqString;
  $responseContent.="<br/><b>NOT AN ITI-TEST-CONTROL COMMAND</b><br/>";
  $responseContent.="</body></html>\n";

  my $response = HTTP::Response->new(	$responseCode,
							$responseMsg,
							$responseHeader,
							$responseContent);
  return $response;
}
# End SimpleResponse
#^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^

# Record:
# Procedure to record to the REC filehandle (assumed to be open,
# in binmode) an HTTP::Request or HTTP::response. This version
# of HTTPrec uses this procedure to do the actual recording once
# one is started per client request.
# The procedure expects two parameters: in order
# ~ $obj: the object to be recorded (either an HTTP::Request or
#	    an HTTP::Response;
# ~ $type: a variable indicating the type of the $obj parameter,
#	    either matching the $REQUEST or the $RESPONSE file-scoped
#	    codes.
# Each of the objects recorded to file by this procedure is preceeded
# by a header line formatted as
# Type=<Type> Time=<timestamp> Size=<Size>
# Where <Type> is a string (either $ReqTypeString or $ResTypeString)
# indicating whether the object recorded is an HTTP::Request or
# HTTP::Response, and <Size> is the size (in bytes) of the record
# itself (the header line is not included in this value).
#^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
sub Record
{
  my ($obj, $type) = @_;
  my ($sec, $min, $hr, $mday, $mon, $year) = localtime time;
  my $time = sprintf "%04d-%02d-%02d-%02d-%02d-%02d", $year+1900, $mon+1, $mday, $hr, $min, $sec;

  my $msg = "Type=";
  my $body = BuildBody($obj);
  if($type==$REQUEST)	{ $msg.=$ReqTypeString; }
  else			{ $msg.=$ResTypeString; }
  my $BS = length($body);

  $msg.=" Time=$time Size=$BS";
  $msg.="\r\n";
  $msg.=$body;

  print REC $msg;
}
# End Record
#^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^

# BuildBody:
# Procedure building the body of a record so that the Record procedure
# can easily write it to file. The Body is built based on the $obj
# parameter received (which is assumed to be an HTTP::Request or
# HTTP::Response object), and includes a list of the headers from
# the $obj object (in alphabetical order, one per line, in name: value
# form), followed by a blank line, and the content of the $obj itself.
#^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
sub BuildBody
{
  my ($obj) = @_;
  my $body;
  @headers = ();
  $obj->scan(\&RecHeader);

  foreach (sort @headers)
  { $body.=$_."\r\n"; }

  $body.="\r\n".$obj->content;

  return $body;
}
# End BuildBody
#^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^

# RecHeader procedure:
# Procedure to format a given pair of strings as a single name: value
# string. Used as callback by the ->scan method invoked in BuildBody.
#^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
sub RecHeader
{
  my ($name, $val) = @_;
  push @headers, "$name: $val";
}
# End RecHeader
#^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^


# ForwardToServer:
# Procedure to Forward a given HTTP::Request to the baseline server
# and await for the matching HTTP::Response.
# This version of HTTPrec simply simulates the process by creating
# a recognizeable HTTP::Response object.
#^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
sub ForwardToServer
{
  # Stub: the following lines will probably work
  # when this will be deployed.
  #
  # my ($request) = @_;
  # my $response = $Agent->send_request($Request);
  # return $Response;
  #
  # For the time being, here's a summy response:

  my ($request) = @_;
  my $reqString = $request->as_string;

  my $responseCode = RC_OK;
  my $responseMsg = status_message($responseCode);
  my $responseHeader = $request->headers();

  my $responseContent = "<html><head><title>";
  my ($sec, $min, $hr, $mday, $mon, $year) = localtime time;
  my $time = sprintf "%04d-%02d-%02d-%02d-%02d-%02d", $year+1900, $mon+1, $mday, $hr, $min, $sec;
  $responseContent.="Response Generated at $time</title></head>\n";
  $responseContent.="<body>\n";
  $responseContent.="<b>Request Received:</b><br/>\n";
  $responseContent.=$reqString;
  $responseContent.="<br/><b>NOT AN ITI-TEST-CONTROL COMMAND</b><br/>";
  $responseContent.="<br><b>################ Assume the request was forwarded to the server, and this was the response received</b><br/>";
  $responseContent.="</body></html>\n";

  my $response = HTTP::Response->new(	$responseCode,
							$responseMsg,
							$responseHeader,
							$responseContent);
  return $response;
}
# End ForwardToServer
#^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^

# ProcessCommand:
# Procedure to Process an HTTP::Request object that has been
# recognized as one of the HTTPrec commands.
# The procedure expects two parameters: in order
# ~ $request: the HTTP::Request object itself;
# ~ $cmdCode: the int code indicating which command was detected
#		  in the request.
#^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
sub ProcessCommand
{
  my ($request, $cmdCode) = @_;

  my $reqString = $request->as_string;

  my $uri = $request->uri;
  my $post = substr($uri, $CMD_PREFIX_S);

  my @pairs = split(/&/,$post);
  my %parameters = ();
  foreach(@pairs)
  {
	my ($name, $val) = split/=/;
	$parameters{$name} = $val;
  }

  my $commandName;
  if($cmdCode == $START_CODE)	{ $commandName = "Start"; }
  if($cmdCode == $STOP_CODE)	{ $commandName = "Stop"; }
  if($cmdCode == $FETCH_CODE)	{ $commandName = "Fetch"; }
  if($cmdCode == $LIST_CODE)	{ $commandName = "List"; }
  if($cmdCode == $MENU_CODE)	{ $commandName = "Menu"; }
  if($cmdCode == $UNREC_CODE)	{ $commandName = "Unrecognized"; }

  my $responseCode = RC_OK;
  my $responseMsg = status_message($responseCode);
  my $responseHeader = $request->headers();

  my $responseContent = "<html><head><title>";
  my ($sec, $min, $hr, $mday, $mon, $year) = localtime time;
  my $time = sprintf "%04d-%02d-%02d-%02d-%02d-%02d", $year+1900, $mon+1, $mday, $hr, $min, $sec;
  $responseContent.="Response Generated at $time</title></head>\n";
  $responseContent.="<body>\n";
  $responseContent.="<b>Request Received:</b><br/>\n";
  $responseContent.=$reqString;
  $responseContent.="<br/><b>ITI-COMMAND: ";
  $responseContent.=$commandName;
  $responseContent.="</b><br/>";
  $responseContent.="<b>Parameters:</b><br/>";

  foreach (sort keys(%parameters))
  { $responseContent.="<b>$_:</b> $parameters{$_}<br/>"; }

  print LOG "$LOGLN\tReceived Command Request:\n";
  $LOGLN++;
  print LOG "$LOGLN\t\tCommand: $commandName\n";
  $LOGLN++;
  print LOG "$LOGLN\t\tParameters: ";
  if(exists $parameters{$PARN_CMD} ) { print LOG "$PARN_CMD => $parameters{$PARN_CMD} "; }
  if(exists $parameters{$PARN_FILE} ) { print LOG "$PARN_FILE => $parameters{$PARN_FILE} "; }
  print LOG "\n";
  $LOGLN++;


  if($cmdCode == $START_CODE)
  {
	# Request to START a recording
	#----------------------------------------------------------------------------------------------------------
	if(!exists $parameters{$PARN_FILE})
	{ $responseContent.="<b>ERROR:</b> No <i>file</i> parameter specified.<br/>"; }
	elsif ($D_STATE == $D_REC)
	{ $responseContent.="<b>ERROR:</b> HTTPrec is already recording (to file $RECFN).<br/>"; }
	else
	{
	  my $tmpFN = "$STORAGE/$parameters{$PARN_FILE}";
	  if(!open(REC, "> $tmpFN"))
	  { $responseContent.="<b>ERROR:</b> Could not open the file $parameters{$PARN_FILE} for recording.<br/>"; }
	  else
	  {
		$RECFN = $parameters{$PARN_FILE};
		binmode REC;
		$D_STATE = $D_REC;
		$responseContent.="Started recording to file $RECFN<br/>";
	  }
	}
  }#IF START 
  elsif($cmdCode == $STOP_CODE)
  {
	# Request to STOP a recording
	#----------------------------------------------------------------------------------------------------------
	if(!exists $parameters{$PARN_FILE})
	{ $responseContent.="<b>ERROR:</b> No <i>file</i> parameter specified.<br/>"; }
	elsif ($D_STATE == $D_IDLE)
	{ $responseContent.="<b>ERROR:</b> HTTPrec is not recording.<br/>"; }
	elsif($RECFN ne $parameters{$PARN_FILE})
	{ $responseContent.="<b>ERROR:</b> HTTPrec is recording to file $RECFN, not to file $parameters{$PARN_FILE}.<br/>"; }
	else
	{
	  close REC;
	  $D_STATE = $D_IDLE;
	  $responseContent.="Stopped recording to file $RECFN.<br/>";
	  $RECFN = "";
	}
  }# IF STOP
  elsif($cmdCode == $FETCH_CODE)
  {
	# Request to FETCH a recording
	#----------------------------------------------------------------------------------------------------------
	if(!exists $parameters{$PARN_FILE})
	{ $responseContent.="<b>ERROR:</b> No <i>file</i> parameter specified.<br/>"; }
	else
	{
	  my $filename = "$STORAGE/$parameters{$PARN_FILE}";
	  if(-e $filename)
	  {
		if(!open(FET, $filename))
		{ $responseContent.="<b>ERROR:</b> Could not open the specified <i>file</i> parameter ($parameters{$PARN_FILE}).<br/>"; }
		else
		{
		  my $fetchRC;
		  binmode FET;
		  while(<FET>)
		  { $fetchRC.=$_; }
		  close FET;
		  my $fetchResponse = HTTP::Response->new( $responseCode, $responseMsg, $responseHeader, $fetchRC);
		  return $fetchResponse;
		}
	  }
	  else
	  { $responseContent.="<b>ERROR:</b> The specified <i>file</i> parameter ($parameters{$PARN_FILE}) does not exist.<br/>"; }
	}
  }# IF FETCH
  elsif($cmdCode == $LIST_CODE)
  {
	# Request to LIST the available recordings
	#----------------------------------------------------------------------------------------------------------
	if(!opendir(STORAGEDIR, $STORAGE))
	{ $responseContent.="<b>ERROR:</b> Could not open the Storage Directory $STORAGE.<br/>"; }
	else
	{
	  $responseContent.="Recordings available:<br/>";
	  my @allRecs = grep !/^\.\.?\z/, readdir STORAGEDIR;
	  closedir STORAGEDIR;
	  foreach(sort @allRecs)
	  {
		if($_ eq $RECFN && $D_STATE == $D_REC)
		{ $responseContent.="$_ [recording]<br/>"; }
		else
		{ $responseContent.="<a href=\"$CMD_PREFIX"."cmd=$CMD_FETCH&file=$_\">$_</a><br/>"; }
	  }
	}
  }# IF LIST
  elsif($cmdCode == $MENU_CODE)
  {
	# Request to display the MENU
	#----------------------------------------------------------------------------------------------------------
	$responseContent.="<br/><b>HTTPrec Menu:</b><br/>";
	$responseContent.="<b>Status:</b> ";
	if($D_STATE == $D_IDLE)
	{ $responseContent.="idle.<br/>"; }
	else
	{ $responseContent.="recording to file $RECFN.<br/>"; }
	$responseContent.="<b>Start:</b> $CMD_PREFIX"."cmd=$CMD_START&file=<b>filename</b><br/>";
	$responseContent.="<b>Stop:</b> $CMD_PREFIX"."cmd=$CMD_STOP&file=<b>filename</b><br/>";
	$responseContent.="<b>Fetch:</b> $CMD_PREFIX"."cmd=$CMD_FETCH&file=<b>filename</b><br/>";
	$responseContent.="<b>List:</b> <a href=\"$CMD_PREFIX"."cmd=$CMD_LIST\">$CMD_PREFIX"."cmd=$CMD_LIST</a><br/>";
  }# IF MENU


  $responseContent.="<br/><a href=\"$CMD_PREFIX"."cmd=$CMD_MENU\">Back to the HTTPrec Menu</a><br/>";

  $responseContent.="</body></html>\n";

  my $response = HTTP::Response->new(	$responseCode,
							$responseMsg,
							$responseHeader,
							$responseContent);
  return $response;
}
# End ProcessCommand
#^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^


# Main:
# Once started, the Daemon listens on the CLIENT_PORT, and behaves
# as follows:
# ~ Requests that are recognized HTTPrec commands are processed
#	via the ProcessCommand procedure;
# ~ Other requests, if HTTPrec is recording, are recorded, and
#	forwarded to the baseline server; the response returned by the
#	server is passed back to the client;
# ~ Other requests, if HTTPrec is not recording, are ignored (Note:
#	in this version, HTTPrec uses these requests to produce
#	Simple Responses and send them back to the client).
#^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
MAIN:
$|++;
print "Contact: <URL:", $daemon->url, ">\n";
while (my $client = $daemon->accept)
{
  print "Connection accepted.\n";
  print LOG "$LOGLN\tAccepted Connection.\n";
  $LOGLN++;

  while (my $request = $client->get_request)
  {
	print "Received request.\n";
	my $response;
	my $cmdCode = RecognizeCommand($request);
	if(!$cmdCode)
	{
	  print LOG "$LOGLN\tReceived Simple Request.\n";
	  $LOGLN++;

	  #Not a Command:
	  if($D_STATE == $D_REC)
	  {
		Record($request, $REQUEST);
		print LOG "$LOGLN\tRecorded Request.\n";
		$LOGLN++;
		$response = ForwardToServer($request);
		print LOG "$LOGLN\tObtained matching Response from Server.\n";
		$LOGLN++;
		Record($response, $RESPONSE);
		print LOG "$LOGLN\tRecorded Response.\n";
		$LOGLN++;
	  }#IF recording
	  else
	  { $response = SimpleResponse($request); }
	}
	else
	{ $response = ProcessCommand($request, $cmdCode); }

	$client->send_response($response);
	print "Response sent.\n";
	print LOG "$LOGLN\tResponse sent.\n";
	$LOGLN++;
  }#WEND
  $client->close;
  undef $client;
  print "Connection closed.\n";
  print LOG "$LOGLN\tClosed Connection.\n";
  $LOGLN++;
}
# End Main
#^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^


#^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
#	EOF
#^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
