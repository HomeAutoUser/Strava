#################################################################
# $Id: 88_Strava.pm 15699 2017-12-26 21:17:50Z HomeAuto_User $
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
											"Client_ID Client_Secret Login Password";
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
	my $getlist = "Data:noArg ";
	my $typ = $hash->{TYPE};

	Log3 $name, 3, "$typ: Get, $cmd" if ($cmd ne "?");

	if ($cmd eq "Data") {
		## !!! only test, data must encrypted and not plain text !!! ##
		return "Some attributes failed! You need Client_ID, Client_Secret, Login, Password" 
		if(!AttrVal($name, "Login", undef) || !AttrVal($name, "Password", undef) || 
			 !AttrVal($name, "Client_ID", undef) || !AttrVal($name, "Client_Secret", undef));

		Strava_GetToken($hash);
		return undef;
	};

	return "Unknown argument $cmd, choose one of $getlist";
}

########################## 
## http://developers.strava.com/docs/reference/
## https://developers.strava.com/docs/
## https://developers.strava.com/docs/authentication/
## https://developers.strava.com/playground/#/Athletes/getStats
#+ https://community.home-assistant.io/t/some-strava-sensors/25901
#+ https://loganrouleau.com/blog/2018/11/27/navigating-strava-api-authentication/
#+ https://stackoverflow.com/questions/52880434/problem-with-access-token-in-strava-api-v3-get-all-athlete-activities
#+ https://yizeng.me/2017/01/11/get-a-strava-api-access-token-with-write-permission/

sub Strava_GetToken($) {
  my ($hash) = @_;
	my $typ = $hash->{TYPE};
	my $name = $hash->{NAME};

	## !!! only test, data must encrypted and not plain text !!! ##
	my $Client_ID = AttrVal($name, "Client_ID", undef);
	my $Client_Secret = AttrVal($name, "Client_Secret", undef);
	my $Login = AttrVal($name, "Login", undef);
	my $Password = AttrVal($name, "Password", undef);

	# 1) Anfrage GET mit Kunden-ID, nicht athlete_id -->
	# 2) Eingabe Login Daten
	# 3) Return Browser nach authentication (with code)
	# 4) Absetzen POST
	# 5) Return Information

  my($err,$data) = HttpUtils_BlockingGet({
    url => "https://www.strava.com/oauth/authorize",
    timeout => 5,
    noshutdown => 1,
    data => {
							client_id       => $Client_ID,
							client_secret   => $Client_Secret,
							password        => $Password,
							scope           => 'read_all',
							username        => $Login,
							redirect_uri    => 'localhost',
							response_type   => 'code'
						},
  });

	return undef if(!defined($data));

  if($err) {
		Log3 $name, 3, "$name: GetToken, ERROR: $err";
    return undef;
  }

	readingsSingleUpdate( $hash, "HTTP_response", $data, 1 );
	readingsSingleUpdate( $hash, "state", "HTTP information received", 1 );
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