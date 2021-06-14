#!/usr/bin/perl -w
=pod

=head1 Test Suite: HTTP Playback Tool

=head1 Synopsis:

	The tool used to playback the HTTP traffic between an ObjectStore or
	HTTP-enabled DPS Client and Server.

=head1 Description:

	The HTTP Playback Tool allows a user to replay a previously
	recorded stream of HTTP communications between a Client and a
	Server, and compare in real-time the sets of results (from the
	recording and from the second run), detecting any unexpected
	difference. The results of this process are recorded to a text
	file structured as described by the HTTP_Playback XML Schema.

=head1 Author:

	Frank Rizzi, frank.rizzi@infotechfl.com

=head1 Version:

	v.0.53,	5-JUN-2k3

=head1 Copyright:

	Info Tech, Inc. 2003

=head1 History:

=head2 v.0.4x and below

	These early versions can be described as early alpha versions.
	Based upon the early Prototype by Charles Engelke and Craig
	Fitzgerald, these versions explored the architecture that would
	allow the implementation of the HTTP Playback tool itself.

=head2 v.0.50,	14-MAY-2k3

	FOR: The first "ObjectStore-Complete" alpha version of the tool.
	This version includes all of the elements involved with
	replaying the stream of transactions between an ObjectStore Client
	and Server, but does not include any section regarding the
	scenario for the HTTP-enabled DPS Client and Server.

=head2 v.0.51,	19-MAY-2k3

	FOR: Working version introducing the Scenario of a DPS playback.
	Changes introduced with this version are enclosed in the
	<v051> and </v051> tag (even in POD documentation).

=head2 v.0.52,	29-MAY-2k3

	FOR: Wrap-up version to accomodate the DPS scenario.
	Changes introduced with this version are enclosed in the
	<v052> and </v052> tags.

=head2 v.0.53,	5-JUN-2k3

	FOR: Fixed issues with configuration file and input file:
	if the HTTP Playback tool is invoked from a location other than the
	one where it is running, it was unable to locate the configuration
	file. The tool also requires the input file parameter to be the
	full path to the input file.

=head1 Notes for v.0.50

	The HTTP Playback tool has been developed and tested by using
	the modified obsverif.pl script (see the documentation for the
	HTTP Recorder tool, v.0.50).

=head1 Notes for v.051 and v.052

	The introduction of the DPS scenario has forced a few changes.
	At the most general level, the instanciation of the LWP::UserAgent
	used to communicate with the Server has been moved to the main
	routine, since, depending on the type of recording to be replayed,
	the user agent might need to be instanciated with or without
	the Keep-Alive option.
	Next, come DPS-Specific logic has been introduced. A few routines
	have been introduced to perform the comparison of DPS responses,
	and the extraction of some elements in the DPS transactions that
	may be different without invalivatind the transaction.
	The most recognizable feature introduced with the DPS scenario is
	the peculiar handling of the DPS JM_JOBLIST transactions, where
	the HTTP Playback tool will perform at most $PROC_STATUS_RETRY
	times (at intervals of $PROC_STATUS_DELAY seconds) before marking
	the transaction replay as a failure.
	From this version, the itidpsc32.dll must be available for the
	Playback to replay a DPS recording.
	Additionally, the HTTP Recorder (v.0.52) introduced a new
	element in the <INFO> element (the <CLIENT_SERVER_VERSION> element).
	Finally, with this version, the configuration file must also
	include a new parameter: CLIENT_IP, with value equal to the
	Ip-Address of the machine where the HTTP PLayback will run.

=head Notes for v.0.53

	The tool should now work even if invoked from a different location.
	All changes are localized in the Init routine and enclosed in the
	<v053> and </v053> tags.

=head1 Known Issues:

=head1 Resolved Issues:

=head1 Implementation Details:

=head2 External Dependencies:

=over 4

=item *

HTTP::Status (v. 1.26)
The constants defined in the HTTP::Status library are used when
constructing HTTP Responses for the Clients, and when analyzing
the HTTP responses received from the Server.

=item *

LWP::UserAgent (v. 2.3)
An LWP::UserAgent object is used to communicate with the Server.

=item *

XML::Simple (v. 1.06)
The XML::Simple library is used to read the content of the
recording file (i.e. the input file), and access its XML element
as needed.

=item *

FindBin (Standard with Perl)
The FindBin module is used to locate the installation directory of the
Perl script that is running (i.e. the HTTPplay.pl script); this is
used in conjunction with the XML::Simple library to read the input
recording file.

=item *

MIME::Base64 (v. 2.14)
The decode_base64 routine from the MIME::Base64 library is used
to decode the content of the SOAP messages recorded in the input
recording file; the encode_base64 routine from the same library is
used to encode the same messages.

=item *

Win32::API (Standard with ActivePerl)
The Win32::API library is used during the playback of a DPS recording
to answer the security challenges by invoking the DPS' DLL.

=back

=head2 Pragmas:

=over 4

=item *

strict
Always good practice.

=back

=cut

#	Libraries and Pragmas:
#^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
use HTTP::Status;
use LWP::UserAgent;
use XML::Simple;
use FindBin qw($Bin);
use MIME::Base64;
use Win32::API;
use strict;

# Un-comment this use statement, and the
# print LOG Dumper($inData);
# statement towards the end of the Input routine to print to the
# log file the data found in the input recording file as one
# big hash (custom-debug only).
# use Data::Dumper;


=head2	Constants:

  VERSION
	The current version of the tool.
	
  CFG_FILENAME
	The [relative path and] name of the configuration file.
	
  LOG_FILENAME
	The name of the file to be used as logfile;
	this file will be created in the Storage Directory for the run.
	
  DEF_STORAGE_DIR
	The [relative path and] name of the Default Storage Directory,
	used when the optional -wd parameter is not specified in the
	invoking command line.
	
  HTTP_MSG_ORIGINAL_REQUEST
  HTTP_MSG_ORIGINAL_RESPONSE
  HTTP_MSG_PLAYBACK_REQUEST
  HTTP_MSG_PLAYBACK_RESPONSE
	Code values used to mark an HTTP Message as either an Original
	or Playback Request or Response.
	
  SERVER_OBS_STR
  SERVER_DPS_STR
	Strings describing (respsectively) an Object Store Server and
	a DPS Server; Note that these strings are used to recognize
	which type of recording is found in the input recording file;
	thus, if different strings are used to create the recording, these
	values might need to be modified.
	
  SERVER_OBS
  SERVER_DPS
  SERVER_UNREC
	Code values used to indicate (respectively) an Object Store, a
	DPS, or an Unrecognized Server.
	
  PAGE_WIDTH
	The width (in number of characters) of the page in the logfile.
	
  ERR_NONE
  ERR_LOGFILE
  ERR_CFGFILE
  ERR_MISS_CFGPAR
  ERR_STORAGE
  ERR_NO_CLPAR
  ERR_INFILE
  ERR_XMLIN
  ERR_OUTFILE
  ERR_MISS_REC_SERVER
  ERR_UNREC_REC_SERVER
  ERR_XML_EXTRACT
	Various error codes (See the ReportError routine for the
	human-readable descriptions of each).
	
  DBG_MIN
  DBG_MED
  DBG_HIGH
	Code values for three recognized debug levels; 0, 5, and 10,
	respectively.
	
  RESULT_OK
  RESULT_DIFF_TO
  RESULT_DIFF_CODE
  RESULT_DIFF_HEADERS
  RESULT_DIFF_CONTENT
	Codes describing the result of comparing two transactions
	(one from the input recording file, the other from the playback
	run); respectively, see the ResultCodeDescription routine for
	human-readable description of each code.
	
  OBS_OBSTORE_URI
  OBS_WSDL_REQUEST_URI
  OBS_WSML_REQUEST_URI
  OBS_EXE_URI
	ObjectStore Specific: values used to recognize certain ObjectStore
	transaction types from the URI of the HTTP Requests.
	
  OBS_SOAP_RETRIEVE_SUPPORTED_CLASSIFICATIONS
  OBS_SOAP_EXECUTE_SEARCH
  OBS_SOAP_ADD_OBJECT
  OBS_SOAP_GET_LAST_UPDATE_TIME
  OBS_SOAP_GET_OBJECT
  OBS_SOAP_UPLOAD_OBJECT_DATA
  OBS_SOAP_DOWNLOAD_OBJECT_DATA
  OBS_SOAP_REMOVE_OBJECT
  OBS_SOAP_UPDATE_OBJECT
	ObjectStore Specific: values used to recognize certain ObjectStore
	transaction types from the SOAP Action in the HTTP Request.
	
  TRANSACTION_NONE
  TRANSACTION_OBS_WSDL
  TRANSACTION_OBS_WSML
  TRANSACTION_OBS_RETRIEVE_SUPPORTED_CLASSIFICATIONS
  TRANSACTION_OBS_EXECUTE_SEARCH
  TRANSACTION_OBS_OBSTORE_POST
  TRANSACTION_OBS_ADD_OBJECT
  TRANSACTION_OBS_GET_LAST_UPDATE_TIME
  TRANSACTION_OBS_GET_OBJECT
  TRANSACTION_OBS_UPLOAD_OBJECT_DATA
  TRANSACTION_OBS_DOWNLOAD_OBJECT_DATA
  TRANSACTION_OBS_OBSTORE_GET
  TRANSACTION_OBS_REMOVE_OBJECT
  TRANSACTION_OBS_UPDATE_OBJECT
  TRANSACTION_DPS_PING
  TRANSACTION_DPS_SUBMIT
  TRANSACTION_DPS_LISTJOBS
  TRANSACTION_DPS_LISTFILES
  TRANSACTION_DPS_COPY
  TRANSACTION_DPS_DELETEJOB
  TRANSACTION_DPS_DELETEFILE
  TRANSACTION_DPS_GETINFO
  TRANSACTION_DPS_SERVERFILES
  TRANSACTION_DPS_TRANSFER
  TRANSACTION_DPS_MOVEFILE
  TRANSACTION_DPS_CHANGESCHEDULE
  TRANSACTION_DPS_SECURITY
	Transaction Type Codes: used to mark a given transaction as
	a transaction of a specific type.
	<v051>
	The TRANSACTION_DPS_* codes have been added in v.0.51.
	</v051>
	
  UNMAPPED
	Constant Value used as default value for keys in the various
	mapping hashes (See file-scoped variables section); this value
	is used to enter a new key in the mapping even if no value has been
	defined yet for that key.
	
  <v051>
  FILENAME
  DATE
  TIME
  SIZE
  BASICFILE
  JOBID
	Constant values used to key the values in the hashes
	produced for each item in the DPS File Lists.
  </v051>
	
  <v051>
  PS_JID
  PS_JNAME
  PS_JNAME2
  PS_JDESC
  PS_DATE
  PS_ENQUEUE
  PS_START
  PS_END
  PS_PRIORITY
  PS_STATUS
  PS_MODULE
	Constant values used to key the values in the hashes
	produced for each item in the DPS Process Status Lists.
  </v051>
	
  <v051>
  DPS_KEY
	Basic key used to encrypt/decrypt DPS Secure messages.
  </v051>
  
  <v052>
  DPS_JOBSTATUS_DEFERRED
  DPS_JOBSTATUS_SCHEDULED
  DPS_JOBSTATUS_PENDING
  DPS_JOBSTATUS_RUNNING
  DPS_JOBSTATUS_COMPLETED
  DPS_JOBSTATUS_APPERROR
  DPS_JOBSTATUS_STOP
  DPS_JOBSTATUS_REXX
  DPS_JOBSTATUS_HARD
  DPS_JOBSTATUS_TRAP
  DPS_JOBSTATUS_SIGTERM
  DPS_JOBSTATUS_TIMEDOUT
  DPS_JOBSTATUS_ABORTED
  DPS_JOBSTATUS_SHUTDOWN
  DPS_JOBSTATUS_UNKNOWN
  DPS_JOBSTATUS_CANTRUN
  DPS_JOBSTATUS_SASW
  DPS_JOBSTATUS_SASE
  DPS_JOBSTATUS_SASF
  DPS_JOBSTATUS_UNKNOWN2
	Values recognized by the HTTP Playback tool when analyzing the
	Process Status field in the response to a JM_JOBLIST request.
  </v052>
  
  <v052>
  DPS_JOBSTATUS_CODE_PENDING
  DPS_JOBSTATUS_CODE_RUNNING
  DPS_JOBSTATUS_CODE_FAILED
  DPS_JOBSTATUS_CODE_SUCCESS
	Codes used to describe the Process Status of each entry in a
	JM_JOBLIST response as one of the four recognized states (Pending,
	Running, Failed, Success).
  </v052>

=cut

#	Constants:
#^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
use constant VERSION					=>"v.0.52";
use constant CFG_FILENAME				=>"HTTPplay.cfg";
use constant LOG_FILENAME				=>"HTTPplay.log";
use constant DEF_STORAGE_DIR			=>"HTTPplayStorage";

use constant HTTP_MSG_ORIGINAL_REQUEST	=>1;
use constant HTTP_MSG_ORIGINAL_RESPONSE	=>2;
use constant HTTP_MSG_PLAYBACK_REQUEST	=>3;
use constant HTTP_MSG_PLAYBACK_RESPONSE	=>4;

use constant SERVER_OBS_STR				=>"Object Store Server";
use constant SERVER_DPS_STR				=>"Distributed Process Server";
use constant SERVER_OBS					=>1;
use constant SERVER_DPS					=>2;
use constant SERVER_UNREC				=>-1;

use constant PAGE_WIDTH					=>70;

use constant ERR_NONE					=>0;
use constant ERR_LOGFILE				=>1;
use constant ERR_CFGFILE				=>2;
use constant ERR_MISS_CFGPAR			=>3;
use constant ERR_STORAGE				=>4;
use constant ERR_NO_CLPAR				=>5;
use constant ERR_INFILE					=>6;
use constant ERR_XMLIN					=>7;
use constant ERR_OUTFILE				=>8;
use constant ERR_MISS_REC_SERVER		=>9;
use constant ERR_UNREC_REC_SERVER		=>10;
use constant ERR_XML_EXTRACT			=>11;

use constant DBG_MIN					=>0;
use constant DBG_MED					=>5;
use constant DBG_HIGH					=>10;

use constant RESULT_OK					=>0;
use constant RESULT_DIFF_TO				=>1;
use constant RESULT_DIFF_CODE			=>2;
use constant RESULT_DIFF_HEADERS		=>3;
use constant RESULT_DIFF_CONTENT		=>4;

use constant OBS_OBSTORE_URI									=>"/obs-cgi-bin/obstore";
use constant OBS_WSDL_REQUEST_URI								=>"/obs-htdocs/objectstore.wsdl";
use constant OBS_WSML_REQUEST_URI								=>"/obs-htdocs/objectstore.wsml";
use constant OBS_EXE_URI										=>"/obs-cgi-bin/ObjStoreServer.exe";

use constant OBS_SOAP_RETRIEVE_SUPPORTED_CLASSIFICATIONS		=>"/action/COBSObjectStore.RetrieveSupportedClassifications";
use constant OBS_SOAP_EXECUTE_SEARCH							=>"/action/COBSObjectStore.ExecuteSearch";
use constant OBS_SOAP_ADD_OBJECT								=>"/action/COBSObjectStore.AddObject";
use constant OBS_SOAP_GET_LAST_UPDATE_TIME						=>"/action/COBSObjectStore.GetLastUpdateTime";
use constant OBS_SOAP_GET_OBJECT								=>"/action/COBSObjectStore.GetObject";
use constant OBS_SOAP_UPLOAD_OBJECT_DATA						=>"/action/COBSObjectStore.UploadObjectData";
use constant OBS_SOAP_DOWNLOAD_OBJECT_DATA						=>"/action/COBSObjectStore.DownloadObjectData";
use constant OBS_SOAP_REMOVE_OBJECT								=>"/action/COBSObjectStore.RemoveObject";
use constant OBS_SOAP_UPDATE_OBJECT								=>"/action/COBSObjectStore.UpdateObject";

use constant TRANSACTION_NONE									=>0;
use constant TRANSACTION_OBS_WSDL								=>1;
use constant TRANSACTION_OBS_WSML								=>2;
use constant TRANSACTION_OBS_RETRIEVE_SUPPORTED_CLASSIFICATIONS	=>3;
use constant TRANSACTION_OBS_EXECUTE_SEARCH						=>4;
use constant TRANSACTION_OBS_OBSTORE_POST						=>5;
use constant TRANSACTION_OBS_ADD_OBJECT							=>6;
use constant TRANSACTION_OBS_GET_LAST_UPDATE_TIME				=>7;
use constant TRANSACTION_OBS_GET_OBJECT							=>8;
use constant TRANSACTION_OBS_UPLOAD_OBJECT_DATA					=>9;
use constant TRANSACTION_OBS_DOWNLOAD_OBJECT_DATA				=>10;
use constant TRANSACTION_OBS_OBSTORE_GET						=>11;
use constant TRANSACTION_OBS_REMOVE_OBJECT						=>12;
use constant TRANSACTION_OBS_UPDATE_OBJECT						=>13;
use constant TRANSACTION_DPS_PING								=>14;
use constant TRANSACTION_DPS_SUBMIT								=>15;
use constant TRANSACTION_DPS_LISTJOBS							=>16;
use constant TRANSACTION_DPS_LISTFILES							=>17;
use constant TRANSACTION_DPS_COPY								=>18;
use constant TRANSACTION_DPS_DELETEJOB							=>19;
use constant TRANSACTION_DPS_DELETEFILE							=>20;
use constant TRANSACTION_DPS_GETINFO							=>21;
use constant TRANSACTION_DPS_SERVERFILES						=>22;
use constant TRANSACTION_DPS_TRANSFER							=>23;
use constant TRANSACTION_DPS_MOVEFILE							=>24;
use constant TRANSACTION_DPS_CHANGESCHEDULE						=>25;
use constant TRANSACTION_DPS_SECURITY							=>26;

use constant UNMAPPED											=>".";
use constant DPS_KEY											=>"HmhTEMkd_Fns_Entmc";

use constant FILENAME											=>"__filename__";
use constant DATE												=>"__date__";
use constant TIME												=>"__time__";
use constant SIZE												=>"__size__";
use constant BASICFILE											=>"__basicfile__";
use constant JOBID												=>"__jobid__";

use constant PS_JID												=>"__ps_jid__";
use constant PS_JNAME											=>"__ps_jname__";
use constant PS_JNAME2											=>"__ps_jname2__";
use constant PS_JDESC											=>"__ps_jdesc__";
use constant PS_DATE											=>"__ps_date__";
use constant PS_ENQUEUE											=>"__ps_enqueue__";
use constant PS_START											=>"__ps_start__";
use constant PS_END												=>"__ps_end__";
use constant PS_PRIORITY										=>"__ps_priority__";
use constant PS_STATUS											=>"__ps_status__";
use constant PS_MODULE											=>"__ps_module__";

use constant DPS_JOBSTATUS_DEFERRED								=>"Process Deferred";
use constant DPS_JOBSTATUS_SCHEDULED							=>"Process Scheduled";
use constant DPS_JOBSTATUS_PENDING								=>"Process Pending";
use constant DPS_JOBSTATUS_RUNNING								=>"Process Running";
use constant DPS_JOBSTATUS_COMPLETED							=>"Completed";
use constant DPS_JOBSTATUS_APPERROR								=>"Application Error";
use constant DPS_JOBSTATUS_STOP									=>"Stop Encountered";
use constant DPS_JOBSTATUS_REXX									=>"REXX Error";
use constant DPS_JOBSTATUS_HARD									=>"Hard Error";
use constant DPS_JOBSTATUS_TRAP									=>"Trap Error";
use constant DPS_JOBSTATUS_SIGTERM								=>"SigTerm Error";
use constant DPS_JOBSTATUS_TIMEDOUT								=>"Timed Out";
use constant DPS_JOBSTATUS_ABORTED								=>"Aborted by User";
use constant DPS_JOBSTATUS_SHUTDOWN								=>"Shutdown Aborted";
use constant DPS_JOBSTATUS_UNKNOWN								=>"Unknown Error";
use constant DPS_JOBSTATUS_CANTRUN								=>"Cannot Run Job";
use constant DPS_JOBSTATUS_SASW									=>"SAS Warning";
use constant DPS_JOBSTATUS_SASE									=>"SAS Error";
use constant DPS_JOBSTATUS_SASF									=>"SAS Fatal Error";
use constant DPS_JOBSTATUS_UNKNOWN2								=>"Unknown Error #2";

use constant DPS_JOBSTATUS_CODE_PENDING							=> 0;
use constant DPS_JOBSTATUS_CODE_RUNNING							=> 1;
use constant DPS_JOBSTATUS_CODE_FAILED							=> 2;
use constant DPS_JOBSTATUS_CODE_SUCCESS							=> 3;

=pod

=head2	File-Scoped variables:

  $errCode
	Variable used to indicate what error (if any) occurred.
	
  $errMsg
	Variable used to store additional information available in
	certain erroneous conditions.
	
  $logIndent
	Variable indicating the current indentation level for the logfile.
	
  $inFilename
	The name of the input recording file.
	
  $inData
	Reference to the hash produced by reading the input recording
	XML file; contains all of the data from the input recording file.
	
  $outFilename
	The name of the ouput file.
	
  $outputDir
	The [relative path and] name of the output directory.
	
  $setOutFilename
	Boolean flag used to indicate if the $outFilename variable has
	been set by a command-line parameter or not.
	
  $transactionID
	The ID (in the form of an integer value) of the current transaction.
	
  $transactionType
	The type of the current transaction (see the TRANSACTION_*
	constants).
	
  $playbackID
	The ID of the playback, optionally provided via command line.
	
  $playbackUser
	The Author of the playback, optionally provided via command line.
	
  $playbackDesc
	The Description of the playback, optionally provided via command
	line.
	
  $recordingID
	The ID of the recording in the input file.
	
  $recordingUser
	The Author of the recording in the input file.
	
  $recordingTimestamp
	The timestamp when the recording in the input file was started.
	
  $recordingServerType
	The type of server used during the recording in the input file.
	
  $HTTPrecVersion
	The version of the HTTP Recorder tool used to produce the
	recording in the input file.
	
  $recordingTimeout
	The timeout value (in seconds) used during the recording in the
	input file.
	
  $originalResponse_timeout
	Boolean flag used to indicate, for the current transaction, if
	the original response from the input file was marked as a
	Timeout response.
	
  $playbackResponse_timeout
	Boolean flag used to indicate, for the current transaction, if the
	playback response is a Timeout response.
	
  $originalRequestTime
	The timestamp of the original request from the input file.
	
  $originalResponseTime
	The timestamp of the original response from the input file.
	
  $result
	The code describing the result of the playback (see the
	RESULT_* constants).
	
  $resultErrInfo
	Variable used to store additional information regarding the error
	detected (for errors that set the $result variable to anything
	but RESULT_OK).
	
  $SERVER_HOST
	The Ip-Address of the server used during the playback, from the
	configuration file.
	
  $SERVER_PORT
	The Port to be used for communications with the Server, from the
	configuration file.
	
  <v052>
  $CLIENT_IP
	The Ip-Address of the machine where the HTTP Playback will run,
	as specified in the configuration file.
  </v052>
	
  $TIMEOUT
	The value (in seconds) to be used as Timeout parameter, from the
	configuration file.
	
  $PROC_STATUS_RETRY
	The number of attempts to be made when replaying a DPS "Process
	Status" transaction, from the configuration file.
	
  $PROC_STATUS_DELAY
	The number of seconds to wait between each successive attempt to
	replay a DPS "Process Status" transaction, from the configuration
	file.
	
  $DBG
	The debug level to be used during the run, from the configuration
	file.
	
  %headers
	hash used to store the headers of an HTTP message.
	
  %logHeaders
	hash used to store the headers of an HTTP message; note that the
	%headers and %logHeaders hashes are used in parallel throughout
	the code.
	
  %queryMap
  %queryMapSet
	Mapping hashes for the Queries found in ObjectStore transactions.
	
  %guidMap
  %guidMapSet
	Mapping hashes for the GUIDs found in ObjectStore transactions.
	
  %filenameMap
  %filenameMapSet
	Mapping hashes for the Filenames found in ObjectStore transactions.
	
  %serializedMap
  %serializedMapSet
	Mapping hashes for the Serialized Objects found in ObjectStore
	transactions.
	
  %envLastUpdatedMap
  %envLastUpdatedMapSet
	Mapping hashes for the envLastUpdated elements found in ObjectStore
	transactions.
	
  %objLastUpdatedMap
  %objLastUpdatedMapSet
	Mapping hashes for the objLastUpdated elements found in ObjectStore
	transactions.
	
  %lpoMap
  %lpoMapSet
	Mapping hashes for the lpObject elements found in ObjectStore
	transactions.
	
  <v051>
  %jobIdMap
  %jobIdMapSet
	Mapping hashes for the jobID elements found in DPS
	transactions.
  </v051>
	
  $agent
	The LWP UserAgent used to communicate with the Server.
	<v051>
	Since the introduction of the DPS playback, with its requirement
	for kept-alive connections, the $agent is instanciated by the
	Main procedure as needed.
	</v051>
	
  <v051>
  $lastDPSchallenge
	The last security challenge received from the Server
	(DPS Specific).
  </v051>

=cut

#	File-Scoped Variables:
#^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
my $errCode								=ERR_NONE;
my $errMsg								="";
my $logIndent							=0;

my $inFilename							="";
my $inData;
my $outFilename							="";
my $outputDir							=DEF_STORAGE_DIR;
my $setOutFilename						=0;

my $transactionID						=0;
my $transactionType						=TRANSACTION_NONE;

my $playbackID							="";
my $playbackUser						="";
my $playbackDesc						="";

my $recordingID							="";
my $recordingUser						="";
my $recordingDesc						="";
my $recordingTimestamp					="";
my $recordingServerType					="";
my $recordingServerVersion				="";
my $HTTPrecVersion						="";
my $recordingTimeout					="";

my $originalResponse_timeout			=0;
my $playbackResponse_timeout			=0;
my $originalRequestTime					="";
my $originalResponseTime				="";

my $result								=RESULT_OK;
my $resultErrInfo						="";

my $SERVER_HOST;
my $SERVER_PORT;
my $CLIENT_IP;
my $TIMEOUT;
my $PROC_STATUS_RETRY;
my $PROC_STATUS_DELAY;
my $DBG									=DBG_MIN;

my %headers 							=();
my %logHeaders 							=();

my %queryMap							=();
my %queryMapSet							=();
my %guidMap								=();
my %guidMapSet							=();
my %filenameMap							=();
my %filenameMapSet						=();
my %serializedMap						=();
my %serializedMapSet					=();
my %envLastUpdatedMap					=();
my %envLastUpdatedMapSet				=();
my %objLastUpdatedMap					=();
my %objLastUpdatedMapSet				=();
my %lpoMap								=();
my %lpoMapSet							=();
my %jobIdMap							=();
my %jobIdMapSet							=();

my $agent;
my $lastDPSchallenge;


=pod

=head1 JobStatusName Procedure

=head2 Description:

  Routine to retrieve the name of a given DPS_JOBSTATUS_CODE_*
  constant.

=head2 Input:

=over 4

=item 1

  $x	The DPS_JOBSTATUS_CODE_* constant whose name should be
		retrieved.

=back


=head2 Returns:

  The name of the $x constant, or "Unrecognized Job Status Code"
  for an unrecognized value.

=head2 Notes:
  <v052>
  This routine was introduced in v.0.52.
  </v052>

=cut

#	JobStatusName
#^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
sub JobStatusName
{
  my $x = $_[0];

  if($x == DPS_JOBSTATUS_CODE_PENDING)	{ return "Pending"; }
  if($x == DPS_JOBSTATUS_CODE_RUNNING)	{ return "Running"; }
  if($x == DPS_JOBSTATUS_CODE_FAILED)	{ return "Failed"; }
  if($x == DPS_JOBSTATUS_CODE_SUCCESS)	{ return "Success"; }
  return "Unrecognized Job Status Code";
}
#	End JobStatusName
#^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^

=pod

=head1 UnlockKey Procedure

=head2 Description:

  Routine to unlock the DPS key.

=head2 Input:


  N/A.

=head2 Returns:

  The unlocked key.

=head2 Notes:
  <v052>
  This routine was introduced in v.0.52.
  </v052>

=cut

#	UnlockKey
#^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
sub UnlockKey
{
  my $r = "";
  my @vals = unpack("C*", DPS_KEY);
  foreach my $v (@vals)	{ $r.=($v!=ord('_')? chr(++$v) : chr($v)); }
  $r=~s/_/ /g;
  return $r;
}
#	End UnlockKey
#^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^

=pod

=head1 DisplayMapping Procedure

=head2 Description:

  A procedure to display the current content of all the
  Mapping hashes to the logifle.

=head2 Input:

  N/A.

=head2 Returns:

  N/A.

=head2 Notes:

  This procedure disregards the current level of indentation.
  This procedure should be used only for custom debugging.

=cut

#	DisplayMappings:
#^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
sub DisplayMappings
{
  print LOG "Current Query mappings:\n";
  foreach my $k (sort keys %queryMap)
  {
	print LOG "$k => ";
	if($queryMapSet{$k})	{ print LOG $queryMap{$k}; }
	else					{ print LOG "NIET"; }
	print LOG "\n";
  }#FOREACH
  print LOG "Current GUID mappings:\n";
  foreach my $k (sort keys %guidMap)
  {
	print LOG "$k => ";
	if($guidMapSet{$k})	{ print LOG $guidMap{$k}; }
	else					{ print LOG "NIET"; }
	print LOG "\n";
  }#FOREACH
  print LOG "Current Filename mappings:\n";
  foreach my $k (sort keys %filenameMap)
  {
	print LOG "$k => ";
	if($filenameMapSet{$k})	{ print LOG $filenameMap{$k}; }
	else					{ print LOG "NIET"; }
	print LOG "\n";
  }#FOREACH
  print LOG "Current Serialized mappings:\n";
  foreach my $k (sort keys %serializedMap)
  {
	print LOG "$k => ";
	if($serializedMapSet{$k})	{ print LOG $serializedMap{$k}; }
	else					{ print LOG "NIET"; }
	print LOG "\n";
  }#FOREACH
  print LOG "Current ELU mappings:\n";
  foreach my $k (sort keys %envLastUpdatedMap)
  {
	print LOG "$k => ";
	if($envLastUpdatedMapSet{$k})	{ print LOG $envLastUpdatedMap{$k}; }
	else							{ print LOG "NIET"; }
	print LOG "\n";
  }#FOREACH
  print LOG "Current OLU mappings:\n";
  foreach my $k (sort keys %objLastUpdatedMap)
  {
	print LOG "$k => ";
	if($objLastUpdatedMapSet{$k})	{ print LOG $objLastUpdatedMap{$k}; }
	else							{ print LOG "NIET"; }
	print LOG "\n";
  }#FOREACH
  
  print LOG "Current lpObject mappings:\n";
  foreach my $k (sort keys %lpoMap)
  {
	print LOG "$k => ";
	if($lpoMapSet{$k})				{ print LOG $lpoMap{$k}; }
	else							{ print LOG "NIET"; }
	print LOG "\n";
  }#FOREACH

}
#	End DisplayMappings
#^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^

=pod

=head1 Indent Procedure

=head2 Description:

  A simple procedure used to indent the output to the current
  level of indentation.

=head2 Input:

=over 4

=item 1

  $n	The number of single white spaces by which the output should
		be indented.

=back

=head2 Returns:

  A scalar string composed of $n single white spaces.

=cut

#	Indent:
#^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
sub Indent
{
  my $n = $_[0];
  my $r = " "x$n;
  return $r;
}
#	End Indent
#^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^

=pod

=head1 ScanHeaders Procedure

=head2 Description:

  A procedure used as delegate by the ->scan method of the
  HTTP::Message objects to store the header into the %headers
  file-scoped hash.

=head2 Input:

=over 4

=item 1

  $_[0]	The string representation of the header, formatted
		as <header_name> '=' <header_value>

=back

=head2 Returns:

  N/A.

=head2 Notes:

  If the %headers hash already contains an entry for the <header_name>,
  the entry is overwritten.

=cut

#    ScanHeaders procedure:
#^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
sub ScanHeaders
{
  my ($name, $val) = @_;
  $headers{$name} = $val;
}
#    End ScanHeaders
#^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^

=pod

=head1 ScanLogHeaders Procedure

=head2 Description:

  A procedure used as delegate by the ->scan method of the
  HTTP::Message objects to store the header into the %logHeaders
  file-scoped hash.

=head2 Input:

=over 4

=item 1

  $_[0]	The string representation of the header, formatted
		as <header_name> '=' <header_value>

=back

=head2 Returns:

  N/A.

=head2 Notes:

  If the %logHeaders hash already contains an entry for the
  <header_name>, the entry is overwritten.

=cut

#    ScanLogHeaders procedure:
#^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
sub ScanLogHeaders
{
  my ($name, $val) = @_;
  $logHeaders{$name} = $val;
}
#    End ScanLogHeaders
#^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^

=pod

=head1 DeepCopyOf Procedure

=head2 Description:

  A procedure to produce a Deep Copy of an HTTP Message.

=head2 Input:

=over 4

=item 1

  $obj	The HTTP Message to be copied

=item 2

  $type	The type of the $obj message (see the HTTP_MSG_* constants).

=back

=head2 Returns:

  $copy	A Deep Copy of the $obj HTTP Message.

=cut

#	DeepCopyOf:
#^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
sub DeepCopyOf
{
  if($DBG >= DBG_MED)	{ LogFunctionEntry("DeepCopyOf"); }
  
  my ($obj, $type) = @_;
  
  if($DBG >= DBG_HIGH)
  {
	print LOG Indent($logIndent);
	print LOG "DeepCopyOf received an object of type $type (".HTTPmsgTypeName($type).")\n";
	print LOG Indent($logIndent);
	print LOG "The object is characterized by:\n";
	if($type == HTTP_MSG_ORIGINAL_REQUEST || $type == HTTP_MSG_PLAYBACK_REQUEST)
	{
	  print LOG Indent($logIndent);
	  print LOG "  Method:      ".$obj->method()."\n";
	  print LOG Indent($logIndent);
	  print LOG "  URI:         ".$obj->uri()."\n";
	}
	else
	{
	  print LOG Indent($logIndent);
	  print LOG "  Code:         ".$obj->code()."\n";
	  print LOG Indent($logIndent);
	  print LOG "  Message:      ".$obj->message()."\n";
	}
	print LOG Indent($logIndent);
	print LOG "  Content Size: ".length($obj->content())."\n";
  }
  
  my $copy;
  if($type == HTTP_MSG_ORIGINAL_REQUEST || $type == HTTP_MSG_PLAYBACK_REQUEST)
  {
	my $theMethod = $obj->method();
	my $theURI = $obj->uri();
	my $theHeadersOriginal = $obj->headers();
	my $theHeadersCopy = $theHeadersOriginal->clone();
	my $theContent = $obj->content();
	$copy = HTTP::Request->new($theMethod, $theURI, $theHeadersCopy, $theContent);
  }
  else
  {
	my $theCode = $obj->code();
	my $theMessage = $obj->message();
	my $theHeadersOriginal = $obj->headers();
	my $theHeadersCopy = $theHeadersOriginal->clone();
	my $theContent = $obj->content();
	$copy = HTTP::Response::new($theCode, $theMessage, $theHeadersCopy, $theContent);
  }
  
  if($DBG >= DBG_HIGH)
  {
	print LOG Indent($logIndent);
	print LOG "Copy of object characterized by:\n";
	if($type == HTTP_MSG_ORIGINAL_REQUEST || $type == HTTP_MSG_PLAYBACK_REQUEST)
	{
	  print LOG Indent($logIndent);
	  print LOG "  Method:      ".$copy->method()."\n";
	  print LOG Indent($logIndent);
	  print LOG "  URI:         ".$copy->uri()."\n";
	}
	else
	{
	  print LOG Indent($logIndent);
	  print LOG "  Code:         ".$copy->code()."\n";
	  print LOG Indent($logIndent);
	  print LOG "  Message:      ".$copy->message()."\n";
	}
	print LOG Indent($logIndent);
	print LOG "  Content Size: ".length($copy->content())."\n";
  }

  if($DBG >= DBG_MED)	{ LogFunctionExit("DeepCopyOf"); }
  return $copy;
}
#	End DeepCopyOf
#^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^

=pod

=head1 StripCDATA Procedure

=head2 Description:

  A procedure to strip the CDATA delimiters from the beginning and
  end of a given HTTP Message's content.

=head2 Input:

=over 4

=item 1

  $s	The message's content to be stripped.

=back

=head2 Returns:

  $r	The stripped message.

=head2 Notes:

  The $s parameter is assumed to be simple text (i.e., if it was
  encoded, it should have been decoded before this procedure
  is invoked).
  The "<![CDATA[" and "]]>" elements are stripped only from
  (respectively) the beginning and end of the $s message content.

=cut

#	StripCDATA:
#^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
sub StripCDATA
{
  if($DBG >= DBG_MED)	{ LogFunctionEntry("StripCDATA"); }
  
  my $s = $_[0];
  my $cdata1 = "\Q<![CDATA[\E";
  my $cdata2 = "\Q]]>\E";
  
  my $r = $s;
  $r =~ s/^\s+//;			# Trim leading spaces
  $r =~ s/^$cdata1//;		# Trim leading "<![CDATA["
  $r =~ s/$cdata2$//;		# Trim trailing "]]>"
  
  if($DBG >= DBG_MED)	{ LogFunctionExit("StripCDATA"); }
  return $r;
}
#	End StripCDATA
#^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^

=pod

=head1 HTTPmsgTypeName Procedure

=head2 Description:

  A procedure to retrieve the name of a given HTTP Message Type
  (see the HTTP_MSG_* constants).

=head2 Input:

=over 4

=item 1

  $type	The HTTP Message type code whose name should be retrieved.

=back

=head2 Returns:

  The name of the $type Type (or "Unrecognized HTTP Message Type").

=cut

#	HTTPmsgTypeName
#^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
sub HTTPmsgTypeName
{
  my $type = $_[0];
  if($type == HTTP_MSG_ORIGINAL_REQUEST)	{ return "Original HTTP Request"; }
  if($type == HTTP_MSG_ORIGINAL_RESPONSE)	{ return "Original HTTP Response"; }
  if($type == HTTP_MSG_PLAYBACK_REQUEST)	{ return "Playback HTTP Request"; }
  if($type == HTTP_MSG_PLAYBACK_RESPONSE)	{ return "Playback HTTP Response"; }
  return "Unrecognized HTTP Message Type";
}
#	End HTTPmsgTypeName
#^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^

=pod

=head1 ServerTypeCode Procedure

=head2 Description:

  A procedure to retrieve the code value for a given server type.

=head2 Input:

=over 4

=item 1

  $x	The name of the server type whose code value should be
		retrieved.

=back

=head2 Returns:

  The code value of the server type with name $x; the code values
  returned are the SERVER_* constants.

=head2 Notes:

  The procedure checks whether the $x parameter matches any of the
  SERVER_*_STR constants.

=cut

#	ServerTypeCode:
#^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
sub ServerTypeCode
{
  my $x = $_[0];
  if($x eq SERVER_OBS_STR)	{ return SERVER_OBS; }
  if($x eq SERVER_DPS_STR)	{ return SERVER_DPS; }
  return SERVER_UNREC;
}
#	End ServerTypeCode
#^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^

=pod

=head1 ServerTypeName Procedure

=head2 Description:

  A procedure to obtain the name of a specified server type.

=head2 Input:

=over 4

=item 1

  $x	The Server Type Code whose name should be returned.

=back

=head2 Returns:

  SERVER_OBS_STR					If $x matches SERVER_OBS;
  SERVER_DPS_STR					If $x matches SERVER_DPS;
  "Unrecognized Server Type Code"	Otherwise.

=cut

#	ServerTypeName:
#^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
sub ServerTypeName
{
  my $x = $_[0];
  if($x == SERVER_OBS)	{ return SERVER_OBS_STR; }
  if($x == SERVER_DPS)	{ return SERVER_DPS_STR; }
  return "Unrecognized Server Type Code ($x)";
}
#	End ServerTypeName
#^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^

=pod

=head1 TransactionTypeName Procedure

=head2 Description:

  A procedure to obtain the name of a specified transaction type.

=head2 Input:

=over 4

=item 1

  $x	The Transaction Type Code whose name should be returned.

=back

=head2 Returns:

  The name of the Transaction Type with Code $x, or
  "Unrecognized Transaction Code" if the parameter $x does not
  match any of the TRANSACTION_* constants.

=cut

#	TransactionTypeName:
#^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
sub TransactionTypeName
{
  my $x = $_[0];
  if($x ==  TRANSACTION_OBS_WSDL)								{ return "ObjectStore: WSDL"; }
  if($x ==  TRANSACTION_OBS_WSML)								{ return "ObjectStore: WSML"; }
  if($x ==  TRANSACTION_OBS_RETRIEVE_SUPPORTED_CLASSIFICATIONS)	{ return "ObjectStore: Retrieve Supported Classifications"; }
  if($x ==  TRANSACTION_OBS_EXECUTE_SEARCH)						{ return "ObjectStore: Execute Search"; }
  if($x ==  TRANSACTION_OBS_OBSTORE_POST)						{ return "ObjectStore: POST to obstore"; }
  if($x ==  TRANSACTION_OBS_ADD_OBJECT)							{ return "ObjectStore: Add Object"; }
  if($x ==  TRANSACTION_OBS_GET_LAST_UPDATE_TIME)				{ return "ObjectStore: Get Last Update Time"; }
  if($x ==  TRANSACTION_OBS_GET_OBJECT)							{ return "ObjectStore: Get Object"; }
  if($x ==  TRANSACTION_OBS_UPLOAD_OBJECT_DATA)					{ return "ObjectStore: Upload Object Data"; }
  if($x ==  TRANSACTION_OBS_DOWNLOAD_OBJECT_DATA)				{ return "ObjectStore: Download Object Data"; }
  if($x ==  TRANSACTION_OBS_OBSTORE_GET)						{ return "ObjectStore: GET from obstore"; }
  if($x ==  TRANSACTION_OBS_REMOVE_OBJECT)						{ return "ObjectStore: Remove Object"; }
  if($x ==	TRANSACTION_OBS_UPDATE_OBJECT)						{ return "ObjectStore: Update Object"; }
  if($x ==	TRANSACTION_DPS_PING)								{ return "DPS: Ping"; }
  if($x ==	TRANSACTION_DPS_SUBMIT)								{ return "DPS: Submit Job"; }
  if($x ==	TRANSACTION_DPS_LISTJOBS)							{ return "DPS: List Jobs"; }
  if($x ==	TRANSACTION_DPS_LISTFILES)							{ return "DPS: List Job Files"; }
  if($x ==	TRANSACTION_DPS_COPY)								{ return "DPS: Copy"; }
  if($x ==	TRANSACTION_DPS_DELETEJOB)							{ return "DPS: Delete Job"; }
  if($x ==	TRANSACTION_DPS_DELETEFILE)							{ return "DPS: Delete File"; }
  if($x ==	TRANSACTION_DPS_GETINFO)							{ return "DPS: Get Info"; }
  if($x ==	TRANSACTION_DPS_SERVERFILES)						{ return "DPS: Server Files"; }
  if($x ==	TRANSACTION_DPS_TRANSFER)							{ return "DPS: Transfer"; }
  if($x ==	TRANSACTION_DPS_MOVEFILE)							{ return "DPS: Move File"; }
  if($x ==	TRANSACTION_DPS_CHANGESCHEDULE)						{ return "DPS: Change Schedule"; }
  if($x ==	TRANSACTION_DPS_SECURITY)							{ return "DPS: Security Check"; }
  
  if($x == TRANSACTION_NONE)									{ return "Generic Transaction"; }
  return "Unrecognized Transaction Code $x";
}
#	End TransactionTypeName
#^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^

=pod

=head1 TypeOfRequest Procedure

=head2 Description:

  A procedure to determine which transaction type the given request
  initiates.

=head2 Input:

=over 4

=item 1

  $request	The HTTP::Request whose type should be determined.

=back

=head2 Returns:

  $answer	The TRANSACTION_* constant corresponding to the
			$request parameter.

=head2 Notes:

  <v052>
  The type of transaction for a DPS transaction is determined
  as follows:
  ~ for even-numbered transactions (0, 2, ...): the type is always
	TRANSACTION_DPS_SECURITY;
  ~ for odd-numbered transactions (1, 3, ...): the type is determined
	by extracting the uCommand value in the $request. This value
	indicates the type of transaction.
  </v052>

=cut

#	TypeOfRequest:
#^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
sub TypeOfRequest
{
  if($DBG >= DBG_MED)	{ LogFunctionEntry("TypeOfRequest"); }
  
  my $request	= $_[0];
  
  # Assume this is a TRANSACTION_NONE (i.e. unrecognized) request:
  my $answer	= TRANSACTION_NONE;
  
#<v051>
#For the DPS transactions, all even transactions are TRANSACTION_DPS_SECURITY;
#The odd transactions' type is determined based on the uCommand field
#in the request.
  if($recordingServerType==SERVER_DPS)
  {
	if($transactionID%2==0)	{ $answer = TRANSACTION_DPS_SECURITY; }
	else
	{
	  my $x = ExtractDPSCommandFromRequest($request->content);
	  if($x==1)		{ $answer = TRANSACTION_DPS_PING; }
	  elsif($x==2)	{ $answer = TRANSACTION_DPS_SUBMIT; }
	  elsif($x==3)	{ $answer = TRANSACTION_DPS_LISTJOBS; }
	  elsif($x==4)	{ $answer = TRANSACTION_DPS_LISTFILES; }
	  elsif($x==6)	{ $answer = TRANSACTION_DPS_COPY; }
	  elsif($x==7)	{ $answer = TRANSACTION_DPS_DELETEJOB; }
	  elsif($x==8)	{ $answer = TRANSACTION_DPS_DELETEFILE; }
	  elsif($x==12)	{ $answer = TRANSACTION_DPS_GETINFO; }
	  elsif($x==15)	{ $answer = TRANSACTION_DPS_SERVERFILES; }
	  elsif($x==16)	{ $answer = TRANSACTION_DPS_TRANSFER; }
	  elsif($x==17)	{ $answer = TRANSACTION_DPS_MOVEFILE; }
	  elsif($x==20)	{ $answer = TRANSACTION_DPS_CHANGESCHEDULE; }
	}
  }
#</v051>
  else
  {
	# Wrap the OBS_* constants in \Q \E for use in Regular Expressions
	# below:
	my $obs_wsdl_request_uri						= "\Q".OBS_WSDL_REQUEST_URI."\E";
	my $obs_wsml_request_uri						= "\Q".OBS_WSML_REQUEST_URI."\E";
	my $obs_obstore_uri								= "\Q".OBS_OBSTORE_URI."\E";
	my $obs_exe_uri									= "\Q".OBS_EXE_URI."\E";
	my $obs_soap_retrieve_supported_classifications	= "\Q".OBS_SOAP_RETRIEVE_SUPPORTED_CLASSIFICATIONS."\E";
	my $obs_soap_execute_search						= "\Q".OBS_SOAP_EXECUTE_SEARCH."\E";
	my $obs_soap_add_object							= "\Q".OBS_SOAP_ADD_OBJECT."\E";
	my $obs_soap_get_last_update_time				= "\Q".OBS_SOAP_GET_LAST_UPDATE_TIME."\E";
	my $obs_soap_get_object							= "\Q".OBS_SOAP_GET_OBJECT."\E";
	my $obs_soap_upload_object_data					= "\Q".OBS_SOAP_UPLOAD_OBJECT_DATA."\E";
	my $obs_soap_download_object_data				= "\Q".OBS_SOAP_DOWNLOAD_OBJECT_DATA."\E";
	my $obs_soap_remove_object						= "\Q".OBS_SOAP_REMOVE_OBJECT."\E";
	my $obs_soap_update_object						= "\Q".OBS_SOAP_UPDATE_OBJECT."\E";
	
	# Get the request's method (GET || POST ||...)
	my $theMethod = $request->method();
	# Get the request's URI:
	my $uri		= $request->uri();
	
	if($DBG >= DBG_HIGH)
	{
	  print LOG Indent($logIndent);
	  print LOG "TypeOfRequest received a request characterized by:\n";
	  print LOG Indent($logIndent);
	  print LOG "  Method: $theMethod\n";
	  print LOG Indent($logIndent);
	  print LOG "  URI:     $uri\n";
	}
	
	# GET Requests:
	if($theMethod eq "GET")
	{
	  if($uri =~ /$obs_wsdl_request_uri$/)										{ $answer = TRANSACTION_OBS_WSDL; }
	  elsif($uri =~ /$obs_wsml_request_uri$/)									{ $answer = TRANSACTION_OBS_WSML; }
	  
	  #Note that the next is the only match that does not require the
	  #pattern to be found at the end of the URI string !!!
	  elsif($uri =~ /$obs_obstore_uri/)											{ $answer = TRANSACTION_OBS_OBSTORE_GET; }
	}
	elsif($theMethod eq "POST")
	{
	  if($uri =~ /$obs_exe_uri$/)
	  {
		#The various Types based on the SOAP Action header:
		my $soapAction = $request->header('SOAPAction');
		
		#Trim the leading and trailing " returned by the call to header..
		my $soapActionS = length($soapAction);
		$soapAction = substr($soapAction, 1, $soapActionS-2);
		
		if($DBG >= DBG_HIGH)
		{
		  print LOG Indent($logIndent);
		  print LOG "It appears to be a POST directed to the ObjectStore program.\n";
		  print LOG Indent($logIndent);
		  print LOG "The type of Transaction depends on the 'SoapAction' header: $soapAction\n";
		}
		
		if		($soapAction =~ /$obs_soap_retrieve_supported_classifications$/)	{ $answer = TRANSACTION_OBS_RETRIEVE_SUPPORTED_CLASSIFICATIONS; }
		elsif	($soapAction =~ /$obs_soap_execute_search$/)						{ $answer = TRANSACTION_OBS_EXECUTE_SEARCH; }
		elsif	($soapAction =~ /$obs_soap_add_object$/)							{ $answer = TRANSACTION_OBS_ADD_OBJECT; }
		elsif	($soapAction =~ /$obs_soap_get_last_update_time$/)					{ $answer = TRANSACTION_OBS_GET_LAST_UPDATE_TIME; }
		elsif	($soapAction =~ /$obs_soap_get_object$/)							{ $answer = TRANSACTION_OBS_GET_OBJECT; }
		elsif	($soapAction =~ /$obs_soap_upload_object_data$/)					{ $answer = TRANSACTION_OBS_UPLOAD_OBJECT_DATA; }
		elsif	($soapAction =~ /$obs_soap_download_object_data$/)					{ $answer = TRANSACTION_OBS_DOWNLOAD_OBJECT_DATA; }
		elsif	($soapAction =~ /$obs_soap_remove_object$/)							{ $answer = TRANSACTION_OBS_REMOVE_OBJECT; }
		elsif 	($soapAction =~ /$obs_soap_update_object$/)							{ $answer = TRANSACTION_OBS_UPDATE_OBJECT; }
	  }
	  # The POST to Obstore case:
	  elsif($uri =~ /$obs_obstore_uri$/)											{ $answer = TRANSACTION_OBS_OBSTORE_POST; }
	}
	# ELSE the method is neither GET nor POST,
	# leave the answer to TRANSACTION_NONE
	
  }#Closes the if($recordingServerType==SERVER_DPS)-else
  
  if($DBG >= DBG_MED)
  {
	print LOG Indent($logIndent);
	print LOG "TypeOfRequest will return: $answer (".TransactionTypeName($answer).")\n";
	LogFunctionExit("TypeOfRequest");
  }
  return $answer;
}
#	End TypeOfRequest
#^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^

=pod

=head1 LogFunctionEntry Procedure

=head2 Description:

  A procedure to log a function entry to the logfile, with proper
  indentation.

=head2 Input:

=over 4

=item 1

  $fn	The name of the function entered.

=back

=head2 Returns:

  N/A.
  
=head2 Notes:

  After logging the function entry at the current level of indentation,
  the routine increments the indentation level.

=cut

#	LogFunctionEntry:
#^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
sub LogFunctionEntry
{
  my $fn = $_[0];
  print LOG Indent($logIndent);
  print LOG "Entering $fn procedure.\n";
  $logIndent+=2;
}
#	End LogFunctionEntry
#^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^

=pod

=head1 LogFunctionExit Procedure

=head2 Description:

  A procedure to log a function exit to the logfile, with proper
  indentation.

=head2 Input:

=over 4

=item 1

  $fn	The name of the function exited.

=back

=head2 Returns:

  N/A.
  
=head2 Notes:

  Before logging the function exit, the routine decrements the current
  indentation level.

=cut

#	LogFunctionExit:
#^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
sub LogFunctionExit
{
  my $fn = $_[0];
  $logIndent-=2;
  print LOG Indent($logIndent);
  print LOG "Exiting $fn procedure.\n";
}
#	End LogFunctionExit
#^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^

=pod

=head1 LogMsg Procedure

=head2 Description:

  A procedure to log a message to the logfile, with proper indentation.

=head2 Input:

=over 4

=item 1

  $msg	The message to be logged.

=back

=head2 Returns:

  N/A.
  
=cut

#	LogMsg:
#^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
sub LogMsg
{
  my $msg = $_[0];
  print STDERR $msg;
  print LOG Indent($logIndent);
  print LOG $msg;
}
#	End of LogMsg
#^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^

=pod

=head1 StartupMsg Procedure

=head2 Description:

  A procedure to produce a Startup Message for the HTTP Playback tool.

=head2 Input:

=over 4

  N/A.

=back

=head2 Returns:

  $msg	The startup message.
  
=head2 Notes:

  The startup message includes the current time, the parameters
  describing the playback (ID, Author, Timeout, Proc_Status Retry,
  Proc_Status Delay, Description), and the similar parameters
  gathered from the input recording file.

=cut

#	StartupMsg:
#^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
sub StartupMsg
{
  my ($Tsec, $Tmin, $Thr, $Tmday, $Tmon, $Tyear) = localtime time;
  my $Ttime = sprintf "%04d-%02d-%02d-%02d-%02d-%02d", $Tyear+1900, $Tmon+1, $Tmday, $Thr, $Tmin, $Tsec;
  my $msg = "*" x PAGE_WIDTH;
  $msg.="\n";
  $msg.="* HTTPplay Tool Started at $Ttime.\n";
  $msg.="* Testing server $SERVER_HOST : $SERVER_PORT.\n";
  $msg.="*\n";
  $msg.="* Playback Parameters:\n";
  $msg.="*   Input File Name:            $inFilename\n";
  $msg.="*   Output File Name:           $outFilename\n";
  $msg.="*   Output Directory:           $outputDir\n";
  $msg.="*   Playback ID:                $playbackID\n";
  $msg.="*   Playback User:              $playbackUser\n";
  $msg.="*   Playback Timeout:           $TIMEOUT\n";
  $msg.="*   Playback Proc_Status Retry: $PROC_STATUS_RETRY\n";
  $msg.="*   Playback Proc_Status Delay: $PROC_STATUS_DELAY\n";
  $msg.="*   Playback Debug Level:       $DBG\n";
  $msg.="*   Playback Description:\n$playbackDesc\n";
  $msg.="*\n";
  $msg.="*" x PAGE_WIDTH;
  $msg.="\n\n";
  return $msg;
}
#	End StartupMsg
#^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^

=pod

=head1 QuitMsg Procedure

=head2 Description:

  A procedure to produce a Quit Message for the HTTP Playback tool.

=head2 Input:

=over 4

  N/A.

=back

=head2 Returns:

  $msg	The quit message.
  
=head2 Notes:

  The quit message includes the current time, and the result of the
  playback (i.e. the value of the file-scoped $result variable).
  If the result is other then RESULT_OK, more information are included,
  from the file-scoped $resultErrInfo and $transactionID variables.

=cut

#	QuitMsg:
#^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
sub QuitMsg
{
  my ($Tsec, $Tmin, $Thr, $Tmday, $Tmon, $Tyear) = localtime time;
  my $Ttime = sprintf "%04d-%02d-%02d-%02d-%02d-%02d", $Tyear+1900, $Tmon+1, $Tmday, $Thr, $Tmin, $Tsec;
  my $msg = "\n";
  $msg.= "*" x PAGE_WIDTH;
  $msg.="\n";
  $msg.="* HTTPplay Tool Done at $Ttime.\n";
  $msg.="* The Result of the Playback is the following:\n";
  $msg.="\n";
  $msg.=ResultCodeDesc();
  $msg.="\n";
  if($result != RESULT_OK)
  {
	$msg.="$resultErrInfo\n";
	$msg.="[ Transaction ID: $transactionID ]\n";
  }
  $msg.="* Details of the Playback are available in the file '$outFilename'\n";
  $msg.="*" x PAGE_WIDTH;
  $msg.="\n\n";
  return $msg;  
}
#	End of QuitMsg
#^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^

=pod

=head1 HTTPmsgLog Procedure

=head2 Description:

  A procedure to log an HTTP Message to the logfile, with proper
  indentation.

=head2 Input:

=over 4

=item 1

  $obj	The HTTP message to be logged.

=item 2

  $type	The type of the $obj message.

=back

=head2 Returns:

  N/A.
  
=head2 Notes:

  The $type parameter should be equal to one of the HTTP_MSG_*
  constants. 
  The routine uses the %logHeaders file-scoped hash to list the
  headers in the $obj message.

=cut

#	HTTPmsgLog:
#^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
sub HTTPmsgLog
{
  my ($obj, $type) = @_;
  my $r = "";
  
  $r.= "-"x PAGE_WIDTH;
  $r.="\n";
  $r = "[HTTP Message of type $type (".HTTPmsgTypeName($type).")]\n";
  
  if($type == HTTP_MSG_ORIGINAL_REQUEST || $type == HTTP_MSG_PLAYBACK_REQUEST)
  {
	$r.="METHOD: ".$obj->method()."\n";
	$r.="URI:    ".$obj->uri()."\n";
  }
  else
  {
	$r.="CODE:    ".$obj->code()."\n";
	$r.="MESSAGE: ".$obj->message()."\n";
	if( ($type == HTTP_MSG_ORIGINAL_RESPONSE && $originalResponse_timeout==1)
	  ||($type == HTTP_MSG_PLAYBACK_RESPONSE && $playbackResponse_timeout==1) )
	{ $r.="***[ ! This Was a Time-Out Response ! ]***\n"; }
  }
  $r.="HEADERS:\n";
  %logHeaders = ();
  $obj->scan(\&ScanLogHeaders);
  foreach (sort keys %logHeaders)
  { $r.="  $_ => $logHeaders{$_}\n"; }
  
  $r.="CONTENT:\n";
  $r.=$obj->content();
  $r.="\n";
  $r.= "-"x PAGE_WIDTH;
  $r.="\n";

  return $r;
}
#	End HTTPmsgLog
#^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^

=pod

=head1 ResultCodeDesc Procedure

=head2 Description:

  A procedure to obtain the description for the current value of the
  file-scoped $result variable.
  
=head2 Input:

=over 4

  N/A.

=back

=head2 Returns:

  $msg	A human-readable description of the current value of the
		file-scoped $result variable.
  
=head2 Notes:

  The value of the file-scoped $result variable should be one of the
  RESULT_* constants.

=cut

#	ResultCodeDesc:
#^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
sub ResultCodeDesc
{
  my $msg = "";
  
  if	($result == RESULT_OK)				{ $msg.="No Error"; }
  elsif	($result == RESULT_DIFF_TO)			{ $msg.="Timeout Responce Difference Detected"; }
  elsif	($result == RESULT_DIFF_CODE)		{ $msg.="Code Difference Detected"; }
  elsif	($result == RESULT_DIFF_HEADERS)	{ $msg.="Headers Difference Detected"; }
  elsif	($result == RESULT_DIFF_CONTENT)	{ $msg.="Content Difference Detected"; }
  else										{ $msg.="Unrecognized Result Code"; }
  
  $msg.=" (Code=$result)";
  return $msg;
}
#	End ResultCodeDesc
#^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^

=pod

=head1 XML_PlaybackHeader Procedure

=head2 Description:

  A procedure to produce the header for the output recording file
  (a.k.a. the playback file).
  
=head2 Input:

=over 4

  N/A.

=back

=head2 Returns:

  $r	The header for the playback file.
  
=head2 Notes:

  The header for the playback file includes the following elements:
  ~ The XML declaration (<?xml version="1.0" encoding="UTF-8" ?>);
  ~ The opening tag for the root <HTTPPLAYBACK> element;
  ~ The <INFO> element, including the following children:
	~ <RECORDING_TIMESTAMP>:	The timestamp from the recording file;
	~ <PLAYBACK_TIMESTAMP>:		The timestamp of the playback;
	~ <RECORDING_ID>:			The ID from the recording file;
	~ <PLAYBACK_ID>:			The ID of the playback;
	~ <RECORDING_USER>:			The Author from the recording file;
	~ <PLAYBACK_USER>:			The AUthor of the playback;
	~ <HTTPREC_VERSION>:		The version of the HTTP Recording tool
								used to produce the recording file;
	~ <HTTPPLAY_VERSION>:		The version of the HTTP Playback tool
								used to produce the playback file;
	~ <SERVER_TYPE>:			The type of server used during the
								recording and playback (see the
								SERVER_*_STR constants);
	~ <RECORDING_TIMEOUT>:		The timeout value used during the
								recording;
	~ <PLAYBACK_TIMEOUT>:		The timeout value used during the
								playback;
	~ <RECORDING_DESC>:			The description from the recording file;
	~ <PLAYBACK_DESC>:			The description of the playback;
	~ <PLAYBACK_RETRY>:			The PROC_STATUC_RETRY value used during
								the playback;
	~ <PLAYBACK_DELAY>:			The PROC_STATUS_DELAY value used during
								the playback.
  <v052>
  A new element has been introduced in the <INFO> element:
	~ <CLIENT_SERVER_VERSION>:	The version of the Client/Server
								software used during the recording and
								playback. This element is added between
								the <SERVER_TYPE> and
								<RECORDING_TIMEOUT> elements.
  </v052>

=cut

#	XML_PlaybackHeader:
#^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
sub XML_PlaybackHeader
{
  if ($DBG >= DBG_HIGH)	{ LogFunctionEntry("XML_PlaybackHeader"); }

  my $r = "";
  my ($Tsec, $Tmin, $Thr, $Tmday, $Tmon, $Tyear) = localtime time;
  my $Ttime = sprintf "%04d-%02d-%02d-%02d-%02d-%02d", $Tyear+1900, $Tmon+1, $Tmday, $Thr, $Tmin, $Tsec;
  my $theVersion = VERSION;
  
  #Data from the Recording File:
  if(exists($inData->{INFO}->{RECORDING_ID}->{content}))
  { $recordingID = $inData->{INFO}->{RECORDING_ID}->{content}; }
  else
  { $recordingID = ""; }
  
  if(exists($inData->{INFO}->{RECORDING_USER}->{content}))
  { $recordingUser = $inData->{INFO}->{RECORDING_USER}->{content}; }
  else
  { $recordingUser = ""; }
  
  if(exists($inData->{INFO}->{RECORDING_DESC}->{content}))
  { $recordingDesc = $inData->{INFO}->{RECORDING_DESC}->{content}; }
  else
  { $recordingDesc = ""; }
  
  if(exists($inData->{INFO}->{RECORDING_TIMESTAMP}->{content}))
  { $recordingTimestamp = $inData->{INFO}->{RECORDING_TIMESTAMP}->{content}; }
  else
  { $recordingTimestamp = ""; }
  
  my $recordingServerTypeName = "";
  if(exists($inData->{INFO}->{SERVER_TYPE}->{content}))
  { $recordingServerTypeName= $inData->{INFO}->{SERVER_TYPE}->{content}; }
  else
  {
	$errCode = ERR_MISS_REC_SERVER;
	ReportError("XML_PlaybackHeader");
  }
  $recordingServerType = ServerTypeCode($recordingServerTypeName);
  if($recordingServerType == SERVER_UNREC)
  {
	$errCode = ERR_UNREC_REC_SERVER;
	$errMsg = "Content of HTTPRECORDING->INFO->SERVER_TYPE: $recordingServerTypeName";
	ReportError("XML_PlaybackHeader");
  }
  
  if(exists($inData->{INFO}->{CLIENT_SERVER_VERSION}->{content}))
  { $recordingServerVersion = $inData->{INFO}->{CLIENT_SERVER_VERSION}->{content}; }
  else
  { $recordingServerVersion = ""; }
  
  if(exists($inData->{INFO}->{HTTPREC_VERSION}->{content}))
  { $HTTPrecVersion	= $inData->{INFO}->{HTTPREC_VERSION}->{content}; }
  else
  { $HTTPrecVersion = ""; }
  
  if(exists($inData->{INFO}->{RECORDING_TIMEOUT}->{content}))
  { $recordingTimeout	= $inData->{INFO}->{RECORDING_TIMEOUT}->{content}; }
  else
  { $recordingTimeout = ""; }
  
  $r.="<?xml version=\"1.0\" encoding=\"UTF-8\" ?>\n";
  $r.="<HTTPPLAYBACK>\n";
  $r.="  <INFO>\n";
  $r.="    <RECORDING_TIMESTAMP>$recordingTimestamp</RECORDING_TIMESTAMP>\n";
  $r.="    <PLAYBACK_TIMESTAMP>$Ttime</PLAYBACK_TIMESTAMP>\n";
  $r.="    <RECORDING_ID>$recordingID</RECORDING_ID>\n";
  $r.="    <PLAYBACK_ID>$playbackID</PLAYBACK_ID>\n";
  $r.="    <RECORDING_USER>$recordingUser</RECORDING_USER>\n";
  $r.="    <PLAYBACK_USER>$playbackUser</PLAYBACK_USER>\n";
  $r.="    <HTTPREC_VERSION>$HTTPrecVersion</HTTPREC_VERSION>\n";
  $r.="    <HTTPPLAY_VERSION>$theVersion</HTTPPLAY_VERSION>\n";
  $r.="    <SERVER_TYPE>$recordingServerTypeName</SERVER_TYPE>\n";
  $r.="    <CLIENT_SERVER_VERSION>$recordingServerVersion</CLIENT_SERVER_VERSION>\n";
  $r.="    <RECORDING_TIMEOUT>$recordingTimeout</RECORDING_TIMEOUT>\n";
  $r.="    <PLAYBACK_TIMEOUT>$TIMEOUT</PLAYBACK_TIMEOUT>\n";
  $r.="    <RECORDING_DESC>$recordingDesc</RECORDING_DESC>\n";
  $r.="    <PLAYBACK_DESC>$playbackDesc</PLAYBACK_DESC>\n";
  $r.="    <PLAYBACK_RETRY>$PROC_STATUS_RETRY</PLAYBACK_RETRY>\n";
  $r.="    <PLAYBACK_DELAY>$PROC_STATUS_DELAY</PLAYBACK_DELAY>\n";
  $r.="  </INFO>\n";
  
  if ($DBG >= DBG_HIGH)	{ LogFunctionExit("XML_PlaybackHeader"); }
  return $r;
}
#	End of XML_PlaybackHeader
#^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^

=pod

=head1 XML_PlaybackFooter Procedure

=head2 Description:

  A procedure to produce the footer for the output recording file
  (a.k.a. the playback file).
  
=head2 Input:

=over 4

  N/A.

=back

=head2 Returns:

  $r	The footer for the playback file.
  
=head2 Notes:

  The footer for the playback file includes the following elements:
  ~ The closing tag for the root <HTTPPLAYBACK> element.

=cut

#	XML_PlaybackFooter:
#^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
sub XML_PlaybackFooter
{
  if ($DBG >= DBG_HIGH)	{ LogFunctionEntry("XML_PlaybackFooter"); }
  
  my $r = "</HTTPPLAYBACK>\n";
  
  if ($DBG >= DBG_HIGH)	{ LogFunctionExit("XML_PlaybackFooter"); }
  return $r;
}
#	End XML_PlaybackFooter
#^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^

=pod

=head1 XML_TransactionHeader Procedure

=head2 Description:

  A procedure to produce the header for a playback transaction.
  
=head2 Input:

=over 4

  N/A.

=back

=head2 Returns:

  $r	The header for a transaction element.
  
=head2 Notes:

  The header for a transaction element includes the following elements:
  ~ The opening tag of the <TRANSACTION> element, including its
	required name attribute, set to be equal to the current value of the
	file-scoped $transactionID variable.

=cut

#	XML_TransactionHeader:
#^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
sub XML_TransactionHeader
{
  if ($DBG >= DBG_HIGH)	{ LogFunctionEntry("XML_TransactionHeader"); }
  
  my $r = "<TRANSACTION name=\"$transactionID\">\n";
  
  if ($DBG >= DBG_HIGH)	{ LogFunctionExit("XML_TransactionHeader"); }
  return $r;  
}
#	End XML_TransactionHeader
#^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
=pod

=head1 XML_TransactionFooter Procedure

=head2 Description:

  A procedure to produce the footer for a playback transaction.
  
=head2 Input:

=over 4

  N/A.

=back

=head2 Returns:

  $r	The footer for a transaction element.
  
=head2 Notes:

  The footer for a transaction element includes the following elements:
  ~ The closing tag of the <TRANSACTION> element.

=cut

#	XML_TransactionFooter:
#^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
sub XML_TransactionFooter
{
  if ($DBG >= DBG_HIGH)	{ LogFunctionEntry("XML_TransactionFooter"); }
  
  my $r = "</TRANSACTION>\n";
  
  if ($DBG >= DBG_HIGH)	{ LogFunctionExit("XML_TransactionFooter"); }
  return $r;  
}
#	End XML_TransactionFooter
#^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^

=pod

=head1 XML_OriginalRequest Procedure

=head2 Description:

  A procedure to produce an <ORIGINAL_REQUEST> XML element.

=head2 Input:

=over 4

=item 1

  $request	The HTTP::Request to be represented by the element
			produced.

=back

=head2 Returns:

  $obj	The <ORIGINAL_REQUEST> element describing the $obj
		HTTP::Request.
  
=head2 Notes:

  The scalar returned includes (in order):
  ~ The <ORIGINAL_REQUEST> element, including the required
	time attribute (set to be equal to the current time, in the
	form YYYY-MM-DD-hh-mm-ss), and the following children:
	~ <ORIGINAL_REQUEST_METHOD>:	The method of the $request;
	~ <ORIGINAL_REQUEST_URI>:		The URI of the $request;
	~ <ORIGINAL_REQUEST_HEADER>:	Optional, unbounded class
									of children, each containing
									a header of the $request, in the
									form <name>=<value>;
	~ <ORIGINAL_REQUEST_CONTENT>:	The content of the $request,
									wrapped in a "<![CDATA[" "]]>"
									tag, and encoded (MIME::Base64);
									This element also includes the
									required size attribute, set to be
									equal to the size of the wrapped
									and encoded content, in bytes.

=cut

#	XML_OriginalRequest:
#^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
sub XML_OriginalRequest
{
  if ($DBG >= DBG_HIGH)	{ LogFunctionEntry("XML_OriginalRequest"); }
  
  my $obj = $_[0];
  my $theMethod = $obj->method();
  my $theURI = $obj->uri();
  
  my $r = "";
  $r.="  <ORIGINAL_REQUEST time=\"$originalRequestTime\">\n";
  $r.="    <ORIGINAL_REQUEST_METHOD>$theMethod</ORIGINAL_REQUEST_METHOD>\n";
  $r.="    <ORIGINAL_REQUEST_URI>$theURI</ORIGINAL_REQUEST_URI>\n";

  %headers = ();
  $obj->scan(\&ScanHeaders);
  foreach (sort keys %headers)
  { $r.="    <ORIGINAL_REQUEST_HEADER>$_=$headers{$_}</ORIGINAL_REQUEST_HEADER>\n"; }
  
  my $theContent		= $obj->content;
  my $wrappedContent	= "<![CDATA[".$theContent."]]>";
  my $encodedContent	= encode_base64($wrappedContent);
  my $encodedSize		= length($encodedContent);
  
  $r.="    <ORIGINAL_REQUEST_CONTENT size=\"$encodedSize\">\n$encodedContent</ORIGINAL_REQUEST_CONTENT>\n";  
  $r.="  </ORIGINAL_REQUEST>\n";
  
  if ($DBG >= DBG_HIGH)	{ LogFunctionExit("XML_OriginalRequest"); }
  return $r;    
}
#	End XML_OriginalRequest
#^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^

=pod

=head1 XML_OriginalResponse Procedure

=head2 Description:

  A procedure to produce an <ORIGINAL_RESPONSE> XML element.

=head2 Input:

=over 4

=item 1

  $obj	The HTTP::Response to be represented by the element
		produced.

=back

=head2 Returns:

  $r	The <ORIGINAL_RESPONSE> element describing the $obj
		HTTP::Response.
  
=head2 Notes:

  The scalar returned includes (in order):
  ~ The <ORIGINAL_RESPONSE> element, including the required
	time attribute (set to be equal to the current time, in the
	form YYYY-MM-DD-hh-mm-ss), the required timeout attribute (set to
	be equal to the value of the file-scoped $originalResponse_timeout
	variable), and the following children:
	~ <ORIGINAL_RESPONSE_CODE>:		The code of the $response;
	~ <ORIGINAL_RESPONSE_MESSAGE>:	The Message of the $response;
	~ <ORIGINAL_RESPONSE_HEADER>:	Optional, unbounded class
									of children, each containing
									a header of the $response, in the
									form <name>=<value>;
	~ <ORIGINAL_RESPONSE_CONTENT>:	The content of the $response,
									wrapped in a "<![CDATA[" "]]>"
									tag, and encoded (MIME::Base64);
									This element also includes the
									required size attribute, set to be
									equal to the size of the wrapped
									and encoded content, in bytes;

=cut

#	XML_OriginalResponse:
#^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
sub XML_OriginalResponse
{
  if ($DBG >= DBG_HIGH)	{ LogFunctionEntry("XML_OriginalResponse"); }
  
  my $obj = $_[0];
  my $theCode = $obj->code();
  my $theMessage = $obj->message();
  
  my $r = "";
  $r.="  <ORIGINAL_RESPONSE time=\"$originalResponseTime\" timeout=\"$originalResponse_timeout\">\n";
  $r.="    <ORIGINAL_RESPONSE_CODE>$theCode</ORIGINAL_RESPONSE_CODE>\n";
  $r.="    <ORIGINAL_RESPONSE_MESSAGE>$theMessage</ORIGINAL_RESPONSE_MESSAGE>\n";

  if($originalResponse_timeout == 0)
  {
	%headers = ();
	$obj->scan(\&ScanHeaders);
	foreach (sort keys %headers)
	  { $r.="    <ORIGINAL_RESPONSE_HEADER>$_=$headers{$_}</ORIGINAL_RESPONSE_HEADER>\n"; }
	
	my $theContent		= $obj->content;
	my $wrappedContent	= "<![CDATA[".$theContent."]]>";
	my $encodedContent	= encode_base64($wrappedContent);
	my $encodedSize		= length($encodedContent);
	
	$r.="    <ORIGINAL_RESPONSE_CONTENT size=\"$encodedSize\">\n$encodedContent</ORIGINAL_RESPONSE_CONTENT>\n";
  }
  $r.="  </ORIGINAL_RESPONSE>\n";
  
  
  if ($DBG >= DBG_HIGH)	{ LogFunctionExit("XML_OriginalResponse"); }
  return $r;
}
#	End XML_OriginalResponset
#^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^

=pod

=head1 XML_PlaybackRequest Procedure

=head2 Description:

  A procedure to produce a <PLAYBACK_REQUEST> XML element.

=head2 Input:

=over 4

=item 1

  $obj	The HTTP::Request to be represented by the element
		produced.

=back

=head2 Returns:

  $r	The <PLAYBACK_REQUEST> element describing the $obj
		HTTP::Request.
  
=head2 Notes:

  The scalar returned includes (in order):
  ~ The <PLAYBACK_REQUEST> element, including the required
	time attribute (set to be equal to the current time, in the
	form YYYY-MM-DD-hh-mm-ss), and the following children:
	~ <PLAYBACK_REQUEST_METHOD>:	The method of the $request;
	~ <PLAYBACK_REQUEST_URI>:		The URI of the $request;
	~ <PLAYBACK_REQUEST_HEADER>:	Optional, unbounded class
									of children, each containing
									a header of the $request, in the
									form <name>=<value>;
	~ <PLAYBACK_REQUEST_CONTENT>:	The content of the $request,
									wrapped in a "<![CDATA[" "]]>"
									tag, and encoded (MIME::Base64);
									This element also includes the
									required size attribute, set to be
									equal to the size of the wrapped
									and encoded content, in bytes.

=cut

#	XML_PlaybackRequest:
#^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
sub XML_PlaybackRequest
{
  if ($DBG >= DBG_HIGH)	{ LogFunctionEntry("XML_PlaybackRequest"); }
  
  my ($Tsec, $Tmin, $Thr, $Tmday, $Tmon, $Tyear) = localtime time;
  my $Ttime = sprintf "%04d-%02d-%02d-%02d-%02d-%02d", $Tyear+1900, $Tmon+1, $Tmday, $Thr, $Tmin, $Tsec;
  
  my $obj = $_[0];
  my $theMethod = $obj->method();
  my $theURI = $obj->uri();
  
  my $r = "";
  $r.="  <PLAYBACK_REQUEST time=\"$Ttime\">\n";
  $r.="    <PLAYBACK_REQUEST_METHOD>$theMethod</PLAYBACK_REQUEST_METHOD>\n";
  $r.="    <PLAYBACK_REQUEST_URI>$theURI</PLAYBACK_REQUEST_URI>\n";

  %headers = ();
  $obj->scan(\&ScanHeaders);
  foreach (sort keys %headers)
  { $r.="    <PLAYBACK_REQUEST_HEADER>$_=$headers{$_}</PLAYBACK_REQUEST_HEADER>\n"; }
  
  my $theContent		= $obj->content;
  my $wrappedContent	= "<![CDATA[".$theContent."]]>";
  my $encodedContent	= encode_base64($wrappedContent);
  my $encodedSize		= length($encodedContent);
  
  $r.="    <PLAYBACK_REQUEST_CONTENT size=\"$encodedSize\">\n$encodedContent</PLAYBACK_REQUEST_CONTENT>\n";
  
  $r.="  </PLAYBACK_REQUEST>\n";
  
  if ($DBG >= DBG_HIGH)	{ LogFunctionExit("XML_PlaybackRequest"); }
  return $r;
}
#	End XML_PlaybackRequest
#^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^

=pod

=head1 XML_PlaybackResponse Procedure

=head2 Description:

  A procedure to produce an <PLAYBACK_RESPONSE> XML element.

=head2 Input:

=over 4

=item 1

  $obj	The HTTP::Response to be represented by the element
			produced.

=back

=head2 Returns:

  $r	The <PLAYBACK_RESPONSE> element describing the $obj
		HTTP::Response.
  
=head2 Notes:

  The scalar returned includes (in order):
  ~ The <PLAYBACK_RESPONSE> element, including the required
	time attribute (set to be equal to the current time, in the
	form YYYY-MM-DD-hh-mm-ss), the required timeout attribute (set to
	be equal to the value of the file-scoped $playbackResponse_timeout
	variable), and the following children:
	~ <PLAYBACK_RESPONSE_CODE>:		The code of the $response;
	~ <PLAYBACK_RESPONSE_MESSAGE>:	The Message of the $response;
	~ <PLAYBACK_RESPONSE_HEADER>:	Optional, unbounded class
									of children, each containing
									a header of the $response, in the
									form <name>=<value>;
	~ <PLAYBACK_RESPONSE_CONTENT>:	The content of the $response,
									wrapped in a "<![CDATA[" "]]>"
									tag, and encoded (MIME::Base64);
									This element also includes the
									required size attribute, set to be
									equal to the size of the wrapped
									and encoded content, in bytes;

=cut

#	XML_PlaybackResponse:
#^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
sub XML_PlaybackResponse
{
  if ($DBG >= DBG_HIGH)	{ LogFunctionEntry("XML_PlaybackResponse"); }
  
  my ($Tsec, $Tmin, $Thr, $Tmday, $Tmon, $Tyear) = localtime time;
  my $Ttime = sprintf "%04d-%02d-%02d-%02d-%02d-%02d", $Tyear+1900, $Tmon+1, $Tmday, $Thr, $Tmin, $Tsec;
  
  my $obj = $_[0];
  my $theCode = $obj->code();
  my $theMessage = $obj->message();
  
  my $r = "";
  $r.="  <PLAYBACK_RESPONSE time=\"$originalResponseTime\" timeout=\"$playbackResponse_timeout\">\n";
  $r.="    <PLAYBACK_RESPONSE_CODE>$theCode</PLAYBACK_RESPONSE_CODE>\n";
  $r.="    <PLAYBACK_RESPONSE_MESSAGE>$theMessage</PLAYBACK_RESPONSE_MESSAGE>\n";

  if($playbackResponse_timeout == 0)
  {
	%headers = ();
	$obj->scan(\&ScanHeaders);
	foreach (sort keys %headers)
	  { $r.="    <PLAYBACK_RESPONSE_HEADER>$_=$headers{$_}</PLAYBACK_RESPONSE_HEADER>\n"; }
	
	my $theContent		= $obj->content;
	my $wrappedContent	= "<![CDATA[".$theContent."]]>";
	my $encodedContent	= encode_base64($wrappedContent);
	my $encodedSize		= length($encodedContent);
	
	$r.="    <PLAYBACK_RESPONSE_CONTENT size=\"$encodedSize\">\n$encodedContent</PLAYBACK_RESPONSE_CONTENT>\n";
  }
  $r.="  </PLAYBACK_RESPONSE>\n";
  
  if ($DBG >= DBG_HIGH)	{ LogFunctionExit("XML_PlaybackResponse"); }
  return $r;
}
#	End XML_PlaybackResponse
#^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^

=pod

=head1 ReportError Procedure

=head2 Description:

  A procedure to report the current value (and meaning) of the
  file-scoped $errCode variable to STDERR and (possibly) to
  the logfile. The procedure also terminates execution of the
  HTTP Playback program by calling exit().

=head2 Input:

=over 4

=item 1

  $origin	The origin of the invokation (e.g.: the name of the
			routine that detected the erroneous condition).

=back

=head2 Returns:

  N/A.
  
=head2 Notes:

  The routine creates an error message based upon the value of the
  file-scoped $errCode variable; see the ERR_* constants for the set
  of values that variable can assume.
  The error message include a human-readable description of the
  error condition, and, in some cases, additional information
  from the file-scoped $errMsg variable.
  The error message thus created is then displayed to STDERR and
  (unless the error to be reported is an error regarding the logfile)
  to the logfile. Finally the routine calls the exit() function to
  terminate execution of the HTTP Playback tool.

=cut

#    ReportError procedure:
#^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
sub ReportError
{
  my $origin = $_[0];
  my $msg = "\n#> ERROR: code $errCode ";
  if($errCode==ERR_NONE)
  {
	$msg.="[ No Error ]\n";
  }
  elsif($errCode==ERR_LOGFILE)
  {
	$msg.="[ Could Not Access Log File ]\n";
	$msg.="   Additional Information:\n$errMsg\n";
  }
  elsif($errCode==ERR_CFGFILE)
  {
	$msg.="[ Could Not Access Configuration File ]\n";
	$msg.="   Additional Information:\n$errMsg\n";
  }
  elsif($errCode==ERR_MISS_CFGPAR)
  {
	$msg.="[ Missing Required Configuration Parameter ]\n";
	$msg.="   Additional Information:\n$errMsg\n";
  }
  elsif($errCode==ERR_STORAGE)
  {
	$msg.="[ Could Not Access the Storage Area ]\n";
	$msg.="   Additional Information:\n$errMsg\n";
  }
  elsif($errCode==ERR_NO_CLPAR)
  {
	$msg.="[ No Command-Line Parameters ]\n";
	$msg.="   Additional Information:\n";
	$msg.="At least one command line argument (the input file name) is required.\n";
  }
  elsif($errCode==ERR_INFILE)
  {
	$msg.="[ Could Not Access Input File ]\n";
	$msg.="   Additional Information:\n$errMsg\n";
  }
  elsif($errCode==ERR_XMLIN)
  {
	$msg.="[ Exception While Reading Input XML File ]\n";
	$msg.="   Additional Information:\n$errMsg\n";
  }
  elsif($errCode==ERR_OUTFILE)
  {
	$msg.="[ Could Not Access Output File ]\n";
	$msg.="   Additional Information:\n$errMsg\n";
  }
  elsif($errCode==ERR_MISS_REC_SERVER)
  {
	$msg.="[ Missing Recording Server Type Data ]\n";
  }
  elsif($errCode==ERR_UNREC_REC_SERVER)
  {
	$msg.="[ Unrecognized Recording Server Type Data ]\n";
	$msg.="   Additional Information:\n$errMsg\n";
  }
  elsif($errCode==ERR_XML_EXTRACT)
  {
	$msg.="[ Exception While Extracting Data from XML Context ]\n";
	$msg.="   Additional Information:\n$errMsg\n";
  }
  else
  { $msg.="[ Unrecognized Error Code ]"; }
  
  $msg.="   Reported By ".$origin."\n\n";
  
  if( $errCode!=ERR_LOGFILE && $errCode!=ERR_STORAGE )	{ LogMsg($msg); }
  else													{ print STDERR $msg; }
  exit(0);
}
#    End ReportError
#^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^

=pod

=head1 Output_PlaybackHeader Procedure

=head2 Description:

  A procedure to display to the output file the Playback Header.

=head2 Input:

=over 4

  N/A.

=back

=head2 Returns:

  N/A.
  
=head2 Notes:

  The routine relies upon the XML_PlaybackHeader to produce
  an appropriate playback header.

=cut

#	Output_PlaybackHeader:
#^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
sub Output_PlaybackHeader
{
  if($DBG >= DBG_MED)	{ LogFunctionEntry("Output_PlaybackHeader"); }
  
  if(!(open(OUT, "> $outFilename") ) )
  {
	$errCode = ERR_OUTFILE;
	$errMsg = "Could Not Open Output File '$outFilename' to Output\n";
	$errMsg.= "The Header of the Playback File.";
	ReportError("Output_PlaybackHeader");
  }
  
  print OUT XML_PlaybackHeader();
  
  if($DBG >= DBG_MED)	{ LogFunctionExit("Output_PlaybackHeader"); }
}
#	End Output_PlaybackHeader
#^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^

=pod

=head1 Output_PlaybackFooter Procedure

=head2 Description:

  A procedure to display to the output file the Playback Footer.

=head2 Input:

=over 4

  N/A.

=back

=head2 Returns:

  N/A.
  
=head2 Notes:

  The routine relies upon the XML_PlaybackFooter to produce
  an appropriate playback footer.

=cut

#	Output_PlaybackFooter:
#^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
sub Output_PlaybackFooter
{
  if($DBG >= DBG_MED)	{ LogFunctionEntry("Output_PlaybackFooter"); }
  
  print OUT XML_PlaybackFooter();
  
  if($DBG >= DBG_MED)	{ LogFunctionExit("Output_PlaybackFooter"); }  
}
#	End Output_PlaybackFooter
#^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^

=pod

=head1 Output_TransactionHeader Procedure

=head2 Description:

  A procedure to display to the output file a Transaction Header.

=head2 Input:

=over 4

  N/A.

=back

=head2 Returns:

  N/A.
  
=head2 Notes:

  The routine relies upon the XML_TransactionHeader to produce
  an appropriate transaction header.

=cut

#	Output_TransactionHeader:
#^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
sub Output_TransactionHeader
{
  if($DBG >= DBG_MED)	{ LogFunctionEntry("Output_TransactionHeader"); }
  
  print OUT XML_TransactionHeader();
  if($DBG >= DBG_MED)
  {
	print LOG Indent($logIndent);
	print LOG "The Transaction Header for Transaction #$transactionID has been written to the output file.\n";
  }
  
  if($DBG >= DBG_MED)	{ LogFunctionExit("Output_TransactionHeader"); }
}
#	End Output_TransactionHeader
#^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^

=pod

=head1 Output_TransactionFooter Procedure

=head2 Description:

  A procedure to display to the output file a Transaction Footer.

=head2 Input:

=over 4

  N/A.

=back

=head2 Returns:

  N/A.
  
=head2 Notes:

  The routine relies upon the XML_TransactionFooter to produce
  an appropriate transaction footer.

=cut

#	Output_TransactionFooter:
#^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
sub Output_TransactionFooter
{
  if($DBG >= DBG_MED)	{ LogFunctionEntry("Output_TransactionFooter"); }
  
  print OUT XML_TransactionFooter();
  
  if($DBG >= DBG_MED)	{ LogFunctionExit("Output_TransactionFooter"); }
}
#	End Output_TransactionHeader
#^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^

=pod

=head1 Output_TransactionElement Procedure

=head2 Description:

  A procedure to display to the output file one of the four main
  children of a Transaction element.

=head2 Input:

=over 4

=item 1

  $obj	The HTTP message to be described by the XML element
		to be displayed.

=item 2

  $type	The code describing which of the four Transaction children
		should be displayed to output file.

=back

=head2 Returns:

  N/A.
  
=head2 Notes:

  The $type parameter should be one of the HTTP_MSG_* constants;
  depending on that value, the routine relies upon one of the
  following routines to produce the appropriate XML element:
  XML_OriginalRequest, XML_OriginalResponse, CML_PlaybackRequest,
  XML_PlaybackResponse.

=cut

#	Output_TransactionElement:
#^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
sub Output_TransactionElement
{
  if($DBG >= DBG_MED)	{ LogFunctionEntry("Output_TransactionElement"); }
  
  my ($obj, $type) = @_;
  
  if($type == HTTP_MSG_ORIGINAL_REQUEST)		{ print OUT XML_OriginalRequest($obj);	}
  elsif($type == HTTP_MSG_ORIGINAL_RESPONSE)	{ print OUT XML_OriginalResponse($obj);	}
  elsif($type == HTTP_MSG_PLAYBACK_REQUEST)		{ print OUT XML_PlaybackRequest($obj);	}
  elsif($type == HTTP_MSG_PLAYBACK_RESPONSE)	{ print OUT XML_PlaybackResponse($obj);	}
  
  if($DBG >= DBG_MED)	{ LogFunctionExit("Output_TransactionElement"); }  
}
#	End Output_TransactionElement
#^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^

=pod

=head1 Output_TransactionResult Procedure

=head2 Description:

  A procedure to display to the output file the <RESULT> child of a
  Transaction.

=head2 Input:

=over 4

  N/A.

=back

=head2 Returns:

  N/A.
  
=head2 Notes:

  The routine appends to the output file a <RESULT> element
  including the following:
  ~ <RESULT_CODE>:	The result code for the current transaction,
					as found in the file-scoped $result variable;
  ~ <RESULT_DESC>:	A human-readable description of the result code,
					as produced by the ResultCodeDesc routine.

=cut

#	Output_TransactionResult:
#^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
sub Output_TransactionResult
{
  if($DBG >= DBG_MED)	{ LogFunctionEntry("Output_TransactionResult"); }
  
  my $desc = ResultCodeDesc();
  if($result != RESULT_OK)		{ $desc.="\n$resultErrInfo"; }
  print OUT "  <RESULT>\n";
  print OUT "    <RESULT_CODE>$result</RESULT_CODE>\n";
  print OUT "    <RESULT_DESC>$desc</RESULT_DESC>\n";
  print OUT "  </RESULT>\n";
  
  if($DBG >= DBG_MED)	{ LogFunctionExit("Output_TransactionResult"); }  
}
#	End Output_TransactionResult
#^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^

=pod

=head1 GetOriginalRequest Procedure

=head2 Description:

  A procedure to create an HTTP::Request object based upon the
  data in the input file regarding the current transaction.

=head2 Input:

=over 4

  N/A.

=back

=head2 Returns:

  $originalRequest	The HTTP::Request object built from the data
					in the input file.
  
=head2 Notes:

  The routine uses the current value of the file-scoped $transactionID
  variable to gather data from the file-scoped $inData variable.

=cut

#	GetOriginalRequest:
#^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
sub GetOriginalRequest
{
  if($DBG >= DBG_MED)	{ LogFunctionEntry("GetOriginalRequest"); }

  my $requestMethod = $inData->{TRANSACTION}->{$transactionID}->{ORIGINAL_REQUEST}->{ORIGINAL_REQUEST_METHOD}->{content};
  my $requestURI = $inData->{TRANSACTION}->{$transactionID}->{ORIGINAL_REQUEST}->{ORIGINAL_REQUEST_URI}->{content};
  my $requestHeadersRef = $inData->{TRANSACTION}->{$transactionID}->{ORIGINAL_REQUEST}->{ORIGINAL_REQUEST_HEADER};
  
  my $encodedContent = $inData->{TRANSACTION}->{$transactionID}->{ORIGINAL_REQUEST}->{ORIGINAL_REQUEST_CONTENT}->{content};
  my $requestContent = decode_base64($encodedContent);
  $requestContent = StripCDATA($requestContent);
  
  my $headersObj = HTTP::Headers->new;
  my @requestHeaders = @$requestHeadersRef;
  foreach my $headerRef (@requestHeaders)
  {
	my $tmp = $headerRef->{content};
	my ($headerName, $headerVal) = split(/=/, $tmp, 2);
	$headersObj->header($headerName => $headerVal);
  }#FOREACH
  
  my $originalRequest = HTTP::Request->new($requestMethod, $requestURI, $headersObj, $requestContent);
  $originalRequestTime = $inData->{TRANSACTION}->{$transactionID}->{ORIGINAL_REQUEST}->{time};
  
  if($DBG >= DBG_HIGH)
  {
	my $gotRequestMsg = HTTPmsgLog($originalRequest, HTTP_MSG_ORIGINAL_REQUEST);
	print LOG $gotRequestMsg;
  }
  if($DBG >= DBG_MED)	{ LogFunctionExit("GetOriginalRequest"); }
  return $originalRequest;
}
#	End GetOriginalRequest
#^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^

=pod

=head1 GetOriginalResponse Procedure

=head2 Description:

  A procedure to create an HTTP::Response object based upon the
  data in the input file regarding the current transaction.

=head2 Input:

=over 4

  N/A.

=back

=head2 Returns:

  $originalResponse	The HTTP::Response object built from the data
					in the input file.
  
=head2 Notes:

  The routine uses the current value of the file-scoped $transactionID
  variable to gather data from the file-scoped $inData variable.

=cut

#	GetOriginalResponse:
#^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
sub GetOriginalResponse
{
  if($DBG >= DBG_MED)	{ LogFunctionEntry("GetOriginalResponse"); }
  
  my $responseCode = $inData->{TRANSACTION}->{$transactionID}->{ORIGINAL_RESPONSE}->{ORIGINAL_RESPONSE_CODE}->{content};
  my $responseMessage = $inData->{TRANSACTION}->{$transactionID}->{ORIGINAL_RESPONSE}->{ORIGINAL_RESPONSE_MESSAGE}->{content};
  my $responseHeadersRef = $inData->{TRANSACTION}->{$transactionID}->{ORIGINAL_RESPONSE}->{ORIGINAL_RESPONSE_HEADER};
  
  my $encodedContent = $inData->{TRANSACTION}->{$transactionID}->{ORIGINAL_RESPONSE}->{ORIGINAL_RESPONSE_CONTENT}->{content};
  my $responseContent = decode_base64($encodedContent);
  $responseContent = StripCDATA($responseContent);
  
  $originalResponse_timeout = $inData->{TRANSACTION}->{$transactionID}->{ORIGINAL_RESPONSE}->{timeout};

  my $headersObj = HTTP::Headers->new;
  
  if($originalResponse_timeout == 0)
  {
	my @responseHeaders = @$responseHeadersRef;
	foreach my $headerRef (@responseHeaders)
	{
	  my $tmp = $headerRef->{content};
	  
#<v051>
# All of the DPS transactions may contain a header with multiple '='
# characters: thus, we use the code originally used only for
# the OBS_OBSTORE_GET transactions for all transactions:
	  # Special case for an OBS_OBSTORE_GET response:
	  # The Content-Disposition Header is formatted as follows:
	  # "Content-Disposition=<foo>; FileName=<filename>"
	  my ($headerName, $headerVal);
	  ($headerName, $headerVal) = split(/=/, $tmp, 2);
	  
# This is the code as it was in v.0.50:
#	  if(	($tmp =~ /Content\-Disposition=/)
#		 &&	($tmp =~ /FileName=/) )
#	  {
#		($headerName, $headerVal) = split(/=/, $tmp, 2);
#	  }
#	  else
#	  {
#		($headerName, $headerVal) = split(/=/, $tmp);
#	  }
#</v051>
	  
	  $headersObj->header($headerName => $headerVal);
	}
  }#IF it was not a Timeout Response

  my $originalResponse = HTTP::Response->new($responseCode, $responseMessage, $headersObj, $responseContent);
  $originalResponseTime = $inData->{TRANSACTION}->{$transactionID}->{ORIGINAL_RESPONSE}->{time};
  
  if($DBG >= DBG_HIGH)
  {
	my $gotResponseMsg = HTTPmsgLog($originalResponse, HTTP_MSG_ORIGINAL_RESPONSE);
	print LOG $gotResponseMsg;
  }
  if($DBG >= DBG_MED)	{ LogFunctionExit("GetOriginalResponse"); }
  return $originalResponse;
}
#	End GetOriginalResponse
#^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^

=pod

=head1 RegExMe Procedure

=head2 Description:

  A procedure to escape certain characters in a scalar intended
  to be used as part of a regular-expression.

=head2 Input:

=over 4

=item 1

  $s	The scalar to be processed.

=back

=head2 Returns:

  $s	The processed scalar.
  
=head2 Notes:

  The routine performs the following substitutions in the $s scalar:
  '\'	->	"\\"
  '-'	->	"\-"
  ':'	->	"\:"
  '/'	->	"\/"
  If any of the Left-Hand Side of these substitutions appears
  multiple times in the $s scalar, the matching substitution will
  be performed a matching number of times.
  Remember that the '\' -> "\\" substitution should always be
  the first one to be performed.

=cut

#	RegExMe:
#^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
sub RegExMe
{
  my $s = $_[0];
  
  $s =~ s/\\/\\\\/g;	# Make each '\' into a '\\' LEAVE FIRST
  $s =~ s/\-/\\\-/g;	# Make each '-' into a '\-'
  $s =~ s/\:/\\\:/g;	# Make each ':' into a '\:'
  $s =~ s/\//\\\//g;	# Make each '/' into a '\/'
  
  return $s;
}
#	End RegExMe
#^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^

=pod

=head1 ValidLPOMapping Procedure

=head2 Description:

  A procedure to verify whether the current transaction elements
  respect any previously set lpObject element mappings (ObjectStore
  specific).

=head2 Input:

=over 4

=item 1

  $originalRequest	The HTTP::Request from the original recording;

=item 2

  $originalResponse	The HTTP::Response from the original recording;

=item 3

  $playbackRequest	The HTTP::Request used during the playback;

=item 4

  $playbackResponse	The HTTP::Response obtained during the playback.

=back

=head2 Returns:

  $res	Equal to 1 (i.e. True) if the transaction respects all
		the previously set lpObject mappings;
		Equal to 0 (i.e. False) otherwise.
  
=head2 Notes:

  All of the mapping verifications are structure din three blocks:
  ~ block #1:	The 'variable' elements from the original request and
				from the playback request are extracted, and the
				file-scoped mapping hashes are analyzed to verify if the
				'variable' elements from the original request were
				mapped to some corresponding element (and, if so,
				whether these pre-existing mappings are respected by the
				playback request);
  ~ block #2:	The 'variable' elements from the original response and
				from the playback response are extracted, and the
				file-scoped mapping hashes are analyzed to verify if the
				'variable' elements from the original response were
				mapped to some corresponding element (and, if so,
				whether these pre-existing mappings are respected by the
				playback response);
  ~ block #3:	If a 'variable' element appears in both the original
				request and original response, and is identical in the
				two HTTP messages, then the playback request and
				playback response are checked to verify that the same
				relationship exists between the 'variable' elements in
				them.
  Each mapping verification routine may implement any combination of
  these three blocks.
  If the mapping verification routine detects an erroneous condition,
  it is expected to set the file-scoped $resultErrInfo variable with
  an appropriate description of the issue, and return 0 (i.e. false)
  to the caller.

=cut

#	ValidLPOMapping:
#^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
sub ValidLPOMapping
{
  if($DBG >= DBG_MED)	{ LogFunctionEntry("ValidLPOMapping"); }
  
  my ($originalRequest, $originalResponse, $playbackRequest, $playbackResponse) = @_;
  
  my $res = 1;
  
  if(	$transactionType == TRANSACTION_OBS_ADD_OBJECT
	 ||	$transactionType == TRANSACTION_OBS_UPDATE_OBJECT )
  {
	my $originalRequestLPO = ExtractLPOFromRequest($originalRequest, $transactionType);
	my $playbackRequestLPO = ExtractLPOFromRequest($playbackRequest, $transactionType);
	
	#--- Look at the LPOs in the requests:
	#--- Comparison Block #1:
    if($originalRequestLPO)
	{
	  if(!$playbackRequestLPO)
	  {
	    $resultErrInfo = "The original Request included the lpObject $originalRequestLPO\n";
	    $resultErrInfo.= "while the playback Request did not include any lpObject.\n";
	    if($DBG >= DBG_MED)
	    {
	  	print LOG Indent($logIndent);
	  	print LOG "ValidLPOMapping will return 0 (i.e. false), and has set the resultErrInfo variable as follows:\n";
	  	print LOG $resultErrInfo;
	  	LogFunctionExit("ValidLPOMapping");
	    }
	    return 0;
	  }
	  elsif(	exists($lpoMap{$originalRequestLPO})
			&&	$lpoMapSet{$originalRequestLPO}
		   )
	  {
		if( $lpoMap{$originalRequestLPO} ne $playbackRequestLPO)
		{
		  $resultErrInfo = "The original Request included the lpObject $originalRequestLPO\n";
		  $resultErrInfo.= "while the playback Request included the lpObject $playbackRequestLPO.\n";
		  $resultErrInfo.= "The lpObject in the original Request, however, was already mapped to\n";
		  $resultErrInfo.= "the lpObject ".$lpoMap{$originalRequestLPO}.".\n";
		  if($DBG >= DBG_MED)
		  {
			print LOG Indent($logIndent);
			print LOG "ValidLPOMapping will return 0 (i.e. false), and has set the resultErrInfo variable as follows:\n";
			print LOG $resultErrInfo;
			LogFunctionExit("ValidLPOMapping");
		  }
		  return 0;
		}
		else
		{
		  if($DBG >= DBG_HIGH)
		  {
			print LOG Indent($logIndent);
			print LOG "The lpObjects found in the original and playback Requests respected the previously\n";
			print LOG Indent($logIndent);
			print LOG "set mapping; no substitution necessary.\n";
		  }
		}
	  }
	  elsif(	(!exists($lpoMap{$originalRequestLPO}))
			||	(!$lpoMapSet{$originalRequestLPO}) )
	  {
		if($DBG >= DBG_HIGH)
		{
			print LOG Indent($logIndent);
			print LOG "The original Request included the lpObject $originalRequestLPO;\n";
			print LOG Indent($logIndent);
			print LOG "the playback Request included the lpObject $playbackRequestLPO.\n";
			print LOG Indent($logIndent);
			print LOG "A new lpObject mapping will be created: $originalRequestLPO => $playbackRequestLPO.\n";
		}
		$lpoMap{$originalRequestLPO} = $playbackRequestLPO;
		$lpoMapSet{$originalRequestLPO} = 1;
	  }
	}
	#--- End Comparison Block #1
	
	if(		$transactionType == TRANSACTION_OBS_GET_OBJECT )
	{
	  my $originalResponseLPO = ExtractLPOFromResponse($originalResponse, $transactionType);
	  my $playbackResponseLPO = ExtractLPOFromResponse($playbackResponse, $transactionType);
	  
	  #--- Look at the filenames in the responses:
	  #--- Comparison Block #2:
	  if($originalResponseLPO)
	  {
		if(!$playbackResponseLPO)
		{
		  $resultErrInfo = "The original Response included the lpObject $originalResponseLPO\n";
		  $resultErrInfo.= "while the playback Response did not include any lpObject.\n";
		  if($DBG >= DBG_MED)
		  {
			print LOG Indent($logIndent);
			print LOG "ValidLPOMapping will return 0 (i.e. false), and has set the resultErrInfo variable as follows:\n";
			print LOG $resultErrInfo;
			LogFunctionExit("ValidLPOMapping");
		  }
		  return 0;
		}
		elsif(		exists($lpoMap{$originalResponseLPO})
			  &&	$lpoMapSet{$originalResponseLPO}
			)
		{
		  if( $lpoMap{$originalResponseLPO} ne $playbackResponseLPO)
		  {
			$resultErrInfo = "The original Response included the lpObject $originalResponseLPO\n";
			$resultErrInfo.= "while the playback Response included the lpObject $playbackResponseLPO.\n";
			$resultErrInfo.= "The lpObject in the original Response, however, was already mapped to\n";
			$resultErrInfo.= "the lpObject ".$lpoMap{$originalResponseLPO}.".\n";
			if($DBG >= DBG_MED)
			{
			  print LOG Indent($logIndent);
			  print LOG "ValidLPOMapping will return 0 (i.e. false), and has set the resultErrInfo variable as follows:\n";
			  print LOG $resultErrInfo;
			  LogFunctionExit("ValidLPOMapping");
			}
			return 0;
		  }
		  else
		  {
			if($DBG >= DBG_HIGH)
			{
			  print LOG Indent($logIndent);
			  print LOG "The lpObject found in the original and playback Responses respected the previously\n";
			  print LOG Indent($logIndent);
			  print LOG "set mapping; no substitution necessary.\n";
			}
		  }
		}
		elsif(		(!exists($lpoMap{$originalResponseLPO}))
			  ||	(!$lpoMapSet{$originalResponseLPO}) )
		{
		  if($DBG >= DBG_HIGH)
		  {
			print LOG Indent($logIndent);
			print LOG "The original Response included the lpObject $originalResponseLPO;\n";
			print LOG Indent($logIndent);
			print LOG "the playback Response included the lpObject $playbackResponseLPO.\n";
			print LOG Indent($logIndent);
			print LOG "A new lpObject mapping will be created: $originalResponseLPO => $playbackResponseLPO.\n";
		  }
		  $lpoMap{$originalResponseLPO} = $playbackResponseLPO;
		  $lpoMapSet{$originalResponseLPO} = 1;
		}
	  }
	  #--- End Comparison Block #2
	}
	elsif($DBG >= DBG_HIGH)
	{
	  print LOG Indent($logIndent);
	  print LOG "No lpObject in the Responses of this kind of transactions.\n";
	}
  }
  elsif($DBG >= DBG_HIGH)
  {
	print LOG Indent($logIndent);
	print LOG "No lpObject in this kind of transactions.\n";
  }

  if($DBG >= DBG_HIGH)
  {
	print LOG Indent($logIndent);
	print LOG "ValidLPOMapping will return $res (i.e. ";
	if($res)	{ print LOG "true"; }
	else		{ print LOG "false"; }
	print LOG ")\n";
  }
  if($DBG >= DBG_MED)	{ LogFunctionExit("ValidLPOMapping"); }
  return $res;
}
#	End ValidLPOMapping
#^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^

=pod

=head1 ValidQueryMapping Procedure

=head2 Description:

  A procedure to verify whether the current transaction elements
  respect any previously set Query element mappings (ObjectStore
  specific).

=head2 Input:

=over 4

=item 1

  $originalRequest	The HTTP::Request from the original recording;

=item 2

  $playbackRequest	The HTTP::Request used during the playback;

=back

=head2 Returns:

  $res	Equal to 1 (i.e. True) if the transaction respects all
		the previously set Query mappings;
		Equal to 0 (i.e. False) otherwise.
  
=head2 Notes:

  All of the mapping verifications are structure din three blocks:
  ~ block #1:	The 'variable' elements from the original request and
				from the playback request are extracted, and the
				file-scoped mapping hashes are analyzed to verify if the
				'variable' elements from the original request were
				mapped to some corresponding element (and, if so,
				whether these pre-existing mappings are respected by the
				playback request);
  ~ block #2:	The 'variable' elements from the original response and
				from the playback response are extracted, and the
				file-scoped mapping hashes are analyzed to verify if the
				'variable' elements from the original response were
				mapped to some corresponding element (and, if so,
				whether these pre-existing mappings are respected by the
				playback response);
  ~ block #3:	If a 'variable' element appears in both the original
				request and original response, and is identical in the
				two HTTP messages, then the playback request and
				playback response are checked to verify that the same
				relationship exists between the 'variable' elements in
				them.
  Each mapping verification routine may implement any combination of
  these three blocks.
  If the mapping verification routine detects an erroneous condition,
  it is expected to set the file-scoped $resultErrInfo variable with
  an appropriate description of the issue, and return 0 (i.e. false)
  to the caller.

=cut

#	ValidQueryMapping:
#^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
sub ValidQueryMapping
{
  if($DBG >= DBG_MED)	{ LogFunctionEntry("ValidQueryMapping"); }
  
  my ($originalRequest, $playbackRequest) = @_;
  
  my $res = 1;
  
  if($DBG >= DBG_HIGH)
  {
	print LOG Indent($logIndent);
	print LOG "Transaction type: $transactionType (".TransactionTypeName($transactionType).")\n";
  }
  
  if(	$transactionType == TRANSACTION_OBS_EXECUTE_SEARCH
	 ||	$transactionType == TRANSACTION_OBS_GET_LAST_UPDATE_TIME	)
  {
	my $originalRequestQuery = ExtractQueryFromRequest($originalRequest, $transactionType);
	my $playbackRequestQuery = ExtractQueryFromRequest($playbackRequest, $transactionType);
	
	  #--- Comparison Block #1:
	  if($originalRequestQuery)
	  {
		if(!$playbackRequestQuery)
		{
		  $resultErrInfo = "The original Request included the query $originalRequestQuery\n";
		  $resultErrInfo.= "while the playback Request did not include any query.\n";
		  if($DBG >= DBG_MED)
		  {
			print LOG Indent($logIndent);
			print LOG "ValidQueryMapping will return 0 (i.e. false), and has set the resultErrInfo variable as follows:\n";
			print LOG $resultErrInfo;
			LogFunctionExit("ValidQueryMapping");
		  }
		  return 0;
		}
		elsif(	exists($queryMap{$originalRequestQuery})
			&&	$queryMapSet{$originalRequestQuery}
			)
		{
		  if( $queryMap{$originalRequestQuery} ne $playbackRequestQuery)
		  {
			$resultErrInfo = "The original Request included the query $originalRequestQuery\n";
			$resultErrInfo.= "while the playback Request included the query $playbackRequestQuery.\n";
			$resultErrInfo.= "The query in the original Request, however, was already mapped to\n";
			$resultErrInfo.= "the query ".$queryMap{$originalRequestQuery}.".\n";
			if($DBG >= DBG_MED)
			{
			  print LOG Indent($logIndent);
			  print LOG "ValidQueryMapping will return 0 (i.e. false), and has set the resultErrInfo variable as follows:\n";
			  print LOG $resultErrInfo;
			  LogFunctionExit("ValidQueryMapping");
			}
			return 0;
		  }
		  else
		  {
			if($DBG >= DBG_HIGH)
			{
			  print LOG Indent($logIndent);
			  print LOG "The queries found in the original and playback Requests respected the previously\n";
			  print LOG Indent($logIndent);
			  print LOG "set mapping; no substitution necessary.\n";
			}
		  }
		}
		elsif(	(!exists($queryMap{$originalRequestQuery}))
			||	(!$queryMapSet{$originalRequestQuery}) )
		{
		  if($DBG >= DBG_HIGH)
		  {
			  print LOG Indent($logIndent);
			  print LOG "The original Request included the query $originalRequestQuery;\n";
			  print LOG Indent($logIndent);
			  print LOG "the playback Request included the query $playbackRequestQuery.\n";
			  print LOG Indent($logIndent);
			  print LOG "A new query mapping will be created: $originalRequestQuery => $playbackRequestQuery.\n";
		  }
		  $queryMap{$originalRequestQuery} = $playbackRequestQuery;
		  $queryMapSet{$originalRequestQuery} = 1;
		}
	  }
	#--- End Comparison Block #1
  }
  elsif($DBG >= DBG_HIGH)
  {
	print LOG Indent($logIndent);
	print LOG "No Query in this kind of transactions.\n";
  }

  if($DBG >= DBG_HIGH)
  {
	print LOG Indent($logIndent);
	print LOG "ValidQueryMapping will return $res (i.e. ";
	if($res)	{ print LOG "true"; }
	else		{ print LOG "false"; }
	print LOG ")\n";
  }
  if($DBG >= DBG_MED)	{ LogFunctionExit("ValidQueryMapping"); }
  return $res;
}
#	End ValidQueryMapping
#^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^

=pod

=head1 ValidGuidMapping Procedure

=head2 Description:

  A procedure to verify whether the current transaction elements
  respect any previously set GUID element mappings (ObjectStore
  specific).

=head2 Input:

=over 4

=item 1

  $originalRequest	The HTTP::Request from the original recording;

=item 2

  $playbackRequest	The HTTP::Request used during the playback;

=back

=head2 Returns:

  $res	Equal to 1 (i.e. True) if the transaction respects all
		the previously set GUID mappings;
		Equal to 0 (i.e. False) otherwise.
  
=head2 Notes:

  All of the mapping verifications are structure din three blocks:
  ~ block #1:	The 'variable' elements from the original request and
				from the playback request are extracted, and the
				file-scoped mapping hashes are analyzed to verify if the
				'variable' elements from the original request were
				mapped to some corresponding element (and, if so,
				whether these pre-existing mappings are respected by the
				playback request);
  ~ block #2:	The 'variable' elements from the original response and
				from the playback response are extracted, and the
				file-scoped mapping hashes are analyzed to verify if the
				'variable' elements from the original response were
				mapped to some corresponding element (and, if so,
				whether these pre-existing mappings are respected by the
				playback response);
  ~ block #3:	If a 'variable' element appears in both the original
				request and original response, and is identical in the
				two HTTP messages, then the playback request and
				playback response are checked to verify that the same
				relationship exists between the 'variable' elements in
				them.
  Each mapping verification routine may implement any combination of
  these three blocks.
  If the mapping verification routine detects an erroneous condition,
  it is expected to set the file-scoped $resultErrInfo variable with
  an appropriate description of the issue, and return 0 (i.e. false)
  to the caller.

=cut

#	ValidGuidMapping:
#^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
sub ValidGuidMapping
{
  if($DBG >= DBG_MED)	{ LogFunctionEntry("ValidGuidMapping"); }
  
  my ($originalRequest, $playbackRequest) = @_;
  
  my $res = 1;
  
  if($DBG >= DBG_HIGH)
  {
	print LOG Indent($logIndent);
	print LOG "Transaction type: $transactionType (".TransactionTypeName($transactionType).")\n";
  }
  
  if(	$transactionType == TRANSACTION_OBS_GET_OBJECT
	 ||	$transactionType == TRANSACTION_OBS_UPLOAD_OBJECT_DATA
	 ||	$transactionType == TRANSACTION_OBS_DOWNLOAD_OBJECT_DATA	)
  {
	my $originalRequestGuid = ExtractGUIDFromRequest($originalRequest, $transactionType);
	my $playbackRequestGuid = ExtractGUIDFromRequest($playbackRequest, $transactionType);
	
	  #--- Comparison Block #1:
	  if($originalRequestGuid)
	  {
		if(!$playbackRequestGuid)
		{
		  $resultErrInfo = "The original Request included the GUID $originalRequestGuid\n";
		  $resultErrInfo.= "while the playback Request did not include any GUID.\n";
		  if($DBG >= DBG_MED)
		  {
			print LOG Indent($logIndent);
			print LOG "ValidGuidMapping will return 0 (i.e. false), and has set the resultErrInfo variable as follows:\n";
			print LOG $resultErrInfo;
			LogFunctionExit("ValidGuidMapping");
		  }
		  return 0;
		}
		elsif(	exists($guidMap{$originalRequestGuid})
			&&	$guidMapSet{$originalRequestGuid}
			)
		{
		  if( $guidMap{$originalRequestGuid} ne $playbackRequestGuid)
		  {
			$resultErrInfo = "The original Request included the guid $originalRequestGuid\n";
			$resultErrInfo.= "while the playback Request included the guid $playbackRequestGuid.\n";
			$resultErrInfo.= "The guid in the original Request, however, was already mapped to\n";
			$resultErrInfo.= "the guid ".$guidMap{$originalRequestGuid}.".\n";
			if($DBG >= DBG_MED)
			{
			  print LOG Indent($logIndent);
			  print LOG "ValidGuidMapping will return 0 (i.e. false), and has set the resultErrInfo variable as follows:\n";
			  print LOG $resultErrInfo;
			  LogFunctionExit("ValidGuidMapping");
			}
			return 0;
		  }
		  else
		  {
			if($DBG >= DBG_HIGH)
			{
			  print LOG Indent($logIndent);
			  print LOG "The guids found in the original and playback Requests respected the previously\n";
			  print LOG Indent($logIndent);
			  print LOG "set mapping; no substitution necessary.\n";
			}
		  }
		}
		elsif(	(!exists($guidMap{$originalRequestGuid}))
			||	(!$guidMapSet{$originalRequestGuid}) )
		{
		  if($DBG >= DBG_HIGH)
		  {
			  print LOG Indent($logIndent);
			  print LOG "The original Request included the guid $originalRequestGuid;\n";
			  print LOG Indent($logIndent);
			  print LOG "the playback Request included the guid $playbackRequestGuid.\n";
			  print LOG Indent($logIndent);
			  print LOG "A new guid mapping will be created: $originalRequestGuid => $playbackRequestGuid.\n";
		  }
		  $guidMap{$originalRequestGuid} = $playbackRequestGuid;
		  $guidMapSet{$originalRequestGuid} = 1;
		}
	  }
	#--- End Comparison Block #1
  }
  elsif($DBG >= DBG_HIGH)
  {
	print LOG Indent($logIndent);
	print LOG "No GUID in this kind of transactions.\n";
  }

  if($DBG >= DBG_HIGH)
  {
	print LOG Indent($logIndent);
	print LOG "ValidGuidMapping will return $res (i.e. ";
	if($res)	{ print LOG "true"; }
	else		{ print LOG "false"; }
	print LOG ")\n";
  }
  if($DBG >= DBG_MED)	{ LogFunctionExit("ValidGuidMapping"); }
  return $res;
}
#	End ValidGuidMapping
#^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^

=pod

=head1 ValidFilenameMapping Procedure

=head2 Description:

  A procedure to verify whether the current transaction elements
  respect any previously set Filename element mappings (ObjectStore
  specific).

=head2 Input:

=over 4

=item 1

  $originalRequest	The HTTP::Request from the original recording;

=item 2

  $originalResponse	The HTTP::Response from the original recording;

=item 3

  $playbackRequest	The HTTP::Request used during the playback;

=item 4

  $playbackResponse	The HTTP::Response obtained during the playback.

=back

=head2 Returns:

  $res	Equal to 1 (i.e. True) if the transaction respects all
		the previously set Filename mappings;
		Equal to 0 (i.e. False) otherwise.
  
=head2 Notes:

  All of the mapping verifications are structure din three blocks:
  ~ block #1:	The 'variable' elements from the original request and
				from the playback request are extracted, and the
				file-scoped mapping hashes are analyzed to verify if the
				'variable' elements from the original request were
				mapped to some corresponding element (and, if so,
				whether these pre-existing mappings are respected by the
				playback request);
  ~ block #2:	The 'variable' elements from the original response and
				from the playback response are extracted, and the
				file-scoped mapping hashes are analyzed to verify if the
				'variable' elements from the original response were
				mapped to some corresponding element (and, if so,
				whether these pre-existing mappings are respected by the
				playback response);
  ~ block #3:	If a 'variable' element appears in both the original
				request and original response, and is identical in the
				two HTTP messages, then the playback request and
				playback response are checked to verify that the same
				relationship exists between the 'variable' elements in
				them.
  Each mapping verification routine may implement any combination of
  these three blocks.
  If the mapping verification routine detects an erroneous condition,
  it is expected to set the file-scoped $resultErrInfo variable with
  an appropriate description of the issue, and return 0 (i.e. false)
  to the caller.

=cut

#	ValidFilenameMapping:
#^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
sub ValidFilenameMapping
{
  if($DBG >= DBG_MED)	{ LogFunctionEntry("ValidFilenameMapping"); }
  
  my ($originalRequest, $originalResponse, $playbackRequest, $playbackResponse) = @_;
  
  my $res = 1;
  
  if(	$transactionType == TRANSACTION_OBS_OBSTORE_POST
	 ||	$transactionType == TRANSACTION_OBS_ADD_OBJECT
	 ||	$transactionType == TRANSACTION_OBS_UPLOAD_OBJECT_DATA
	 ||	$transactionType == TRANSACTION_OBS_DOWNLOAD_OBJECT_DATA
	 ||	$transactionType == TRANSACTION_OBS_OBSTORE_GET )
  {
	my $originalRequestFilename = ExtractFilenameFromRequest($originalRequest, $transactionType);
	my $playbackRequestFilename = ExtractFilenameFromRequest($playbackRequest, $transactionType);
	
	#--- Look at the filenames in the requests:
	#--- Comparison Block #1:
    if($originalRequestFilename)
	{
	  if(!$playbackRequestFilename)
	  {
	    $resultErrInfo = "The original Request included the filename $originalRequestFilename\n";
	    $resultErrInfo.= "while the playback Request did not include any filename.\n";
	    if($DBG >= DBG_MED)
	    {
	  	print LOG Indent($logIndent);
	  	print LOG "ValidFilenameMapping will return 0 (i.e. false), and has set the resultErrInfo variable as follows:\n";
	  	print LOG $resultErrInfo;
	  	LogFunctionExit("ValidFilenameMapping");
	    }
	    return 0;
	  }
	  elsif(	exists($filenameMap{$originalRequestFilename})
			&&	$filenameMapSet{$originalRequestFilename}
		   )
	  {
		if( $filenameMap{$originalRequestFilename} ne $playbackRequestFilename)
		{
		  $resultErrInfo = "The original Request included the filename $originalRequestFilename\n";
		  $resultErrInfo.= "while the playback Request included the filename $playbackRequestFilename.\n";
		  $resultErrInfo.= "The filename in the original Request, however, was already mapped to\n";
		  $resultErrInfo.= "the filename ".$filenameMap{$originalRequestFilename}.".\n";
		  if($DBG >= DBG_MED)
		  {
			print LOG Indent($logIndent);
			print LOG "ValidFilenameMapping will return 0 (i.e. false), and has set the resultErrInfo variable as follows:\n";
			print LOG $resultErrInfo;
			LogFunctionExit("ValidFilenameMapping");
		  }
		  return 0;
		}
		else
		{
		  if($DBG >= DBG_HIGH)
		  {
			print LOG Indent($logIndent);
			print LOG "The filenames found in the original and playback Requests respected the previously\n";
			print LOG Indent($logIndent);
			print LOG "set mapping; no substitution necessary.\n";
		  }
		}
	  }
	  elsif(	(!exists($filenameMap{$originalRequestFilename}))
			||	(!$filenameMapSet{$originalRequestFilename}) )
	  {
		if($DBG >= DBG_HIGH)
		{
			print LOG Indent($logIndent);
			print LOG "The original Request included the filename $originalRequestFilename;\n";
			print LOG Indent($logIndent);
			print LOG "the playback Request included the filename $playbackRequestFilename.\n";
			print LOG Indent($logIndent);
			print LOG "A new filename mapping will be created: $originalRequestFilename => $playbackRequestFilename.\n";
		}
		$filenameMap{$originalRequestFilename} = $playbackRequestFilename;
		$filenameMapSet{$originalRequestFilename} = 1;
	  }
	}
	#--- End Comparison Block #1
	
	if(		$transactionType == TRANSACTION_OBS_OBSTORE_POST
	   ||	$transactionType == TRANSACTION_OBS_DOWNLOAD_OBJECT_DATA
	   ||	$transactionType == TRANSACTION_OBS_OBSTORE_GET)
	{
	  my $originalResponseFilename = ExtractFilenameFromResponse($originalResponse, $transactionType);
	  my $playbackResponseFilename = ExtractFilenameFromResponse($playbackResponse, $transactionType);
	  
	  #--- Look at the filenames in the responses:
	  #--- Comparison Block #2:
	  if($originalResponseFilename)
	  {
		if(!$playbackResponseFilename)
		{
		  $resultErrInfo = "The original Response included the filename $originalResponseFilename\n";
		  $resultErrInfo.= "while the playback Response did not include any filename.\n";
		  if($DBG >= DBG_MED)
		  {
			print LOG Indent($logIndent);
			print LOG "ValidFilenameMapping will return 0 (i.e. false), and has set the resultErrInfo variable as follows:\n";
			print LOG $resultErrInfo;
			LogFunctionExit("ValidFilenameMapping");
		  }
		  return 0;
		}
		elsif(		exists($filenameMap{$originalResponseFilename})
			  &&	$filenameMapSet{$originalResponseFilename}
			)
		{
		  if( $filenameMap{$originalResponseFilename} ne $playbackResponseFilename)
		  {
			$resultErrInfo = "The original Response included the filename $originalResponseFilename\n";
			$resultErrInfo.= "while the playback Response included the filename $playbackResponseFilename.\n";
			$resultErrInfo.= "The filename in the original Response, however, was already mapped to\n";
			$resultErrInfo.= "the filename ".$filenameMap{$originalResponseFilename}.".\n";
			if($DBG >= DBG_MED)
			{
			  print LOG Indent($logIndent);
			  print LOG "ValidFilenameMapping will return 0 (i.e. false), and has set the resultErrInfo variable as follows:\n";
			  print LOG $resultErrInfo;
			  LogFunctionExit("ValidFilenameMapping");
			}
			return 0;
		  }
		  else
		  {
			if($DBG >= DBG_HIGH)
			{
			  print LOG Indent($logIndent);
			  print LOG "The filenames found in the original and playback Responses respected the previously\n";
			  print LOG Indent($logIndent);
			  print LOG "set mapping; no substitution necessary.\n";
			}
		  }
		}
		elsif(		(!exists($filenameMap{$originalResponseFilename}))
			  ||	(!$filenameMapSet{$originalResponseFilename}) )
		{
		  if($DBG >= DBG_HIGH)
		  {
			print LOG Indent($logIndent);
			print LOG "The original Response included the filename $originalResponseFilename;\n";
			print LOG Indent($logIndent);
			print LOG "the playback Response included the filename $playbackResponseFilename.\n";
			print LOG Indent($logIndent);
			print LOG "A new filename mapping will be created: $originalResponseFilename => $playbackResponseFilename.\n";
		  }
		  $filenameMap{$originalResponseFilename} = $playbackResponseFilename;
		  $filenameMapSet{$originalResponseFilename} = 1;
		}
	  }
	  #--- End Comparison Block #2
	  
	  #--- Look across the transaction:
	  #--- Comparison Block #3:
	  if(	$originalRequestFilename
		 &&	$originalResponseFilename
		 &&	($originalRequestFilename eq $originalResponseFilename)
		 &&	(	(!$playbackRequestFilename)
			 ||	(!$playbackResponseFilename)
			 ||	($playbackRequestFilename ne $playbackResponseFilename)
			)
		)
	  {
		$resultErrInfo = "The original Transaction included the same filename $originalRequestFilename\n";
		$resultErrInfo.= "in both the Request and Response.\n";
		$resultErrInfo.= "The playback Transaction did not match this requirement:\n";
		$resultErrInfo.= "The filename in the playback Request:  $playbackRequestFilename\n";
		$resultErrInfo.= "The filename in the playback Response: $playbackResponseFilename\n";
		if($DBG >= DBG_MED)
		{
		  print LOG Indent($logIndent);
		  print LOG "ValidFilenameMapping will return 0 (i.e. false), and has set the resultErrInfo variable as follows:\n";
		  print LOG $resultErrInfo;
		  LogFunctionExit("ValidFilenameMapping");
		}
		return 0;
	  }
	  #--- End Comparison Block #3
	}
	elsif($DBG >= DBG_HIGH)
	{
	  print LOG Indent($logIndent);
	  print LOG "No Filename in the Responses of this kind of transactions.\n";
	}
  }
  elsif($DBG >= DBG_HIGH)
  {
	print LOG Indent($logIndent);
	print LOG "No Filename in this kind of transactions.\n";
  }

  if($DBG >= DBG_HIGH)
  {
	print LOG Indent($logIndent);
	print LOG "ValidFilenameMapping will return $res (i.e. ";
	if($res)	{ print LOG "true"; }
	else		{ print LOG "false"; }
	print LOG ")\n";
  }
  if($DBG >= DBG_MED)	{ LogFunctionExit("ValidFilenameMapping"); }
  return $res;
}
#	End ValidFilenameMapping
#^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^

=pod

=head1 ValidSerializedMapping Procedure

=head2 Description:

  A procedure to verify whether the current transaction elements
  respect any previously set Serialized Object element mappings
  (ObjectStore specific).

=head2 Input:

=over 4

=item 1

  $originalRequest	The HTTP::Request from the original recording;

=item 2

  $originalResponse	The HTTP::Response from the original recording;

=item 3

  $playbackRequest	The HTTP::Request used during the playback;

=item 4

  $playbackResponse	The HTTP::Response obtained during the playback.

=back

=head2 Returns:

  $res	Equal to 1 (i.e. True) if the transaction respects all
		the previously set Serialized Object mappings;
		Equal to 0 (i.e. False) otherwise.
  
=head2 Notes:

  All of the mapping verifications are structure din three blocks:
  ~ block #1:	The 'variable' elements from the original request and
				from the playback request are extracted, and the
				file-scoped mapping hashes are analyzed to verify if the
				'variable' elements from the original request were
				mapped to some corresponding element (and, if so,
				whether these pre-existing mappings are respected by the
				playback request);
  ~ block #2:	The 'variable' elements from the original response and
				from the playback response are extracted, and the
				file-scoped mapping hashes are analyzed to verify if the
				'variable' elements from the original response were
				mapped to some corresponding element (and, if so,
				whether these pre-existing mappings are respected by the
				playback response);
  ~ block #3:	If a 'variable' element appears in both the original
				request and original response, and is identical in the
				two HTTP messages, then the playback request and
				playback response are checked to verify that the same
				relationship exists between the 'variable' elements in
				them.
  Each mapping verification routine may implement any combination of
  these three blocks.
  If the mapping verification routine detects an erroneous condition,
  it is expected to set the file-scoped $resultErrInfo variable with
  an appropriate description of the issue, and return 0 (i.e. false)
  to the caller.

=cut

#	ValidSerializedMapping:
#^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
sub ValidSerializedMapping
{
  if($DBG >= DBG_MED)	{ LogFunctionEntry("ValidSerializedMapping"); }
  
  my ($originalRequest, $originalResponse, $playbackRequest, $playbackResponse) = @_;
  
  my $res = 1;
  
  if(	$transactionType == TRANSACTION_OBS_ADD_OBJECT
	 ||	$transactionType == TRANSACTION_OBS_GET_OBJECT	)
  {
	my $originalRequestSerialized = ExtractSerializedFromRequest($originalRequest, $transactionType);
	my $playbackRequestSerialized = ExtractSerializedFromRequest($playbackRequest, $transactionType);
	
	#--- Look at the filenames in the requests:
	#--- Comparison Block #1:
    if($originalRequestSerialized)
	{
	  if(!$playbackRequestSerialized)
	  {
	    $resultErrInfo = "The original Request included the serialized object $originalRequestSerialized\n";
	    $resultErrInfo.= "while the playback Request did not include any serialized object.\n";
	    if($DBG >= DBG_MED)
	    {
	  	print LOG Indent($logIndent);
	  	print LOG "ValidSerializedMapping will return 0 (i.e. false), and has set the resultErrInfo variable as follows:\n";
	  	print LOG $resultErrInfo;
	  	LogFunctionExit("ValidSerializedMapping");
	    }
	    return 0;
	  }
	  elsif(	exists($serializedMap{$originalRequestSerialized})
			&&	$serializedMapSet{$originalRequestSerialized}
			)
	  {
	    if( $serializedMap{$originalRequestSerialized} ne $playbackRequestSerialized)
		{
		  $resultErrInfo = "The original Request included the serialized object $originalRequestSerialized\n";
		  $resultErrInfo.= "while the playback Request included the serialized object $playbackRequestSerialized.\n";
		  $resultErrInfo.= "The serialized object in the original Request, however, was already mapped to\n";
		  $resultErrInfo.= "the serialized object ".$serializedMap{$originalRequestSerialized}.".\n";
		  if($DBG >= DBG_MED)
		  {
		    print LOG Indent($logIndent);
		    print LOG "ValidSerializedMapping will return 0 (i.e. false), and has set the resultErrInfo variable as follows:\n";
		    print LOG $resultErrInfo;
		    LogFunctionExit("ValidSerializedMapping");
		  }
		  return 0;
		}
		else
		{
		  if($DBG >= DBG_HIGH)
		  {
		    print LOG Indent($logIndent);
		    print LOG "The serialized objects found in the original and playback Requests respected the previously\n";
		    print LOG Indent($logIndent);
		    print LOG "set mapping; no substitution necessary.\n";
		  }
		}
	  }
	  elsif(	(!exists($serializedMap{$originalRequestSerialized}))
			||	(!$serializedMapSet{$originalRequestSerialized}) )
	  {
	    if($DBG >= DBG_HIGH)
	    {
		  print LOG Indent($logIndent);
		  print LOG "The original Request included the serialized object $originalRequestSerialized;\n";
	  	  print LOG Indent($logIndent);
	  	  print LOG "the playback Request included the serialized object $playbackRequestSerialized.\n";
	  	  print LOG Indent($logIndent);
	  	  print LOG "A new serialized object mapping will be created: $originalRequestSerialized => $playbackRequestSerialized.\n";
	    }
		$serializedMap{$originalRequestSerialized} = $playbackRequestSerialized;
	    $serializedMapSet{$originalRequestSerialized} = 1;
	  }
	}
	#--- End Comparison Block #1
	
	if(		$transactionType == TRANSACTION_OBS_GET_OBJECT	)
	{
	  my $originalResponseSerialized = ExtractSerializedFromResponse($originalResponse, $transactionType);
	  my $playbackResponseSerialized = ExtractSerializedFromResponse($playbackResponse, $transactionType);
	  
	  #--- Look at the filenames in the responses:
	  #--- Comparison Block #2:
	  if($originalResponseSerialized)
	  {
		if(!$playbackResponseSerialized)
		{
		  $resultErrInfo = "The original Response included the serialized object $originalResponseSerialized\n";
		  $resultErrInfo.= "while the playback Response did not include any serialized object.\n";
		  if($DBG >= DBG_MED)
		  {
			print LOG Indent($logIndent);
			print LOG "ValidSerializedMapping will return 0 (i.e. false), and has set the resultErrInfo variable as follows:\n";
			print LOG $resultErrInfo;
			LogFunctionExit("ValidSerializedMapping");
		  }
		  return 0;
		}
		elsif(	exists($serializedMap{$originalResponseSerialized})
			&&	$serializedMapSet{$originalResponseSerialized}
			)
		{
		  if( $serializedMap{$originalResponseSerialized} ne $playbackResponseSerialized)
		  {
			$resultErrInfo = "The original Response included the serialized object $originalResponseSerialized\n";
			$resultErrInfo.= "while the playback Response included the serialized object $playbackResponseSerialized.\n";
			$resultErrInfo.= "The serialized object in the original Response, however, was already mapped to\n";
			$resultErrInfo.= "the serialized object ".$serializedMap{$originalResponseSerialized}.".\n";
			if($DBG >= DBG_MED)
			{
			  print LOG Indent($logIndent);
			  print LOG "ValidSerializedMapping will return 0 (i.e. false), and has set the resultErrInfo variable as follows:\n";
			  print LOG $resultErrInfo;
			  LogFunctionExit("ValidSerializedMapping");
			}
			return 0;
		  }
		  else
		  {
			if($DBG >= DBG_HIGH)
			{
			  print LOG Indent($logIndent);
			  print LOG "The serialized objects found in the original and playback Responses respected the previously\n";
			  print LOG Indent($logIndent);
			  print LOG "set mapping; no substitution necessary.\n";
			}
		  }
		}
		elsif(	(!exists($serializedMap{$originalResponseSerialized}))
			||	(!$serializedMapSet{$originalResponseSerialized}) )
		{
		  if($DBG >= DBG_HIGH)
		  {
			  print LOG Indent($logIndent);
			  print LOG "The original Response included the serialized object $originalResponseSerialized;\n";
			  print LOG Indent($logIndent);
			  print LOG "the playback Response included the serialized object $playbackResponseSerialized.\n";
			  print LOG Indent($logIndent);
			  print LOG "A new serialized object mapping will be created: $originalResponseSerialized => $playbackResponseSerialized.\n";
		  }
		  $serializedMap{$originalResponseSerialized} = $playbackResponseSerialized;
		  $serializedMapSet{$originalResponseSerialized} = 1;
		}
	  }
	  #--- End Comparison Block #2
	  
	  #--- Look across the transaction:
	  #--- Comparison Block #3:
	  if(	$originalRequestSerialized
		 &&	$originalResponseSerialized
		 &&	($originalRequestSerialized eq $originalResponseSerialized)
		 &&	(	(!$playbackRequestSerialized)
			 ||	(!$playbackResponseSerialized)
			 ||	($playbackRequestSerialized ne $playbackResponseSerialized)
			)
		)
	  {
		$resultErrInfo = "The original Transaction included the same serialized object $originalRequestSerialized\n";
		$resultErrInfo.= "in both the Request and Response.\n";
		$resultErrInfo.= "The playback Transaction did not match this requirement:\n";
		$resultErrInfo.= "The serialized object in the playback Request:  $playbackRequestSerialized\n";
		$resultErrInfo.= "The serialized object in the playback Response: $playbackResponseSerialized\n";
		if($DBG >= DBG_MED)
		{
		  print LOG Indent($logIndent);
		  print LOG "ValidSerializedMapping will return 0 (i.e. false), and has set the resultErrInfo variable as follows:\n";
		  print LOG $resultErrInfo;
		  LogFunctionExit("ValidSerializedMapping");
		}
		return 0;
	  }
	  #--- End Comparison Block #3
	}
	elsif($DBG >= DBG_HIGH)
	{
	  print LOG Indent($logIndent);
	  print LOG "No Serialized Object in the Responses of this kind of transactions.\n";
	}
  }
  elsif($DBG >= DBG_HIGH)
  {
	print LOG Indent($logIndent);
	print LOG "No Serialized Object in this kind of transactions.\n";
  }

  if($DBG >= DBG_HIGH)
  {
	print LOG Indent($logIndent);
	print LOG "ValidSerializedMapping will return $res (i.e. ";
	if($res)	{ print LOG "true"; }
	else		{ print LOG "false"; }
	print LOG ")\n";
  }
  if($DBG >= DBG_MED)	{ LogFunctionExit("ValidSerializedMapping"); }
  return $res;
}
#	End ValidSerializedMapping
#^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^

=pod

=head1 ValidEnvLastUpdatedMapping Procedure

=head2 Description:

  A procedure to verify whether the current transaction elements
  respect any previously set envLastUpdated element mappings
  (ObjectStore specific).

=head2 Input:

=over 4

=item 1

  $originalResponse	The HTTP::Response from the original recording;

=item 2

  $playbackResponse	The HTTP::Response obtained during the playback.

=back

=head2 Returns:

  $res	Equal to 1 (i.e. True) if the transaction respects all
		the previously set envLastUpdated mappings;
		Equal to 0 (i.e. False) otherwise.
  
=head2 Notes:

  All of the mapping verifications are structure din three blocks:
  ~ block #1:	The 'variable' elements from the original request and
				from the playback request are extracted, and the
				file-scoped mapping hashes are analyzed to verify if the
				'variable' elements from the original request were
				mapped to some corresponding element (and, if so,
				whether these pre-existing mappings are respected by the
				playback request);
  ~ block #2:	The 'variable' elements from the original response and
				from the playback response are extracted, and the
				file-scoped mapping hashes are analyzed to verify if the
				'variable' elements from the original response were
				mapped to some corresponding element (and, if so,
				whether these pre-existing mappings are respected by the
				playback response);
  ~ block #3:	If a 'variable' element appears in both the original
				request and original response, and is identical in the
				two HTTP messages, then the playback request and
				playback response are checked to verify that the same
				relationship exists between the 'variable' elements in
				them.
  Each mapping verification routine may implement any combination of
  these three blocks.
  If the mapping verification routine detects an erroneous condition,
  it is expected to set the file-scoped $resultErrInfo variable with
  an appropriate description of the issue, and return 0 (i.e. false)
  to the caller.

=cut

#	ValidEnvLastUpdatedMapping:
#^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
sub ValidEnvLastUpdatedMapping
{
  if($DBG >= DBG_MED)	{ LogFunctionEntry("ValidEnvLastUpdatedMapping"); }
  
  my ($originalResponse, $playbackResponse) = @_;
  
  my $res = 1;
  
  if(	$transactionType == TRANSACTION_OBS_GET_LAST_UPDATE_TIME	)
  {
    my $originalResponseELU = ExtractEnvLastUpdatedFromResponse($originalResponse, $transactionType);
    my $playbackResponseELU = ExtractEnvLastUpdatedFromResponse($playbackResponse, $transactionType);
    
    #--- Look at the EnvLastUpdated elements in the responses:
    #--- Comparison Block #2:
    if($originalResponseELU)
    {
  	if(!$playbackResponseELU)
  	{
  	  $resultErrInfo = "The original Response included the EnvLastUpdated element $originalResponseELU\n";
  	  $resultErrInfo.= "while the playback Response did not include any EnvLastUpdated element.\n";
  	  if($DBG >= DBG_MED)
  	  {
  		print LOG Indent($logIndent);
  		print LOG "ValidEnvLastUpdatedMapping will return 0 (i.e. false), and has set the resultErrInfo variable as follows:\n";
  		print LOG $resultErrInfo;
  		LogFunctionExit("ValidEnvLastUpdatedMapping");
  	  }
  	  return 0;
  	}
		elsif(	exists($envLastUpdatedMap{$originalResponseELU})
			&&	$envLastUpdatedMapSet{$originalResponseELU}
			)
		{
		  if( $envLastUpdatedMap{$originalResponseELU} ne $playbackResponseELU)
		  {
			$resultErrInfo = "The original Response included the envLastUpdated element $originalResponseELU\n";
			$resultErrInfo.= "while the playback Response included the envLastUpdated element $playbackResponseELU.\n";
			$resultErrInfo.= "The envLastUpdated element in the original Response, however, was already mapped to\n";
			$resultErrInfo.= "the envLastUpdated element ".$envLastUpdatedMap{$originalResponseELU}.".\n";
			if($DBG >= DBG_MED)
			{
			  print LOG Indent($logIndent);
			  print LOG "ValidEnvLastUpdatedMapping will return 0 (i.e. false), and has set the resultErrInfo variable as follows:\n";
			  print LOG $resultErrInfo;
			  LogFunctionExit("ValidEnvLastUpdatedMapping");
			}
			return 0;
		  }
		  else
		  {
			if($DBG >= DBG_HIGH)
			{
			  print LOG Indent($logIndent);
			  print LOG "The envLastUpdated elements found in the original and playback Responses respected the previously\n";
			  print LOG Indent($logIndent);
			  print LOG "set mapping; no substitution necessary.\n";
			}
		  }
		}
		elsif(	(!exists($envLastUpdatedMap{$originalResponseELU}))
			||	(!$envLastUpdatedMapSet{$originalResponseELU}) )
		{
		  if($DBG >= DBG_HIGH)
		  {
			  print LOG Indent($logIndent);
			  print LOG "The original Response included the envLastUpdated element $originalResponseELU;\n";
			  print LOG Indent($logIndent);
			  print LOG "the playback Response included the envLastUpdated element $playbackResponseELU.\n";
			  print LOG Indent($logIndent);
			  print LOG "A new envLastUpdated element mapping will be created: $originalResponseELU => $playbackResponseELU.\n";
		  }
		  $envLastUpdatedMap{$originalResponseELU} = $playbackResponseELU;
		  $envLastUpdatedMapSet{$originalResponseELU} = 1;
		}
	  }
	  #--- End Comparison Block #2
	
	#--- Comparison Block 3: Across the transaction, not possible
	# since the EnvLastUpdated element appears only in the responses
  }
  elsif($DBG >= DBG_HIGH)
  {
	print LOG Indent($logIndent);
	print LOG "No EnvLastUpdate in this kind of transactions.\n";
  }

  if($DBG >= DBG_HIGH)
  {
	print LOG Indent($logIndent);
	print LOG "ValidEnvLastUpdateMapping will return $res (i.e. ";
	if($res)	{ print LOG "true"; }
	else		{ print LOG "false"; }
	print LOG ")\n";
  }
  if($DBG >= DBG_MED)	{ LogFunctionExit("ValidEnvLastUpdatedMapping"); }
  return $res;
}
#	End ValidEnvLastUpdatedMapping
#^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^

=pod

=head1 ValidObjLastUpdatedMapping Procedure

=head2 Description:

  A procedure to verify whether the current transaction elements
  respect any previously set objLastUpdated element mappings
  (ObjectStore specific).

=head2 Input:

=over 4

=item 1

  $originalResponse	The HTTP::Response from the original recording;

=item 2

  $playbackResponse	The HTTP::Response obtained during the playback.

=back

=head2 Returns:

  $res	Equal to 1 (i.e. True) if the transaction respects all
		the previously set objLastUpdated mappings;
		Equal to 0 (i.e. False) otherwise.
  
=head2 Notes:

  All of the mapping verifications are structure din three blocks:
  ~ block #1:	The 'variable' elements from the original request and
				from the playback request are extracted, and the
				file-scoped mapping hashes are analyzed to verify if the
				'variable' elements from the original request were
				mapped to some corresponding element (and, if so,
				whether these pre-existing mappings are respected by the
				playback request);
  ~ block #2:	The 'variable' elements from the original response and
				from the playback response are extracted, and the
				file-scoped mapping hashes are analyzed to verify if the
				'variable' elements from the original response were
				mapped to some corresponding element (and, if so,
				whether these pre-existing mappings are respected by the
				playback response);
  ~ block #3:	If a 'variable' element appears in both the original
				request and original response, and is identical in the
				two HTTP messages, then the playback request and
				playback response are checked to verify that the same
				relationship exists between the 'variable' elements in
				them.
  Each mapping verification routine may implement any combination of
  these three blocks.
  If the mapping verification routine detects an erroneous condition,
  it is expected to set the file-scoped $resultErrInfo variable with
  an appropriate description of the issue, and return 0 (i.e. false)
  to the caller.

=cut

#	ValidObjLastUpdatedMapping:
#^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
sub ValidObjLastUpdatedMapping
{
  if($DBG >= DBG_MED)	{ LogFunctionEntry("ValidObjLastUpdatedMapping"); }
  
  my ($originalResponse, $playbackResponse) = @_;
  
  my $res = 1;
  
  if(	$transactionType == TRANSACTION_OBS_GET_LAST_UPDATE_TIME	)
  {
    my $originalResponseOLU = ExtractObjLastUpdatedFromResponse($originalResponse, $transactionType);
    my $playbackResponseOLU = ExtractObjLastUpdatedFromResponse($playbackResponse, $transactionType);
    
    #--- Look at the EnvLastUpdated elements in the responses:
    #--- Comparison Block #2:
    if($originalResponseOLU)
    {
  	if(!$playbackResponseOLU)
  	{
  	  $resultErrInfo = "The original Response included the ObjLastUpdated element $originalResponseOLU\n";
  	  $resultErrInfo.= "while the playback Response did not include any ObjLastUpdated element.\n";
  	  if($DBG >= DBG_MED)
  	  {
  		print LOG Indent($logIndent);
  		print LOG "ValidObjLastUpdatedMapping will return 0 (i.e. false), and has set the resultErrInfo variable as follows:\n";
  		print LOG $resultErrInfo;
  		LogFunctionExit("ValidObjLastUpdatedMapping");
  	  }
  	  return 0;
  	}
		elsif(	exists($objLastUpdatedMap{$originalResponseOLU})
			&&	$objLastUpdatedMapSet{$originalResponseOLU}
			)
		{
		  if( $objLastUpdatedMap{$originalResponseOLU} ne $playbackResponseOLU)
		  {
			$resultErrInfo = "The original Response included the objLastUpdated element $originalResponseOLU\n";
			$resultErrInfo.= "while the playback Response included the objLastUpdated element $playbackResponseOLU.\n";
			$resultErrInfo.= "The objLastUpdated element in the original Response, however, was already mapped to\n";
			$resultErrInfo.= "the objLastUpdated element ".$objLastUpdatedMap{$originalResponseOLU}.".\n";
			if($DBG >= DBG_MED)
			{
			  print LOG Indent($logIndent);
			  print LOG "ValidObjLastUpdatedMapping will return 0 (i.e. false), and has set the resultErrInfo variable as follows:\n";
			  print LOG $resultErrInfo;
			  LogFunctionExit("ValidObjLastUpdatedMapping");
			}
			return 0;
		  }
		  else
		  {
			if($DBG >= DBG_HIGH)
			{
			  print LOG Indent($logIndent);
			  print LOG "The objLastUpdated elements found in the original and playback Responses respected the previously\n";
			  print LOG Indent($logIndent);
			  print LOG "set mapping; no substitution necessary.\n";
			}
		  }
		}
		elsif(	(!exists($objLastUpdatedMap{$originalResponseOLU}))
			||	(!$objLastUpdatedMapSet{$originalResponseOLU}) )
		{
		  if($DBG >= DBG_HIGH)
		  {
			  print LOG Indent($logIndent);
			  print LOG "The original Response included the objLastUpdated element $originalResponseOLU;\n";
			  print LOG Indent($logIndent);
			  print LOG "the playback Response included the objLastUpdated element $playbackResponseOLU.\n";
			  print LOG Indent($logIndent);
			  print LOG "A new objLastUpdated element mapping will be created: $originalResponseOLU => $playbackResponseOLU.\n";
		  }
		  $objLastUpdatedMap{$originalResponseOLU} = $playbackResponseOLU;
		  $objLastUpdatedMapSet{$originalResponseOLU} = 1;
		}
	  }
	  #--- End Comparison Block #2
	
	#--- Comparison Block 3: Across the transaction, not possible
	# since the ObjLastUpdated element appears only in the responses
  }
  elsif($DBG >= DBG_HIGH)
  {
	print LOG Indent($logIndent);
	print LOG "No ObjLastUpdated element in this kind of transactions.\n";
  }

  if($DBG >= DBG_HIGH)
  {
	print LOG Indent($logIndent);
	print LOG "ValidObjLastUpdatedMapping will return $res (i.e. ";
	if($res)	{ print LOG "true"; }
	else		{ print LOG "false"; }
	print LOG ")\n";
  }
  if($DBG >= DBG_MED)	{ LogFunctionExit("ValidObjLastUpdatedMapping"); }
  return $res;
}
#	End ValidObjLastUpdatedMapping
#^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^

=pod

=head1 ValidMappings Procedure

=head2 Description:

  A procedure to verify whether the current transaction elements
  respect any previously set mapping of the 'variable' elements
  that may appear in it (ObjectStore specific).

=head2 Input:

=over 4

=item 1

  $originalRequest	The HTTP::Request from the original recording;

=item 2

  $originalResponse	The HTTP::Response from the original recording;

=item 3

  $playbackRequest	The HTTP::Request used during the playback;

=item 4

  $playbackResponse	The HTTP::Response obtained during the playback.

=back

=head2 Returns:

  $res	Equal to 1 (i.e. True) if the transaction respects all
		the previously set 'variable' element mappings;
		Equal to 0 (i.e. False) otherwise.
  
=head2 Notes:

  The routine relies upon the various mapping verification routines
  to determine if the transaction respects the various mappings.
  Since these routines are required to set the file-scoped
  $resultErrInfo variable with a description of any issue detected,
  this routine needs only return true or false.
  <v052>
  The various mapping verification routines are not even invoked
  in the case of a DPS playback to save a few cycles.
  </v052>

=cut

#	ValidMappings:
#^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
sub ValidMappings
{
  if($DBG >= DBG_MED)	{ LogFunctionEntry("ValidMappings"); }
  
  my ($originalRequest, $originalResponse, $playbackRequest, $playbackResponse) = @_;

  my $res = 1;
  
  #<v052>
  # Don't even call these routines in the case of a DPS recording.
  #</v052>
  if($recordingServerType == SERVER_OBS)
  {
  
  if(!ValidQueryMapping($originalRequest, $playbackRequest))
  {
	if($DBG >= DBG_HIGH)
	{
	  print LOG Indent($logIndent);
	  print LOG "ValidQueryMapping has returned false. ValidMappings will return false.\n";
	}
	$res = 0;
  }
  if($res && (!ValidGuidMapping($originalRequest, $playbackRequest)) )
  {
	if($DBG >= DBG_HIGH)
	{
	  print LOG Indent($logIndent);
	  print LOG "ValidGuidMapping has returned false. ValidMappings will return false.\n";
	}
	$res = 0;
  }
  if($res && (!ValidFilenameMapping($originalRequest, $originalResponse, $playbackRequest, $playbackResponse)) )
  {
	if($DBG >= DBG_HIGH)
	{
	  print LOG Indent($logIndent);
	  print LOG "ValidFilenameMapping has returned false. ValidMappings will return false.\n";
	}
	$res = 0;
  }
  if($res && (!ValidSerializedMapping($originalRequest, $originalResponse, $playbackRequest, $playbackResponse)) )
  {
	if($DBG >= DBG_HIGH)
	{
	  print LOG Indent($logIndent);
	  print LOG "ValidSerializedMapping has returned false. ValidMappings will return false.\n";
	}
	$res = 0;
  }
  if($res && (!ValidEnvLastUpdatedMapping($originalResponse, $playbackResponse) ) )
  {
	if($DBG >= DBG_HIGH)
	{
	  print LOG Indent($logIndent);
	  print LOG "ValidEnvLastUpdatedMapping has returned false. ValidMappings will return false.\n";
	}
	$res = 0;
  }
  if($res && (!ValidObjLastUpdatedMapping($originalResponse, $playbackResponse) ) )
  {
	if($DBG >= DBG_HIGH)
	{
	  print LOG Indent($logIndent);
	  print LOG "ValidObjLastUpdatedMapping has returned false. ValidMappings will return false.\n";
	}
	$res = 0;
  }
  if($res && (!ValidLPOMapping($originalRequest, $originalResponse, $playbackRequest, $playbackResponse) ) )
  {
	if($DBG >= DBG_HIGH)
	{
	  print LOG Indent($logIndent);
	  print LOG "ValidLPOMapping has returned false. ValidMappings will return false.\n";
	}
	$res = 0;
  }
  
  }# IF $recordingServerType == SERVER_OBS;
  #ELSE do nothing (none of the 'variables' checked in the block above
  # exist in the DPS recordings.
  
  if($DBG >= DBG_HIGH)
  {
	print LOG Indent($logIndent);
	print LOG "ValidMappings will return $res (i.e. ";
	if($res)	{ print LOG "true"; }
	else		{ print LOG "false"; }
	print LOG ")\n";
  }
  
  if($DBG >= DBG_MED)	{ LogFunctionExit("ValidMappings"); }
  return $res;
}
#	End ValidMappings
#^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^

=pod

=head1 ExtractLPOFromRequest Procedure

=head2 Description:

  A procedure to extract the lpObject element from an ObjectStore
  HTTP::Request (ObjectStore specific).

=head2 Input:

=over 4

=item 1

  $obj	The HTTP Message from which the element should be extracted.

=item 2

  $type	The type of transaction that the $obj is part of.

=back

=head2 Returns:

  $res	The lpObject extracted from the $obj message.
  
=head2 Notes:

  The $res scalar will be empty if the $obj message does not contain
  any such element.

=cut

#	ExtractLPOFromRequest:
#^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
sub ExtractLPOFromRequest
{
  if($DBG >= DBG_MED)	{ LogFunctionEntry("ExtractLPOFromRequest"); }
  
  my ($obj, $type) = @_;
  
  if($DBG >= DBG_HIGH)
  {
	print LOG Indent($logIndent);
	print LOG "Type of Transaction: $type (".TransactionTypeName($type).")\n";
  }
  
  my $res = "";
  
  if(	$type == TRANSACTION_OBS_ADD_OBJECT
	 ||	$type == TRANSACTION_OBS_UPDATE_OBJECT )
  {
	my $content = $obj->content();
	
	if($DBG >= DBG_HIGH)
	{
	  print LOG Indent($logIndent);
	  print LOG "The content received: $content\n";
	}
	
	if($content)
	{
	  my ($pre, $post) = split(/<lpObject>/, $content);
	  ($pre, $post) = split(/<\/lpObject>/, $post);
	  $res = $pre;
	}#IF any content
  }#IF $type is one of those WITH a Serialized in the content
  elsif($DBG >= DBG_HIGH)
  {
	print LOG Indent($logIndent);
	print LOG "No lpObject exists in this kind of request.\n";
  }
  
  if($DBG >=DBG_HIGH)
  {
	print LOG Indent($logIndent);
	print LOG "lpObject Extracted: $res\n";
  }  
  
  if($DBG >= DBG_MED)	{ LogFunctionExit("ExtractLPOFromRequest"); }
  return $res;
}
#	End ExtractLPOFromRequest
#^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^

=pod

=head1 ExtractSerializedFromRequest Procedure

=head2 Description:

  A procedure to extract the Serialized Object element from an
  ObjectStore HTTP::Request (ObjectStore specific).

=head2 Input:

=over 4

=item 1

  $obj	The HTTP Message from which the element should be extracted.

=item 2

  $type	The type of transaction that the $obj is part of.

=back

=head2 Returns:

  $res	The Serialized Object extracted from the $obj message.
  
=head2 Notes:

  The $res scalar will be empty if the $obj message does not contain
  any such element.

=cut

#	ExtractSerializedFromRequest:
#^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
sub ExtractSerializedFromRequest
{
  if($DBG >= DBG_MED)	{ LogFunctionEntry("ExtractSerializedFromRequest"); }
  
  my ($obj, $type) = @_;
  
  if($DBG >= DBG_HIGH)
  {
	print LOG Indent($logIndent);
	print LOG "Type of Transaction: $type (".TransactionTypeName($type).")\n";
  }
  
  my $res = "";
  
  if(	$type == TRANSACTION_OBS_ADD_OBJECT
	 ||	$type == TRANSACTION_OBS_GET_OBJECT	)
  {
	my $content = $obj->content();
	
	if($DBG >= DBG_HIGH)
	{
	  print LOG Indent($logIndent);
	  print LOG "The content received: $content\n";
	}
	
	if($content)
	{
	  my ($pre, $post) = split(/<bstrSerializedObject>/, $content);
	  ($pre, $post) = split(/<\/bstrSerializedObject>/, $post);
	  $res = $pre;
	}#IF any content
  }#IF $type is one of those WITH a Serialized in the content
  elsif($DBG >= DBG_HIGH)
  {
	print LOG Indent($logIndent);
	print LOG "No Serialized Object exists in this kind of request.\n";
  }
  
  if($DBG >=DBG_HIGH)
  {
	print LOG Indent($logIndent);
	print LOG "Serialized Object Extracted: $res\n";
  }  
  
  if($DBG >= DBG_MED)	{ LogFunctionExit("ExtractSerializedFromRequest"); }
  return $res;
}
#	End ExtractSerializedFromRequest
#^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^

=pod

=head1 ExtractGUIDFromRequest Procedure

=head2 Description:

  A procedure to extract the GUID element from an
  ObjectStore HTTP::Request (ObjectStore specific).

=head2 Input:

=over 4

=item 1

  $obj	The HTTP Message from which the element should be extracted.

=item 2

  $type	The type of transaction that the $obj is part of.

=back

=head2 Returns:

  $res	The GUID extracted from the $obj message.
  
=head2 Notes:

  The $res scalar will be empty if the $obj message does not contain
  any such element.

=cut

#	ExtractGUIDFromRequest:
#^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
sub ExtractGUIDFromRequest
{
  if($DBG >= DBG_MED)	{ LogFunctionEntry("ExtractGUIDFromRequest"); }
  
  my ($obj, $type) = @_;
  
  if($DBG >= DBG_HIGH)
  {
	print LOG Indent($logIndent);
	print LOG "Type of Transaction: $type (".TransactionTypeName($type).")\n";
  }
  
  my $res = "";
  
  if(	$type == TRANSACTION_OBS_GET_OBJECT
	||	$type == TRANSACTION_OBS_UPLOAD_OBJECT_DATA
	||	$type == TRANSACTION_OBS_ADD_OBJECT
	||	$type == TRANSACTION_OBS_DOWNLOAD_OBJECT_DATA
	||	$type == TRANSACTION_OBS_REMOVE_OBJECT	)
  {
	my $content = $obj->content();
	if($content)
	{
	  my ($pre, $post) = split(/<bstrObjectGUID>/, $content);
	  ($pre, $post) = split(/<\/bstrObjectGUID>/, $post);
	  $res = $pre;
	}#IF any content
  }#IF $type is one of those WITH a GUID in the content
  elsif($DBG >= DBG_HIGH)
  {
	print LOG Indent($logIndent);
	print LOG "No GUID exists in this kind of request.\n";
  }

  if($DBG >=DBG_HIGH)
  {
	print LOG Indent($logIndent);
	print LOG "GUID Extracted: $res\n";
  }
 
  if($DBG >= DBG_MED)	{ LogFunctionExit("ExtractGUIDFromRequest"); }
  return $res;
}
#	End ExtractGUIDFromRequest
#^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^

=pod

=head1 ExtractFilenameFromRequest Procedure

=head2 Description:

  A procedure to extract the Filename element from an
  ObjectStore HTTP::Request (ObjectStore specific).

=head2 Input:

=over 4

=item 1

  $obj	The HTTP Message from which the element should be extracted.

=item 2

  $type	The type of transaction that the $obj is part of.

=back

=head2 Returns:

  $res	The Filename extracted from the $obj message.
  
=head2 Notes:

  The $res scalar will be empty if the $obj message does not contain
  any such element.

=cut

#	ExtractFilenameFromRequest:
#^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
sub ExtractFilenameFromRequest
{
  if($DBG >= DBG_MED)	{ LogFunctionEntry("ExtractFilenameFromRequest"); }
  
  my ($obj, $type) = @_;
  
  if($DBG >= DBG_HIGH)
  {
	print LOG Indent($logIndent);
	print LOG "Type of Transaction: $type (".TransactionTypeName($type).")\n";
  }
  
  my $res = "";
  
  if( $type == TRANSACTION_OBS_OBSTORE_POST )
  {
	my $content = $obj->content();
	my @lines = split(/\n/, $content);
	foreach my $line (@lines)
	{
	  if($line =~ /filename=/)
	  {
		#Store the filename (in quotes) in $post:
		my ($pre, $post) = split(/filename=/, $line);
		
		#Trim the double quotes:
		my $postS = length($post);
		$post = substr($post, 1, ($postS-3));
		$res = $post;
		last;
	  }#IF
	}#FOREACH
  }
  elsif(	$type == TRANSACTION_OBS_OBSTORE_GET )
  {
	my $theURI = $obj->uri();
	my $theSplit = "\Q/get/\E";
	my ($pre, $post) = split(/$theSplit/, $theURI);
	$res = $post;
  }
  elsif(	$type == TRANSACTION_OBS_ADD_OBJECT
		||	$type == TRANSACTION_OBS_UPLOAD_OBJECT_DATA
		||	$type == TRANSACTION_OBS_DOWNLOAD_OBJECT_DATA	)
  {
	my $content = $obj->content();
	if($content)
	{
	  my ($pre, $post) = split(/<bstrFileName>/, $content);
	  ($pre, $post) = split(/<\/bstrFileName>/, $post);
	  $res = $pre;
	}#IF any content
  }#IF $type is one of those WITH a Filename in the content
  elsif($DBG >= DBG_HIGH)
  {
	print LOG Indent($logIndent);
	print LOG "No Filename exists in this kind of request.\n";
  }

  if($DBG >=DBG_HIGH)
  {
	print LOG Indent($logIndent);
	print LOG "Filename Extracted: $res\n";
  }
  
  if($DBG >= DBG_MED)	{ LogFunctionExit("ExtractFilenameFromRequest"); }
  return $res;
}
#	End ExtractFilenameFromRequest
#^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^

=pod

=head1 ExtractQueryFromRequest Procedure

=head2 Description:

  A procedure to extract the Query element from an
  ObjectStore HTTP::Request (ObjectStore specific).

=head2 Input:

=over 4

=item 1

  $obj	The HTTP Message from which the element should be extracted.

=item 2

  $type	The type of transaction that the $obj is part of.

=back

=head2 Returns:

  $res	The Query extracted from the $obj message.
  
=head2 Notes:

  The $res scalar will be empty if the $obj message does not contain
  any such element.

=cut

#	ExtractQueryFromRequest:
#^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
sub ExtractQueryFromRequest
{
  if($DBG >= DBG_MED)	{ LogFunctionEntry("ExtractQueryFromRequest"); }
  
  my ($obj, $type) = @_;
  
  if($DBG >= DBG_HIGH)
  {
	print LOG Indent($logIndent);
	print LOG "Type of Transaction: $type (".TransactionTypeName($type).")\n";
  }
  
  my $res = "";
  
  if(	$type == TRANSACTION_OBS_EXECUTE_SEARCH
	 ||	$type == TRANSACTION_OBS_GET_LAST_UPDATE_TIME)
  {
	my $content = $obj->content();
	if($content)
	{
	  my ($pre, $post) = split(/<bstrQueryIn>/, $content);
	  ($pre, $post) = split(/<\/bstrQueryIn>/, $post);
	  $res = $pre;
	}#IF any content
  }#IF $type is one of those WITH a Query in the content
  elsif($DBG >= DBG_HIGH)
  {
	print LOG Indent($logIndent);
	print LOG "No Query exists in this kind of request.\n";
  }

  if($DBG >=DBG_HIGH)
  {
	print LOG Indent($logIndent);
	print LOG "Query Extracted: $res\n";
  }
  
  if($DBG >= DBG_MED)	{ LogFunctionExit("ExtractQueryFromRequest"); }
  return $res;
}
#	End ExtractQueryFromRequest
#^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^

=pod

=head1 ExtractDPSCommandFromRequest Procedure

=head2 Description:

  A procedure to extract the DPS Command Value from a
  DPS HTTP::Request (DPS specific).

=head2 Input:

=over 4

=item 1

  $content	The content of the HTTP::Request, from which the Command
			Value should be extracted.

=back

=head2 Returns:

  $result	The Command Value extracted from the $content.
  
=head2 Notes:

  <v052>
  This routine has been introduced with v.0.52.
  The $result scalar will be empty if the $content does not contain
  any such element.
  The routine looks for a numeric value immediatly following the
  "uCommand" string in the $content. The Command Value must be found
  between that string and the next --[...]--000 delimiter.
  </v052>

=cut

#	ExtractDPSCommandFromRequest
#^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
sub ExtractDPSCommandFromRequest
{
  if($DBG >= DBG_MED)	{ LogFunctionEntry("ExtractDPSCommandFromRequest"); }
  
  my $content = $_[0];
  
  my ($pre, $post) = split(/\Q"uCommand"\E/, $content);
  
  my $result = "";
  my @tmp = ();
  
  @tmp = split(//, $post);
  
  my $L = @tmp;
  my $cursor = 0;
  while($cursor<$L && $tmp[$cursor] ne "-" && $tmp[$cursor]!~/\d/)
  { $cursor++; }
  if($cursor<$L && $tmp[$cursor]=~/\d/)
  {
	while($cursor<$L && $tmp[$cursor]=~/\d/)
	{ $result.=$tmp[$cursor]; $cursor++; }
  }
  
  if($DBG >= DBG_MED)
  {
	print LOG Indent($logIndent);
	print LOG "DPS Command extracted: $result\n";
	LogFunctionExit("ExtractDPSCommandFromRequest");
  }
  return $result;
}
#	End ExtractDPSCommandFromRequest
#^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^

=pod

=head1 ExtractJobIDFromRequest Procedure

=head2 Description:

  A procedure to extract the Job ID from a
  DPS HTTP::Request (DPS specific).

=head2 Input:

=over 4

=item 1

  $content	The content of the HTTP::Request, from which the Job ID
			should be extracted.

=back

=head2 Returns:

  $result	The Job ID extracted from the $content.
  
=head2 Notes:

  <v052>
  This routine has been introduced with v.0.52.
  The $result scalar will be empty if the $content does not contain
  any such element.
  The routine looks for a numeric value immediatly following the
  "pszJobID" string in the $content. The Command Value must be found
  between that string and the next --[...]--000 delimiter.
  </v052>

=cut

#	ExtractJobIDFromRequest
#^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
sub ExtractJobIDFromRequest
{
  if($DBG >= DBG_MED)	{ LogFunctionEntry("ExtractJobIDFromRequest"); }
  
  my $result = "";

  if($transactionID%2!=0)
  {
	my $content = $_[0];
	my ($pre, $post) = split(/\Q"pszJobID"\E/, $content);
	
	my @tmp = ();
	@tmp = split(//, $post);
	my $L = @tmp;
	
	my $cursor = 0;
	while($cursor<$L && $tmp[$cursor] ne "-" && $tmp[$cursor]!~ /\d/ )
	{ $cursor++; }
	if($cursor<$L && $tmp[$cursor]=~/\d/)
	{
	  while($cursor<$L && $tmp[$cursor]=~/\d/)
	  { $result.=$tmp[$cursor]; $cursor++; }
	}
	
  }
  
  if($DBG >= DBG_MED)	{ LogFunctionExit("ExtractJobIDFromRequest"); }
  return $result;
}
#	End ExtractJobIDFromRequest
#^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^

=pod

=head1 ExtractClientIpFromRequest Procedure

=head2 Description:

  Routine to extract the Client Ip element from a DPS Request
  (DPS Specific).

=head2 Input:

=over 4

=item 1

  $content	The content of the HTTP::Request from which the element
			should be extracted.

=back

=head2 Returns:

  $result	The Client Ip element in the $content, if any.

=head2 Notes:
  <v052>
  This routine was introduced in v.0.52.
  The routine recognizes a client Ip address as a sequence
  of digits and/or periods between the "pszClientID" marker and
  the ---[...]---000 delimiter.
  </v052>

=cut

#	ExtractClientIpFromRequest
#^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
sub ExtractClientIpFromRequest
{
  if($DBG >= DBG_MED)	{ LogFunctionEntry("ExtractClientIpFromRequest"); }
  
  my $result = "";

  if($transactionID%2!=0)
  {
	my $content = $_[0];
	my ($pre, $post) = split(/\Q"pszClientID"\E/, $content);
	
	my @tmp = ();
	@tmp = split(//, $post);
	my $L = @tmp;
	
	my $cursor = 0;
	while($cursor<$L && $tmp[$cursor] ne "-" && $tmp[$cursor]!~ /\d/ )
	{ $cursor++; }
	if($cursor<$L && ($tmp[$cursor]=~/\d/ || $tmp[$cursor] eq "."))
	{
	  while($cursor<$L && ($tmp[$cursor]=~/\d/ || $tmp[$cursor] eq "."))
	  { $result.=$tmp[$cursor]; $cursor++; }
	}
	
  }
  
  if($DBG >= DBG_MED)	{ LogFunctionExit("ExtractClientIpFromRequest"); }
  return $result;
}
#	End ExtractClientIpFromRequest
#^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
=pod

=head1 ExtractServerIpFromRequest Procedure

=head2 Description:

  Routine to extract the Server Ip element from a DPS Request
  (DPS Specific).

=head2 Input:

=over 4

=item 1

  $content	The content of the HTTP::Request from which the element
			should be extracted.

=back

=head2 Returns:

  $result	The Server Ip element in the $content, if any.

=head2 Notes:
  <v052>
  This routine was introduced in v.0.52.
  The routine recognizes a client Ip address as a sequence
  of digits and/or periods between the "pszServerID" marker and
  the ---[...]---000 delimiter.
  </v052>

=cut

#	ExtractServerIpFromRequest
#^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
sub ExtractServerIpFromRequest
{
  if($DBG >= DBG_MED)	{ LogFunctionEntry("ExtractServerIpFromRequest"); }
  
  my $result = "";

  if($transactionID%2!=0)
  {
	my $content = $_[0];
	my ($pre, $post) = split(/\Q"pszServerID"\E/, $content);
	
	my @tmp = ();
	@tmp = split(//, $post);
	my $L = @tmp;
	
	my $cursor = 0;
	while($cursor<$L && $tmp[$cursor] ne "-" && $tmp[$cursor]!~ /\d/ )
	{ $cursor++; }
	if($cursor<$L && ($tmp[$cursor]=~/\d/ || $tmp[$cursor] eq "."))
	{
	  while($cursor<$L && ($tmp[$cursor]=~/\d/ || $tmp[$cursor] eq "."))
	  { $result.=$tmp[$cursor]; $cursor++; }
	}
	
  }
  
  if($DBG >= DBG_MED)	{ LogFunctionExit("ExtractServerIpFromRequest"); }
  return $result;
}
#	End ExtractServerIpFromRequest
#^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^

=pod

=head1 ExtractLPOFromResponse Procedure

=head2 Description:

  A procedure to extract the lpObject element from an
  ObjectStore HTTP::Response (ObjectStore specific).

=head2 Input:

=over 4

=item 1

  $obj	The HTTP Message from which the element should be extracted.

=item 2

  $type	The type of transaction that the $obj is part of.

=back

=head2 Returns:

  $res	The lpObject extracted from the $obj message.
  
=head2 Notes:

  The $res scalar will be empty if the $obj message does not contain
  any such element.

=cut

#	ExtractLPOFromResponse:
#^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
sub ExtractLPOFromResponse
{
  if($DBG >= DBG_MED)	{ LogFunctionEntry("ExtractLPOFromResponse"); }
  
  my ($obj, $type) = @_;
  
  if($DBG >= DBG_HIGH)
  {
	print LOG Indent($logIndent);
	print LOG "Type of Transaction: $type (".TransactionTypeName($type).")\n";
  }
  
  my $res = "";
  if($type == TRANSACTION_OBS_GET_OBJECT)
  {
	my $content = $obj->content();
	if($content)
	{
	  my ($pre, $post) = split(/<lpObject>/, $content);
	  ($pre, $post) = split(/<\/lpObject>/, $post);
	  $res = $pre;
	}#IF any content
  }#IF $type is one of those WITH a Serialized in the content
  elsif($DBG >= DBG_HIGH)
  {
	print LOG Indent($logIndent);
	print LOG "No lpObject exists in this type of response.\n";
  }
  
  if($DBG >=DBG_HIGH)
  {
	print LOG Indent($logIndent);
	print LOG "lpObject Extracted: $res\n";
  }
  
  if($DBG >= DBG_MED)	{ LogFunctionExit("ExtractLPOFromResponse"); }
  return $res;
}
#	End ExtractLPOFromResponse
#^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^

=pod

=head1 ExtractSerializedFromResponse Procedure

=head2 Description:

  A procedure to extract the Serialized Object element from an
  ObjectStore HTTP::Response (ObjectStore specific).

=head2 Input:

=over 4

=item 1

  $obj	The HTTP Message from which the element should be extracted.

=item 2

  $type	The type of transaction that the $obj is part of.

=back

=head2 Returns:

  $res	The Serialized Object extracted from the $obj message.
  
=head2 Notes:

  The $res scalar will be empty if the $obj message does not contain
  any such element.

=cut

#	ExtractSerializedFromResponse:
#^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
sub ExtractSerializedFromResponse
{
  if($DBG >= DBG_MED)	{ LogFunctionEntry("ExtractSerializedFromResponse"); }
  
  my ($obj, $type) = @_;
  
  if($DBG >= DBG_HIGH)
  {
	print LOG Indent($logIndent);
	print LOG "Type of Transaction: $type (".TransactionTypeName($type).")\n";
  }
  
  my $res = "";
  if($type == TRANSACTION_OBS_GET_OBJECT)
  {
	my $content = $obj->content();
	if($content)
	{
	  my ($pre, $post) = split(/<bstrSerializedObject>/, $content);
	  ($pre, $post) = split(/<\/bstrSerializedObject>/, $post);
	  $res = $pre;
	}#IF any content
  }#IF $type is one of those WITH a Serialized in the content
  elsif($DBG >= DBG_HIGH)
  {
	print LOG Indent($logIndent);
	print LOG "No Serialized Object exists in this type of response.\n";
  }
  
  if($DBG >=DBG_HIGH)
  {
	print LOG Indent($logIndent);
	print LOG "Serialized Object Extracted: $res\n";
  }
  
  if($DBG >= DBG_MED)	{ LogFunctionExit("ExtractSerializedFromResponse"); }
  return $res;
}
#	End ExtractSerializedFromResponse
#^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^

=pod

=head1 ExtractFilenameFromResponse Procedure

=head2 Description:

  A procedure to extract the Filename element from an
  ObjectStore HTTP::Response (ObjectStore specific).

=head2 Input:

=over 4

=item 1

  $obj	The HTTP Message from which the element should be extracted.

=item 2

  $type	The type of transaction that the $obj is part of.

=back

=head2 Returns:

  $res	The Filename extracted from the $obj message.
  
=head2 Notes:

  The $res scalar will be empty if the $obj message does not contain
  any such element.

=cut

#	ExtractFilenameFromResponse:
#^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
sub ExtractFilenameFromResponse
{
  if($DBG >= DBG_MED)	{ LogFunctionEntry("ExtractFilenameFromResponse"); }
  
  my ($obj, $type) = @_;
  
  if($DBG >= DBG_HIGH)
  {
	print LOG Indent($logIndent);
	print LOG "Type of Transaction: $type (".TransactionTypeName($type).")\n";
  }
  
  my $res = "";
  if($type == TRANSACTION_OBS_OBSTORE_POST)
  {
	if($DBG >= DBG_HIGH)
	{
	  print LOG Indent($logIndent);
	  print LOG "It is an ObjectStore Obstore POST transaction Response:\n";
	  print LOG Indent($logIndent);
	  print LOG "Will scan for the 'OK: file=' token\n";
	}
	my $content = $obj->content();
	if($content =~ /OK: file=/)
	{
	  my ($pre, $post) = split(/OK: file=/, $content);
	  ($pre, $post) = split(/;/, $post);
	  $res = $pre;
	}
  }
  elsif($type == TRANSACTION_OBS_OBSTORE_GET)
  {
	my $CDheader = $obj->header('Content-Disposition');
	my ($pre, $post) = split(/filename=/, $CDheader);
	$res = $post;
  }
  elsif($type == TRANSACTION_OBS_DOWNLOAD_OBJECT_DATA)
  {
	my $content = $obj->content();
	if($content)
	{
	  my ($pre, $post) = split(/<bstrFileName>/, $content);
	  ($pre, $post) = split(/<\/bstrFileName>/, $post);
	  $res = $pre;
	}#IF any content
  }#IF $type is one of those WITH a Filename in the content
  elsif($DBG >= DBG_HIGH)
  {
	print LOG Indent($logIndent);
	print LOG "No Filename exists in this type of response.\n";
  }

  if($DBG >=DBG_HIGH)
  {
	print LOG Indent($logIndent);
	print LOG "Filename Extracted: ";
	if($res)	{ print LOG $res; }
	print LOG "\n";
  }
  
  if($DBG >= DBG_MED)	{ LogFunctionExit("ExtractFilenameFromResponse"); }
  return $res;
}
#	End ExtractFilenameFromResponse
#^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^

=pod

=head1 ExtractEnvLastUpdatedFromresponse Procedure

=head2 Description:

  A procedure to extract the envLastUpdated element from an
  ObjectStore HTTP::Response (ObjectStore specific).

=head2 Input:

=over 4

=item 1

  $obj	The HTTP Message from which the element should be extracted.

=item 2

  $type	The type of transaction that the $obj is part of.

=back

=head2 Returns:

  $res	The envLastUpdated extracted from the $obj message.
  
=head2 Notes:

  The $res scalar will be empty if the $obj message does not contain
  any such element.

=cut

#	ExtractEnvLastUpdatedFromResponse:
#^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
sub ExtractEnvLastUpdatedFromResponse
{
  if($DBG >= DBG_MED)	{ LogFunctionEntry("ExtractEnvLastUpdatedFromResponse"); }
  
  my ($obj, $type) = @_;
  
  if($DBG >= DBG_HIGH)
  {
	print LOG Indent($logIndent);
	print LOG "Type of Transaction: $type (".TransactionTypeName($type).")\n";
  }
  
  my $res = "";
  if($type == TRANSACTION_OBS_GET_LAST_UPDATE_TIME)
  {
	my $content = $obj->content();
	if($content)
	{
	  my ($pre, $post) = split(/<dEnvLastUpdated>/, $content);
	  ($pre, $post) = split(/<\/dEnvLastUpdated>/, $post);
	  $res = $pre;
	}#IF any content
  }#IF $type is one of those WITH a EnvLastUpdate in the content
  elsif($DBG >= DBG_HIGH)
  {
	print LOG Indent($logIndent);
	print LOG "No EnvLastUpdated element exists in this type of response.\n";
  }
  
  if($DBG >=DBG_HIGH)
  {
	print LOG Indent($logIndent);
	print LOG "EnvLastUpdated Extracted: $res\n";
  }
  
  if($DBG >= DBG_MED)	{ LogFunctionExit("ExtractEnvLastUpdatedFromResponse"); }
  return $res;
}
#	End ExtractEnvLastUpdatedFromResponse
#^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^

=pod

=head1 ExtractObjLastUpdatedFromResponse Procedure

=head2 Description:

  A procedure to extract the objLastUpdated element from an
  ObjectStore HTTP::Response (ObjectStore specific).

=head2 Input:

=over 4

=item 1

  $obj	The HTTP Message from which the element should be extracted.

=item 2

  $type	The type of transaction that the $obj is part of.

=back

=head2 Returns:

  $res	The objLastUpdated extracted from the $obj message.
  
=head2 Notes:

  The $res scalar will be empty if the $obj message does not contain
  any such element.

=cut

#	ExtractObjLastUpdatedFromResponse:
#^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
sub ExtractObjLastUpdatedFromResponse
{
  if($DBG >= DBG_MED)	{ LogFunctionEntry("ExtractObjLastUpdatedFromResponse"); }
  
  my ($obj, $type) = @_;
  
  if($DBG >= DBG_HIGH)
  {
	print LOG Indent($logIndent);
	print LOG "Type of Transaction: $type (".TransactionTypeName($type).")\n";
  }
  
  my $res = "";
  if($type == TRANSACTION_OBS_GET_LAST_UPDATE_TIME)
  {
	my $content = $obj->content();
	if($content)
	{
	  my ($pre, $post) = split(/<dObjLastUpdated>/, $content);
	  ($pre, $post) = split(/<\/dObjLastUpdated>/, $post);
	  $res = $pre;
	}#IF any content
  }#IF $type is one of those WITH a ObjLastUpdated in the content
  elsif($DBG >= DBG_HIGH)
  {
	print LOG Indent($logIndent);
	print LOG "No ObjLastUpdated element exists in this type of response.\n";
  }
  
  if($DBG >=DBG_HIGH)
  {
	print LOG Indent($logIndent);
	print LOG "ObjLastUpdated Extracted: $res\n";
  }
  
  if($DBG >= DBG_MED)	{ LogFunctionExit("ExtractObjLastUpdatedFromResponse"); }
  return $res;
}
#	End ExtractObjLastUpdatedFromResponse
#^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^

=pod

=head1 ExtractDPSChallenge Procedure

=head2 Description:

  A procedure to extract the security challenge sent by a DPS
  Server in a "WWW-Authenticate" HTTP::Header (DPS specific).

=head2 Input:

=over 4

=item 1

  $theHeader	The HTTP Header from which the security challenge
				should be extracted.

=back

=head2 Returns:

  $r	The security challenge.
  
=head2 Notes:

  <v052>
  This routine has been introduced with v.0.52.
  The routine assumes that the $theHeader is an appropriate header,
  and that the security challenge will be the first quotes-delimited
  substring in the header's value.
  </v052>

=cut

#	ExtractDPSChallenge
#^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
sub ExtractDPSChallenge
{
  if($DBG >= DBG_MED)	{ LogFunctionEntry("ExtractDPSChallenge"); }
  
  my $theHeader = $_[0];
  
  my @parts = split(/"/, $theHeader);
  
  my $r =$parts[1];
  
  if($DBG >= DBG_MED)	{ LogFunctionExit("ExtractDPSChallenge"); }
  return $r;
}
#	End ExtractDPSChallenge
#^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^

=pod

=head1 DPSchallengeReply Procedure

=head2 Description:

  A procedure to create a DPS security challenge reply.

=head2 Input:

=over 4

=item 1

  $challenge	The security challenge to which the reply answers.

=back

=head2 Returns:

  $r	The security challenge reply.
  
=head2 Notes:

  <v052>
  This routine has been introduced with v.0.52.
  The routine relies upon the itidpsc32.dll module.
  </v052>

=cut

#	DPSchallengeReply
#^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
sub DPSchallengeReply
{
  if($DBG >= DBG_MED)	{ LogFunctionEntry("DPSchallengeReply"); }
  
  my $challenge = $lastDPSchallenge;
  my $r = $challenge.":";
  my $api = new Win32::API("itdpsc32.dll", "DesEncrypt",
						   ['P', 'P', 'P'], 'P');
  my $secureKey = UnlockKey();
  my $dummy = " "x128;
  my $enc = $api->Call($dummy, $challenge, $secureKey);
  $r.=$enc;
  
  $r = encode_base64($r);
  
  if($DBG >= DBG_MED)	{ LogFunctionExit("DPSchallengeReply"); }
  return $r;
}
#	End DPSchallengeReply
#^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^

=pod

=head1 HashFileList Procedure

=head2 Description:

  A procedure to transform the content of a DPS JM_LISTFILES response
  into a hash.

=head2 Input:

=over 4

=item 1

  $src	The content of the JM_LISTFILES response.

=back

=head2 Returns:

  $theHashRef	A reference to the hash generated.
  
=head2 Notes:

  <v052>
  This routine has been introduced with v.0.52.
  Each element in the hash generated is keyed by filename, and is
  structured as follows:
  <filename> ->	{
				  FILENAME	->	<filename>,
				  DATE		->	<date>,
				  TIME		->	<time>,
				  SIZE		->	<size>,
				  BASICFILE	->	<basicfile_flag>,
				  JOBID		->	<job_id>
				}
  The keys of the inner hashes are script-scoped constants.
  the values in the inner hashes are gathered from the data in the $src
  parameter. The routine assumes that the $src is structured as a series
  of lines (\n-terminated), and that each line represents a file in the
  list, and is formatted as follows:
  <filename>\t<date>\t<time>\t<size>\t<basicfile_flag>\t<job_id>
  If one or more of these elements are missing from the line,
  the routine will NOT create an inner hash for that element.
  </v052>

=cut

#	HashFileList
#^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
sub HashFileList
{
  if($DBG >= DBG_MED)	{ LogFunctionEntry("HashFileList"); }
  
  my $src = $_[0];
  
  my %theHash = ();
  my @lines = split(/\n/, $src);
  foreach my $line (@lines)
  {
	my @parts = split(/\t/, $line);
	my $partsSize = @parts;
	
	my %miniHash = ();
	if($partsSize>=1)
	{
	  $miniHash{FILENAME}			= $parts[0];
	  if($partsSize>=2)
	  {
		$miniHash{DATE}				= $parts[1];
		if($partsSize>=3)
		{
		  $miniHash{TIME}			= $parts[2];
		  if($partsSize>=4)
		  {
			$miniHash{SIZE}			= $parts[3];
			if($partsSize>=5)
			{
			  $miniHash{BASICFILE}	= $parts[4];
			  if($partsSize>=6)
			  {
				$miniHash{JOBID}	= $parts[5];
				my $miniHashRef = \%miniHash;
				$theHash{$parts[0]}=$miniHashRef;
			  }
			}
		  }
		}
	  }
	}
  }#FOREACH
  
  my $theHashRef =\%theHash;
  if($DBG >= DBG_MED)	{ LogFunctionExit("HashFileList"); }
  return $theHashRef;
}
#	End HashFileList
#^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^

=pod

=head1 HashJobList Procedure

=head2 Description:

  A procedure to transform the content of a DPS JM_LISTJOBS response
  into a hash.

=head2 Input:

=over 4

=item 1

  $src	The content of the JM_LISTJOBS response.

=back

=head2 Returns:

  $theHashRef	A reference to the hash generated.
  
=head2 Notes:

  <v052>
  This routine has been introduced with v.0.52.
  Each element in the hash generated is keyed by Job ID, and is
  structured as follows:
  <filename> ->	{
				  PS_JID		->	<job_id>,
				  PS_JNAME		->	<job_name>,
				  PS_JNAME2		->	<user_job_name>,
				  PS_JDESC		->	<job_description>,
				  PS_DATE		->	<date>,
				  PS_ENQUEUE	->	<enqueue_time>,
				  PS_START		->	<start_time>,
				  PS_END		->	<end_time>,
				  PS_PRIORITY	->	<job_priority>,
				  PS_STATUS		->	<job_status>,
				  PS_MODULE		->	<module>
				}
  The keys of the inner hashes are script-scoped constants.
  the values in the inner hashes are gathered from the data in the $src
  parameter. The routine assumes that the $src is structured as a series
  of lines (\n-terminated), and that each line represents a job in the
  list, and is formatted as follows:
  <job_id>\t<job_name>\t<user_job_name>\t<job_description>\t<date>\t
	<enqueue_time>\t<start_time>\t<end_time>\t<job_priority>\t
	<job_status>\t<module>
  If one or more of these elements are missing from the line,
  the routine will NOT create an inner hash for that element.
  </v052>

=cut

#	HashJobList
#^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
sub HashJobList
{
  if($DBG >= DBG_MED)	{ LogFunctionEntry("HashJobList"); }
  
  my $src = $_[0];
  
  my %theHash = ();
  my @lines = split(/\n/, $src);
  foreach my $line (@lines)
  {
	my @parts = split(/\t/, $line);
	my $partsSize = @parts;
	
	my %miniHash = ();
	if($partsSize>=1)
	{
	  $miniHash{PS_JID}							= $parts[0];
	  if($partsSize>=2)
	  {
		$miniHash{PS_JNAME}						= $parts[1];
		if($partsSize>=3)
		{
		  $miniHash{PS_JNAME2}					= $parts[2];
		  if($partsSize>=4)
		  {
			$miniHash{PS_JDESC}					= $parts[3];
			if($partsSize>=5)
			{
			  $miniHash{PS_DATE}				= $parts[4];
			  if($partsSize>=6)
			  {
				$miniHash{PS_ENQUEUE}			= $parts[5];
				if($partsSize>=7)
				{
				  $miniHash{PS_START}			= $parts[6];
				  if($partsSize>=8)
				  {
					$miniHash{PS_END}			= $parts[7];
					if($partsSize>=9)
					{
					  $miniHash{PS_PRIORITY}	= $parts[8];
					  if($partsSize>=10)
					  {
						$miniHash{PS_STATUS}	= $parts[9];
						if($partsSize>=11)
						{
						  $miniHash{PS_MODULE}	= $parts[10];
						  my $miniHashRef = \%miniHash;
						  $theHash{$parts[0]}=$miniHashRef;
						}
					  }
					}
				  }
				}
			  }
			}
		  }
		}
	  }
	}
  }#FOREACH
  
  my $theHashRef =\%theHash;
  if($DBG >= DBG_MED)	{ LogFunctionExit("HashJobList"); }
  return $theHashRef;
}
#	End HashJobList
#^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^

=pod

=head1 CompareFileLists Procedure

=head2 Description:

  A procedure to compare the contents of two responses to DPS
  JM_LISTFILES requests.

=head2 Input:

=over 4

=item 1

  $originalContent	The content of the first of the two responses;

=item 2

  $playbackContent	The content of the second of the two responses.

=back

=head2 Returns:

  $result	Equal to 1 (i.e. true) if the two responses match;
			equal to 0 (i.e. false) if any unexpected difference is
			detected.

=head2 Notes:

  <v052>
  This routine has been introduced with v.0.52.
  The routine relies upon the HashFileList routine to create a hash
  for each of the two lists to be compared.
  The routine recognizes as un-expected differences the following cases:
  ~	The two lists contain a different number of items;
  ~ An item in one of the two lists is not matched by a corresponding
	item in the other list;
  ~ The size or the basicfile-flag of two corresponding items in the
	two lists do not match.
  When an unexpected difference is detected, the routine also
  sets the file-scoped $resultErrInfo variable.
  </v052>

=cut

#	CompareFileLists
#^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
sub CompareFileLists
{
  if($DBG >= DBG_MED)	{ LogFunctionEntry("CompareFileLists"); }
  
  my ($originalContent, $playbackContent) = @_;
  
  my $originalListRef = HashFileList($originalContent);
  my $playbackListRef = HashFileList($playbackContent);
  
  my $result = 1;
  my %originalList = %$originalListRef;
  my %playbackList = %$playbackListRef;
  my $originalSize = keys(%originalList);
  my $playbackSize = keys(%playbackList);
  if($originalSize != $playbackSize)
  {
	$resultErrInfo = "The original and playback file lists include a different number\n";
	$resultErrInfo.= "of items.\n";
	$resultErrInfo.= "The original List ($originalSize items):\n";
	foreach my $n (sort(keys(%originalList)))
	{
	  $resultErrInfo.="  ".$originalList{$n}->{FILENAME};
	  $resultErrInfo.=", ".$originalList{$n}->{DATE};
	  $resultErrInfo.=", ".$originalList{$n}->{TIME};
	  $resultErrInfo.=", ".$originalList{$n}->{SIZE};
	  $resultErrInfo.=", ".$originalList{$n}->{BASICFILE};
	  $resultErrInfo.=", ".$originalList{$n}->{JOBID};
	  $resultErrInfo.="\n";
	}
	$resultErrInfo.= "The playback List ($playbackSize items):\n";
	foreach my $n (sort(keys(%playbackList)))
	{
	  $resultErrInfo.="  ".$playbackList{$n}->{FILENAME};
	  $resultErrInfo.=", ".$playbackList{$n}->{DATE};
	  $resultErrInfo.=", ".$playbackList{$n}->{TIME};
	  $resultErrInfo.=", ".$playbackList{$n}->{SIZE};
	  $resultErrInfo.=", ".$playbackList{$n}->{BASICFILE};
	  $resultErrInfo.=", ".$playbackList{$n}->{JOBID};
	  $resultErrInfo.="\n";
	}
	$result = 0;
  }
  else
  {
	foreach my $n (sort(keys(%originalList)))
	{
	  #Here $n is a filename, so they have to match exactly!
	  if(!exists($playbackList{$n}))
	  {
		$resultErrInfo = "The original List includes an item missing from the playback List:\n";
		$resultErrInfo.="  ".$originalList{$n}->{FILENAME};
		$resultErrInfo.=", ".$originalList{$n}->{DATE};
		$resultErrInfo.=", ".$originalList{$n}->{TIME};
		$resultErrInfo.=", ".$originalList{$n}->{SIZE};
		$resultErrInfo.=", ".$originalList{$n}->{BASICFILE};
		$resultErrInfo.=", ".$originalList{$n}->{JOBID};
		$resultErrInfo.="\n";
		last;
	  }
	  
	  my $originalName = $originalList{$n}->{FILENAME};
	  my $originalDate = $originalList{$n}->{DATE};
	  my $originalTime = $originalList{$n}->{TIME};
	  my $originalSize = $originalList{$n}->{SIZE};
	  my $originalBasic= $originalList{$n}->{BASICFILE};
	  my $originalJob  = $originalList{$n}->{JOBID};
	  
	  my $pbkName = $playbackList{$n}->{FILENAME};
	  my $pbkDate = $playbackList{$n}->{DATE};
	  my $pbkTime = $playbackList{$n}->{TIME};
	  my $pbkSize = $playbackList{$n}->{SIZE};
	  my $pbkBasic= $playbackList{$n}->{BASICFILE};
	  my $pbkJob  = $playbackList{$n}->{JOBID};
	  
	  if($originalSize ne $pbkSize)
	  {
		$resultErrInfo = "The size of the file $originalName in the original and\n";
		$resultErrInfo.= "playback file lists is different:\n";
		$resultErrInfo.= "$originalSize in the original list; $pbkSize in the playback list.\n";
		$result = 0;
		last;
	  }
	  if($originalBasic ne $pbkBasic)
	  {
		$resultErrInfo = "The basic-file flag of the file $originalName in the original and\n";
		$resultErrInfo.= "playback file lists is different:\n";
		$resultErrInfo.= "$originalBasic in the original list; $pbkBasic in the playback list.\n";
		$result = 0;
		last;
	  }
	  #Date and Time differences are accepted.
	}#FOREACH
  }#ELSE
  
  if($result==0 && $DBG>=DBG_MED)
  {
	print LOG Indent($logIndent);
	print LOG "CompareFileLists has detected a discrepancy in the two file lists.\n";
	print LOG Indent($logIndent);
	print LOG "The resultErrInfo has been set as follows, and the routine will return 0 (i.e. false):\n";
	print LOG $resultErrInfo;
  }
  
  if($DBG >= DBG_MED)	{ LogFunctionExit("CompareFileLists"); }
  return $result;
}
#	End CompareFileLists
#^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^

=pod

=head1 CompareJobLists Procedure

=head2 Description:

  A procedure to compare the contents of two responses to DPS
  JM_LISTJOBS requests.

=head2 Input:

=over 4

=item 1

  $originalResponseContent	The content of the first of the two responses;

=item 2

  $playbackResponseContent	The content of the second of the two responses.

=item 3

  $playbackRequest	The HTTP::Request object used to obtain the
					$playbackResponseContent from the server.

=back

=head2 Returns:

  $result	Equal to 1 (i.e. true) if the two responses match;
			equal to 0 (i.e. false) if any unexpected difference is
			detected.

=head2 Notes:

  <v052>
  This routine has been introduced with v.0.52.
  The routine relies upon the MatchingJobLists routine to actually
  compare the two responses. If they don't match, the routine implements
  the "retry" loop. In short, the routine will try for at most
  $PROC_STATUS_RETRY times (at intervals of $PROC_STATUS_DELAY seconds)
  to obtain a new Joblist from the server, and each time it will check
  whether the new response matches the $originalResponseContent.
  As soon as the two responses match (or once the routine has tried
  $PROC_STATUS_RETRY times), the loop terminates.
  The routine relies upon the ReplayProcStatusTransaction routine
  to obtain a new response when needed.
  
  B<VERY IMPORTANT>: The wait cycle is implemented by a call
  to sleep $PROC_STATUS_DELAY seconds.
  </v052>

=cut

#	CompareJobLists
#^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
sub CompareJobLists
{
  if($DBG >= DBG_MED)	{ LogFunctionEntry("CompareJobLists"); }
  
  my ($originalResponseContent, $playbackResponseContent, $playbackRequest) = @_;
  
  my $repeats = 0;
  my $result = MatchingJobLists($originalResponseContent, $playbackResponseContent);

  while($result==0 && $repeats<$PROC_STATUS_RETRY)
  {
	#Wait for $PROC_STATUS_DELAY seconds:
	sleep $PROC_STATUS_DELAY;
	
	#Replay the whole transaction:
	my $newResponse = ReplayProcStatusTransaction($playbackRequest);
	
	#Re-compare:
	$result = MatchingJobLists($originalResponseContent, $newResponse->content);
	
	$repeats++;
  }#WEND
  
  if($DBG >= DBG_MED)	{ LogFunctionExit("CompareJobLists"); }
  return $result;
}
#	End CompareJobLists
#^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^

=pod

=head1 MatchingJobLists Procedure

=head2 Description:

  A procedure to compare the contents of two responses to DPS
  JM_LISTJOBS requests.

=head2 Input:

=over 4

=item 1

  $originalContent	The content of the first of the two responses;

=item 2

  $playbackContent	The content of the second of the two responses.

=back

=head2 Returns:

  $result	Equal to 1 (i.e. true) if the two responses match;
			equal to 0 (i.e. false) if any unexpected difference is
			detected.

=head2 Notes:

  <v052>
  This routine has been introduced with v.0.52.
  The routine relies upon the HashJobList routine to create a hash
  for each of the two lists to be compared.
  The routine recognizes as un-expected differences the following cases:
  ~	The two lists contain a different number of items;
  ~ An item in one of the two lists is not matched by a corresponding
	item in the other list (note that any pre-existing mapping of
	job Ids is considered when determining which job in the playback
	list corresponds to a given job in the original list);
  ~ Two corresponding jobs in the two lists have different statuses,
	and the statuses are incompatible (see below).
  When an unexpected difference is detected, the routine also
  sets the file-scoped $resultErrInfo variable.
  In regard to "compatible" and "incompatible" statuses, the following
  matrix summarizes which combination of job statuses are dimmed
  compatible:
   \ in pbk	|			|			|			|
  in\		| Pending	| Running	| Failed	| Success
  rec\______|			|			|			|
  			|			|			|			|
	Pending	|	V		|	V		|	V		|	V
	Running	|	X		|	V		|	V		|	V
	Failed	|	X		|	X		|	V		|	X
	Success	|	X		|	X		|	X		|	V
	
  Where 'V' indicates that the combination should be accepted
  as if the two statuses were identical (i.e. the statuses are
  compatible), while 'X' indicates that the combination should be
  refused (i.e. the statuses are incompatible).
  See the GetStatusIndex routine for an explanation of what job statuses
  are recognized as Pending, Running, Failed and Success.
  </v052>

=cut

#	MatchingJobLists
#^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
sub MatchingJobLists
{
  if($DBG >= DBG_MED)	{ LogFunctionEntry("MatchingJobLists"); }
  
  my ($originalContent, $playbackContent) = @_;

  my $result = 1;
  $resultErrInfo = "";
  
  my $originalListRef = HashJobList($originalContent);
  my $playbackListRef = HashJobList($playbackContent);
  
  my %originalList = %$originalListRef;
  my %playbackList = %$playbackListRef;
  
  my $originalListSize = keys(%originalList);
  my $playbackListSize = keys(%playbackList);

  if($originalListSize != $playbackListSize)
  {
	$resultErrInfo = "The number of items in the original and playback\n";
	$resultErrInfo.= "job lists are different.\n";
	$resultErrInfo.= "The Original List ($originalListSize items):\n";
	foreach my $n (sort(keys(%originalList)))
	{
	  $resultErrInfo.="  ".$originalList{$n}->{PS_JID};
	  $resultErrInfo.=", ".$originalList{$n}->{PS_JNAME};
	  $resultErrInfo.=", ".$originalList{$n}->{PS_JNAME2};
	  $resultErrInfo.=", ".$originalList{$n}->{PS_JDESC};
	  $resultErrInfo.=", ".$originalList{$n}->{PS_DATE};
	  $resultErrInfo.=", ".$originalList{$n}->{PS_ENQUEUE};
	  $resultErrInfo.=", ".$originalList{$n}->{PS_START};
	  $resultErrInfo.=", ".$originalList{$n}->{PS_END};
	  $resultErrInfo.=", ".$originalList{$n}->{PS_PRIORITY};
	  $resultErrInfo.=", ".$originalList{$n}->{PS_STATUS};
	  $resultErrInfo.=", ".$originalList{$n}->{PS_MODULE};
	  $resultErrInfo.=" \n";
	}#FOREACH
	$resultErrInfo.="The Playback List ($playbackListSize items):\n";
	foreach my $n (sort(keys(%playbackList)))
	{
	  $resultErrInfo.="  ".$playbackList{$n}->{PS_JID};
	  $resultErrInfo.=", ".$playbackList{$n}->{PS_JNAME};
	  $resultErrInfo.=", ".$playbackList{$n}->{PS_JNAME2};
	  $resultErrInfo.=", ".$playbackList{$n}->{PS_JDESC};
	  $resultErrInfo.=", ".$playbackList{$n}->{PS_DATE};
	  $resultErrInfo.=", ".$playbackList{$n}->{PS_ENQUEUE};
	  $resultErrInfo.=", ".$playbackList{$n}->{PS_START};
	  $resultErrInfo.=", ".$playbackList{$n}->{PS_END};
	  $resultErrInfo.=", ".$playbackList{$n}->{PS_PRIORITY};
	  $resultErrInfo.=", ".$playbackList{$n}->{PS_STATUS};
	  $resultErrInfo.=", ".$playbackList{$n}->{PS_MODULE};
	  $resultErrInfo.=" \n";
	}#FOREACH
	$result = 0;
  }
  else
  {
	foreach my $n (sort(keys(%originalList)))
	{
	  #If $n does not exists in the playback one, maybe there
	  #is a record in the playback for the JIB mapped to by $n ?
	  my $expectedJID = $n;
	  
	  if(exists($jobIdMap{$n}))
	  { $expectedJID = $jobIdMap{$n}; }
	  
	  if(!exists($playbackList{$expectedJID}))
	  {
		$resultErrInfo = "The original job list includes an item missing from the\n";
		$resultErrInfo.= "playback list:\n";
		$resultErrInfo.="  ".$originalList{$n}->{PS_JID};
		$resultErrInfo.=", ".$originalList{$n}->{PS_JNAME};
		$resultErrInfo.=", ".$originalList{$n}->{PS_JNAME2};
		$resultErrInfo.=", ".$originalList{$n}->{PS_JDESC};
		$resultErrInfo.=", ".$originalList{$n}->{PS_DATE};
		$resultErrInfo.=", ".$originalList{$n}->{PS_ENQUEUE};
		$resultErrInfo.=", ".$originalList{$n}->{PS_START};
		$resultErrInfo.=", ".$originalList{$n}->{PS_END};
		$resultErrInfo.=", ".$originalList{$n}->{PS_PRIORITY};
		$resultErrInfo.=", ".$originalList{$n}->{PS_STATUS};
		$resultErrInfo.=", ".$originalList{$n}->{PS_MODULE};
		$resultErrInfo.=" \n";
		$result = 0;
		last;
	  }
	  if(	($originalList{$n}->{PS_JNAME} ne $playbackList{$expectedJID}->{PS_JNAME} )
		 ||	($originalList{$n}->{PS_JNAME2} ne $playbackList{$expectedJID}->{PS_JNAME2} )
		 ||	($originalList{$n}->{PS_JDESC} ne $playbackList{$expectedJID}->{PS_JDESC} )
		 ||	($originalList{$n}->{PS_PRIORITY} ne $playbackList{$expectedJID}->{PS_PRIORITY} )
		 ||	($originalList{$n}->{PS_MODULE} ne $playbackList{$expectedJID}->{PS_MODULE} )
		)
	  {
		$resultErrInfo = "The original and playback lists differ in the following rows, which should match:\n";
		$resultErrInfo.="In the original List: ".$originalList{$n}->{PS_JID};
		$resultErrInfo.=", ".$originalList{$n}->{PS_JNAME};
		$resultErrInfo.=", ".$originalList{$n}->{PS_JNAME2};
		$resultErrInfo.=", ".$originalList{$n}->{PS_JDESC};
		$resultErrInfo.=", ".$originalList{$n}->{PS_DATE};
		$resultErrInfo.=", ".$originalList{$n}->{PS_ENQUEUE};
		$resultErrInfo.=", ".$originalList{$n}->{PS_START};
		$resultErrInfo.=", ".$originalList{$n}->{PS_END};
		$resultErrInfo.=", ".$originalList{$n}->{PS_PRIORITY};
		$resultErrInfo.=", ".$originalList{$n}->{PS_STATUS};
		$resultErrInfo.=", ".$originalList{$n}->{PS_MODULE};
		$resultErrInfo.=" \n";
		$resultErrInfo.="In the playback list: ".$playbackList{$expectedJID}->{PS_JID};
		$resultErrInfo.=", ".$playbackList{$expectedJID}->{PS_JNAME};
		$resultErrInfo.=", ".$playbackList{$expectedJID}->{PS_JNAME2};
		$resultErrInfo.=", ".$playbackList{$expectedJID}->{PS_JDESC};
		$resultErrInfo.=", ".$playbackList{$expectedJID}->{PS_DATE};
		$resultErrInfo.=", ".$playbackList{$expectedJID}->{PS_ENQUEUE};
		$resultErrInfo.=", ".$playbackList{$expectedJID}->{PS_START};
		$resultErrInfo.=", ".$playbackList{$expectedJID}->{PS_END};
		$resultErrInfo.=", ".$playbackList{$expectedJID}->{PS_PRIORITY};
		$resultErrInfo.=", ".$playbackList{$expectedJID}->{PS_STATUS};
		$resultErrInfo.=", ".$playbackList{$expectedJID}->{PS_MODULE};
		$resultErrInfo.=" \n";
		$result = 0;
		last;
	  }# IF un-acceptable difference
	  elsif(	$originalList{$n}->{PS_STATUS} ne $playbackList{$expectedJID}->{PS_STATUS}	)
	  {
		#Status difference:
		#the character in @table at row=index of status in original list
		#and col=index of status in playback list indicates whether
		#the combination is compatible or not: V is compatible,
		#X is not.
		
		my @table = ();
		push(@table, "VVVV");
		push(@table, "XVVV");
		push(@table, "XXVX");
		push(@table, "XXXV");
		
		my $originalStatusIndex = GetStatusIndex($originalList{$n}->{PS_STATUS});
		my $playbackStatusIndex = GetStatusIndex($playbackList{$expectedJID}->{PS_STATUS});
		
		my $action = substr($table[$originalStatusIndex],$playbackStatusIndex,1);
		if($action eq "X")
		{
		  $resultErrInfo = "The status of two corresponding jobs in the original and playback\n";
		  $resultErrInfo.= "job lists are incompatible.\n";
		  $resultErrInfo.="In the original List: ".$originalList{$n}->{PS_JID};
		  $resultErrInfo.=", ".$originalList{$n}->{PS_JNAME};
		  $resultErrInfo.=", ".$originalList{$n}->{PS_JNAME2};
		  $resultErrInfo.=", ".$originalList{$n}->{PS_JDESC};
		  $resultErrInfo.=", ".$originalList{$n}->{PS_DATE};
		  $resultErrInfo.=", ".$originalList{$n}->{PS_ENQUEUE};
		  $resultErrInfo.=", ".$originalList{$n}->{PS_START};
		  $resultErrInfo.=", ".$originalList{$n}->{PS_END};
		  $resultErrInfo.=", ".$originalList{$n}->{PS_PRIORITY};
		  $resultErrInfo.=", ".$originalList{$n}->{PS_STATUS};
		  $resultErrInfo.=", ".$originalList{$n}->{PS_MODULE};
		  $resultErrInfo.=" \n";
		  $resultErrInfo.="In the playback list: ".$playbackList{$expectedJID}->{PS_JID};
		  $resultErrInfo.=", ".$playbackList{$expectedJID}->{PS_JNAME};
		  $resultErrInfo.=", ".$playbackList{$expectedJID}->{PS_JNAME2};
		  $resultErrInfo.=", ".$playbackList{$expectedJID}->{PS_JDESC};
		  $resultErrInfo.=", ".$playbackList{$expectedJID}->{PS_DATE};
		  $resultErrInfo.=", ".$playbackList{$expectedJID}->{PS_ENQUEUE};
		  $resultErrInfo.=", ".$playbackList{$expectedJID}->{PS_START};
		  $resultErrInfo.=", ".$playbackList{$expectedJID}->{PS_END};
		  $resultErrInfo.=", ".$playbackList{$expectedJID}->{PS_PRIORITY};
		  $resultErrInfo.=", ".$playbackList{$expectedJID}->{PS_STATUS};
		  $resultErrInfo.=", ".$playbackList{$expectedJID}->{PS_MODULE};
		  $resultErrInfo.=" \n";
		  $result = 0;
		  last;
		}# IF action eq 'X'
		#ELSE action is 'V' and we consider this an acceptable difference.
	  }# IF status-difference detected.
	}#FOREACH
  }
  
  if($result==0 && $DBG>=DBG_MED)
  {
	print LOG Indent($logIndent);
	print LOG "MatchingJobLists will return 0 (i.e. false), and has set the resultErrInfo variable as follows:\n";
	print LOG $resultErrInfo;
  }
  if($DBG >= DBG_MED)	{ LogFunctionExit("MatchingJobLists"); }
  return $result;
}
#	End MatchingJobLists
#^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^

=pod

=head1 ReplayProcStatusTransaction Procedure

=head2 Description:

  A procedure in charge of providing a new response to a JM_LISTJOBS
  DPS request.

=head2 Input:

=over 4

=item 1

  $modelRequest	The request to be used as model when generating a new
				JM_LISTJOBS request.

=back

=head2 Returns:

  $newResponse	The new HTTP::Response received from the Server.

=head2 Notes:

  <v052>
  This routine has been introduced with v.0.52.
  Since the DPS transactions are paired, this routine actually
  sends two requests to the server: the first request is used
  to establish a communication and receive the security challenge; the
  second request is a JM_LISTJOBS request (modeled after the
  $modelRequest received by the routine, but including the appropriate
  security challenge response).
  </v052>

=cut

#	ReplayProcStatusTransaction
#^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
sub ReplayProcStatusTransaction
{
  if($DBG >= DBG_MED)	{ LogFunctionEntry("ReplayProcStatusTransaction"); }
  
  my $modelRequest = $_[0];
  my $theUserAgent = "TrnsPort TestSuite - HTTPplay ".VERSION;
  
  my $firstRequestMethod = "POST";
  my $firstRequestURI = $modelRequest->uri();
  my $firstRequestHeadersObj = HTTP::Headers->new;
  $firstRequestHeadersObj->header("User-Agent" => $theUserAgent);
  $firstRequestHeadersObj->header("Host" => $SERVER_HOST);
  $firstRequestHeadersObj->header("Content-Length" => 0);
  my $firstRequestContent = "";
  
  my $firstRequest = HTTP::Request->new($firstRequestMethod, $firstRequestURI, $firstRequestHeadersObj, $firstRequestContent);
  
  $agent = LWP::UserAgent->new(keep_alive=>2);
  $agent->timeout($TIMEOUT);
  
  my $firstResponse = $agent->send_request($firstRequest);
  
  $lastDPSchallenge = ExtractDPSChallenge($firstResponse->header("WWW-Authenticate"));

  my $secondRequest = DeepCopyOf($modelRequest, HTTP_MSG_ORIGINAL_REQUEST);
  
  $secondRequest->header('Host' => $SERVER_HOST);
  $secondRequest->header('User-Agent' => $theUserAgent);
  
  my $challengeReply = DPSchallengeReply();
  my $newHeader = "Basic ".$challengeReply;
  $secondRequest->header("Authorization" => $newHeader);
  
  my $newResponse = $agent->send_request($secondRequest);
  
  if($DBG >= DBG_MED)	{ LogFunctionExit("ReplayProcStatusTransaction"); }
  return $newResponse
}
#	End ReplayProcStatusTransaction
#^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^

=pod

=head1 GetStatusIndex Procedure

=head2 Description:

  A procedure to obtain the index in the job-status-pairs table
  corresponding to a given job status.

=head2 Input:

=over 4

=item 1

  $status	The job status in analysis, as obtained from the
			content of a JM_LISTJOBS response.

=back

=head2 Returns:

  $result	The index in the job-status-pairs table associated with
			the $status status.

=head2 Notes:

  <v052>
  This routine has been introduced with v.0.52.
  The job-status-pairs table is a 4x4 square matrix.
  Hence, the routine returns indices in the range [0..3].
  Here's a summary of how the incoming statuses are associated with
  the indices in the table:
  String in the JM_LISTJOBS status field:	Type:		Index:
  ==================================================================
  Process Deferred							Pending		0
  Process Scheduled								"		0
  Process Pending								"		0
  Process Running							Running		1
  Application Error							Failed		2
  Stop Encountered								"		2
  REXX Error									"		2
  Hard Error									"		2
  Trap Error									"		2
  SigTerm Error									"		2
  Timed Out										"		2
  Aborted by User								"		2
  Shutdown Aborted								"		2
  Unknown Error									"		2
  Cannot Run Job								"		2
  SAS Warning									"		2
  SAS Error										"		2
  SAS Fatal Error								"		2
  Unknown Error #2								"		2
  Completed									Success		3
  
  Note that any string not matching any of those listed in this table
  will be dimmed as a Failed (i.e. with index 0) status.
  </v052>

=cut

#	GetStatusIndex
#^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
sub GetStatusIndex
{
  if($DBG >= DBG_MED)	{ LogFunctionEntry("GetStatusIndex"); }
  
  my $status = $_[0];
  
  if($DBG >= DBG_MED)
  {
	print LOG Indent($logIndent);
	print LOG "The status: $status\n";
  }
  
  
  my $type = -1;
  if	($status eq DPS_JOBSTATUS_DEFERRED)		{ $type=DPS_JOBSTATUS_CODE_PENDING; }
  elsif	($status eq DPS_JOBSTATUS_SCHEDULED)	{ $type=DPS_JOBSTATUS_CODE_PENDING; }
  elsif	($status eq DPS_JOBSTATUS_PENDING)		{ $type=DPS_JOBSTATUS_CODE_PENDING; }
  elsif	($status eq DPS_JOBSTATUS_RUNNING)		{ $type=DPS_JOBSTATUS_CODE_RUNNING; }
  elsif	($status eq DPS_JOBSTATUS_COMPLETED)	{ $type=DPS_JOBSTATUS_CODE_SUCCESS; }
  
  # All the other are failures:
  # Note that an unrecognized job status will be considered
  # a failure.
  else	{ $type=DPS_JOBSTATUS_CODE_FAILED; }
  
  #Based on the type, return the appropriate index:
  # Pending	=> 0
  # Running	=> 1
  # Failed	=> 2
  # Success	=> 3
  
  my $result = -1;
  if($type == DPS_JOBSTATUS_CODE_PENDING)		{ $result = 0; }
  if($type == DPS_JOBSTATUS_CODE_RUNNING)		{ $result = 1; }
  if($type == DPS_JOBSTATUS_CODE_FAILED)		{ $result = 2; }
  if($type == DPS_JOBSTATUS_CODE_SUCCESS)		{ $result = 3; }

  if($DBG >= DBG_MED)
  {
	print LOG Indent($logIndent);
	print LOG "GetStatusIndex recognized that status as a ".JobStatusName($type)." (index: $result)\n";
	LogFunctionExit("GetStatusIndex");
  }
  return $result;
}
#	End GetStatusIndex
#^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^

=pod

=head1 MatchingHeaders Procedure

=head2 Description:

  A procedure to verify whether the headers included in the HTTP
  messages of two transactions match.

=head2 Input:

=over 4

=item 1

  $originalRequest	The HTTP::Request of the first transaction;

=item 2

  $originalResponse	The HTTP::Response of the first transaction;

=item 3

  $playbackrequest	The HTTP::Request of the second transaction;

=item 4

  $playbackResponse	The HTTP::Response of the second transaction.

=back

=head2 Returns:

  1		(i.e. True) If the headers in the two transactions match;
  0		(i.e. False) Otherwise.
  
=head2 Notes:

  In all cases the headers of the two responses are ordered
  and compared (the routine relies upon ScanHeaders to store the
  headers of the $originalResponse in the file-scopes %headers hash
  and upon the ScanLogHeaders routine to store the headers of the
  $playbackResponse in the file-scoped %logHeaders hash).
  The headers are compared by name (since no header appears to
  contain any data that may indicate an unexpected difference, see
  below the one exception, and further comments inlined in the code),
  and 0 is returned if the number of the headers in the two responses
  is different, or if some header in one of the two does not appear
  in the other.
  One exception is implemented: the case for a transaction of type
  TRANSACTION_OBS_OBSTORE_GET (the routine checks the value of the
  file-scoped $transactionType variable to verify whether the
  two transactions received as parameters represent POSTs to the
  Obstore script, an ObjectStore transaction).
  In that case, in fact, one of the headers (named
  "Content-Disposition") also includes a 'variable' el;ement: the
  Filename. Thus, for that type of transaction, this routine implements
  further checks on that specific header.

=cut

#	MatchingHeaders:
#^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
sub MatchingHeaders
{
  if($DBG >= DBG_MED)	{ LogFunctionEntry("MatchingHeaders"); }
  
  my ($originalRequest, $originalResponse, $playbackRequest, $playbackResponse) = @_;
  
  #Store the $originalResponse headers in %headers;
  #Store the $playbackResponse headers in %logHeaders.
  %headers = ();
  %logHeaders = ();
  $originalResponse->scan(\&ScanHeaders);
  $playbackResponse->scan(\&ScanLogHeaders);
  
  my $headersS 		= keys %headers;
  my $logHeadersS	= keys %logHeaders;
  
  if($DBG >= DBG_HIGH)
  {
	print LOG Indent($logIndent);
	print LOG "Headers in the Original Response: ($headersS)\n";
	foreach (sort keys %headers)
	{
	  print LOG Indent($logIndent);
	  print LOG "  $_ => $headers{$_}\n";
	}#FOREACH
	print LOG Indent($logIndent);
	print LOG "Headers in the Playback Response: ($logHeadersS)\n";
	foreach (sort keys %logHeaders)
	{
	  print LOG Indent($logIndent);
	  print LOG "  $_ => $logHeaders{$_}\n";
	}#FOREACH
  }
  
  my $matched = 0;				#Counter of how many headers from the %headers
								#hash are matched in the %logHeaders one
  
  foreach (sort keys %headers)
  {
	if(!exists($logHeaders{$_}))
	{
	  $resultErrInfo = "The Original Response included the header $_ => $headers{$_}\n";
	  $resultErrInfo.= "while the Playback Response did not include a header by that name.\n";
	  if($DBG >= DBG_MED)
	  {
		print LOG Indent($logIndent);
		print LOG "MatchingHeaders will return 0 (i.e. false), and has set the resultErrInfo variable as follows:\n";
		print LOG $resultErrInfo;
		LogFunctionExit("MatchingHeaders");
	  }
	  return 0;
	}
	$matched++;
  }#FOREACH
  
  if($logHeadersS != $matched)
  {
	$resultErrInfo = "The following headers were included in the Playback Response, but\n";
	$resultErrInfo.= "not in the Original Response:\n";
	foreach (sort keys %logHeaders)
	{
	  if(!exists($headers{$_}))
	  { $resultErrInfo.="$_ => $logHeaders{$_}\n"; }
	}#FOREACH
	if($DBG >= DBG_MED)
	{
	  print LOG Indent($logIndent);
	  print LOG "MatchingHeaders will return 0 (i.e. false), and has set the resultErrInfo variable as follows:\n";
	  print LOG $resultErrInfo;
	  LogFunctionExit("MatchingHeaders");
	}
	return 0;
  }

# The following block of code is commented out because it appears
# that none of the headers' values should be considered as showstoppers.
# Here's a list of the headers considered so far:
#
# Accept-Range		(type of data in the message)
# Client-Date		(date on the client machine)
# Client-Peer		(Ip-Address [+port] of the client)
# Connection		(close or keep alive)
# Content-Length	(length of response's content)
# Content-Type		(type of content)
# Date				(Date on the server that sent the response)
# ETag				(? seems a GUID)
# Last-Modified		(Date when the returned file was last modified)
# Server			(Web-server running on the server)
#
# The values of these headers may very well be different from the baseline to
# test runs (i.e. from the original and the playback responses), but this
# does not seem to indicate an error.
#
#	else
#	{
#	  if( $headers{$_} ne $logHeaders{$_} )
#	  {
#		$resultErrInfo = "The Responses differ in the value of the header $_:\n";
#		$resultErrInfo.= "Original Response: $_ => $headers{$_}\n";
#		$resultErrInfo.= "Playback Response: $_ => $logHeaders{$_}\n";
#		if($DBG >= DBG_HIGH)
#		{
#		  print LOG Indent($logIndent);
#		  print LOG "MatchingHeaders will return 0 (i.e. false), and has set the resultErrInfo variable as follows:\n";
#		  print LOG $resultErrInfo;
#		  LogFunctionExit("MatchingHeaders");
#		}
#		return 0;
#	  }
#	}
#
# Note the peculiar case of the Content-Disposition header, in the context
# of an Object Store OBSTORE GET response:
# In this case, the header also contains the filename, and this filename
# should match the one appended to the URI of the matching request.
# At this point, the Content-Disposition Header is checked against the
# matching header in the original response:

  if($transactionType == TRANSACTION_OBS_OBSTORE_GET)
  {
	#In the case of an Obstore GET we need to check that the filenames
	#in the Content-Disposition match: that's why we need the two requests in this
	#routine (to see if the filenames appeared in the requests' URIs)
	if($DBG >= DBG_HIGH)
	{
	  print LOG Indent($logIndent);
	  print LOG "Since the Transaction is of ".TransactionTypeName($transactionType).",\n";
	  print LOG Indent($logIndent);
	  print LOG "the Content-Disposition headers' content will be checked as well.\n";
	}
	
	if(exists($headers{"Content-Disposition"}))
	{
	  #Since the headers' number and names matched so far, at this point
	  #we know that the same headers exists for the playback response
	  #as well.
	  
	  my $originalRequestFilename = ExtractFilenameFromRequest($originalRequest, TRANSACTION_OBS_OBSTORE_GET);
	  my $playbackRequestFilename = ExtractFilenameFromRequest($playbackRequest, TRANSACTION_OBS_OBSTORE_GET);
	  my $originalResponseFilename= ExtractFilenameFromResponse($originalResponse, TRANSACTION_OBS_OBSTORE_GET);
	  my $playbackResponseFilename= ExtractFilenameFromResponse($playbackResponse, TRANSACTION_OBS_OBSTORE_GET);
	  
	  #--- Comparison Block #1:
	  if($originalRequestFilename)
	  {
		if(!$playbackRequestFilename)
		{
		  $resultErrInfo = "The original Request included the filename $originalRequestFilename\n";
		  $resultErrInfo.= "while the playback Request did not include any filename.\n";
		  if($DBG >= DBG_MED)
		  {
			print LOG Indent($logIndent);
			print LOG "MatchingHeaders will return 0 (i.e. false), and has set the resultErrInfo variable as follows:\n";
			print LOG $resultErrInfo;
			LogFunctionExit("MatchingHeaders");
		  }
		  return 0;
		}
		elsif(		exists($filenameMap{$originalRequestFilename})
			  &&	$filenameMapSet{$originalRequestFilename}
			  &&	($filenameMap{$originalRequestFilename} ne $playbackRequestFilename)
			 )
		{
		  $resultErrInfo = "The original Request included the filename $originalRequestFilename\n";
		  $resultErrInfo.= "while the playback Request included the filename $playbackRequestFilename.\n";
		  $resultErrInfo.= "The filename in the original Request, however, was already mapped to\n";
		  $resultErrInfo.= "the filename ".$filenameMap{$originalRequestFilename}.".\n";
		  if($DBG >= DBG_MED)
		  {
			print LOG Indent($logIndent);
			print LOG "MatchingHeaders will return 0 (i.e. false), and has set the resultErrInfo variable as follows:\n";
			print LOG $resultErrInfo;
			LogFunctionExit("MatchingHeaders");
		  }
		  return 0;
		}
		if($DBG >= DBG_HIGH)
		{
			print LOG Indent($logIndent);
			print LOG "The original Request included the filename $originalRequestFilename;\n";
			print LOG Indent($logIndent);
			print LOG "the playback Request included the filename $playbackRequestFilename.\n";
			print LOG Indent($logIndent);
			print LOG "A new filename mapping will be created: $originalRequestFilename => $playbackRequestFilename.\n";
		}
		$filenameMap{$originalRequestFilename} = $playbackRequestFilename;
		$filenameMapSet{$originalRequestFilename} = 1;
	  }
	  #--- End Comparison Block #1
	  
	  #--- Comparison Block #2:
	  if($originalResponseFilename)
	  {
		if(!$playbackResponseFilename)
		{
		  $resultErrInfo = "The original Response included the filename $originalResponseFilename\n";
		  $resultErrInfo.= "while the playback Response did not include any filename.\n";
		  if($DBG >= DBG_MED)
		  {
			print LOG Indent($logIndent);
			print LOG "MatchingHeaders will return 0 (i.e. false), and has set the resultErrInfo variable as follows:\n";
			print LOG $resultErrInfo;
			LogFunctionExit("MatchingHeaders");
		  }
		  return 0;
		}
		elsif(		exists($filenameMap{$originalResponseFilename})
			  &&	$filenameMapSet{$originalResponseFilename}
			  &&	($filenameMap{$originalResponseFilename} ne $playbackResponseFilename)
			 )
		{
		  $resultErrInfo = "The original Response included the filename $originalResponseFilename\n";
		  $resultErrInfo.= "while the playback Response included the filename $playbackResponseFilename.\n";
		  $resultErrInfo.= "The filename in the original Response, however, was already mapped to\n";
		  $resultErrInfo.= "the filename ".$filenameMap{$originalResponseFilename}.".\n";
		  if($DBG >= DBG_MED)
		  {
			print LOG Indent($logIndent);
			print LOG "MatchingHeaders will return 0 (i.e. false), and has set the resultErrInfo variable as follows:\n";
			print LOG $resultErrInfo;
			LogFunctionExit("MatchingHeaders");
		  }
		  return 0;
		}
		if($DBG >= DBG_HIGH)
		{
		  print LOG Indent($logIndent);
		  print LOG "The original Response included the filename $originalResponseFilename;\n";
		  print LOG Indent($logIndent);
		  print LOG "the playback Response included the filename $playbackResponseFilename.\n";
		  print LOG Indent($logIndent);
		  print LOG "A new filename mapping will be created: $originalResponseFilename => $playbackResponseFilename.\n";
		}
		$filenameMap{$originalResponseFilename} = $playbackResponseFilename;
		$filenameMapSet{$originalResponseFilename} = 1;
	  }
	  #--- End Comparison Block #2
	  
	  #--- Comparison Block #3:
	  if(	$originalRequestFilename
		 &&	$originalResponseFilename
		 &&	($originalRequestFilename eq $originalResponseFilename)
		 &&	(	(!$playbackRequestFilename)
			 ||	(!$playbackResponseFilename)
			 ||	($playbackRequestFilename ne $playbackResponseFilename)
			)
		)
	  {
		$resultErrInfo = "The original Transaction included the same filename $originalRequestFilename\n";
		$resultErrInfo.= "in both the Request and Response.\n";
		$resultErrInfo.= "The playback Transaction did not match this requirement:\n";
		$resultErrInfo.= "The filename in the playback Request:  $playbackRequestFilename\n";
		$resultErrInfo.= "The filename in the playback Response: $playbackResponseFilename\n";
		if($DBG >= DBG_MED)
		{
		  print LOG Indent($logIndent);
		  print LOG "MatchingHeaders will return 0 (i.e. false), and has set the resultErrInfo variable as follows:\n";
		  print LOG $resultErrInfo;
		  LogFunctionExit("MatchingHeaders");
		}
		return 0;
	  }
	  #--- End Comparison Block #3
	}
	else
	{
	  if($DBG >= DBG_HIGH)
	  {
		print LOG Indent($logIndent);
		print LOG "The Content-Disposition Header did not appear in the Original Response.\n";
		print LOG Indent($logIndent);
		print LOG "No Comparison performed.\n";
	  }
	}
  }

  if($DBG >= DBG_MED)
  {
		print LOG Indent($logIndent);
		print LOG "MatchingHeaders will return 1 (i.e. true) since the headers match.\n";
		LogFunctionExit("MatchingHeaders");
  }
  return 1;
}
#	End MatchingHeaders
#^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^

=pod

=head1 NextToken Procedure

=head2 Description:

  A procedure to produce the next token from a given HTTP Message's
  content.

=head2 Input:

=over 4

=item 1

  $src	The source from which the next token should be extracted.

=back

=head2 Returns:

  @tmpArray	An array composed of two elements: in order
			$tmpArray[0]	The next token extracted from $src;
			$tmpArray[1]	The tail, or the remaining part of $src
							once the next token has been extracted.
  
=head2 Notes:

  The extraction of the Next token is based upon the expected format
  of the various HTTP::Responses that the HTTP Playback deals with.
  The routine checks the value of the file-scoped $transactionType
  variable to determine which type of transaction is being handled.
  The $src parameter is assumed to be the content (or part of the
  content) of the HTTP::Response of a transaction of the type
  indicated by $transactionType.
  The $src parameter is checked to verify whether it contains certain
  recognizable substrings. The presence of these substrings, in
  conjunction with the type of transaction, indicates which token
  should be extracted next by the routine.
  See further comments inlined in the code for Very Simple BNFs
  of each type of HTTP::Response content.
  <v052>
  For DPS transactions, the routine simply returns the whole $src
  as the next token.
  </v052>

=cut

#	NextToken:
#^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
sub NextToken
{
  if($DBG >= DBG_MED)	{ LogFunctionEntry("NextToken"); }
  
  my $src = $_[0];
  my $res = "";
  my $tail= "";

  if($src) #If no src was sent, let $res be empty.
  {
	if($recordingServerType == SERVER_DPS)
	{
	  $res = $src;
	  $tail = "";
	}
	else
	{
	  if	(	$transactionType == TRANSACTION_OBS_WSDL	)
	  {
		# For a TRANSACTION_OBS_WSDL:
		# <content>	->	<stuff> "<soap:address location='" <URL> "'/>" <stuff>	
	  	if 	($src =~ /\Q<soap:address location=\E/)
		{
		  $res = $`;
		  $res.="<soap:address location='";
		  $tail = $';
		}
		else
		{
		  #Skip the actual location:
		  $src =~ m/(\/>)/;
		  $res = "/>";
		  $res.= $';
		  $tail = "";
		}
	  }
	  elsif	(	$transactionType == TRANSACTION_OBS_WSML
		  ||	$transactionType == TRANSACTION_OBS_RETRIEVE_SUPPORTED_CLASSIFICATIONS
		  ||	$transactionType == TRANSACTION_OBS_EXECUTE_SEARCH
		  ||	$transactionType == TRANSACTION_OBS_ADD_OBJECT
		  ||	$transactionType == TRANSACTION_OBS_UPLOAD_OBJECT_DATA
		  ||	$transactionType == TRANSACTION_OBS_REMOVE_OBJECT
		  ||	$transactionType == TRANSACTION_OBS_UPDATE_OBJECT )
	  {
		# For these transactions:
		# <content>	-> <stuff>
		$res = $src;
		$tail = "";
	  }
	  elsif (	$transactionType == TRANSACTION_OBS_GET_LAST_UPDATE_TIME	)
	  {
		# For a TRANSACTION_OBS_GET_LAST_UPDATE_TIME:
		# <content>	->	<stuff> "<dEnvLastUpdated>" <EnvLastUpdated> "</dEnvLastUpdated>"
		#				<stuff> "<dObjLastUpdated>" <ObjLastUpdated> "</dObjLastUpdated>"
		#				<stuff>
		# (Note: the Env one comes always before the Obj one)
		if($src =~ /\Q<dEnvLastUpdated>\E/)
		{
		  $res = $`;
		  $res.="<dEnvLastUpdated>";
		  $tail = $';
		}
		elsif($src =~ /\Q<dObjLastUpdated>\E/)
		{
		  # Skip the dEnvLastUpdated element:
		  my ($pre, $post) = split(/\Q<\/dEnvLastUpdated>\E/, $src);
		  $post =~ m/\Q<dObjLastUpdated>\E/;
		  $res = "</dEnvLastUpdated>";
		  $res.= $`;
		  $res.= "</dObjLastUpdated>";
		  $tail = $';
		}
		else
		{
		  $src =~ m/\Q<\/dObjLastUpdated>\E/;
		  $res = "</dObjLastUpdated>";
		  $res.=$';
		  $tail = "";
		}
	  }
	  elsif	(	$transactionType == TRANSACTION_OBS_OBSTORE_POST	)
	  {
		# For a TRANSACTION_OBS_OBSTORE_POST:
		# <content>	-> <stuff> "OK: file=" <filename> ";" <stuff>
		if($src =~ /\QOK: file=\E/)
		{
		  $res = $`;
		  $res.="OK: file=";
		  $tail = $';
		}
		else
		{
		  #Skip the actual filename:
		  $src =~ m/;/;
		  $res = ";";
		  $res.=$';
		  $tail = "";
		}
	  }
	  elsif	(	$transactionType == TRANSACTION_OBS_GET_OBJECT	)
	  {
		# For a TRANSACTION_OBS_GET_OBJECT:
		# <content>	->	<stuff> "<lpObject>" <lpObject> "</lpObject>"
		#				<stuff> "<bstrSerializedObject>" <SerializedObject> "</bstrSerializedObject>"
		#				<stuff>
		# (Note: the lpObject comes always before the SerializedObject)
		if($src =~ /\Q<lpObject>\E/)
		{
		  $res = $`;
		  $res.="<lpObject>";
		  $tail = $';
		}
		elsif($src =~ /\Q<bstrSerializedObject>\E/)
		{
		  # Skip the dEnvLastUpdated element:
		  my ($pre, $post) = split(/\Q<\/lpObject>\E/, $src);
		  $post =~ m/\Q<bstrSerializedObject>\E/;
		  $res = "</lpObject>";
		  $res.= $`;
		  $res.= "</bstrSerializedObject>";
		  $tail = $';
		}
		else
		{
		  $src =~ m/\Q<\/bstrSerializedObject>\E/;
		  $res = "</bstrSerializedObject>";
		  $res.=$';
		  $tail = "";
		}
	  }
	  elsif	(	$transactionType == TRANSACTION_OBS_DOWNLOAD_OBJECT_DATA	)
	  {
		# For a TRANSACTION_OBS_DOWNLOAD_OBJECT:
		# <content>	->	<stuff> "<bstrFileName>" <filename> "</bstrFileName>" <stuff>
		if($src =~ /\Q<bstrFileName>\E/)
		{
		  $res = $`;
		  $res.="<bstrFileName>";
		  $tail = $';
		}
		else
		{
		  $src =~ m/\Q<\/bstrFileName>\E/;
		  $res = "</bstrFileName>";
		  $res.= $';
		  $tail = "";
		}
	  }
	  elsif	(	$transactionType == TRANSACTION_OBS_OBSTORE_GET	)
	  {
		# For a TRANSACTION_OBS_OBSTORE_GET:
		# <ContentDispositionHeader>	->	<stuff> "FileName=" <filename>
		if($src =~ /FileName=/)
		{
		  $res = $`;
		  $res.="FileName=";
		  $tail = $';
		}
		else
		{
		  $res = $src;
		  $tail = "";
		}
	  }
	} #Closes if($recordingServerType==SERVER_DPS)-else
  } #Closes the if($src)
  
  if($DBG >= DBG_MED)	{ LogFunctionExit("NextToken"); }
  my @tmpArray;
  push(@tmpArray, $res, $tail);
  return @tmpArray;
}
#	End nextToken
#^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^

=pod

=head1 MatchDPSContents Procedure

=head2 Description:

  A procedure to compare the content of two DPS HTTP::Responses.

=head2 Input:

=over 4

=item 1

  $originalResponse	The first HTTP::Response to be compared.

=item 2

  $playbackResponse	The second HTTP::Response to be compared.

=item 3

  $playbackRequest	The HTTP::Request that prompted the
					$playbackResponse

=back

=head2 Returns:

  $res	Equal to 0 (i.e. false) if any unexpected diffference
		was detected; equal to 1 (i.e. true) otherwise.

=head2 Notes:

  <v052>
  This routine has been introduced with v.0.52.
  The routine performs different verififcations depending on the
  type of transaction that the two responses belong to (as indicated
  by the file-scoped $transactionType variable):
  ~ TRANSACTION_DPS_GETINFO:
	The two responses always match;
	
  ~ TRANSACTION_DPS_PING,
	TRANSACTION_DPS_COPY,
	TRANSACTION_DPS_DELETEFILE,
	TRANSACTION_DPS_DELETEJOB,
	TRANSACTION_DPS_TRANSFER,
	TRANSACTION_DPS_CHANGESCHEDULE,
	TRANSACTION_DPS_MOVEFILE:
	The two response match if and only if their contents are identical;
	
  ~ TRANSACTION_DPS_SUBMIT:
	The two responses match if and only if their contents are identical
	or differ ONLY in the JobID they include; note that, if two
	different job IDs are found, a new job Id mapping is created
	between the two (see the file-scoped %jobIdMap hash);
	
  ~ TRANSACTION_DPS_LISTFILES,
	TRANSACTION_DPS_SERVERFILES:
	The routinerelies upon the CompareFileLists routine to determine
	if the two responses match or not;
	
  ~ TRANSACTION_DPS_LISTJOBS:
	The routine relies upon the CompareJobLists routine to determine
	if the two responses match.
  If the two responses do not match, the routine also sets the
  file-scoped $resultErrInfo variable to contain a description of
  the unexpected difference detected.
  </v052>

=cut

#	MatchDPSContents
#^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
sub MatchDPSContents
{
  if($DBG >= DBG_MED)	{ LogFunctionEntry("MatchDPSContents"); }
  
  my ($originalResponse, $playbackResponse, $playbackRequest) = @_;
  my $originalContent = $originalResponse->content;
  my $playbackContent = $playbackResponse->content;
  
  my $res = 1;

  if(		$transactionType == TRANSACTION_DPS_GETINFO)
  {
	$res = 1;
  }
  elsif(	$transactionType == TRANSACTION_DPS_PING
	  ||	$transactionType == TRANSACTION_DPS_COPY
	  ||	$transactionType == TRANSACTION_DPS_DELETEFILE
	  ||	$transactionType == TRANSACTION_DPS_DELETEJOB
	  ||	$transactionType == TRANSACTION_DPS_TRANSFER
	  ||	$transactionType == TRANSACTION_DPS_CHANGESCHEDULE
	  ||	$transactionType == TRANSACTION_DPS_MOVEFILE	)
  {
	$res = ($originalContent eq $playbackContent);
  }
  elsif(	$transactionType == TRANSACTION_DPS_SUBMIT	)
  {
	#Check the job ID returned (a s acomparison block #2):
	  #--- Comparison Block #2:
	  if($originalContent)
	  {
		if(!$playbackContent)
		{
		  $resultErrInfo = "The original Response included the jobID $originalContent\n";
		  $resultErrInfo.= "while the playback Response did not include any jobID.\n";
		  if($DBG >= DBG_MED)
		  {
			print LOG Indent($logIndent);
			print LOG "MatchDPSContents will return 0 (i.e. false), and has set the resultErrInfo variable as follows:\n";
			print LOG $resultErrInfo;
			LogFunctionExit("MatchDPSContents");
		  }
		  return 0;
		}
		elsif(		exists($jobIdMap{$originalContent})
			  &&	$jobIdMapSet{$originalContent}
			)
		{
		  if( $jobIdMap{$originalContent} ne $playbackContent)
		  {
			$resultErrInfo = "The original Response included the jobID $originalContent\n";
			$resultErrInfo.= "while the playback Response included the jobID $playbackContent.\n";
			$resultErrInfo.= "The jobID in the original Response, however, was already mapped to\n";
			$resultErrInfo.= "the jobID ".$jobIdMap{$originalContent}.".\n";
			if($DBG >= DBG_MED)
			{
			  print LOG Indent($logIndent);
			  print LOG "MatchDPSContents will return 0 (i.e. false), and has set the resultErrInfo variable as follows:\n";
			  print LOG $resultErrInfo;
			  LogFunctionExit("MatchDPSContents");
			}
			return 0;
		  }
		  else
		  {
			if($DBG >= DBG_HIGH)
			{
			  print LOG Indent($logIndent);
			  print LOG "The jobID found in the original and playback Responses respected the previously\n";
			  print LOG Indent($logIndent);
			  print LOG "set mapping; no substitution necessary.\n";
			}
		  }
		}
		elsif(		(!exists($jobIdMap{$originalContent}))
			  ||	(!$jobIdMapSet{$originalContent}) )
		{
		  if($DBG >= DBG_HIGH)
		  {
			print LOG Indent($logIndent);
			print LOG "The original Response included the jobID $originalContent;\n";
			print LOG Indent($logIndent);
			print LOG "the playback Response included the jobID $playbackContent.\n";
			print LOG Indent($logIndent);
			print LOG "A new jobID mapping will be created: $originalContent => $playbackContent.\n";
		  }
		  $jobIdMap{$originalContent} = $playbackContent;
		  $jobIdMapSet{$originalContent} = 1;
		}
	  }
	  #--- End Comparison Block #2
  }
  elsif(	$transactionType == TRANSACTION_DPS_LISTFILES
		||	$transactionType == TRANSACTION_DPS_SERVERFILES	)
  {
	$res = CompareFileLists($originalContent, $playbackContent);
  }
  elsif(	$transactionType == TRANSACTION_DPS_LISTJOBS	)
  {
	$res = CompareJobLists($originalContent, $playbackContent, $playbackRequest);
  }

  if($DBG >= DBG_MED)	{ LogFunctionExit("MatchDPSContents"); }
  return $res;
}
#	End MatchDPSContents
#^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^

=pod

=head1 MatchingContents Procedure

=head2 Description:

  A procedure to verify if the contents of the HTTP::Requests
  and HTTP::Responses of two transactions match.

=head2 Input:

=over 4

=item 1

  $originalRequest	The HTTP::Request of the first transaction;

=item 2

  $originalResponse	The HTTP::Response of the first transaction;

=item 3

  $playbackrequest	The HTTP::Request of the second transaction;

=item 4

  $playbackResponse	The HTTP::Response of the second transaction.

=back

=head2 Returns:

  1		If the contents of the two transactions match;
  0		Otherwise.
  
=head2 Notes:

  The routine relies upon the ValidMappings routine to verify that the
  'variable' elements in the two transactions respect any pre-existing
  mapping. If the mappings are respected, then the routine analyzes
  the contents of the two HTTP::Responses to verify that they match.
  This contents' comparison relies upon the NextToken routine
  to produce, for each of the two contents, the next token (which
  never includes any of the 'variable' elements).
  <v052>
  During a playback of a DPS recording, the routine relies upon the
  ValidMappings routine to verify the mapping of any 'variable' element,
  and then on the MatchDPSContents routine to verify that the content
  of the two responses match each other.
  </v052>

=cut

#	MatchingContents:
#^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
sub MatchingContents
{
  if($DBG >= DBG_MED)	{ LogFunctionEntry("MatchingContents"); }
  
  my ($originalRequest, $originalResponse, $playbackRequest, $playbackResponse) = @_;
  
  my $res = 1;
  
  if(!ValidMappings($originalRequest, $originalResponse, $playbackRequest, $playbackResponse))
  {
	if($DBG >= DBG_HIGH)
    {
	  print LOG ($logIndent);
	  print LOG "ValidMappings returned false: MatchingContents will set the result to be returned to 0 (i.e. false).\n";
    }
    $res = 0;
  }
  elsif($recordingServerType==SERVER_DPS)
  {
	if($DBG >= DBG_MED)
	{
	  print LOG Indent($logIndent);
	  print LOG "ValidMappings returned true. This is a DPS transaction, MatchingContents will rely\n";
	  print LOG Indent($logIndent);
	  print LOG "upon MatchDPSContents to verify the two transactions.\n";
	}
	$res = MatchDPSContents($originalResponse, $playbackResponse, $playbackRequest);
  }
  else
  {
	if($DBG >= DBG_HIGH)
	{
	  print LOG Indent($logIndent);
	  print LOG "ValidMappings returned true. MatchingContents will perform a token-by-token\n";
	  print LOG Indent($logIndent);
	  print LOG "Comparison, skipping the 'variable' tokens.\n";
	}
	
	my $originalResponseContent = $originalResponse->content();
	my $playbackResponseContent = $playbackResponse->content();
	my $originalToken = "";
	my $playbackToken = "";
	
	($originalToken, $originalResponseContent) = NextToken($originalResponseContent);
	while($originalToken)
	{
	  ($playbackToken, $playbackResponseContent) = NextToken($playbackResponseContent);
	  
	  if($originalToken ne $playbackToken)
	  {
		$resultErrInfo = "Difference in Content Detected:\n";
		$resultErrInfo.= "The variable elements (Filenames, GUIDs, Queries, Serialized Objects, Timestamps) have already\n";
		$resultErrInfo.= "been checked and match as required.\n";
		$resultErrInfo.= "However, a difference was detected in the following section:\n";
		$resultErrInfo.= "~ from the Original Response:\n$originalToken\n";
		$resultErrInfo.= "~ from the Playback response:\n$playbackToken\n";
		$res = 0;
		last;
	  }
	  
	  ($originalToken, $originalResponseContent) = NextToken($originalResponseContent);
	}#WEND
  }
  
  if($DBG >= DBG_HIGH)
  {
	print LOG Indent($logIndent);
	print LOG "Matching Contents will return $res.\n";
  }
  if($DBG >= DBG_MED)	{ LogFunctionExit("MatchingContents"); }
  return $res;
}
#	End MatchingContents
#^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^

=pod

=head1 Init Procedure

=head2 Description:

  A procedure to initialize the HTTP Playback tool.

=head2 Input:

=over 4

=item 1

  @argv	The array of command-line parameters received by the tool.

=back

=head2 Returns:

  1		If the initialization process was succesfully completed;
  0		Otherwise (see Notes).
  
=head2 Notes:

  Any erroneous condition detected during the initialization process
  is dimmed as a showstopper. The issue is reported via the
  ReportError routine, which also ensures that the Playback tool
  is stopped.
  <v051>
  Since the introduction of the DPS playback, the file-scoped $agent
  LWP::UserAgent is instanciated as needed by the Main routine.
  Thus, the Init routine cannot set the $agent's timeout attribute
  any more. The Init routine, however, still sets the file-scoped
  $TIMEOUT variable so that the Main routine will be able to
  set that attribute as needed.
  </v051>
  <v052>
  The Init routine has been modified to accept the new CLIENT_IP
  configuration parameter.
  </v052>
  <v053>
  See inline comments for code changes applied. The tool now
  figures out the full path t the configuration file.
  Also, since the input file parameter should now represent the
  whole path to the input file, the routine does not prepend it
  with the current working directory anymore. This changed only the
  code immediatly preceeding the call to the XML::Simple XMLin
  method.
  </v053>

=cut

#	Init:
#^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
sub Init
{
  my @argv = @_;
  my $args = @argv;

  #Look in the command line for the "working directory" parameter:
  #Do this first so that we create the log file where it should
  #go. If no "-wd=" parameter is found, the default value for the
  #output directory is the constant DEF_STORAGE_DIR, and the log file
  #will be created there.
  foreach my $s (@argv)
  {
	my ($s1, $s2) = split(/=/, $s);
	if( ($s1 eq "-wd") && ($s2 ne "") )
	{ $outputDir = $s2; }
  }
  
  my $fullLogFilename = $outputDir."\\".LOG_FILENAME;
  
  #Check if the directory is there, and if not, attempt
  #to create it:
  if (! (-d $outputDir) )
  {
    mkdir $outputDir, 777;
    if(! (-d $outputDir))
    {
  	$errCode = ERR_STORAGE;
  	$errMsg = "Failed to Create Storage Area Named $outputDir";
  	ReportError("Init");
    }
  }

  #Attempt to open the LOG file:
  if(!(open(LOG, "> $fullLogFilename")))
  {
	$errCode = ERR_LOGFILE;
	$errMsg = "Log File Name: $fullLogFilename";
	ReportError("Init");
  }
  #Set the LOG handle to be flushed after every output statement:
  my $old_out = select(LOG);
  $| = 1;
  select ($old_out);
  
  #<v053>
  # Get the full path+name for the configuration file:
  #This is equal to the current working directory + CFG_FILENAME:
  my $fullCfgFilename =$Bin."\\".CFG_FILENAME;
  
  #Attempt to open the configuration file:
  if(!(open(CFG, $fullCfgFilename)))
  {
	$errCode = ERR_CFGFILE;
	$errMsg = "Configuration File Name: $fullCfgFilename";
	ReportError("Init");
  }
  #</v053>
  
  #Read the parameters in the configuration file:
  my %cfgParameters = ();
  while(<CFG>)
  {
	chomp;				# chomp \n
	s/#.*//;			# Skip Perl-style comment lines
	s/^\s+//;			# Trim leading spaces
	s/\s+$//;			# Trim trailing spaces
	
	next unless length;	# If there is anything left:
						# Split on the '=' (and any surrounding
						# white space):
	my ($parName, $parVal) = split(/\s*=\s*/, $_, 2);
	if (	$parName eq "SERVER_HOST"
		||	$parName eq "SERVER_PORT"
		||	$parName eq "CLIENT_IP"
		||	$parName eq "TIMEOUT"
		||	$parName eq "DEBUG"
		||	$parName eq "PROC_STATUS_RETRY"
		||	$parName eq "PROC_STATUS_DELAY" )
	{ $cfgParameters{$parName} = $parVal; }
  }#WEND
  close CFG;
  
  #Check for the required parameters:
  if(!exists($cfgParameters{"SERVER_HOST"}))
  {
	$errCode = ERR_MISS_CFGPAR;
	$errMsg = "Missing SERVER_HOST Parameter";
	ReportError("Init");
  }
  else { $SERVER_HOST = $cfgParameters{"SERVER_HOST"}; }
  
  if(!exists($cfgParameters{"SERVER_PORT"}))
  {
	$errCode = ERR_MISS_CFGPAR;
	$errMsg = "Missing SERVER_PORT Parameter";
	ReportError("Init");
  }
  else { $SERVER_PORT = $cfgParameters{"SERVER_PORT"}; }
  
  #<v052>
  #The CLIENT_IP configuration parameter is required.
  if(!exists($cfgParameters{"CLIENT_IP"}))
  {
	$errCode = ERR_MISS_CFGPAR;
	$errMsg = "Missing CLIENT_IP Parameter";
	ReportError("Init");
  }
  else { $CLIENT_IP = $cfgParameters{"CLIENT_IP"}; }
  #</v052>

  if(!exists($cfgParameters{"TIMEOUT"}))
  {
	$errCode = ERR_MISS_CFGPAR;
	$errMsg = "Missing TIMEOUT Parameter";
	ReportError("Init");
  }
  else
  { $TIMEOUT = $cfgParameters{"TIMEOUT"}; }

  if(!exists($cfgParameters{"PROC_STATUS_RETRY"}))
  {
	$errCode = ERR_MISS_CFGPAR;
	$errMsg = "Missing PROC_STATUS_RETRY Parameter";
	ReportError("Init");
  }
  else
  { $PROC_STATUS_RETRY = $cfgParameters{"PROC_STATUS_RETRY"}; }

  if(!exists($cfgParameters{"PROC_STATUS_DELAY"}))
  {
	$errCode = ERR_MISS_CFGPAR;
	$errMsg = "Missing PROC_STATUS_DELAY Parameter";
	ReportError("Init");
  }
  else
  { $PROC_STATUS_DELAY = $cfgParameters{"PROC_STATUS_DELAY"}; }

  #The DEBUG parameter, if missing, does not cause
  #an error, but the $DBG file-scoped variable is
  #set to the minimum level:
  if(!exists($cfgParameters{"DEBUG"}))
  { $DBG = DBG_MIN; }
  else
  { $DBG= $cfgParameters{"DEBUG"}; }
  
  #Check if there is a Storage Area where the $outputDir
  #variable points to or not;
  #If not, create it; Report error if it can't be created:
  if (! (-d $outputDir) )
  {
	mkdir $outputDir, 777;
	if(! (-d $outputDir))
	{
	  $errCode = ERR_STORAGE;
	  $errMsg = "Failed to Create Storage Area Named $outputDir";
	  ReportError("Init");
	}
  }

  #Check for the command line parameters:
  if($args<1)
  {
	$errCode = ERR_NO_CLPAR;
	ReportError("Init");
  }
  
  #Set the input file name:
  $inFilename = $argv[0];
  
  #Check if input file is available:
  if(!(-e $inFilename) )
  {
	$errCode = ERR_INFILE;
	$errMsg = "Could Not Find Input File '$inFilename'";
	ReportError("Init");
  }
  
  #Any more command line parameters?
  for(my $i=1; $i<$args; $i++)
  {
	my ($clPar, $clVal) = split(/=/, $argv[$i]);
	if($clVal)
	{
	  if($clPar eq "-o")
	  {
		$outFilename = $outputDir."\\$clVal";
		$setOutFilename = 1;
	  }
	  elsif($clPar eq "-id")
	  {
		$playbackID = $clVal;
	  }
	  elsif($clPar eq "-u")
	  {
		$playbackUser = $clVal;
	  }
	  elsif($clPar eq "-desc")
	  {
		$playbackDesc = $clVal;
	  }
	}#IF
  }#FOR
  
  #<v053>
  # The input file parameter is now assumed to be the full path to the
  # input file. Thus, the following code (used to prepend the
  # parameter received with the current working directory) is
  # commented out:
  
  #Get the full path to the input file (The XMLin call
  #assumes you'll provide an absolute path):
  #  my $fullInFileName =$Bin."\\$inFilename";

  #</v053>

  #Slurp up file in a hash referred to by the $inData reference:
  #Using eval allows us to catch any 'exception' thrown in the call:
  $inData = eval { XMLin($inFilename, forcecontent => 1) };
  if($@)
  {
	$errCode = ERR_XMLIN;
	$errMsg = $@;
	ReportError("Init");
  }
  
# Uncomment this line, and the 'use Data::Dumper' line at the top
# to display the content of the $inData hash in the LOG file:
#
# print LOG Dumper($inData);
  
  #Set the output file name if no command-line argument did:
  if($setOutFilename==0)
  {
	my $tmp = $inFilename;
	my @chars = split(//, $tmp);
	my $lastPeriod = @chars;
	$lastPeriod--;
	while(($lastPeriod>=0) && ($chars[$lastPeriod] ne "."))
	{ $lastPeriod--; }
	my $t2 = "";
	if($lastPeriod<0)
	{
	  $t2 = $inFilename;
	  $t2.="_pbk.xml";
	}
	else
	{
	  $t2 = substr($inFilename, 0, $lastPeriod);
	  $t2.="_pbk.xml";
	}
	$outFilename = $outputDir."\\".$t2;
  }#IF
  
  #Attempt to open the output file:
  if(!(open(OUT, "> $outFilename") ) )
  {
	$errCode = ERR_OUTFILE;
	$errMsg = "Could Not Open Output File '$outFilename'\n";
	ReportError("Init");
  }
  # Set OUT handle in binmode, and to be
  # flushed after every output statement:
  # binmode(OUT);
  $old_out = select(OUT);
  $| = 1;
  select($old_out);
  
  #<v051>
  # Since the $agent is instanciated by the Main procedure,
  # its timeout attribute is set every time it is instanciated.
  #Set the agent's timeout:
  #$agent->timeout($TIMEOUT);
  #</v051>

  #Return "true":
  return 1;
}
#	End Init
#^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^

=pod

=head1 ModifyRequestGUID Procedure

=head2 Description:

  A procedure to modify the GUID element in an HTTP::Request to
  respect a pre-existing mapping, if one exists (ObjectStore specific).

=head2 Input:

=over 4

=item 1

  $request	The HTTP::Request to be modified.

=back

=head2 Returns:

  N/A.
  
=head2 Notes:

  The routine applies a modification if and only if the GUID element
  in the $request received is the key in a pre-existing mapping.
  In that case, the content of the $request is modified to include the
  other element in that mapping in place of the one found.

=cut

#	ModifyRequestGUID:
#^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
sub ModifyRequestGUID
{
  if($DBG >= DBG_MED)	{ LogFunctionEntry("ModifyRequestGUID"); }
  
  my $request = $_[0];
  
  my $theGUID = ExtractGUIDFromRequest($request, $transactionType);
  
  if($DBG >= DBG_HIGH)
  {
	print LOG Indent($logIndent);
	print LOG "GUID Extracted: $theGUID\n";
  }
  
  if($theGUID)
  {
	if(		(exists($guidMap{$theGUID}))
	   &&	$guidMapSet{$theGUID} )
	{
	  my $newGUID = RegExMe($guidMap{$theGUID});
		my $theContent = $request->content();
		
		if($DBG >= DBG_HIGH)
		{
		  print LOG Indent($logIndent);
		  print LOG "Translating the GUID in the Request:\n";
		  print LOG Indent($logIndent);
		  print LOG "USE         $newGUID\n";
		  print LOG Indent($logIndent);
		  print LOG "IN PLACE OF $theGUID\n";
		}
		my $theGUIDRegexed = RegExMe($theGUID);
		
		$theContent =~ s/$theGUIDRegexed/$newGUID/;
		
		my $unregContent = "";
		my $pre = "";
		my $post = "";
		
		my $unreggedGUID = $newGUID;
		  $unreggedGUID =~ s/\\\//\//g;	# Make each '\/' into a '/'
		  $unreggedGUID =~ s/\\\:/\:/g;	# Make each '\:' into a ':'
		  $unreggedGUID =~ s/\\\-/\-/g;	# Make each '\-' into a '-'
		  $unreggedGUID =~ s/\\\\/\\/g;	# Make each '\\' into a '\' LEAVE LAST
		  
		my @parts = split(/\Q$theGUIDRegexed\E/, $theContent);
		
		my $partsSize = @parts;
		my $counter = 0;
		while($counter<$partsSize)
		{
		  $unregContent.=$parts[$counter];
		  if($counter<($partsSize-1) )	{ $unregContent.=$unreggedGUID; }
		  $counter++;
		}#WEND
		
		$request->content($unregContent);
	}
	elsif($DBG >= DBG_HIGH)
	{
	  print LOG Indent($logIndent);
	  print LOG "The GUID $theGUID was un-mapped: no substitution performed.\n";
	}
  }
  
  if($DBG >= DBG_MED)	{ LogFunctionExit("ModifyRequestGUID"); }
}
#	End ModifyRequestGUID
#^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^

=pod

=head1 ModifyRequestSerialized Procedure

=head2 Description:

  A procedure to modify the Serialized Object element in an
  HTTP::Request to respect a pre-existing mapping, if one exists
  (ObjectStore specific).

=head2 Input:

=over 4

=item 1

  $request	The HTTP::Request to be modified.

=back

=head2 Returns:

  N/A.
  
=head2 Notes:

  The routine applies a modification if and only if the Serialized
  Object element in the $request received is the key in a pre-existing
  mapping.
  In that case, the content of the $request is modified to include the
  other element in that mapping in place of the one found.

=cut

#	ModifyRequestSerialized:
#^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
sub ModifyRequestSerialized
{
  if($DBG >= DBG_MED)	{ LogFunctionEntry("ModifyRequestSerialized"); }
  
  my $request = $_[0];
  
  my $theSerialized = ExtractSerializedFromRequest($request, $transactionType);

  if($DBG >= DBG_HIGH)
  {
	print LOG Indent($logIndent);
	print LOG "Serialized Extracted: $theSerialized\n";
  }
  
  if($theSerialized)
  {
	if(		(exists($serializedMap{$theSerialized}))
	   &&	$serializedMapSet{$theSerialized} )
	{
	  my $newSerialized = RegExMe($serializedMap{$theSerialized});
	  
		my $theContent = $request->content();
		
		if($DBG >= DBG_HIGH)
		{
		  print LOG Indent($logIndent);
		  print LOG "Translating the Serialized Object in the Request:\n";
		  print LOG Indent($logIndent);
		  print LOG "USE         $newSerialized\n";
		  print LOG Indent($logIndent);
		  print LOG "IN PLACE OF $theSerialized\n";
		}
		my $theSerializedRegexed = RegExMe($theSerialized);
		$theContent =~ s/$theSerializedRegexed/$newSerialized/;
		
		my $unregContent = "";
		my $pre = "";
		my $post = "";
		
		#All transactions have the filename in the <bstrSerializedObject> tag
		  ($pre, $post) = split(/<bstrSerializedObject>/, $theContent);
		  
		  $unregContent = $pre;
		  $unregContent.="<bstrSerializedObject>";
		  
		  ($pre, $post) = split(/<\/bstrSerializedObject>/, $post);
		  
		  $pre =~ s/\\\//\//g;	# Make each '\/' into a '/'
		  $pre =~ s/\\\:/\:/g;	# Make each '\:' into a ':'
		  $pre =~ s/\\\-/\-/g;	# Make each '\-' into a '-'
		  $pre =~ s/\\\\/\\/g;	# Make each '\\' into a '\' LEAVE LAST
		  
		  $unregContent.=$pre;
		  $unregContent.="</bstrSerializedObject>";
		  $unregContent.=$post;
		$request->content($unregContent);
	}
	elsif($DBG >= DBG_HIGH)
	{
	  print LOG Indent($logIndent);
	  print LOG "The Serialized Object $theSerialized was un-mapped: no substitution performed.\n";
	}
  }
  
  if($DBG >= DBG_MED)	{ LogFunctionExit("ModifyRequestSerialized"); }
}
#	End ModifyRequestSerialized
#^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^

=pod

=head1 ModifyRequestFilename Procedure

=head2 Description:

  A procedure to modify the Filename element in an HTTP::Request to
  respect a pre-existing mapping, if one exists (ObjectStore specific).

=head2 Input:

=over 4

=item 1

  $request	The HTTP::Request to be modified.

=back

=head2 Returns:

  N/A.
  
=head2 Notes:

  The routine applies a modification if and only if the Filename element
  in the $request received is the key in a pre-existing mapping.
  In that case, the content of the $request is modified to include the
  other element in that mapping in place of the one found.
  Also note that in the case of a transaction of type
  TRANSACTION_OBS_OBSTORE_GET the substitution is performed in the
  $request's URI.

=cut

#	ModifyRequestFilename:
#^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
sub ModifyRequestFilename
{
  if($DBG >= DBG_MED)	{ LogFunctionEntry("ModifyRequestFilename"); }
  
  my $request = $_[0];
  
  my $theFilename = ExtractFilenameFromRequest($request, $transactionType);

  if($DBG >= DBG_HIGH)
  {
	print LOG Indent($logIndent);
	print LOG "Filename Extracted: $theFilename\n";
  }
  
  if($theFilename)
  {
	if(		(exists($filenameMap{$theFilename}))
	   &&	$filenameMapSet{$theFilename} )
	{
	  my $newFilename = RegExMe($filenameMap{$theFilename});
	  
	  if($transactionType == TRANSACTION_OBS_OBSTORE_GET)
	  {
		if($DBG >= DBG_HIGH)
		{
		  print LOG Indent($logIndent);
		  print LOG "This is an ObjectStore Obstore GET Transaction: the filename\n";
		  print LOG Indent($logIndent);
		  print LOG "must be substituted in the URI.\n";
		}
		my $theURI = $request->uri();
		
		if($DBG >= DBG_HIGH)
		{
		  print LOG Indent($logIndent);
		  print LOG "Translating the Filename in the Request's URI:\n";
		  print LOG Indent($logIndent);
		  print LOG "USE         $newFilename\n";
		  print LOG Indent($logIndent);
		  print LOG "IN PLACE OF $theFilename\n";
		}
		my $theFilenameRegexed = RegExMe($theFilename);
		$theURI =~ s/$theFilenameRegexed/$newFilename/;
		
		#Unreg the URI:
		  my $unregURI = "";
		  my ($pre, $post) = split(/get\//, $theURI);
		  
		  $unregURI = $pre;
		  $unregURI.="get/";
		  
		  $post =~ s/\\\//\//g;	# Make each '\/' into a '/'
		  $post =~ s/\\\:/\:/g;	# Make each '\:' into a ':'
		  $post =~ s/\\\-/\-/g;	# Make each '\-' into a '-'
		  $post =~ s/\\\\/\\/g;	# Make each '\\' into a '\' LEAVE LAST
		  
		  $unregURI.=$post;
		
		$request->uri($unregURI);
	  }
	  else
	  {
		my $theContent = $request->content();
		
		if($DBG >= DBG_HIGH)
		{
		  print LOG Indent($logIndent);
		  print LOG "Translating the Filename in the Request:\n";
		  print LOG Indent($logIndent);
		  print LOG "USE         $newFilename\n";
		  print LOG Indent($logIndent);
		  print LOG "IN PLACE OF $theFilename\n";
		}
		my $theFilenameRegexed = RegExMe($theFilename);
		$theContent =~ s/$theFilenameRegexed/$newFilename/;
		
		my $unregContent = "";
		my $pre = "";
		my $post = "";
		
		#All transactions have the filename in the <bstrFileName> tag,
		#except the OBS_OBSTORE_POST ones:
		if($transactionType == TRANSACTION_OBS_OBSTORE_POST)
		{
		  ($pre, $post) = split(/filename="/, $theContent);
		  
		  $unregContent = $pre;
		  $unregContent.="filename=\"";
		  
		  ($pre, $post) = split(/"/, $post);
		  
		  $pre =~ s/\\\//\//g;	# Make each '\/' into a '/'
		  $pre =~ s/\\\:/\:/g;	# Make each '\:' into a ':'
		  $pre =~ s/\\\-/\-/g;	# Make each '\-' into a '-'
		  $pre =~ s/\\\\/\\/g;	# Make each '\\' into a '\' LEAVE LAST
		  
		  $unregContent.=$pre;
		  $unregContent.="\"";
		  $unregContent.=$post;
		}
		else
		{
		  ($pre, $post) = split(/<bstrFileName>/, $theContent);
		  
		  $unregContent = $pre;
		  $unregContent.="<bstrFileName>";
		  
		  ($pre, $post) = split(/<\/bstrFileName>/, $post);
		  
		  $pre =~ s/\\\//\//g;	# Make each '\/' into a '/'
		  $pre =~ s/\\\:/\:/g;	# Make each '\:' into a ':'
		  $pre =~ s/\\\-/\-/g;	# Make each '\-' into a '-'
		  $pre =~ s/\\\\/\\/g;	# Make each '\\' into a '\' LEAVE LAST
		  
		  $unregContent.=$pre;
		  
		  $unregContent.="</bstrFileName>";
		  $unregContent.=$post;
		}
		$request->content($unregContent);
	  }
	}
	elsif($DBG >= DBG_HIGH)
	{
	  print LOG Indent($logIndent);
	  print LOG "The Filename $theFilename was un-mapped: no substitution performed.\n";
	}
  }
  
  if($DBG >= DBG_MED)	{ LogFunctionExit("ModifyRequestFilename"); }
}
#	End ModifyRequestFilename
#^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^

=pod

=head1 ModifyRequestQuery Procedure

=head2 Description:

  A procedure to modify the Query element in an HTTP::Request to
  respect a pre-existing mapping, if one exists (ObjectStore specific).

=head2 Input:

=over 4

=item 1

  $request	The HTTP::Request to be modified.

=back

=head2 Returns:

  N/A.
  
=head2 Notes:

  The routine applies a modification if and only if the Query element
  in the $request received is the key in a pre-existing mapping.
  In that case, the content of the $request is modified to include the
  other element in that mapping in place of the one found.

=cut

#	ModifyRequestQuery:
#^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
sub ModifyRequestQuery
{
  if($DBG >= DBG_MED)	{ LogFunctionEntry("ModifyRequestQuery"); }
  
  my $request = $_[0];
  
  my $theQuery = ExtractQueryFromRequest($request, $transactionType);
  
  if($DBG >= DBG_HIGH)
  {
	print LOG Indent($logIndent);
	print LOG "Query Extracted: $theQuery\n";
  }
  
  if($theQuery)
  {
	if(		(exists($queryMap{$theQuery}) )
	   &&	$queryMapSet{$theQuery})
	{
	  my $newQuery = RegExMe($queryMap{$theQuery});
	  my $content = $request->content();
	  
	  if($DBG >= DBG_HIGH)
	  {
		print LOG Indent($logIndent);
		print LOG "Translating the Query in the Request:\n";
		print LOG Indent($logIndent);
		print LOG "USE         $newQuery\n";
		print LOG Indent($logIndent);
		print LOG "IN PLACE OF $theQuery\n";
	  }
	  my $theQueryRegexed = RegExMe($theQuery);
	  $content =~ s/$theQueryRegexed/$newQuery/;
	  $request->content($content);
	}
	elsif($DBG >= DBG_HIGH)
	{
	  print LOG Indent($logIndent);
	  print LOG "The Query $theQuery was un-mapped: no substitution performed.\n";
	}
  }
  
  if($DBG >= DBG_MED)	{ LogFunctionExit("ModifyRequestQuery"); }
}
#	End ModifyRequestQuery
#^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^

=pod

=head1 ModifyRequestLPO Procedure

=head2 Description:

  A procedure to modify the lpObject element in an HTTP::Request to
  respect a pre-existing mapping, if one exists (ObjectStore specific).

=head2 Input:

=over 4

=item 1

  $request	The HTTP::Request to be modified.

=back

=head2 Returns:

  N/A.
  
=head2 Notes:

  The routine applies a modification if and only if the lpObject element
  in the $request received is the key in a pre-existing mapping.
  In that case, the content of the $request is modified to include the
  other element in that mapping in place of the one found.

=cut

#	ModifyRequestLPO:
#^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
sub ModifyRequestLPO
{
  if($DBG >= DBG_MED)	{ LogFunctionEntry("ModifyRequestLPO"); }
  
  my $request = $_[0];
  
  my $theLPO = ExtractLPOFromRequest($request, $transactionType);
  
  if($DBG >= DBG_HIGH)
  {
	print LOG Indent($logIndent);
	print LOG "lpObject Extracted: $theLPO\n";
  }
  
  if($theLPO)
  {
	if(		(exists($lpoMap{$theLPO}) )
	   &&	$lpoMapSet{$theLPO})
	{
	  my $newLPO = RegExMe($lpoMap{$theLPO});
	  my $content = $request->content();
	  
	  if($DBG >= DBG_HIGH)
	  {
		print LOG Indent($logIndent);
		print LOG "Translating the lpObject in the Request:\n";
		print LOG Indent($logIndent);
		print LOG "USE         $newLPO\n";
		print LOG Indent($logIndent);
		print LOG "IN PLACE OF $theLPO\n";
	  }
	  my $theLPORegexed = RegExMe($theLPO);
	  $content =~ s/$theLPORegexed/$newLPO/;
	  $request->content($content);
	}
	elsif($DBG >= DBG_HIGH)
	{
	  print LOG Indent($logIndent);
	  print LOG "The lpObject $theLPO was un-mapped: no substitution performed.\n";
	}
  }
  
  if($DBG >= DBG_MED)	{ LogFunctionExit("ModifyRequestLPO"); }
}
#	End ModifyRequestLPO
#^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^

=pod

=head1 ModifyRequestDPSJobID Procedure

=head2 Description:

  A procedure to modify the Job ID element in an HTTP::Request to
  respect a pre-existing mapping, if one exists (DPS specific).

=head2 Input:

=over 4

=item 1

  $request	The HTTP::Request to be modified.

=back

=head2 Returns:

  N/A.
  
=head2 Notes:

  <v052>
  This routine has been included with v.0.52.
  The routine applies a modification if and only if the job ID element
  in the $request received is the key in a pre-existing mapping.
  In that case, the content of the $request is modified to include the
  other element in that mapping in place of the one found.
  </v052>

=cut

#	ModifyRequestDPSJobID
#^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
sub ModifyRequestDPSJobID
{
  if($DBG >= DBG_MED)	{ LogFunctionEntry("ModifyRequestDPSJobID"); }
  
  my $request = $_[0];
  
  my $theJobID = ExtractJobIDFromRequest($request->content);
  
  if($DBG >= DBG_HIGH)
  {
	print LOG Indent($logIndent);
	print LOG "jobID Extracted: $theJobID\n";
  }
  
  if($theJobID)
  {
	if(		(exists($jobIdMap{$theJobID}) )
	   &&	$jobIdMapSet{$theJobID})
	{
	  my $newJobID = RegExMe($jobIdMap{$theJobID});
	  my $content = $request->content();
	  
	  if($DBG >= DBG_HIGH)
	  {
		print LOG Indent($logIndent);
		print LOG "Translating the jobID in the Request:\n";
		print LOG Indent($logIndent);
		print LOG "USE         $newJobID\n";
		print LOG Indent($logIndent);
		print LOG "IN PLACE OF $theJobID\n";
	  }
	  my $theJobIdRegexed = RegExMe($theJobID);
	  $content =~ s/$theJobIdRegexed/$newJobID/;
	  $request->content($content);
	  if($DBG>=DBG_MED)
	  {
		print LOG Indent($logIndent);
		print LOG "The job ID has been substituted: $theJobID => ".$jobIdMap{$theJobID}."\n";
	  }
	}
	elsif($DBG >= DBG_HIGH)
	{
	  print LOG Indent($logIndent);
	  print LOG "The jobID $theJobID was un-mapped: no substitution performed.\n";
	}
  }
  
  if($DBG >= DBG_MED)	{ LogFunctionExit("ModifyRequestDPSJobID"); }
}
#	End ModifyRequestDPSJobID
#^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^

=pod

=head1 ModifyRequestDPSClientID Procedure

=head2 Description:

  A procedure to modify the Client ID element in an HTTP::Request to
  point to the client currently in use (i.e. the machine where the HTTP
  Playback tool is running).

=head2 Input:

=over 4

=item 1

  $request	The HTTP::Request to be modified.

=back

=head2 Returns:

  N/A.
  
=head2 Notes:

  <v052>
  This routine has been included with v.0.52.
  The routine applies a modification if and only if the $request
  includes a client ID element.
  The Client ID element is substituted by the value of the
  file-scoped $CLIENT_IP variable.
  </v052>

=cut

#	ModifyRequestDPSClientID
#^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
sub ModifyRequestDPSClientID
{
  if($DBG >= DBG_MED)	{ LogFunctionEntry("ModifyRequestDPSClientID"); }
  
  my $request = $_[0];
  
  my $theClientIp = ExtractClientIpFromRequest($request->content);
  
  if($DBG >= DBG_HIGH)
  {
	print LOG Indent($logIndent);
	print LOG "Client Ip Extracted: $theClientIp\n";
  }
  
  #Apply substitution only if a client IP was found:
  if($theClientIp)
  {
	my $content = $request->content();
	my $newContent = "";
	my ($pre, $post) = split(/\Q"pszClientID"\E/, $content);
	
	$newContent.=$pre;
	$newContent.="\"pszClientID\"";
	$newContent.=$CLIENT_IP;
	
	#Skip over the client ip in the $post:
	($pre, $post) = split(/\-/, $post, 2);
	$newContent.="-".$post;
	
	$request->content($newContent);
  }
  
  if($DBG >= DBG_MED)	{ LogFunctionExit("ModifyRequestDPSClientID"); }
}
#	End ModifyRequestDPSJobID
#^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^

=pod

=head1 ModifyRequestDPSServerID Procedure

=head2 Description:

  A procedure to modify the Server ID element in an HTTP::Request to
  point to the server currently in use.

=head2 Input:

=over 4

=item 1

  $request	The HTTP::Request to be modified.

=back

=head2 Returns:

  N/A.
  
=head2 Notes:

  <v052>
  This routine has been included with v.0.52.
  The routine applies a modification if and only if the $request
  includes a server ID element.
  The Server ID element is substituted by the value of the
  file-scoped $SERVER_HOST variable.
  </v052>

=cut

#	ModifyRequestDPSServerID
#^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
sub ModifyRequestDPSServerID
{
  if($DBG >= DBG_MED)	{ LogFunctionEntry("ModifyRequestDPSServerID"); }
  
  my $request = $_[0];
  
  my $theServerIp = ExtractServerIpFromRequest($request->content);
  
  if($DBG >= DBG_HIGH)
  {
	print LOG Indent($logIndent);
	print LOG "Server Ip Extracted: $theServerIp\n";
  }
  
  #Apply substitution only if a server IP was found:
  if($theServerIp)
  {
	my $content = $request->content();
	my $newContent = "";
	my ($pre, $post) = split(/\Q"pszServerID"\E/, $content);
	
	$newContent.=$pre;
	$newContent.="\"pszServerID\"";
	$newContent.=$SERVER_HOST;
	
	#Skip over the server ip in the $post:
	($pre, $post) = split(/\-/, $post, 2);
	$newContent.="-".$post;
	
	$request->content($newContent);
  }

  if($DBG >= DBG_MED)	{ LogFunctionExit("ModifyRequestDPSServerID"); }
}
#	End ModifyRequestDPSServerID
#^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^

=pod

=head1 ModifyRequestContent Procedure

=head2 Description:

  A procedure to modify the content of an HTTP::Request to respect
  any pre-existing mapping of 'variable' elements (ObjectStore
  specific).

=head2 Input:

=over 4

=item 1

  $request	The HTTP::Request to be modified.

=back

=head2 Returns:

  N/A.
  
=head2 Notes:

  The routine relies upon the ModifyRequestQuery, ModifyRequestFilename,
  ModifyRequestSerialized, ModifyRequestGUID, and ModifyRequestLPO
  routines to perform the necessary (if any) modifications.
  <v052>
  The routine now also calls the ModifyRequestDPSJobID,
  ModifyRequestDPSClientID and ModifyRequestDPSServerID routines
  in the case of a DPS playback. These calls is performed only on the
  odd-numbered transactions (since the even-numbered ones are assumed to
  be Security Challenge transactions that never include job IDs).
  </v052>

=cut

#	ModifyPlaybackRequestContent:
#^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
sub ModifyPlaybackRequestContent
{
  if($DBG >= DBG_MED)	{ LogFunctionEntry("ModifyPlaybackRequestContent"); }
  
  my $request = $_[0];
  
  if(	$transactionType == TRANSACTION_OBS_EXECUTE_SEARCH
  ||	$transactionType == TRANSACTION_OBS_GET_LAST_UPDATE_TIME	)
  { ModifyRequestQuery($request); }
  
  if(	$transactionType == TRANSACTION_OBS_OBSTORE_POST
  ||	$transactionType == TRANSACTION_OBS_ADD_OBJECT
  ||	$transactionType == TRANSACTION_OBS_UPLOAD_OBJECT_DATA
  ||	$transactionType == TRANSACTION_OBS_DOWNLOAD_OBJECT_DATA
  ||	$transactionType == TRANSACTION_OBS_OBSTORE_GET				)
  { ModifyRequestFilename($request); }
  
  if(	$transactionType == TRANSACTION_OBS_ADD_OBJECT
  ||	$transactionType == TRANSACTION_OBS_GET_OBJECT				)
  { ModifyRequestSerialized($request); }
  
  if(	$transactionType == TRANSACTION_OBS_GET_OBJECT
  ||	$transactionType == TRANSACTION_OBS_UPLOAD_OBJECT_DATA
  ||	$transactionType == TRANSACTION_OBS_ADD_OBJECT
  ||	$transactionType == TRANSACTION_OBS_DOWNLOAD_OBJECT_DATA
  ||	$transactionType == TRANSACTION_OBS_REMOVE_OBJECT			)
  { ModifyRequestGUID($request); }
  
  if(	$transactionType == TRANSACTION_OBS_ADD_OBJECT
  ||	$transactionType == TRANSACTION_OBS_UPDATE_OBJECT 			)
  { ModifyRequestLPO($request); }
  
  if(	$recordingServerType == SERVER_DPS
	 &&	($transactionID%2!=0)										)
  {
	ModifyRequestDPSClientID($request);
	ModifyRequestDPSServerID($request);
	ModifyRequestDPSJobID($request);
  }
  
  if($DBG >= DBG_MED)	{ LogFunctionExit("ModifyPlaybackRequestContent"); }
  return $request;
}
#	End ModifyPlaybackRequestContent
#^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^

=pod

=head1 MakePlaybackRequest Procedure

=head2 Description:

  A procedure to create a copy of a given HTTP::Request suitable
  for use during the playback process.

=head2 Input:

=over 4

=item 1

  $originalRequest	The HTTP::Request to be copied.

=back

=head2 Returns:

  $newRequest	An HTTP::Request based upon the $originalRequest
				received by the routine, but suitable for use during
				the playback process.
  
=head2 Notes:

  The routine relies upon the DeepCopyOf routine to produce a deep copy
  of the $originalrequest. Once the deep copy is available, the
  following modifications are performed on it:
  ~ the 'User-Agent' header's value is set to the current
	version of the HTTP Playback tool;
  ~ the 'Host' header's value is set to the file-scoped $SERVER_HOST
	variable;
  ~ the scheme of the request's URI is set to http;
  ~ the host of the request's URI is set to the file-scoped
	$SERVER_HOST variable;
  ~ the port of the request's URI is set to the file-scoped
	$SERVER_PORT variable;
  ~ The content of the request might be modified by the
	ModifyPlaybackRequestContent routine;
  ~ the 'Content-Length' header's value may be accordingly modified.
  <v051>
  The routine now includes code to deal with the DPS playback
  of a security challenge transaction. Every even-numbered transaction
  (0, 2, ...) is assumed to be one such transaction, and its
  "Authorization" header is modified to include the value produced
  by the DPSchallengeReply routine.
  </v051>

=cut

#	MakePlaybackRequest:
#^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
sub MakePlaybackRequest
{
  if($DBG >= DBG_MED)	{ LogFunctionEntry("MakePlaybackRequest"); }
  
  my $originalRequest = $_[0];
  
  my $newRequest = DeepCopyOf($originalRequest, HTTP_MSG_ORIGINAL_REQUEST);
  
  my $theUserAgent = "TrnsPort TestSuite - HTTPplay ".VERSION;
  
  my $originalHostHeader = $newRequest->header('Host');
  my $originalUserAgentHeader = $newRequest->header('User-Agent');
  my $originalURI = $newRequest->uri();
  
  if($DBG >= DBG_HIGH)
  {
	print LOG Indent($logIndent);
	print LOG "Modifying Playback request:\n";
  }
  
  $newRequest->header('Host' => $SERVER_HOST);
  $newRequest->header('User-Agent' => $theUserAgent);
  
  my $uri = $newRequest->uri();
  $uri->scheme("http");
  $uri->host($SERVER_HOST);
  $uri->port($SERVER_PORT);
  $newRequest->uri($uri);
  
  if($DBG >= DBG_HIGH)
  {
	print LOG Indent($logIndent);
	print LOG "  Host Header: $originalHostHeader => ".$newRequest->header('Host')."\n";
	print LOG Indent($logIndent);
	print LOG "  User-Agent Header: $originalUserAgentHeader => ".$newRequest->header('User-Agent')."\n";
	print LOG Indent($logIndent);
	print LOG "  URI: $originalURI => ".$newRequest->uri()."\n";
  }
  
  ModifyPlaybackRequestContent($newRequest);
  
  my $newContentSize = length($newRequest->content());
  $newRequest->header("Content-Length" => $newContentSize);
  
#<v051>
# For the second transactions in each DPS pair of transactions,
# we must deal with the security challenge:
  if($recordingServerType==SERVER_DPS && ($transactionID%2!=0) )
  {
	my $challengeReply = DPSchallengeReply();
	my $newHeader = "Basic ".$challengeReply;
	$newRequest->header("Authorization" => $newHeader);
	if($DBG >= DBG_MED)
	{
	  print LOG Indent($logIndent);
	  print LOG "The Authorization header has been modified to keep the new DPS challenge reply\n";
	}
  }
#</v051>
  
  if($DBG >= DBG_MED)
  {
	my $gotRequestMsg = HTTPmsgLog($newRequest, HTTP_MSG_PLAYBACK_REQUEST);
	print LOG $gotRequestMsg;
	LogFunctionExit("MakePlaybackRequest");
  }
  return $newRequest;
}
#	End MakePlaybackRequest
#^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^

=pod

=head1 GetPlaybackResponse Procedure

=head2 Description:

  A procedure to replay a given HTTP::Request and retrieve the
  HTTP::Response returned by the Server.

=head2 Input:

=over 4

=item 1

  $request	The HTTP::Request to be sent to the Server.

=back

=head2 Returns:

  $response	The HTTP::Response returned by the Server.
  
=head2 Notes:

  The routine uses the $request as it receives it, without applying
  any modification to it.
  Communications with the Servers are regulated by the file-scoped
  $agent LWP::UserAgent.
  <v051>
  Since the introduction of the DPS playbacks, this routine is also
  in charge of setting the file-scoped $lastDPSchallenge variable
  as needed (DPS Specific).
  </v051>

=cut

#	GetPlaybackResponse:
#^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
sub GetPlaybackResponse
{
  if($DBG >= DBG_MED)	{ LogFunctionEntry("GetPlaybackResponse"); }
  
  my $request = $_[0];
  
  if($DBG >= DBG_HIGH)
  {
	print LOG Indent($logIndent);
	print LOG "Sending Playback request to Server.\n";
  }
  
  my $response = $agent->send_request($request);
  
  if($DBG >= DBG_HIGH)
  {
	print LOG Indent($logIndent);
	print LOG "Received Playback response from Server.\n";
  }
  
  if($recordingServerType==SERVER_DPS && ($transactionID%2==0) )
  {
	$lastDPSchallenge = ExtractDPSChallenge($response->header("WWW-Authenticate"));
	if($DBG >= DBG_MED)
	{
	  print LOG Indent($logIndent);
	  print LOG "Extracted DPS challenge: $lastDPSchallenge\n";
	}
  }
  
  if($DBG >= DBG_MED)
  {
	my $gotResponseMsg = HTTPmsgLog($response, HTTP_MSG_PLAYBACK_RESPONSE);
	print LOG $gotResponseMsg;
	LogFunctionExit("GetPlaybackResponse");
  }

  return $response;  
}
#	End GetPlaybackResponse
#^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^

=pod

=head1 CompareResponses Procedure

=head2 Description:

  A procedure to compare two transactions (with particular focus
  upon the HTTP::Responses in the two transactions) and verify
  whether they contain any unexpected difference.

=head2 Input:

=over 4

=item 1

  $originalRequest	The HTTP::Request of the first transaction;

=item 2

  $originalResponse	The HTTP::Response of the first transaction;

=item 3

  $playbackrequest	The HTTP::Request of the second transaction;

=item 4

  $playbackResponse	The HTTP::Response of the second transaction.

=back

=head2 Returns:

  One of the RESULT_* constants, indicating whether the two
  transactions match (if the returned code is RESULT_OK), or if any
  unexpected difference (and which type of difference) was detected.
  
=head2 Notes:

  The routine checks the two responses' codes, and the two
  file-scoped $originalresponse_timeout and $playbackresponse_timeout
  variables to verify if they match.
  Next, MatchingHeaders and matchingContents are called to verify
  that the headers and contents match as well.

=cut

#	CompareResponses:
#^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
sub CompareResponses
{
  if($DBG >= DBG_MED)	{ LogFunctionEntry("CompareResponses"); }
  
  my ($originalRequest, $originalResponse, $playbackRequest, $playbackResponse) = @_;
  
  #Check the response codes:
  if($originalResponse->code() != $playbackResponse->code())
  {
	$resultErrInfo = "Code of Original Response: ".$originalResponse->code()." (".$originalResponse->message().")\n";
	$resultErrInfo.= "Code of Playback Response: ".$playbackResponse->code()." (".$playbackResponse->message().")\n";
	if($DBG >= DBG_HIGH)
	{
	  print LOG Indent($logIndent);
	  print LOG "CompareResponses detected a difference in the Responses' Codes:\n";
	  print LOG $resultErrInfo;
	  print LOG Indent($logIndent);
	  print LOG "CompareResponses will return ".RESULT_DIFF_CODE."\n";
	}
	if($DBG >= DBG_MED)	{ LogFunctionExit("CompareResponses"); }
	return RESULT_DIFF_CODE;
  }
  
  #Timeout matches?
  if($originalResponse_timeout != $playbackResponse_timeout)
  {
	$resultErrInfo = "The Original Response was ";
	if(!$originalResponse_timeout)
	{ $resultErrInfo.="not "; }
	$resultErrInfo.= "a Timeout Response.\n";
	$resultErrInfo.= "The Playback Response was ";
	if(!$playbackResponse_timeout)
	{ $resultErrInfo.="not "; }
	$resultErrInfo.= "a Timeout Response.\n";
	if($DBG >= DBG_HIGH)
	{
	  print LOG Indent($logIndent);
	  print LOG "CompareResponses detected a difference in the Responses' Timeouts:\n";
	  print LOG $resultErrInfo;
	  print LOG Indent($logIndent);
	  print LOG "CompareResponses will return ".RESULT_DIFF_TO."\n";
	}
	if($DBG >= DBG_MED)	{ LogFunctionExit("CompareResponses"); }
	return RESULT_DIFF_TO;
  }
  
  #Header matches?
  if(!MatchingHeaders($originalRequest, $originalResponse, $playbackRequest, $playbackResponse))
  {
	if($DBG >= DBG_HIGH)
	{
	  print LOG Indent($logIndent);
	  print LOG "MatchingHeaders returned false:\n";
	  print LOG $resultErrInfo;
	  print LOG Indent($logIndent);
	  print LOG "CompareResponses will return ".RESULT_DIFF_HEADERS."\n";
	}
	if($DBG >= DBG_MED)	{ LogFunctionExit("CompareResponses"); }
	return RESULT_DIFF_HEADERS;
  }
  
  #Content Matches?
  if(!MatchingContents($originalRequest, $originalResponse, $playbackRequest, $playbackResponse))
  {
	if($DBG >= DBG_HIGH)
	{
	  print LOG Indent($logIndent);
	  print LOG "MatchingContents returned false:\n";
	  print LOG $resultErrInfo;
	  print LOG Indent($logIndent);
	  print LOG "CompareResponses will return ".RESULT_DIFF_CONTENT."\n";
	}
	if($DBG >= DBG_MED)	{ LogFunctionExit("CompareResponses"); }
	return RESULT_DIFF_CONTENT;
  }

  #All Good !
  if($DBG >= DBG_HIGH)
  {
	print LOG Indent($logIndent);
	print LOG "CompareResponses will return ".RESULT_OK." (no significant difference detected)\n";
  }  
  if($DBG >= DBG_MED)	{ LogFunctionExit("CompareResponses"); }
  return RESULT_OK;
}
#	End CompareResponses
#^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^

=pod

=head1 PlaybackTransaction Procedure

=head2 Description:

  A procedure to replay the transaction identified by the
  current value of the file-scoped $transactionID variable.

=head2 Input:

=over 4

  N/A.

=back

=head2 Returns:

  N/A.
  
=head2 Notes:

  The routine drives the process of reading the information regarding
  this transaction from the file-scoped $inData variable (which
  contains the data gathered from the input file), replaying a
  copy of the transaction, comparing the results obtained, and
  write to the output file the result of the replay.
  The routine does not return any value, but (indirectly) may set the
  file-scoped $result variable to a value other than RESULT_OK,
  which will indicate to the Main procedure that the replay should be
  stopped.

=cut

#	PlaybackTransaction:
#^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
sub PlaybackTransaction
{
  if($DBG >= DBG_MED)	{ LogFunctionEntry("PlaybackTransaction"); }

  if($DBG >= DBG_HIGH)
  {
	print LOG Indent($logIndent);
	print LOG "PlaybackTransaction will call Output_TransactionHeader.\n";
  }
  Output_TransactionHeader();

  if($DBG >= DBG_HIGH)
  {
	print LOG Indent($logIndent);
	print LOG "PlaybackTransaction will call GetOriginalrequest.\n";
  }
  my $originalRequest = GetOriginalRequest();
  Output_TransactionElement($originalRequest, HTTP_MSG_ORIGINAL_REQUEST);

  if($DBG >= DBG_HIGH)
  {
	print LOG Indent($logIndent);
	print LOG "PlaybackTransaction will set the transactionType variable.\n";
  }  
  $transactionType = TypeOfRequest($originalRequest);
  
  if($DBG >= DBG_HIGH)
  {
	print LOG Indent($logIndent);
	print LOG "PlaybackTransaction will call GetoriginalResponse.\n";
  }
  my $originalResponse = GetOriginalResponse();
  Output_TransactionElement($originalResponse, HTTP_MSG_ORIGINAL_RESPONSE);

  if($DBG >= DBG_HIGH)
  {
	print LOG Indent($logIndent);
	print LOG "PlaybackTransaction will call MakePlaybackRequest.\n";
  }  
  my $playbackRequest = MakePlaybackRequest($originalRequest);
  Output_TransactionElement($playbackRequest, HTTP_MSG_PLAYBACK_REQUEST);

  if($DBG >= DBG_HIGH)
  {
	print LOG Indent($logIndent);
	print LOG "PlaybackTransaction will call GetPlaybackResponse.\n";
  }
  my $playbackResponse = GetPlaybackResponse($playbackRequest);
  Output_TransactionElement($playbackResponse, HTTP_MSG_PLAYBACK_RESPONSE);

  if($DBG >= DBG_HIGH)
  {
	print LOG Indent($logIndent);
	print LOG "PlaybackTransaction will call CompareResponses to set the result variable.\n";
  }
  $result = CompareResponses($originalRequest, $originalResponse, $playbackRequest, $playbackResponse);
  
  Output_TransactionResult();
  
  if($DBG >= DBG_HIGH)
  {
	print LOG Indent($logIndent);
	print LOG "PlaybackTransaction will call Output_TransactionFooter.\n";
  }
  Output_TransactionFooter();
  
  if($DBG >= DBG_HIGH)
  {
	print LOG Indent($logIndent);
	print LOG "PlaybackTransaction: after comparing the responses, the result is $result (".ResultCodeDesc().")\n";
  }
  
  if($DBG >= DBG_MED)	{ LogFunctionExit("PlaybackTransaction"); }  
}
#	End PlaybackTransaction
#^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^

=pod

=head1 Main Procedure

=head2 Description:

  The main procedure of the HTTP Playback tool.

=head2 Input:

=over 4

=item 1

  @ARGV	The array of command line arguments.

=back

=head2 Returns:

  N/A.
  
=head2 Notes:

  The routine drives the program through Initialization,
  and replay of each transaction found in the input file.
  The replay process terminates as soon as an unexpected difference
  is found (the file-scoped $result variable is used to indicate
  such an occurrence), or once all the transactions found in the
  input file have been replayed.
  <v051>
  The main loop in the routine has been restructured to accomodate
  for the replay of the DPS paired transactions.
  The main loop is also in charge of instanciating the file-scoped
  $agent LWP::UserAgent as needed.
  See further comments inlined.
  </v051>

=cut

#    Main procedure:
#^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
MAIN:
Init(@ARGV);

my $startupMsg = StartupMsg();
LogMsg($startupMsg);

if($DBG >= DBG_MED)	{ LogFunctionEntry("Main"); }

Output_PlaybackHeader();

#<v051>
# The introduction of the DPS playback forced a restructuring of
# the following loop. The original code (v.0.50) implemented
# this loop as a foreach loop, for each value in the sorted
# set of keys from the $inData->{TRANSACTION} hash.
# The new version first creates an array @allIDs to store
# all of the sorted keys from the same hash, and then implements
# the loop as a simple for loop running util the end of this array
# is reached (or, of course, an error is detected).
# This new arrangement allows us to advance the loop counter
# by an additional unit when a set of paired transactions is found
# (i.e. in the case of a DPS replay).
#</v051>

my @allIDs = (sort{$a <=> $b} (keys (%{$inData->{TRANSACTION}})));
my $limit = @allIDs;

for(my $k = 0; $k<$limit; )
{
  $transactionID = $allIDs[$k];
  
#<v051>
# Since the introduction of the DPS playback, the file-scoped $agent
# LWP::UserAgent needs to be instanciated in one of tow ways:
# ~ for ObjectStore replays: so that it will ensure the connection
#	to the Server is closed after playing each transaction;
# ~ for DPS replays: so that it will ensure that the connection
#	to the Server is kept-alive as needed (for paired transactions).
# Thus the $agent is instanciated by the Main routine as needed.
# In either case, however, the Main routine sets the $agent's timeout
# attribute to the value of the file-scoped $TIMEOUT variable.
  if($recordingServerType == SERVER_OBS)
  {
print LOG "Instanciating UserAgent with NO Keep-Alive\n";
	$agent = LWP::UserAgent->new(); }
  else
  {
print LOG "Instanciating UserAgent WITH Keep-Alive.\n";
	$agent = LWP::UserAgent->new(keep_alive=>2); }
  $agent->timeout($TIMEOUT);
#</v051>

  print STDERR "Replaying Transaction #$transactionID\n";
  PlaybackTransaction();
  if($result != RESULT_OK)	{ last; }

#<v051>
# In the case of a DPS playback, we must play the next transaction
# over the same connection (i.e. using the same LWP::UserAgent).
# To do so, we advance the $k loop counter, and call the
# PlaybackTransaction routine again.
#</v051>
  if($recordingServerType==SERVER_DPS)
  {
	$k++;
	$transactionID = $allIDs[$k];
	print STDERR "Replaying Transaction #$transactionID\n";
	PlaybackTransaction();
	if($result != RESULT_OK)	{ last; }
  }
#<v051>
# We must increment the $k loop counter in any case:
#</v051>
  $k++;
}#FOREACH

Output_PlaybackFooter();

my $quitMsg = QuitMsg();
LogMsg($quitMsg);

if($DBG >= DBG_MED)	{ LogFunctionExit("Main"); }

#	End of Main Procedure
#^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^

#^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
#	EOF
#^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
