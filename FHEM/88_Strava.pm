#################################################################
# $Id: 88_Strava.pm 15699 2020-02-25 12:15:50Z HomeAuto_User $
#
# Github - https://github.com/HomeAutoUser/Strava
#
# 2020 - HomeAuto_User
#
#################################################################
#
## http://developers.strava.com/docs/reference/
## https://developers.strava.com/docs/
#+ https://developers.strava.com/docs/authentication/
## https://developers.strava.com/playground/#/Athletes/getStats
#+ https://community.home-assistant.io/t/some-strava-sensors/25901
#+ https://loganrouleau.com/blog/2018/11/27/navigating-strava-api-authentication/
#+ https://stackoverflow.com/questions/52880434/problem-with-access-token-in-strava-api-v3-get-all-athlete-activities
#+ https://yizeng.me/2017/01/11/get-a-strava-api-access-token-with-write-permission/
#
#################################################################
# Note´s
# - only test, all security data must encrypted and not plain text
#################################################################

package main;

use strict;
use warnings;

use LWP;
use JSON;
use Data::Dumper qw (Dumper);

use HttpUtils;					# um Daten via HTTP auszutauschen https://wiki.fhem.de/wiki/HttpUtils

##########################
sub Strava_Initialize($) {
	my ($hash) = @_;

	$hash->{DefFn}    =	"Strava_Define";
	$hash->{GetFn}    =	"Strava_Get";
	$hash->{SetFn}    = "Strava_Set";
	$hash->{UndefFn}  = "Strava_Undef";
	$hash->{AttrFn}   = "Strava_Attr";
	$hash->{AttrList} = "disable ".
											"Code Client_ID Client_Secret Login Password Refresh_Token";
											#$readingFnAttributes;
}

##########################
sub Strava_Define($$) {
	my ($hash, $def) = @_;
	my @arg = split("[ \t][ \t]*", $def);
	my $name = $arg[0];
	my $typ = $hash->{TYPE};

	return "Usage: define <name> $name"  if(@arg != 2);

	### default value´s ###
	readingsBeginUpdate($hash);
	readingsBulkUpdate($hash, "state" , "Defined");
	readingsEndUpdate($hash, 0);
	return undef;
}

########################## function to all set action
sub Strava_Set($$$@) {
	my ( $hash, $name, @a ) = @_;
	my $typ = $hash->{TYPE};
	my $setList = "AuthApp_code";
	return "no set value specified" if(int(@a) < 1);

	my $cmd = $a[0];
	my $cmd2 = defined $a[1] ? $a[1] : "";

	Log3 $name, 3, "$typ: Set, $cmd" if ($cmd ne "?");

	if ($cmd eq "AuthApp_code") {
		if ($cmd2 eq "") {
			return "ERROR: $cmd failed argument";
		} else {
			$hash->{helper}{AuthApp_code} = $cmd2;
		}
	}

	return "Unknown argument $cmd, choose one of $setList" if (index($setList, $cmd) == -1);
}

########################## function to all get action
sub Strava_Get($$$@) {
	my ( $hash, $name, $cmd, @a ) = @_;
	my $cmd2 = defined $a[0] ? $a[0] : "";
	my $getlist = "AuthApp:noArg ";
	$getlist.= "activity athlete:noArg AuthRefresh:noArg Deauth:noArg " if($hash->{helper}{AuthApp} && $hash->{helper}{AuthApp} eq "SUCCESS");
	my $typ = $hash->{TYPE};

	Log3 $name, 3, "$name: Get, $cmd" if ($cmd ne "?");

	if ($cmd eq "AuthApp" || $cmd eq "AuthRefresh" || $cmd eq "activity" || $cmd eq "Deauth") {
		## !!! only test, data must encrypted and not plain text !!! ##
		return "Some attributes failed! You need Client_ID, Client_Secret, Login, Password" 
		if(!AttrVal($name, "Login", undef) || !AttrVal($name, "Password", undef) || 
			 !AttrVal($name, "Client_ID", undef) || !AttrVal($name, "Client_Secret", undef) ||
			 !AttrVal($name,"Refresh_Token",undef));
	}

	if ($cmd eq "activity") {
		Strava_activity($hash,$cmd2);
		return undef;
	};

	if ($cmd eq "athlete") {
		Strava_athlete($hash);
		return undef;
	};

	if ($cmd eq "AuthApp") {
		my $return = Strava_AuthApp($hash);
		return $return;
	};

	if ($cmd eq "AuthRefresh") {
		Strava_AuthRefresh($hash);
		return undef; 
	};

	if ($cmd eq "Deauth") {
		Strava_Deauth($hash);
		return undef; 
	};

	return "Unknown argument $cmd, choose one of $getlist";
}

########################## https://developers.strava.com/docs/authentication/#oauthoverview
sub Strava_AuthApp($) {
	my ($hash) = @_;
	my $typ = $hash->{TYPE};
	my $name = $hash->{NAME};
	my $Client_ID = AttrVal($name, "Client_ID", undef);
	my $cb = "http://localhost/exchange_token";

	# https://developers.strava.com/docs/authentication/#detailsaboutrequestingaccess
	# Todo, for user one attribut ???
	my $scope = "read,read_all,profile:read_all,activity:read_all";
	my $code = $hash->{helper}{AuthApp_code} ? $hash->{helper}{AuthApp_code} : "";
	my $url = "https://www.strava.com/oauth/authorize?response_type=code&client_id=".$Client_ID."&scope=".$scope."&redirect_uri=".$cb;

	Log3 $name, 4, "$name: AuthApp, GET ".$url;

	my $datahash = {	url        => "https://www.strava.com/api/v3/oauth/token",
										method     => "POST",
										timeout    => 10,
										noshutdown => 1,
										data       => {
																		client_id     => $Client_ID,
																		client_secret => AttrVal($name, "Client_Secret", undef),
																		code          => $code,
																		grant_type    => 'authorization_code',
																		redirect_uri  => $cb
																	},
	};

	my($err,$data) = HttpUtils_BlockingGet($datahash);

  if ($err ne "" || !defined($data) || $data =~ /Bad Request/) {
    Log3 $name, 1, "$name: AuthApp, error: $err" if ($err ne "");
		Log3 $name, 4, "$name: AuthApp, data: $data";
		readingsSingleUpdate( $hash, "state", "AuthApp must generates new code with Strava-Login", 1 );

		return "Please Login and authorize for new code!\n\n".
		"steps:\n".
		"1) click on website and Login\n".
		"<a href=$url target=\"_blank\">$url</a>\n".
		"2) copy Code from callback site from adress line [ ... =&code={YOUR CODE}&scope= ... ]\n".
		"3) set Code with 'set $name AuthApp_code'\n".
		"4) please run again 'get $name AuthApp'\n".
		"5) ready to use module";
  }

  my $json = eval { JSON::decode_json($data) };

  if($@) {
		Log3 $name, 1, "$name: AuthApp, JSON ERROR: $data";
		return undef;
  }

  Log3 $name, 5, "$name: AuthApp, SUCCESS: $data";
	$hash->{helper}{AuthApp} = "SUCCESS";
	$hash->{_AuthApp_access_token} = $json->{access_token} if(defined($json->{access_token})); ## for test
	$hash->{helper}{access_token} = $json->{access_token} if(defined($json->{access_token}));
	$hash->{helper}{AuthApp_expires_at} = $json->{expires_at} if(defined($json->{expires_at}));

	readingsSingleUpdate( $hash, "state", "AuthApp accomplished", 1 );

	return undef;
}

########################## https://developers.strava.com/docs/authentication/#tokenexchange
sub Strava_AuthRefresh($) {
  my ($hash) = @_;
	my $typ = $hash->{TYPE};
	my $name = $hash->{NAME};

	my $datahash =  {	url        => "https://www.strava.com/oauth/token",
										method     => "POST",
										timeout    => 10,
										noshutdown => 1,
										data       => {
																		client_id     => AttrVal($name, "Client_ID", undef),
																		client_secret => AttrVal($name, "Client_Secret", undef),
																		grant_type    => 'refresh_token',
																		refresh_token => AttrVal($name,'Refresh_Token','')
																	},
	};

	my($err,$data) = HttpUtils_BlockingGet($datahash);

  if ($err ne "" || !defined($data) || $data =~ /Authorization Error/ || $data =~ /not a valid/ || $data =~ /Bad Request/) {
    Log3 $name, 1, "$name: AuthRefresh, error: $err" if ($err ne "");
		Log3 $name, 4, "$name: AuthRefresh, data: $data";
		readingsSingleUpdate( $hash, "state", "Error: AuthRefresh, no data retrieval", 1 );
    return undef;
  }

  my $json = eval { JSON::decode_json($data) };

  if($@) {
    Log3 $name, 1, "$name: AuthRefresh, JSON ERROR: $data";
    return undef;
  }

  Log3 $name, 5, "$name: AuthRefresh, SUCCESS: $data";


	$hash->{_AuthRefresh_access_token} = $json->{access_token} if(defined($json->{access_token})); ## for test
	$hash->{helper}{access_token} = $json->{access_token} if(defined($json->{access_token}));
	$hash->{helper}{AuthRefresh_expires_at} = $json->{expires_at} if(defined($json->{expires_at}));
	$hash->{helper}{AuthRefresh_refresh_toke} = $json->{refresh_toke} if(defined($json->{refresh_toke}));

	readingsSingleUpdate( $hash, "state", "AuthRefresh accomplished", 1 );

  #InternalTimer(gettimeofday()+$json->{expires_in}-60, "Strava_AuthRefresh", $hash, 0);

	return undef;
}

##########################
sub Strava_Deauth($) {
  my ($hash) = @_;
	my $typ = $hash->{TYPE};
	my $name = $hash->{NAME};
	my $access_token = $hash->{helper}{access_token} ? $hash->{helper}{access_token} : "";

	my $url = "https://www.strava.com/oauth/deauthorize?access_token=".$access_token;
	Log3 $name, 4, "$name: Deauth, GET ".$url;

	my $datahash =  {	url        => $url,
										method     => "POST",
										timeout    => 10,
										noshutdown => 1,
	};

	my($err,$data) = HttpUtils_BlockingGet($datahash);

  if ($err ne "" || !defined($data) || $data =~ /Authorization Error/ || $data =~ /not a valid/) {
    Log3 $name, 1, "$name: Deauth, error: $err" if ($err ne "");
		Log3 $name, 4, "$name: Deauth, data: $data";
		readingsSingleUpdate( $hash, "state", "Error: Deauth, no data retrieval", 1 );
    return undef;
  }

  my $json = eval { JSON::decode_json($data) };

  if($@) {
    Log3 $name, 1, "$name: Deauth, JSON ERROR: $data";
    return undef;
  }

  Log3 $name, 5, "$name: Deauth, SUCCESS: $data";

	readingsSingleUpdate( $hash, "state", "Deauth accomplished, remove access_token", 1 );

	return undef;
}

##########################
sub Strava_activity($$) {
	my ($hash,$cmd2) = @_;
	my $typ = $hash->{TYPE};
	my $name = $hash->{NAME};
	my $access_token = $hash->{helper}{access_token} ? $hash->{helper}{access_token} : "";

	## https://developers.strava.com/docs/reference/#api-Activities
	## some example ##
	# activities                 - all activities (9 months backwards ??? or always 29 pieces)
	# activities/{id}            - one activity
	# activities/{id}/comments   - one activity comments
	# activities/{id}/kudos      - one activity kudos

	my $activities = $cmd2 ne "" ? "activities/$cmd2" : "activities";
	Log3 $name, 4, "$name: activity, GET ".'https://www.strava.com/api/v3/'.$activities.'?access_token='.$access_token;

	my $datahash = {	url        => 'https://www.strava.com/api/v3/'.$activities.'?access_token='.$access_token,
										method     => "GET",
										timeout    => 10,
										noshutdown => 1,
	};

	my($err,$data) = HttpUtils_BlockingGet($datahash);

	if ($err ne "" || !defined($data) || $data =~ /Authorization Error/ || $data =~ /invalid/ || $data =~ /Resource Not Found/) {
		Log3 $name, 1, "$name: activity, error: $err" if ($err ne "");
		Log3 $name, 4, "$name: activity, error: $data" if ($data);

		readingsSingleUpdate( $hash, "state", "Error: activity, no data retrieval", 1 );
		return undef;
	}

	my $json = eval { JSON::decode_json($data) };

	if($@) {
		Log3 $name, 1, "$name: activity, JSON ERROR: $data";
		return undef;
	}
	Log3 $name, 5, "$name: activity, SUCCESS: $data";

	readingsSingleUpdate( $hash, "state", "activity accomplished", 1 );
}

##########################
sub Strava_athlete($) {
  my ($hash) = @_;
	my $typ = $hash->{TYPE};
	my $name = $hash->{NAME};
	my $access_token = $hash->{helper}{access_token} ? $hash->{helper}{access_token} : "";

	## https://developers.strava.com/docs/reference/#api-Athletes
	# athlete - statistic to user

	Log3 $name, 4, "$name: athlete, GET ".'https://www.strava.com/api/v3/athlete?access_token='.$access_token;

	my $datahash = {	url        => 'https://www.strava.com/api/v3/athlete?access_token='.$access_token,
										method     => "GET",
										timeout    => 10,
										noshutdown => 1,
	};

	my($err,$data) = HttpUtils_BlockingGet($datahash);

  if ($err ne "" || !defined($data) || $data =~ /Authorization Error/ || $data =~ /invalid/) {
    Log3 $name, 1, "$name: athlete, error: $err" if ($err ne "");
    Log3 $name, 4, "$name: athlete, error: $data" if ($data);

		readingsSingleUpdate( $hash, "state", "Error: athlete, no data retrieval", 1 );
    return undef;
  }

  my $json = eval { JSON::decode_json($data) };

  if($@) {
    Log3 $name, 1, "$name: athlete, JSON ERROR: $data";
    return undef;
  }
  Log3 $name, 5, "$name: athlete, SUCCESS: $data";

	readingsSingleUpdate( $hash, "state", "athlete accomplished", 1 );
}

########################## function is used to check and modify attributes
sub Strava_Attr() {
	my ($cmd, $name, $attrName, $attrValue) = @_;
	my $hash = $defs{$name};
	my $typ = $hash->{TYPE};

	Log3 $name, 3, "$typ: Attr | Attribute $attrName set to $attrValue" if ($cmd eq "set");
	Log3 $name, 3, "$typ: Attr | Attribute $attrName delete" if ($cmd eq "del");
}

##########################
sub Strava_Undef($$) {
	my ($hash, $arg) = @_;
	my $name = $hash->{NAME};

	RemoveInternalTimer($hash);

	foreach my $value (qw( AuthApp AuthApp_expires_at AuthRefresh_expires_at AuthRefresh_refresh_toke )) {
		delete $hash->{helper}{$value} if(defined($hash->{helper}{$value}));
	}
	return undef;
}

##########################
# Eval-Rückgabewert für erfolgreiches
# Laden des Moduls
1;


# Beginn der Commandref

=pod
=item [helper|device|command]
=item summary Kurzbeschreibung in Englisch was MYMODULE steuert/unterstützt
=item summary_DE Kurzbeschreibung in Deutsch was MYMODULE steuert/unterstützt

=begin html

<a name="Strava"></a>
<h3>Strava API</h3>
<ul>
This is an Strava API module.<br>
</ul>
=end html


=begin html_DE

<a name="Strava"></a>
<h3>Strava API</h3>
<ul>
Das ist ein Strava API Modul.<br>
</ul>
=end html_DE

# Ende der Commandref
=cut