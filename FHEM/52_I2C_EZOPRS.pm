##############################################
# $Id: 52_I2C_EZOPH.pm 9272 2017-04-10 22:31:34 danieljo $
# Based on the I2C_SHT21 Modul from klauswitt
# Thanks to Klaus Witt for help
# working copy for der-lolo
package main;

use strict;
use warnings;

use Time::HiRes qw(usleep);
use Scalar::Util qw(looks_like_number);
#use Error qw(:try);

use constant {
	EZOPRS_I2C_ADDRESS => '0x6A',
};

sub I2C_EZOPRS_Initialize($);
sub I2C_EZOPRS_Define($$);
sub I2C_EZOPRS_Attr(@);
sub I2C_EZOPRS_Poll($);
sub I2C_EZOPRS_Set($@);
sub I2C_EZOPRS_Undef($$);
sub I2C_EZOPRS_DbLog_splitFn($);

my %sets = (
	"readValues" => 1,
	"pressureUnit" => "",
#	"CalibrateReset" => 1,
#	"CalibrateLow" => "",
#	"CalibrateMiddle" => "",
#	"CalibrateHigh" => "",
);

sub I2C_EZOPRS_Initialize($) {
	my ($hash) = @_;

	$hash->{DefFn}    = 'I2C_EZOPRS_Define';
	$hash->{InitFn}   = 'I2C_EZOPRS_Init';
	$hash->{AttrFn}   = 'I2C_EZOPRS_Attr';
	$hash->{SetFn}    = 'I2C_EZOPRS_Set';
	$hash->{UndefFn}  = 'I2C_EZOPRS_Undef';
	$hash->{I2CRecFn} = 'I2C_EZOPRS_I2CRec';
	$hash->{AttrList} = 'IODev do_not_notify:0,1 showtime:0,1 poll_interval:2,5,10,30,60,300,600,1800,3600 ' .
						'DebugLED:on,off ' .
						$readingFnAttributes;
    $hash->{DbLog_splitFn} = "I2C_EZOPRS_DbLog_splitFn";
}

sub I2C_EZOPRS_Define($$) {
	my ($hash, $def) = @_;
	my @a = split('[ \t][ \t]*', $def);

	$hash->{STATE} = "defined";

	if ($main::init_done) {
		eval { I2C_EZOPRS_Init( $hash, [ @a[ 2 .. scalar(@a) - 1 ] ] ); };
		return I2C_EZOPRS_Catch($@) if $@;
	}
	return undef;
}

sub I2C_EZOPRS_Init($$) {
	my ( $hash, $args ) = @_;
	my $name = $hash->{NAME};

	if (defined $args && int(@$args) > 1)
 	{
  	return "Define: Wrong syntax. Usage:\n" .
         	"define <name> I2C_EZOPRS [<i2caddress>]";
 	}

 	if (defined (my $address = shift @$args)) {
   	$hash->{I2C_Address} = $address =~ /^0.*$/ ? oct($address) : $address;
   	return "$name I2C Address not valid" unless ($address < 128 && $address > 3);
 	} else {
		$hash->{I2C_Address} = hex(EZOPRS_I2C_ADDRESS);
	}

	my $msg = '';
	if (AttrVal($name, 'poll_interval', '?') eq '?') {
    	$msg = CommandAttr(undef, $name . ' poll_interval 5');
    	if ($msg) {
      		Log3 ($hash, 1, $msg);
      		return $msg;
    	}
	}
	AssignIoPort($hash);
	$hash->{STATE} = 'Initialized';
	return undef;
}

sub I2C_EZOPRS_Catch($) {
	my $exception = shift;
	if ($exception) {
    $exception =~ /^(.*)( at.*FHEM.*)$/;
    return $1;
	}
	return undef;
}

sub I2C_EZOPRS_Attr (@) {
	my ($command, $name, $attr, $val) =  @_;
	my $hash = $defs{$name};
	my $msg = '';
	if ($command && $command eq "set" && $attr && $attr eq "IODev") {
		if ($main::init_done and (!defined ($hash->{IODev}) or $hash->{IODev}->{NAME} ne $val)) {
			main::AssignIoPort($hash,$val);
			my @def = split (' ',$hash->{DEF});
			I2C_EZOPRS_Init($hash,\@def) if (defined ($hash->{IODev}));
		}
	}
	if ($attr eq 'poll_interval') {

		if ($val > 0) {
			RemoveInternalTimer($hash);
			InternalTimer(1, 'I2C_EZOPRS_Poll', $hash, 0);
		} else {
			$msg = 'Wrong poll intervall defined. poll_interval must be a number > 0';
		}
	}
	if ($attr eq 'DebugLED') {
		if ($val eq "on" or $val eq "off") {
			I2C_Set_PRSDebugLED($hash,$val);
			Log3 $hash, 5, "$hash->{NAME}: set attr DebugLED:";
		} else {
			$msg = "$hash->{NAME}: Wrong $attr value. Use on or off";
		}
	}
	return ($msg) ? $msg : undef;
}

sub I2C_EZOPRS_Poll($) {
	my ($hash) =  @_;
	my $name = $hash->{NAME};

	I2C_EZOPRS_Set($hash, ($name, "readValues"));

	my $pollInterval = AttrVal($hash->{NAME}, 'poll_interval', 0);
	if ($pollInterval > 0) {
		InternalTimer(gettimeofday() + $pollInterval, 'I2C_EZOPRS_Poll', $hash, 0);
	}
}

sub I2C_EZOPRS_Set($@) {
	my ($hash, @a) = @_;
	my $name = $a[0];
	my $cmd =  $a[1];
	my $val = $a[2];

	if(!defined($sets{$cmd})) {
		return 'Unknown argument ' . $cmd . ', choose one of ' . join(' ', keys %sets)
	}

	if ($cmd eq "readValues") {
		I2C_EZOPRS_readpressure($hash);
	}
	if ($cmd eq "pressureUnit") {
		I2C_SET_PRSUNITSET($hash,$val);
	}
#	if ($cmd eq "CalibrateReset") {
#		I2C_SET_PRSTCALRESET($hash);
#	}
#	if ($cmd eq "CalibrateLow") {
#		I2C_SET_PRSCALLOW($hash,$val);
#	}
#	if ($cmd eq "CalibrateMiddle") {
#		I2C_SET_PRSCALMID($hash,$val);
#	}
#	if ($cmd eq "CalibrateHigh") {
#		I2C_SET_PRSCALHIGH($hash,$val);
#	}
}

sub I2C_EZOPRS_Undef($$) {
	my ($hash, $arg) = @_;

	RemoveInternalTimer($hash);
	return undef;
}

sub I2C_EZOPRS_I2CRec ($$) {
	my ($hash, $clientmsg) = @_;
	my $name = $hash->{NAME};
	my $phash = $hash->{IODev};
	my $pname = $phash->{NAME};
	while ( my ( $k, $v ) = each %$clientmsg ) { 	#erzeugen von Internals fuer alle Keys in $clientmsg die mit dem physical Namen beginnen
		$hash->{$k} = $v if $k =~ /^$pname/ ;
	}

    if ( $clientmsg->{direction} && $clientmsg->{$pname . "_SENDSTAT"} && $clientmsg->{$pname . "_SENDSTAT"} eq "Ok" ) {
    	if ( $clientmsg->{direction} eq "i2cread" && defined($clientmsg->{received}) ) {
	    	Log3 $hash, 5, "empfangen: $clientmsg->{received}";
        	my $raw = $clientmsg->{received};
			my @ascii = split(" ", $raw);
			my $erster = shift(@ascii);
			my $new = pack("C*", @ascii);
			$new =~ s/\0+$//;
			my @split1 = split(",", $new);

			readingsBeginUpdate($hash);
			readingsBulkUpdate($hash,'state','S: ' . $erster . ' bar: ' . $split1[0]);
			readingsBulkUpdate($hash, 'bar', $split1[0]);
			readingsBulkUpdate($hash, 'Status', $erster);
			readingsEndUpdate($hash, 1);
        }
    }
}

sub I2C_EZOPRS_readpressure($) {
	my ($hash) = @_;
	my $name = $hash->{NAME};
  	return "$name: no IO device defined" unless ($hash->{IODev});
  	my $phash = $hash->{IODev};
    my $pname = $phash->{NAME};

	# Schreibe 0x52. Lˆst ein Messung aus
	my $i2creq = { i2caddress => $hash->{I2C_Address}, direction => "i2cwrite" };
    $i2creq->{data} = hex("52"); # Sende "R" = 0x52
	CallFn($pname, "I2CWrtFn", $phash, $i2creq);
	usleep(1000000); # Warte 1 Sekunde bis Messung abgeschlossen ist.

	# Lesen des 14 Byte Strings
	my $i2cread = { i2caddress => $hash->{I2C_Address}, direction => "i2cread" };
    $i2cread->{nbyte} = 14;
	$i2cread->{type} = "bar";
	CallFn($pname, "I2CWrtFn", $phash, $i2cread);

	return;
}

sub I2C_Set_PRSDebugLED($) {
	my ($hash,$val) = @_;
	my $name = $hash->{NAME};
  	return "$name: no IO device defined" unless ($hash->{IODev});
  	my $phash = $hash->{IODev};
    my $pname = $phash->{NAME};
	my $lev = $val eq "on" ? 1 : $val eq "off" ? 0 : return;

	my $debugled = "L,".$lev;  # L,0 -> Debug LED aus ; L,1 -> Debug LED an
	my @debugledascii = unpack("c*", $debugled); # Wandle String nach ASCII um
	my $asciistring = join(" ",@debugledascii);

	my $i2creq = { i2caddress => $hash->{I2C_Address}, direction => "i2cwrite" };
    $i2creq->{data} = $asciistring;
	CallFn($pname, "I2CWrtFn", $phash, $i2creq);

	readingsSingleUpdate($hash,"Set_DebugLED", $debugled, 1);

	return;
}

sub I2C_SET_PRSUNITSET($) {
	my ($hash,$val) = @_;
	my $name = $hash->{NAME};
  	return "$name: no IO device defined" unless ($hash->{IODev});
  	my $phash = $hash->{IODev};
    my $pname = $phash->{NAME};

	my $pressureUnitSet = "U,".$val;
	my @pressureunitascii = unpack("c*", $pressureUnitSet); # Wandle String nach ASCII um
	my $asciistring = join(" ",@pressureunitascii);

	my $i2creq = { i2caddress => $hash->{I2C_Address}, direction => "i2cwrite" };
    $i2creq->{data} = $asciistring;
	CallFn($pname, "I2CWrtFn", $phash, $i2creq);
	usleep(300000); # Warte 0,3 Sekunden bis Messung abgeschlossen ist.

	readingsSingleUpdate($hash,"pressureUnit", $val, 1);

	return;
}

#sub I2C_SET_PRSTCALRESET($) {
#	my ($hash) = @_;
#	my $name = $hash->{NAME};
#  	return "$name: no IO device defined" unless ($hash->{IODev});
#  	my $phash = $hash->{IODev};
#    my $pname = $phash->{NAME};

#	my $phcalreset = "Cal,clear";
#	my @phcalresetascii = unpack("c*", $phcalreset); # Wandle String nach ASCII um
#	my $asciistring = join(" ",@phcalresetascii);

#	my $i2creq = { i2caddress => $hash->{I2C_Address}, direction => "i2cwrite" };
#    $i2creq->{data} = $asciistring;
#	CallFn($pname, "I2CWrtFn", $phash, $i2creq);
#	usleep(300000); # Warte 0,3 Sekunden bis Messung abgeschlossen ist.

#	readingsSingleUpdate($hash,"Set_pHCalReset", $phcalreset, 1);

#	return;
#}

#sub I2C_SET_PRSCALLOW($) {
#	my ($hash,$val) = @_;
#	my $name = $hash->{NAME};
#  	return "$name: no IO device defined" unless ($hash->{IODev});
#  	my $phash = $hash->{IODev};
#    my $pname = $phash->{NAME};

#	my $phcallow = "Cal,low,".$val;
#	my @phcallowascii = unpack("c*", $phcallow); # Wandle String nach ASCII um
#	my $asciistring = join(" ",@phcallowascii);

#	my $i2creq = { i2caddress => $hash->{I2C_Address}, direction => "i2cwrite" };
#    $i2creq->{data} = $asciistring;
#	CallFn($pname, "I2CWrtFn", $phash, $i2creq);
#	usleep(1300000); # Warte 1,3 Sekunden bis Messung abgeschlossen ist.

#	readingsSingleUpdate($hash,"Set_pHCalLow", $phcallow, 1);

#	return;
#}

#sub I2C_SET_PRSCALMID($) {
#	my ($hash,$val) = @_;
#	my $name = $hash->{NAME};
#  	return "$name: no IO device defined" unless ($hash->{IODev});
#  	my $phash = $hash->{IODev};
#    my $pname = $phash->{NAME};

#	my $phcalmid = "Cal,mid,".$val;
#	my @phcalmidascii = unpack("c*", $phcalmid); # Wandle String nach ASCII um
#	my $asciistring = join(" ",@phcalmidascii);

#	my $i2creq = { i2caddress => $hash->{I2C_Address}, direction => "i2cwrite" };
#    $i2creq->{data} = $asciistring;
#	CallFn($pname, "I2CWrtFn", $phash, $i2creq);
#	usleep(1300000); # Warte 1,3 Sekunden bis Messung abgeschlossen ist.

#	readingsSingleUpdate($hash,"Set_pHCalMid", $phcalmid, 1);

#	return;
#}

#sub I2C_SET_PRSCALHIGH($) {
#	my ($hash,$val) = @_;
#	my $name = $hash->{NAME};
#  	return "$name: no IO device defined" unless ($hash->{IODev});
#  	my $phash = $hash->{IODev};
#    my $pname = $phash->{NAME};

#	my $phcalhigh = "Cal,high,".$val;
#	my @phcalhighascii = unpack("c*", $phcalhigh); # Wandle String nach ASCII um
#	my $asciistring = join(" ",@phcalhighascii);

#	my $i2creq = { i2caddress => $hash->{I2C_Address}, direction => "i2cwrite" };
#    $i2creq->{data} = $asciistring;
#	CallFn($pname, "I2CWrtFn", $phash, $i2creq);
#	usleep(1300000); # Warte 1,3 Sekunden bis Messung abgeschlossen ist.

#	readingsSingleUpdate($hash,"Set_pHCalHigh", $phcalhigh, 1);

#	return;
#}

sub I2C_EZOPRS_DbLog_splitFn($) {
    my ($event) = @_;
    Log3 undef, 5, "in DbLog_splitFn empfangen: $event";
    my ($reading, $value, $unit) = "";
    my @parts = split(/ /,$event);
    $reading = shift @parts;
    $reading =~ tr/://d;
    $value = $parts[0];
    $unit = "" if(lc($reading) =~ m/pH/);
    return ($reading, $value, $unit);
}

1;
