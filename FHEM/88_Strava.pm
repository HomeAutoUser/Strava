#################################################################
# $Id: 88_Strava.pm 15699 2020-02-26 17:15:50Z HomeAuto_User $
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
use HttpUtils;					# um Daten via HTTP auszutauschen https://wiki.fhem.de/wiki/HttpUtils

my $missingModul		= "";
eval "use JSON;1" or $missingModul .= "JSON ";
eval "use Digest::MD5;1" or $missingModul .= "Digest::MD5 ";

##########################
sub Strava_Initialize($) {
	my ($hash) = @_;

	$hash->{DefFn}    =	"Strava_Define";
	$hash->{GetFn}    =	"Strava_Get";
	$hash->{RenameFn} = "Strava_Rename";
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
	return "Cannot define $name device. Perl modul ${missingModul} is missing." if ( $missingModul );

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
	my $setList = "AuthApp_code Client_Secret Client_Secret_delete:noArg";
	$setList.= "Deauth:noArg " if($hash->{helper}{AuthApp} && $hash->{helper}{AuthApp} eq "SUCCESS");
	return "no set value specified" if(int(@a) < 1);

	my $cmd = $a[0];
	my $cmd2 = defined $a[1] ? $a[1] : "";

	Log3 $name, 4, "$typ: Set, $cmd" if ($cmd ne "?");

	if ($cmd eq "AuthApp_code") {
		return "ERROR: $cmd failed argument" if ($cmd2 eq "");

		$hash->{helper}{access_token} = $cmd2;
	}

	if ($cmd eq "Deauth") {
		Strava_Data_exchange($hash,$cmd,undef);
		FW_directNotify("FILTER=room=$FW_room", "#FHEMWEB:$FW_wname", "location.reload('true')", "");
		return undef;
	};
	
	if ($cmd eq "Client_Secret") {
		return "ERROR: $cmd failed argument" if ($cmd2 eq "");

		my $return = Strava_StoreValue($hash,$cmd,$cmd2);
		return $return;
	}
	
	if ($cmd eq "Client_Secret_delete") {
		my $return = Strava_DeleteValue($hash,"Client_Secret");
		return $return;
	}
	
	return "Unknown argument $cmd, choose one of $setList" if (index($setList, $cmd) == -1);
}

########################## function to all get action
sub Strava_Get($$$@) {
	my ( $hash, $name, $cmd, @a ) = @_;
	my $cmd2 = defined $a[0] ? $a[0] : "";
	my $getlist = "AuthApp:noArg AuthRefresh:noArg Client_Secret:noArg";
	$getlist.= "activity athlete:noArg " if($hash->{helper}{AuthApp} && $hash->{helper}{AuthApp} eq "SUCCESS");
	my $typ = $hash->{TYPE};

	Log3 $name, 4, "$name: Get, $cmd" if ($cmd ne "?");

	if ($cmd eq "AuthApp" || $cmd eq "AuthRefresh" || $cmd eq "activity" || $cmd eq "Deauth") {
		## !!! only test, data must encrypted and not plain text !!! ##
		return "Some attributes failed! You need Client_ID, Client_Secret, Refresh_Token" 
		if(!AttrVal($name, "Client_ID", undef) || !AttrVal($name, "Client_Secret", undef) ||
			 !AttrVal($name,"Refresh_Token",undef));
	}

	if ($cmd eq "activity") {
		Strava_Data_exchange($hash,$cmd,$cmd2);
		return undef;
	};

	if ($cmd eq "athlete") {
		Strava_Data_exchange($hash,$cmd,undef);
		return undef;
	};

	if ($cmd eq "AuthApp") {
		my $return = Strava_Data_exchange($hash,$cmd,undef);
		return $return;
	};

	if ($cmd eq "AuthRefresh") {
		Strava_Data_exchange($hash,$cmd,undef);
		return undef; 
	};
	
	if ($cmd eq "Client_Secret") {
		my $return = Strava_ReadValue($hash,$cmd);
		return $return;
	};

	return "Unknown argument $cmd, choose one of $getlist";
}

########################## ########################## ##########################
sub Strava_Data_exchange($$$) {
	my ($hash,$cmd,$cmd2) = @_;
	my $access_token = $hash->{helper}{access_token} ? $hash->{helper}{access_token} : "";
	my $datahash;
	my $name = $hash->{NAME};
	my $state;
	my $typ = $hash->{TYPE};
	my $url;
	my $Client_ID = AttrVal($name, "Client_ID", undef);

  Log3 $name, 4, "$name: Data_exchange, was calling with command $cmd";

#### all data parameters ####
	if ($cmd eq "AuthApp") { # https://developers.strava.com/docs/authentication/#oauthoverview
		Log3 $name, 4, "$name: Data_exchange - $cmd parameters are loaded";
		my $callback = "http://localhost/exchange_token";
		# https://developers.strava.com/docs/authentication/#detailsaboutrequestingaccess
		# Todo, for user one attribut ???
		my $scope = "read,read_all,profile:read_all,activity:read_all";
		$url = "https://www.strava.com/oauth/authorize?response_type=code&client_id=".$Client_ID."&scope=".$scope."&redirect_uri=".$callback;

		Log3 $name, 4, "$name: Data_exchange - $cmd POST ".$url;

		$datahash = {	url        => "https://www.strava.com/api/v3/oauth/token",
									method     => "POST",
									timeout    => 10,
									noshutdown => 1,
									data       => {
																	client_id     => $Client_ID,
																	client_secret => AttrVal($name, "Client_Secret", undef),
																	code          => $access_token,
																	grant_type    => 'authorization_code',
																	redirect_uri  => $callback
																},
		};
	}

	if ($cmd eq "AuthRefresh") { # https://developers.strava.com/docs/authentication/#tokenexchange
		$datahash =  {	url        => "https://www.strava.com/api/v3/oauth/token",
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
	}

	if ($cmd eq "Deauth") { # https://developers.strava.com/docs/authentication/#deauthorization
		$url = "https://www.strava.com/api/v3/oauth/token/deauthorize?access_token=".$access_token;
		Log3 $name, 4, "$name: Data_exchange - $cmd POST ".$url;

		$datahash =  {	url        => $url,
										method     => "POST",
										timeout    => 10,
										noshutdown => 1,
		};
	}

	if ($cmd eq "activity") { # https://developers.strava.com/docs/reference/#api-Activities
		## some example ##
		# activities                 - all activities (9 months backwards ??? or always 29 pieces)
		# activities/{id}            - one activity
		# activities/{id}/comments   - one activity comments
		# activities/{id}/kudos      - one activity kudos

		my $activities = $cmd2 ne "" ? "activities/$cmd2" : "activities";
		$url = 'https://www.strava.com/api/v3/'.$activities.'?access_token='.$access_token;
		Log3 $name, 4, "$name: Data_exchange - $cmd GET ".$url;

		$datahash = {	url        => $url,
									method     => "GET",
									timeout    => 10,
									noshutdown => 1,
		};
	}

	if ($cmd eq "athlete") { # https://developers.strava.com/docs/reference/#api-Athletes
		## athlete - statistic to user ##
		Log3 $name, 4, "$name: Data_exchange - $cmd GET ".'https://www.strava.com/api/v3/athlete?access_token='.$access_token;

		$datahash = {	url        => 'https://www.strava.com/api/v3/athlete?access_token='.$access_token,
									method     => "GET",
									timeout    => 10,
									noshutdown => 1,
		};
	}

#### END data parameters ####

	my($err,$data) = HttpUtils_BlockingGet($datahash);
	Log3 $name, 1, "$name: Data_exchange - $cmd error: $err" if ($err ne "");

#### returns ERROR ####
	if ($cmd eq "AuthApp") {
		if ($err ne "" || !defined($data) || $data =~ /Authorization Error/ || $data =~ /Bad Request/) {
			Log3 $name, 4, "$name: Data_exchange - $cmd data: $data" if ($data);
			readingsSingleUpdate( $hash, "state", "$cmd must generates new code with Strava-Login", 1 );

			return "Please Login and authorize for new code!\n\n".
			"steps:\n".
			"1) click on website and Login\n".
			"<a href=$url target=\"_blank\">$url</a>\n".
			"2) copy Code from callback site from adress line [ ... =&code={YOUR CODE}&scope= ... ]\n".
			"3) set Code with 'set $name AuthApp_code'\n".
			"4) please run again 'get $name AuthApp'\n".
			"5) ready to use module";
		}
	}

	if ($cmd eq "AuthRefresh") {
		if ($err ne "" || !defined($data) || $data =~ /Authorization Error/ || $data =~ /not a valid/ || $data =~ /Bad Request/) {
			Log3 $name, 4, "$name: Data_exchange - $cmd data: $data" if ($data);
			$state = "Error: $cmd, no data retrieval";
		}
	}

	if ($cmd eq "Deauth") {
		if ($err ne "" || !defined($data) || $data =~ /Authorization Error/ || $data =~ /not a valid/) {
			Log3 $name, 4, "$name: Data_exchange - $cmd data: $data" if ($data);
			$state = "Error: $cmd, no data retrieval";
		}
	}

	if($cmd eq "activity" || $cmd eq "athlete") {
		if ($err ne "" || !defined($data) || $data =~ /Authorization Error/ || $data =~ /invalid/ || $data =~ /Resource Not Found/) {
			Log3 $name, 4, "$name: Data_exchange - $cmd data: $data" if ($data);

			$state = "Error: $cmd, no data retrieval";
			$state = "Error: $cmd not found" if ($cmd eq "activity" && $data =~ /Record Not Found/);
		}
	}

	## returns ERROR ##
	if ($state) {
		readingsSingleUpdate( $hash, "state", $state, 1 );
		return undef;
	}
#### END returns ERROR ####

  my $json = eval { JSON::decode_json($data) };

  if($@) {
		Log3 $name, 1, "$name: Data_exchange, $cmd - JSON ERROR: $data";
		return undef;
  }

  Log3 $name, 5, "$name: Data_exchange, $cmd - SUCCESS: $data";

#### informations & action ####

	if ($cmd eq "AuthApp") {
		$hash->{helper}{AuthApp} = "SUCCESS";
		$hash->{_AuthApp_access_token} = $json->{access_token} if(defined($json->{access_token})); ## for test
		$hash->{helper}{access_token} = $json->{access_token} if(defined($json->{access_token}));
		$hash->{helper}{AuthApp_expires_at} = $json->{expires_at} if(defined($json->{expires_at}));
	}

	if ($cmd eq "AuthRefresh") {
		$hash->{_AuthRefresh_access_token} = $json->{access_token} if(defined($json->{access_token}));   ## for test

		$hash->{token_expires_at} = FmtDateTime($json->{expires_at}) if(defined($json->{expires_at}));
		$hash->{helper}{AuthRefresh_expires_at} = $json->{expires_at} if(defined($json->{expires_at}));
		$hash->{helper}{access_token} = $json->{access_token} if(defined($json->{access_token}));
		$hash->{helper}{AuthRefresh_refresh_toke} = $json->{refresh_toke} if(defined($json->{refresh_toke}));	

		#InternalTimer(gettimeofday()+$json->{expires_in}-60, "Strava_AuthRefresh", $hash, 0);
	}

	if ($cmd eq "Deauth") {
		## delete helpers ##
		foreach my $value (qw( AuthApp AuthApp_expires_at AuthRefresh_expires_at access_token )) {
			delete $hash->{helper}{$value} if(defined($hash->{helper}{$value}));
		}

		## delete some internals ##
		foreach my $value (qw( token_expires_at )) {
			delete $hash->{$value} if(defined($hash->{$value}));
		}		
	}

	readingsSingleUpdate( $hash, "state", "$cmd accomplished", 1 );

#### END informations & action ####

	return undef;
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

	foreach my $value (qw( AuthApp AuthApp_expires_at AuthRefresh_expires_at AuthRefresh_refresh_toke access_token )) {
		delete $hash->{helper}{$value} if(defined($hash->{helper}{$value}));
	}
	return undef;
}

##########################
sub Strava_Rename(@) {
	my ( $new, $old ) = @_;
	my $hash = $defs{$new};

	Log3 $hash->{NAME}, 3, "$hash->{NAME}: Rename $old to $new";

	## need FIX, after rename value not found ##
	## value from read is undefind !!!
	Log3 $hash->{NAME}, 3, "$hash->{NAME}: ".Strava_ReadValue($hash,"Client_ID");

	Strava_StoreValue( $hash, "Client_ID", Strava_ReadValue($hash,"Client_ID") ); ## NEED FIX ##
	setKeyValue( $hash->{TYPE} . "_" . $old . "_Client_ID", undef );
	return undef;
}

##########################
sub Strava_StoreValue($$$) {
	my ( $hash, $valuename, $value ) = @_;
	my $name    = $hash->{NAME};
	my $type    = $hash->{TYPE};
	my $index   = $type . "_" . $name . "_$valuename";
	my $key     = getUniqueId() . $index;
	my $enc_val = "";

	if ( eval "use Digest::MD5;1" ) {
		$key  = Digest::MD5::md5_hex( unpack "H*", $key );
		$key .= Digest::MD5::md5_hex($key);
	}

	for my $char ( split //, $value ) {
		my $encode = chop($key);
		$enc_val .= sprintf( "%.2x", ord($char) ^ ord($encode) );
		$key = $encode . $key;
	}

	my $err = setKeyValue( $index, $enc_val );
	return "ERROR: while saving $valuename - $err" if ( defined($err) );
	return "$valuename successfully saved";
}

##########################
sub Strava_ReadValue($$) {
	my ($hash, $valuename) = @_;
	my $name   = $hash->{NAME};
	my $index  = $hash->{TYPE} . "_" . $hash->{NAME} . "_$valuename";
	my $key    = getUniqueId() . $index;
	my ( $value, $err );

	Log3 $name, 4, "$name: ReadValue - Read $valuename from file";

	( $err, $value ) = getKeyValue($index);

	if ( defined($err) ) {
		Log3 $name, 3, "$name: ReadValue - unable to read $valuename from file: $err";
		return undef;
	}

	if ( defined($value) ) {
		if ( eval "use Digest::MD5;1" ) {
			$key = Digest::MD5::md5_hex( unpack "H*", $key );
			$key .= Digest::MD5::md5_hex($key);
		}

		my $dec_val = '';

		for my $char ( map { pack( 'C', hex($_) ) } ( $value =~ /(..)/g ) ) {
			my $decode = chop($key);
			$dec_val .= chr( ord($char) ^ ord($decode) );
			$key = $decode . $key;
		}
		return $dec_val;

	} else {
		Log3 $name, 3, "$name: ReadValue - No $valuename in file";
		return undef;
	}
}

##########################
sub Strava_DeleteValue($$) {
	my ($hash, $valuename) = @_;
	setKeyValue( $hash->{TYPE} . "_" . $hash->{NAME} . "_$valuename", undef );
	return "delete";
}

####################################################
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