#################################################################
# $Id: 88_Strava.pm 15699 2020-02-23 23:37:50Z HomeAuto_User $
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
	my $setList = "";
	return "no set value specified" if(int(@a) < 1);

	my $cmd = $a[0];
	Log3 $name, 3, "$typ: Set, $cmd" if ($cmd ne "?");

	return "Unknown argument $cmd, choose one of $setList" if (index($setList, $cmd) == -1);
}

########################## function to all get action
sub Strava_Get($$$@) {
	my ( $hash, $name, $cmd, @a ) = @_;
	my $cmd2 = defined $a[0] ? $a[0] : "";
	my $getlist = "AuthApp:noArg AuthRefresh:noArg";
	my $typ = $hash->{TYPE};

	Log3 $name, 3, "$typ: Get, $cmd" if ($cmd ne "?");

	if ($cmd eq "AuthApp" || $cmd eq "AuthRefresh") {
		## !!! only test, data must encrypted and not plain text !!! ##
		return "Some attributes failed! You need Client_ID, Client_Secret, Login, Password" 
		if(!AttrVal($name, "Login", undef) || !AttrVal($name, "Password", undef) || 
			 !AttrVal($name, "Client_ID", undef) || !AttrVal($name, "Client_Secret", undef) ||
			 !AttrVal($name,"Refresh_Token",undef));
	}

	if ($cmd eq "AuthApp") {
		Strava_AuthApp($hash);
		return undef;
	};

	if ($cmd eq "AuthRefresh") {
		Strava_AuthRefresh($hash);
		return undef;
	};

	return "Unknown argument $cmd, choose one of $getlist";
}

########################## 
## http://developers.strava.com/docs/reference/
## https://developers.strava.com/docs/
#+ https://developers.strava.com/docs/authentication/
## https://developers.strava.com/playground/#/Athletes/getStats
#+ https://community.home-assistant.io/t/some-strava-sensors/25901
#+ https://loganrouleau.com/blog/2018/11/27/navigating-strava-api-authentication/
#+ https://stackoverflow.com/questions/52880434/problem-with-access-token-in-strava-api-v3-get-all-athlete-activities
#+ https://yizeng.me/2017/01/11/get-a-strava-api-access-token-with-write-permission/

sub Strava_AuthApp($) {
	my ($hash) = @_;
	my $typ = $hash->{TYPE};
	my $name = $hash->{NAME};

	## !!! only test, data must encrypted and not plain text !!! ##
	my $Client_ID = AttrVal($name, "Client_ID", undef);
	my $Client_Secret = AttrVal($name, "Client_Secret", undef);
	my $Code = AttrVal($name, "Code", undef);
	my $Login = AttrVal($name, "Login", undef);
	my $Password = AttrVal($name, "Password", undef);
	my $cb = "http://localhost/exchange_token";

	# 1) Anfrage GET mit Kunden-ID, nicht athlete_id -->
	# 2) Eingabe Login Daten
	# 3) Return Browser nach authentication (with code)
	# 4) Absetzen POST
	# 5) Return Information

	## https://www.strava.com/oauth/authorize?client_id=08153311&response_type=code&redirect_uri=http://localhost/exchange_token&approval_prompt=force&scope=read_all
	my $url = "https://www.strava.com/oauth/authorize?response_type=code&client_id=".$Client_ID."&scope=read_all&redirect_uri=".$cb;

	my $datahash = {
		url        => "https://www.strava.com/oauth/token",
		method     => "POST",
		timeout    => 10,
		noshutdown => 1,
		data       => { 
										client_id     => $Client_ID,
										client_secret => $Client_Secret,
										code          => $Code,
										grant_type    => 'authorization_code',
										redirect_uri  => $cb
									},
	};

	my($err,$data) = HttpUtils_BlockingGet($datahash);
	$err = $err eq "" ? "none" : $err;

	readingsSingleUpdate( $hash, "HTTP_error", $err, 1 );
	readingsSingleUpdate( $hash, "HTTP_response", $data, 1 );
	readingsSingleUpdate( $hash, "HTTP_url", $url, 1 );
	readingsSingleUpdate( $hash, "state", "AuthApp information", 1 );
}

##########################
sub Strava_AuthRefresh($) {
  my ($hash) = @_;
	my $typ = $hash->{TYPE};
	my $name = $hash->{NAME};

	## !!! only test, data must encrypted and not plain text !!! ##
	my $Client_ID = AttrVal($name, "Client_ID", undef);
	my $Client_Secret = AttrVal($name, "Client_Secret", undef);
	my $Login = AttrVal($name, "Login", undef);
	my $Password = AttrVal($name, "Password", undef);
	my $ref = AttrVal($name,'Refresh_Token','');
	my $cb = "http://localhost/exchange_token";

	my $datahash = {
										url => "https://www.strava.com/oauth/token",
										method => "POST",
										timeout => 10,
										noshutdown => 1,
										data => { 
															client_id     => $Client_ID,
															client_secret => $Client_Secret,
															grant_type    => 'refresh_token',
															refresh_token => $ref
														},
	};

	my($err,$data) = HttpUtils_BlockingGet($datahash);
	$err = $err eq "" ? "none" : $err;

	readingsSingleUpdate( $hash, "HTTP_error", $err, 1 );
	readingsSingleUpdate( $hash, "HTTP_response", $data, 1 );
	readingsSingleUpdate( $hash, "state", "AuthRefresh information", 1 );
}
########################## function is used to check and modify attributes
sub Strava_Attr() {
	my ($cmd, $name, $attrName, $attrValue) = @_;
	my $hash = $defs{$name};
	my $typ = $hash->{TYPE};
	
	Log3 $name, 3, "$typ: Attr | Attributes $attrName = $attrValue";
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
<h3>example web modul</h3>
<ul>
This is an example web module.<br>
</ul>
=end html


=begin html_DE

<a name="Strava"></a>
<h3>Strava Modul</h3>
<ul>
Das ist ein Strava Modul.<br>
</ul>
=end html_DE

# Ende der Commandref
=cut