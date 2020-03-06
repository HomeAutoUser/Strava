#################################################################
# $Id: 88_Strava.pm 15699 2020-03-06 18:59:50Z HomeAuto_User $
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
use HttpUtils;

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
											"$readingFnAttributes";
}

##########################
sub Strava_Define($$) {
	my ($hash, $def) = @_;
	my @arg = split("[ \t][ \t]*", $def);
	my $name = $arg[0];
	my $typ = $hash->{TYPE};
	my $filelogName = "FileLog_$name";
	my ($autocreateFilelog, $autocreateHash, $autocreateName, $autocreateDeviceRoom, $autocreateWeblinkRoom) = ('%L' . $name . '-%Y-%m.log', undef, 'autocreate', $typ, $typ);
	my ($cmd, $ret);

	return "Usage: define <name> $name Client_ID"  if(@arg != 3);
	return "Cannot define $name device. PERL packages ${missingModul} is missing." if ( $missingModul );

	if ($init_done) {
		if (!defined(AttrVal($autocreateName, "disable", undef)) && !exists($defs{$filelogName})) {
			### create FileLog ###
			$autocreateFilelog = AttrVal($autocreateName, "filelog", undef) if (defined AttrVal($autocreateName, "filelog", undef));
			$autocreateFilelog =~ s/%NAME/$name/g;
			$cmd = "$filelogName FileLog $autocreateFilelog $name";
			Log3 $filelogName, 2, "$name: define $cmd";
			$ret = CommandDefine(undef, $cmd);
			if($ret) {
				Log3 $filelogName, 2, "$name: ERROR: $ret";
			} else {
				### Attributes ###
				CommandAttr($hash,"$filelogName room $autocreateDeviceRoom");
				CommandAttr($hash,"$filelogName logtype text");
				CommandAttr($hash,"$name room $autocreateDeviceRoom");
			}
		}

		### Attributes ###
		CommandAttr($hash,"$name room $typ") if (!defined AttrVal($name, "room", undef));
		CommandAttr($hash,"$name event-min-interval .*:300") if (!defined AttrVal($name, "event-min-interval", undef));
		CommandAttr($hash,"$name event-on-change-reading .*") if (!defined AttrVal($name, "event-on-change-reading", undef));
	}

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
	my $setList = "AuthApp_code Client_Secret Client_Secret_delete:noArg Refresh_Token Refresh_Token_delete:noArg";
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

	if ($cmd eq "Client_Secret" || $cmd eq "Refresh_Token") {
		return "ERROR: $cmd failed argument" if ($cmd2 eq "");

		my $return = Strava_StoreValue($hash,$name,$cmd,$cmd2);
		return $return;
	}

	if ($cmd eq "Client_Secret_delete" || $cmd eq "Refresh_Token_delete") {
		$cmd =~ s/_delete//g;
		my $return = Strava_DeleteValue($hash,$cmd);
		return $return;
	}
	
	return "Unknown argument $cmd, choose one of $setList" if (index($setList, $cmd) == -1);
}

########################## function to all get action
sub Strava_Get($$$@) {
	my ( $hash, $name, $cmd, @a ) = @_;
	my $cmd2 = defined $a[0] ? $a[0] : "";
	my $getlist = "AuthApp:noArg AuthRefresh:noArg Client_Secret:noArg Refresh_Token:noArg ";
	$getlist.= "activity athlete:noArg stats:noArg" if($hash->{helper}{AuthApp} && $hash->{helper}{AuthApp} eq "SUCCESS");
	my $typ = $hash->{TYPE};

	Log3 $name, 4, "$name: Get, $cmd" if ($cmd ne "?");

	## check value Client_Secret exists ##
	if ($cmd eq "AuthApp" || $cmd eq "AuthRefresh") {
		foreach my $value (qw( Client_Secret Refresh_Token )) {
			my $return = Strava_ReadValue($hash,$name,$value);

			return "ERROR: necessary $value token failed!\n\nPlease set this token with cmd \"set $name $value\""
			if ($return eq "ERROR: No $value token found");
		}
	}

	if ($cmd eq "activity") {
		Strava_Data_exchange($hash,$cmd,$cmd2);
		return undef;
	};

	if ($cmd eq "athlete") {
		Strava_Data_exchange($hash,$cmd,undef);
		return undef;
	};

	if ($cmd eq "stats") {
		Strava_Data_exchange($hash,$cmd,undef);
		return undef;
	}

	if ($cmd eq "AuthApp") {
		my $return = Strava_Data_exchange($hash,$cmd,undef);
		return $return;
	};

	if ($cmd eq "AuthRefresh") {
		Strava_Data_exchange($hash,$cmd,undef);
		return undef; 
	};

	if ($cmd eq "Client_Secret" || $cmd eq "Refresh_Token") {
		my $return = Strava_ReadValue($hash,$name,$cmd);
		return $return;
	};

	return "Unknown argument $cmd, choose one of $getlist";
}

########################## ########################## ##########################
sub Strava_Data_exchange($$$) {
	my ($hash,$cmd,$cmd2) = @_;
	my $access_token = $hash->{helper}{access_token} ? $hash->{helper}{access_token} : "";
	my $datahash;
	my $method;
	my $name = $hash->{NAME};
	my $state;
	my $typ = $hash->{TYPE};
	my $url;
	my $Client_ID = $hash->{DEF};

	my $Client_Secret = Strava_ReadValue($hash,$name,"Client_Secret");
	my $Refresh_Token = Strava_ReadValue($hash,$name,"Refresh_Token");
	
  Log3 $name, 4, "$name: Data_exchange, was calling with command $cmd";

#### all data parameters ####
	if ($cmd eq "AuthApp") { # https://developers.strava.com/docs/authentication/#oauthoverview
		Log3 $name, 4, "$name: Data_exchange - $cmd parameters are loaded";
		my $callback = "http://localhost/exchange_token";
		# https://developers.strava.com/docs/authentication/#detailsaboutrequestingaccess
		# Todo, for user one attribut ???
		my $scope = "read,read_all,profile:read_all,activity:read_all";
		$url = "https://www.strava.com/oauth/authorize?response_type=code&client_id=".$Client_ID."&scope=".$scope."&redirect_uri=".$callback;
		$method = "POST";

		$datahash = {	url        => "https://www.strava.com/api/v3/oauth/token",
									method     => $method,
									timeout    => 10,
									noshutdown => 1,
									data       => {
																	client_id     => $Client_ID,
																	client_secret => $Client_Secret,
																	code          => $access_token,
																	grant_type    => 'authorization_code',
																	redirect_uri  => $callback
																},
		};
	}

	if ($cmd eq "AuthRefresh") { # https://developers.strava.com/docs/authentication/#tokenexchange
		$url = 'https://www.strava.com/api/v3/oauth/token?client_id='.$Client_ID.'&client_secret='.$Client_Secret.'&grant_type=refresh_token&refresh_token='.$Refresh_Token;
		$method = "POST";

		$datahash =  {	url        => "https://www.strava.com/api/v3/oauth/token",
										method     => $method,
										timeout    => 10,
										noshutdown => 1,
										data       => {
																		client_id     => $Client_ID,
																		client_secret => $Client_Secret,
																		grant_type    => 'refresh_token',
																		refresh_token => $Refresh_Token
																	},
		};
	}

	if ($cmd eq "Deauth") { # https://developers.strava.com/docs/authentication/#deauthorization
		$url = "https://www.strava.com/api/v3/oauth/token/deauthorize?access_token=".$access_token;
		$method = "POST";

		$datahash =  {	url        => $url,
										method     => $method,
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
		$method = "GET";

		$datahash = {	url        => $url,
									method     => $method,
									timeout    => 10,
									noshutdown => 1,
		};
	}

	if ($cmd eq "athlete") { # https://developers.strava.com/docs/reference/#api-Athletes
		## athlete - statistic to user ##
		$url = 'https://www.strava.com/api/v3/athlete?access_token='.$access_token;
		$method = "GET";

		$datahash = {	url        => $url,
									method     => $method,
									timeout    => 10,
									noshutdown => 1,
		};
	}

	if ($cmd eq "stats") { # https://developers.strava.com/docs/reference/#api-Athletes-getStats
		## statistic of user ##
		if (ReadingsVal($name, "athlete_id", undef)) {
			$url = 'https://www.strava.com/api/v3/athletes/'.ReadingsVal($name, "athlete_id", undef).'/stats?access_token='.$access_token;
			$method = "GET";

			$datahash = {	url        => $url,
										method     => $method,
										timeout    => 10,
										noshutdown => 1,
			};
		} else {
			return "ERROR: your athlete_id reading is not found";
		}
	}

#### END data parameters ####

	Log3 $name, 4, "$name: Data_exchange -> $method $url" if ($method);
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

	if ($cmd eq "AuthRefresh" || $cmd eq "Deauth") {
		if ($err ne "" || !defined($data) || $data =~ /Authorization Error/ || $data =~ /not a valid/ || $data =~ /Bad Request/) {
			Log3 $name, 4, "$name: Data_exchange - $cmd data: $data" if ($data);
			$state = "Error: $cmd, no data retrieval";
		}
	}

	if($cmd eq "activity" || $cmd eq "athlete" || $cmd eq "stats") {
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

	readingsBeginUpdate($hash);

	if ($cmd eq "AuthApp") {
		$hash->{_AuthApp_access_token} = $json->{access_token} if(defined($json->{access_token})); ## for test
		$hash->{helper}{AuthApp_expires_at} = $json->{expires_at} if(defined($json->{expires_at}));

		my $athlete_adress = "";
		$athlete_adress.= $json->{athlete}->{country} if(defined($json->{athlete}->{country}));
		$athlete_adress.= ", ".$json->{athlete}->{state} if(defined($json->{athlete}->{state}));
		$athlete_adress.= ", ".$json->{athlete}->{city} if(defined($json->{athlete}->{city}));
		readingsBulkUpdate($hash, "athlete_adress" , $athlete_adress);

		readingsBulkUpdate($hash, "athlete_id" , $json->{athlete}->{id}) if(defined($json->{athlete}->{id}));

		my $athlete_name = "";
		$athlete_name.= $json->{athlete}->{firstname} if(defined($json->{athlete}->{firstname}));
		$athlete_name.= " ".$json->{athlete}->{lastname} if(defined($json->{athlete}->{lastname}));
		$athlete_name.= " (".$json->{athlete}->{sex}.")" if(defined($json->{athlete}->{sex}));
		readingsBulkUpdate($hash, "athlete_name" , $athlete_name);
		
		my $athlete_account = "";
		my $created_at = $json->{athlete}->{created_at} if(defined($json->{athlete}->{created_at})); # 2013-07-22T12:07:10Z
		$created_at = "created: ".substr($created_at,0,10);
		$athlete_account.= $created_at;
		my $updated_at = $json->{athlete}->{updated_at} if(defined($json->{athlete}->{updated_at})); # 2020-02-24T17:14:03Z
		$updated_at = ", updated: ".substr($updated_at,0,10).", ";
		$athlete_account.= $updated_at;
		$athlete_account.= $json->{athlete}->{premium} eq 1 ? "premium" : "no premium" if(defined($json->{athlete}->{premium}));
		readingsBulkUpdate($hash, "athlete_account" , $athlete_account);
	}

	if ($cmd eq "AuthRefresh") {
		$hash->{_AuthRefresh_access_token} = $json->{access_token} if(defined($json->{access_token}));   ## for test
		$hash->{token_expires_at} = FmtDateTime($json->{expires_at}) if(defined($json->{expires_at}));
		$hash->{helper}{AuthRefresh_expires_at} = $json->{expires_at} if(defined($json->{expires_at}));
		$hash->{helper}{AuthRefresh_refresh_toke} = $json->{refresh_toke} if(defined($json->{refresh_toke}));	

		#InternalTimer(gettimeofday()+$json->{expires_in}-60, "Strava_AuthRefresh", $hash, 0);
	}

	if ($cmd eq "AuthApp" || $cmd eq "AuthRefresh") {
		$hash->{helper}{AuthApp} = "SUCCESS" if!($hash->{helper}{AuthApp});	
		$hash->{helper}{access_token} = $json->{access_token} if(defined($json->{access_token}));
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

	if ($cmd eq "athlete") {
		my $athlete_counts;
		$athlete_counts = "friend: " . $json->{friend_count} if(defined($json->{friend_count}));
		$athlete_counts.= " , follower_requests: ".$json->{follower_count} if(defined($json->{follower_count}));
		readingsBulkUpdate( $hash, "athlete_counts", $athlete_counts ) if ($athlete_counts);

		my $athlete_info;
		$athlete_info = "weight: " . $json->{weight} . " , " if(defined($json->{weight}));
		$athlete_info.= "FTP: " . $json->{ftp} ." watt" if(defined($json->{ftp}));
		readingsBulkUpdate( $hash, "athlete_info", $athlete_info ) if ($athlete_info);

		$hash->{helper}{measurement_preference} = $json->{measurement_preference} if(defined($json->{measurement_preference}));
	}

	if ($cmd eq "stats") {
		my $divider = 1;
		my $divider_txt = "";
		if ($hash->{helper}{measurement_preference} && $hash->{helper}{measurement_preference} eq "meters") {
			$divider = 1000;
			$divider_txt = "km";
		}
		## ToDo - Meilen ???

		if(defined($json->{all_ride_totals}->{count}) && $json->{all_ride_totals}->{count} != 0) {
			readingsBulkUpdate( $hash, "ride_all_totals", $json->{all_ride_totals}->{count} );
			readingsBulkUpdate( $hash, "ride_all_distance", (sprintf "%.2f", ($json->{all_ride_totals}->{distance} / $divider)) . " " . $divider_txt ) if(defined($json->{all_ride_totals}->{distance}));
			readingsBulkUpdate( $hash, "ride_all_moving_time", (sprintf "%.2f", ($json->{all_ride_totals}->{moving_time} / 60)) . " minutes" ) if(defined($json->{all_ride_totals}->{moving_time}));
			readingsBulkUpdate( $hash, "ride_all_elevation_gain", $json->{all_ride_totals}->{elevation_gain} . " meters" ) if(defined($json->{all_ride_totals}->{elevation_gain}));
			readingsBulkUpdate( $hash, "ride_biggest_distance", (sprintf "%.2f", ($json->{biggest_ride_distance} / $divider)) . " " . $divider_txt ) if(defined($json->{biggest_ride_distance}));

			readingsBulkUpdate( $hash, "ride_year_all_totals", $json->{ytd_ride_totals}->{count} );
			readingsBulkUpdate( $hash, "ride_year_all_distance", (sprintf "%.2f", ($json->{ytd_ride_totals}->{distance} / $divider)) . " " . $divider_txt ) if(defined($json->{ytd_ride_totals}->{distance}));
			readingsBulkUpdate( $hash, "ride_year_all_moving_time", (sprintf "%.2f", ($json->{ytd_ride_totals}->{moving_time} / 60)) . " minutes" ) if(defined($json->{ytd_ride_totals}->{moving_time}));
			readingsBulkUpdate( $hash, "ride_year_all_elevation_gain", $json->{ytd_ride_totals}->{elevation_gain} . " meters" ) if(defined($json->{ytd_ride_totals}->{elevation_gain}));

			readingsBulkUpdate( $hash, "ride_last4week_all_totals", $json->{recent_ride_totals}->{count} );
			readingsBulkUpdate( $hash, "ride_last4week_all_distance", (sprintf "%.2f", ($json->{recent_ride_totals}->{distance} / $divider)) . " " . $divider_txt ) if(defined($json->{recent_ride_totals}->{distance}));
			readingsBulkUpdate( $hash, "ride_last4week_all_moving_time", (sprintf "%.2f", ($json->{recent_ride_totals}->{moving_time} / 60)) . " minutes" ) if(defined($json->{recent_ride_totals}->{moving_time}));
			readingsBulkUpdate( $hash, "ride_last4week_all_elevation_gain", $json->{recent_ride_totals}->{elevation_gain} . " meters" ) if(defined($json->{recent_ride_totals}->{elevation_gain}));
		};
		
		if(defined($json->{all_run_totals}->{count}) && $json->{all_run_totals}->{count} != 0) {
			readingsBulkUpdate( $hash, "run_all_totals", $json->{all_run_totals}->{count} );
			readingsBulkUpdate( $hash, "run_all_distance", (sprintf "%.2f", ($json->{all_run_totals}->{distance} / $divider)) . " " . $divider_txt ) if(defined($json->{all_run_totals}->{distance}));
			readingsBulkUpdate( $hash, "run_all_moving_time", (sprintf "%.2f", ($json->{all_run_totals}->{moving_time} / 60)) . " minutes" ) if(defined($json->{all_run_totals}->{moving_time}));
			readingsBulkUpdate( $hash, "run_all_elevation_gain", $json->{all_run_totals}->{elevation_gain} . " meters" ) if(defined($json->{all_run_totals}->{elevation_gain}));

			readingsBulkUpdate( $hash, "run_year_all_totals", $json->{ytd_run_totals}->{count} );
			readingsBulkUpdate( $hash, "run_year_all_distance", (sprintf "%.2f", ($json->{ytd_run_totals}->{distance} / $divider)) . " " . $divider_txt ) if(defined($json->{ytd_run_totals}->{distance}));
			readingsBulkUpdate( $hash, "run_year_all_moving_time", (sprintf "%.2f", ($json->{ytd_run_totals}->{moving_time} / 60)) . " minutes" ) if(defined($json->{ytd_run_totals}->{moving_time}));
			readingsBulkUpdate( $hash, "run_year_all_elevation_gain", $json->{ytd_run_totals}->{elevation_gain} . " meters" ) if(defined($json->{ytd_run_totals}->{elevation_gain}));

			readingsBulkUpdate( $hash, "run_last4week_all_totals", $json->{recent_run_totals}->{count} );
			readingsBulkUpdate( $hash, "run_last4week_all_distance", (sprintf "%.2f", ($json->{recent_run_totals}->{distance} / $divider)) . " " . $divider_txt ) if(defined($json->{recent_run_totals}->{distance}));
			readingsBulkUpdate( $hash, "run_last4week_all_moving_time", (sprintf "%.2f", ($json->{recent_run_totals}->{moving_time} / 60)) . " minutes" ) if(defined($json->{recent_run_totals}->{moving_time}));
			readingsBulkUpdate( $hash, "run_last4week_all_elevation_gain", $json->{recent_run_totals}->{elevation_gain} . " meters" ) if(defined($json->{recent_run_totals}->{elevation_gain}));
		}

		if(defined($json->{all_swim_totals}->{count}) && $json->{all_swim_totals}->{count} != 0) {
			readingsBulkUpdate( $hash, "swim_all_totals", $json->{all_swim_totals}->{count} );
			readingsBulkUpdate( $hash, "swim_all_distance", (sprintf "%.2f", ($json->{all_swim_totals}->{distance} / $divider)) . " " . $divider_txt ) if(defined($json->{all_swim_totals}->{distance}));
			readingsBulkUpdate( $hash, "swim_all_moving_time", (sprintf "%.2f", ($json->{all_swim_totals}->{moving_time} / 60)) . " minutes" ) if(defined($json->{all_swim_totals}->{moving_time}));

			readingsBulkUpdate( $hash, "swim_year_all_totals", $json->{ytd_swim_totals}->{count} );
			readingsBulkUpdate( $hash, "swim_year_all_distance", (sprintf "%.2f", ($json->{ytd_swim_totals}->{distance} / $divider)) . " " . $divider_txt ) if(defined($json->{ytd_swim_totals}->{distance}));
			readingsBulkUpdate( $hash, "swim_year_all_moving_time", (sprintf "%.2f", ($json->{ytd_swim_totals}->{moving_time} / 60)) . " minutes" ) if(defined($json->{ytd_swim_totals}->{moving_time}));

			readingsBulkUpdate( $hash, "swim_last4week_all_totals", $json->{recent_swim_totals}->{count} );
			readingsBulkUpdate( $hash, "swim_last4week_all_distance", (sprintf "%.2f", ($json->{recent_swim_totals}->{distance} / $divider)) . " " . $divider_txt ) if(defined($json->{recent_swim_totals}->{distance}));
			readingsBulkUpdate( $hash, "swim_last4week_all_moving_time", (sprintf "%.2f", ($json->{recent_swim_totals}->{moving_time} / 60)) . " minutes" ) if(defined($json->{recent_swim_totals}->{moving_time}));
		}
	}

	readingsBulkUpdate( $hash, "state", "$cmd accomplished" );
	readingsEndUpdate($hash, 1);
#### END informations & action ####

	return undef;
}

########################## function is used to check and modify attributes
sub Strava_Attr() {
	my ($cmd, $name, $attrName, $attrValue) = @_;
	my $hash = $defs{$name};
	my $typ = $hash->{TYPE};

	Log3 $name, 4, "$typ: Attr | Attribute $attrName set to $attrValue" if ($cmd eq "set");
	Log3 $name, 3, "$typ: Attr | Attribute $attrName delete" if ($cmd eq "del");
}

##########################
sub Strava_Undef($$) {
	my ($hash, $arg) = @_;
	my $name = $hash->{NAME};

	RemoveInternalTimer($hash);

	foreach my $value (qw( AuthApp AuthApp_expires_at AuthRefresh_expires_at AuthRefresh_refresh_toke access_token measurement_preference )) {
		delete $hash->{helper}{$value} if(defined($hash->{helper}{$value}));
	}
	return undef;
}

##########################
sub Strava_Rename(@) {
	my ( $new, $old ) = @_;
	my $hash = $defs{$new};

	foreach my $value (qw( Client_Secret Refresh_Token )) {
		my $return = Strava_ReadValue($hash,$old,$value);
		if ($return ne "ERROR: No $value token found") {
			Strava_StoreValue( $hash, $new, $value, Strava_ReadValue($hash,$old,$value) );
			setKeyValue( $hash->{TYPE} . "_" . $old . "_$value", undef );
		}
	}
	return undef;	
}

##########################
sub Strava_StoreValue($$$$) {
	my ( $hash, $name, $cmd, $value ) = @_;
	my $index     = $hash->{TYPE} . "_" . $name . "_$cmd";
	my $key       = getUniqueId() . $index;
	my $enc_value = "";

	if ( eval "use Digest::MD5;1" ) {
	$key  = Digest::MD5::md5_hex( unpack "H*", $key );
	$key .= Digest::MD5::md5_hex($key);
	}

	for my $char ( split //, $value ) {
		my $encode = chop($key);
		$enc_value .= sprintf( "%.2x", ord($char) ^ ord($encode) );
		$key = $encode . $key;
	}

	my $err = setKeyValue( $index, $enc_value );
	return "error while saving the $cmd - $err" if ( defined($err) );

	return "$cmd successfully saved";
}

##########################
sub Strava_ReadValue($$$) {
	my ( $hash, $name , $cmd ) = @_;
	my $index  = $hash->{TYPE} . "_" . $name . "_$cmd";
	my $key    = getUniqueId() . $index;
	my ( $value, $err );

	Log3 $name, 4, "$name: ReadValue - Read $cmd from file";

	( $err, $value ) = getKeyValue($index);

	if ( defined($err) ) {
		Log3 $name, 3,"$name: ReadValue - unable to read $cmd from file: $err";
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
		return "ERROR: No $cmd value found";
	}
}

##########################
sub Strava_DeleteValue($$) {
	my ($hash, $valuename) = @_;
	setKeyValue( $hash->{TYPE} . "_" . $hash->{NAME} . "_$valuename", undef );
	return "$valuename delete";
}

####################################################
# Eval-Rückgabewert für erfolgreiches
# Laden des Moduls
1;


# Beginn der Commandref

=pod
=item [helper|device|command]
=item summary Retrieve the data from his Strava account
=item summary_DE Abrufen der Daten von seinem Strava Account

=begin html

<a name="Strava"></a>
<h3>Strava</h3>
<ul>
	The Strava module is the connection to the <a href="https://www.strava.com/">Strava</a> portal of the same name, which you can use to record and evaluate your activities.<br>
	An account is required for the use and also a registration of the API. The connection is documented <a href="https://developers.strava.com/">here</a>.<br>
	<br>
	To register this API, create yourself under your account -> Settings --> My API - personal <a href="https://www.strava.com/settings/api">access via token</a>.<br>
	The tokens thus assigned should be treated confidentially and you need them to retrieve the data.<br>
	<i><u>It is needed Client_ID / Client_Secret and Refresh_Token.</u></i><br>
	<br><br>

	<b>Define</b><br>
		<ul><code>define &lt;NAME&gt; Strava &lt;Client_ID&gt;</code></ul>

	<br>
	<b>Set</b><br>
		<ul>
		<a name="AuthApp_code"></a>
		<li>AuthApp_code: sets the code that you get as a return for authentication</li><a name=""></a>
		<a name="Client_Secret"></a>
		<li>Client_Secret: sets the Client_Secret, which is necessary</li><a name=""></a>
		<a name="Client_Secret_delete"></a>
		<li>Client_Secret_delete: delete Client_Secret. From now on you will no longer get access.</li><a name=""></a>
		<a name="Refresh_Token"></a>
		<li>Refresh_Token: sets the Refresh_Token, which is necessary</li><a name=""></a>
		<a name="Refresh_Token_delete"></a>
		<li>Refresh_Token_delete: deletes the Refresh_Token. From now on you only have limited access.</li><a name=""></a>
		</ul>

	<br><br>
	<b>Get</b><br>
		<ul>
		<a name="AuthApp"></a>
		<li>AuthApp: Starts and completes authentication for use</li><a name=""></a>
		<a name="AuthRefresh"></a>
		<li>AuthRefresh: gets a new Refresh_Token</li><a name=""></a>
		<a name="Client_Secret"></a>
		<li>Client_Secret: shows the entered Client_ID</li><a name=""></a>
		<a name="Refresh_Token"></a>
		<li>Refresh_Token: shows the entered Refresh_Token</li><a name=""></a>
		</ul>

	<br><br>
	<b>Attribute</b><br>
	<ul><li><a href="#disable">disable</a></li></ul><br>
=end html


=begin html_DE

<a name="Strava"></a>
<h3>Strava</h3>
<ul>
	Das Strava Modul ist die Anbindung zum namensgleichen Portal <a href="https://www.strava.com/">Strava</a> womit man seine Aktivitäten aufzeichnen und auswerten kann.<br>
	Für die Nutzung ist ein Account Vorausetzung und zusätzlich eine Registrierung der API. Die Anbindung ist <a href="https://developers.strava.com/">hier</a> dokumentiert.<br>
	<br>
	Um diese API zu registrieren, erstellen Sie sich unter Ihrem Account -> Einstellungen --> Meine API - einen persönlichen <a href="https://www.strava.com/settings/api">Zugang via Token</a>.<br>
	Die somit zugewiesenen Token sollten Sie vertraulich behandeln und benötigen Sie um die Daten abzurufen.<br>
	<i><u>Benötigt wird die Kunden-ID / Kunden-Geheimfrage und der Aktualisierungs-Token.</u></i><br>
	<br><br>

	<b>Define</b><br>
		<ul><code>define &lt;NAME&gt; Strava &lt;Kunden-ID&gt;</code></ul>

	<br>
	<b>Set</b><br>
		<ul>
		<a name="AuthApp_code"></a>
		<li>AuthApp_code: setzt den Code, welchen man als Return bei der Authentifizierung erhält</li><a name=""></a>
		<a name="Client_Secret"></a>
		<li>Client_Secret: setzt die Kunden-Geheimfrage, welche notwendig ist</li><a name=""></a>
		<a name="Client_Secret_delete"></a>
		<li>Client_Secret_delete: löscht die Kunden-Geheimfrage. Ab sofort erhält man keinen Zugang mehr.</li><a name=""></a>
		<a name="Refresh_Token"></a>
		<li>Refresh_Token: setzt den Aktualisierungs-Token, welcher notwendig ist</li><a name=""></a>
		<a name="Refresh_Token_delete"></a>
		<li>Refresh_Token_delete: löscht den Aktualisierungs-Token. Ab sofort hat man nur noch einen zeitlich beschränken Zugang.</li><a name=""></a>
		</ul>

	<br><br>
	<b>Get</b><br>
		<ul>
		<a name="AuthApp"></a>
		<li>AuthApp: Startet und Vollendet die Authentifizierung zur Nutzung</li><a name=""></a>
		<a name="AuthRefresh"></a>
		<li>AuthRefresh: ruft einen neuen Aktualisierungs-Token ab</li><a name=""></a>
		<a name="Client_Secret"></a>
		<li>Client_Secret: gibt die eingegebene Kunden-ID wieder</li><a name=""></a>
		<a name="Refresh_Token"></a>
		<li>Refresh_Token: gibt den eingegebene Aktualisierungs-Token wieder</li><a name=""></a>
		</ul>

	<br><br>
	<b>Attribute</b><br>
	<ul><li><a href="#disable">disable</a></li></ul><br>

</ul>
=end html_DE

# Ende der Commandref
=cut