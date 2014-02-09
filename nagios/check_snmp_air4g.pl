#!/usr/bin/perl -w

#Imports
use strict;
use Net::SNMP;
use Getopt::Long;

#Constants
my %ERRORS=('OK'=>0,'WARNING'=>1,'CRITICAL'=>2,'UNKNOWN'=>3,'DEPENDENT'=>4);
my @valid_types = ("temperature", "voltage", "sync", "gps", "ms_count", "noise", "utilisation");

# OIDs
my $airspan = "1.3.6.1.4.1.989.1.16";
my $temperature_prefix = "$airspan.1.5.1.5";#Temperature Sensors
my $voltage_prefix = "$airspan.1.7.1.5";#Voltage Sensors
my $sync_prefix = "$airspan.2.7.2.2.1";#1 pps, 10 Mhz Sync Status
my $gps_prefix = "$airspan.2.1.2.2.1";#GPS Lock
my $ms_count = "$airspan.2.9.5.1.1.1";#Subscriber Count
my $noise = "$airspan.2.9.8.1.26.1";#Current Noise Level
my $subframe_prefix = "$airspan.2.9.7.1";#Subframe Utilisation

#Variables
my $o_host              = undef;        # hostname
my $o_community         = undef;        # community
my $o_port              = 161;          # port
my $o_help              = undef;        # want some help ?
my $o_check_type        = "temperature";
my $o_warn              = undef;        # warning level
my $o_crit              = undef;        # critical level
my $o_timeout           = undef;        # Timeout (Default 30)
my $o_perf              = undef;        # Output performance data

# Usage
sub print_usage {
    print "Usage: $0 -H <host> -C <snmp_community>  [-p <port>] [-w <warn level>] [-c <crit level>] -T=[temperature|voltage|sync|gps|ms_count|noise|utilisation] [-f] [-t <timeout>]\n";
}

# Is not numeric
sub isnnum {
  my $num = shift;
  if ( $num =~ /^(\d+\.?\d*)|(^\.\d+)$/ ) { return 0; }
  return 1;
}

# Round
sub round ($$) {
    sprintf "%.$_[1]f", $_[0];
}

# Help
sub help {
   print_usage();
   print <<EOT;
-h, --help
   print this help message
-H, --hostname=HOST
   name or IP address of host to check
-C, --community=COMMUNITY NAME
   community name for the host's SNMP agent
-p, --port=PORT
   SNMP port (Default 161)
-w, --warn=INTEGER
   ms_count: Warning Level if connected stations drop below
   noise: Warning Level for Noise (negative)
   utilisation: Warning Level for Subframe Utilisation (up,down) (%)
-c, --crit=INTEGER
   ms_count: Critical Level if connected stations drop below
   noise: Critical Level for Noise (negative)
   utilisation: Critical Level for Subframe Utilisation (up,down) (%)
-T, --type=STRING
   temperature: Temperature Sensors Alerting
   voltage: Voltage Sensors Alerting
   sync: Synchronization Status Alerting
   gps: GPS Status Alerting
   ms_count: Mobile Station Count
   noise: Current Noise Level
   utilisation: Subframe Utilisation (%)
-f, --perfparse
   Perfparse compatible output
-t, --timeout=INTEGER
   timeout for SNMP in seconds (Default: 30)
EOT
}

# Options parsing
sub check_options {
    Getopt::Long::Configure ("bundling");
    GetOptions(
      'h'     => \$o_help,              'help'          => \$o_help,
      'H:s'   => \$o_host,              'hostname:s'    => \$o_host,
      'p:i'   => \$o_port,              'port:i'        => \$o_port,
      'C:s'   => \$o_community,         'community:s'   => \$o_community,
      't:i'   => \$o_timeout,           'timeout:i'     => \$o_timeout,
      'c:s'   => \$o_crit,              'critical:s'    => \$o_crit,
      'w:s'   => \$o_warn,              'warn:s'        => \$o_warn,
      'f'     => \$o_perf,              'perfparse'     => \$o_perf,
      'T:s'   => \$o_check_type,        'type:s'        => \$o_check_type
    );

    my $T_option_valid = 0;
    foreach (@valid_types) {
                if ($_ eq $o_check_type) {
                        $T_option_valid = 1
                }
    };
    if ( $T_option_valid == 0 ) {
                print "Invalid check type (-T)!\n";
                print_usage();
                exit $ERRORS{"UNKNOWN"}
    }

    if (defined($o_timeout) && (isnnum($o_timeout) || ($o_timeout < 2) || ($o_timeout > 60))) {
                print "Timeout must be >1 and <60 !\n";
                print_usage();
                exit $ERRORS{"UNKNOWN"}
    }

    if (!defined($o_timeout)) {
                $o_timeout=15;
    }

    if (defined ($o_help) ) {
                help();
                exit $ERRORS{"UNKNOWN"}
    };

    if (!defined($o_host)) {
                print_usage();
                exit $ERRORS{"UNKNOWN"}
    }

    if (!defined($o_community)) {
                print "Put snmp community!\n";
                print_usage();
                exit $ERRORS{"UNKNOWN"}
    }

    if ($o_check_type eq "ms_count" || $o_check_type eq "noise" || $o_check_type eq "utilisation") {
	if (!defined($o_warn) || !defined($o_crit)) {
                print "put warning and critical info!\n";
                print_usage();
                exit $ERRORS{"UNKNOWN"}
	}

	if ($o_check_type eq "ms_count" || $o_check_type eq "noise") {
		if (($o_warn =~ /,/) || ($o_crit =~ /,/)) {
			print "Multiple warning/critical levels not available for this check\n";
			print_usage();
			exit $ERRORS{"UNKNOWN"}
		}

	        if (isnnum($o_warn) || isnnum($o_crit)) {
			print "Numeric value for warning or critical !\n";
			print_usage();
			exit $ERRORS{"UNKNOWN"}
		}

		if ($o_warn < $o_crit) {
			print "warning >= critical ! \n";
			print_usage();
			exit $ERRORS{"UNKNOWN"}
		}
	} else {
		if (!($o_warn =~ /,/) || !($o_crit =~ /,/)) {
			print "Specify warning/critical levels in: uplink,downlink\n";
			print_usage();
			exit $ERRORS{"UNKNOWN"}
		}
	}
    }
}

#Main Code

check_options();

$SIG{'ALRM'} = sub {
 print "No answer from host\n";
 exit $ERRORS{"UNKNOWN"};
};

my ($session,$error);
($session, $error) = Net::SNMP->session(
        -hostname  => $o_host,
        -version   => 2,
        -community => $o_community,
        -port      => $o_port,
        -timeout   => $o_timeout
);

if (!defined($session)) {
   printf("ERROR opening session: %s.\n", $error);
   exit $ERRORS{"UNKNOWN"};
}

if ($o_check_type eq "temperature") {
	my @oidlist = ();
	my @sensors = (2,3,4,5,20,21,22,23,24,25);
	my $sensor = undef;
	foreach $sensor(@sensors) {
		push(@oidlist, "$temperature_prefix.$sensor");
	}

#	my $result = (Net::SNMP->VERSION < 4) ? $session->get_request(@oidlist) : $session->get_request(-varbindlist => \@oidlist);
	my $result = $session->get_request(-varbindlist => \@oidlist);
	if (!defined($result)) {
 		printf("ERROR: Description table : %s.\n", $session->error);
		$session->close;
		exit $ERRORS{"UNKNOWN"};
	}
	$session->close;

	my $low = 0;
	my $high = 0;
	my $total = 0;
	my $oid = undef;
	foreach $sensor(@sensors) {
		$oid = "$temperature_prefix.$sensor";

		if (!defined ($$result{$oid})) {
			print "No information : UNKNOWN\n";
			exit $ERRORS{"UNKNOWN"};
		} else {
			if ($$result{$oid} == 2) {
				$low++;
			} elsif ($$result{$oid} == 1) {
				$high++;
			}
		}
		$total++;
	}

	print "Temperature Sensors: ";
	
	my $exit_val=$ERRORS{"OK"};

	if ($high > 0) {
           print "Temperature Too High ($high/$total): CRITICAL";
           $exit_val=$ERRORS{"CRITICAL"};
	} elsif ($low > 0) {
           print "Temperature Too Low ($low/$total): WARNING";
           $exit_val=$ERRORS{"WARNING"};
        } else {
	   print "OK" 
	}

	if (defined($o_perf)) {
                print " | low=$low;high=$high;total=$total\n";
        } else {
                print "\n";
        }

	exit $exit_val;
}

if ($o_check_type eq "voltage") {
	my @oidlist = ();
	my @sensors = (30,31,32,33,34);
	my $sensor = undef;
	foreach $sensor(@sensors) {
		push(@oidlist, "$voltage_prefix.$sensor");
	}

#	my $result = (Net::SNMP->VERSION < 4) ? $session->get_request(@oidlist) : $session->get_request(-varbindlist => \@oidlist);
	my $result = $session->get_request(-varbindlist => \@oidlist);
	if (!defined($result)) {
 		printf("ERROR: Description table : %s.\n", $session->error);
		$session->close;
		exit $ERRORS{"UNKNOWN"};
	}
	$session->close;

	my $low = 0;
	my $high = 0;
	my $oob = 0;
	my $total = 0;
	my $oid = undef;
	foreach $sensor(@sensors) {
		$oid = "$voltage_prefix.$sensor";

		if (!defined ($$result{$oid})) {
			print "No information : UNKNOWN\n";
			exit $ERRORS{"UNKNOWN"};
		} else {
			if ($$result{$oid} == 1) {
				$high++;
			} elsif ($$result{$oid} == 2) {
				$low++;
			} elsif ($$result{$oid} == 3) {
				$oob++;
			}
		}
		$total++;
	}

	print "Voltage Sensors: ";
	
	my $exit_val=$ERRORS{"OK"};

	if ($low > 0) {
           print "Voltage Too Low ($low/$total): CRITICAL";
           $exit_val=$ERRORS{"CRITICAL"};
	} elsif ($high > 0) {
           print "Temperature Too High ($high/$total): WARNING";
           $exit_val=$ERRORS{"WARNING"};
	} elsif ($oob > 0) {
           print "Temperature Out Of Bounds ($oob/$total): UNKNOWN";
           $exit_val=$ERRORS{"UNKNOWN"};
        } else {
	   print "OK" 
	}

	if (defined($o_perf)) {
                print " | low=$low;high=$high;oob=$oob;total=$total\n";
        } else {
                print "\n";
        }

	exit $exit_val;
}

if ($o_check_type eq "sync") {
	my @oidlist = ();
	my @sensors = (3,4,6);
	my $sensor = undef;
	foreach $sensor(@sensors) {
		push(@oidlist, "$sync_prefix.$sensor.1");
	}

#	my $result = (Net::SNMP->VERSION < 4) ? $session->get_request(@oidlist) : $session->get_request(-varbindlist => \@oidlist);
	my $result = $session->get_request(-varbindlist => \@oidlist);
	if (!defined($result)) {
 		printf("ERROR: Description table : %s.\n", $session->error);
		$session->close;
		exit $ERRORS{"UNKNOWN"};
	}
	$session->close;

	my $oid = undef;
	foreach $sensor(@sensors) {
		$oid = "$sync_prefix.$sensor.1";

		if (!defined ($$result{$oid})) {
			print "No information : UNKNOWN\n";
			exit $ERRORS{"UNKNOWN"};
		}
	}

	my $gpspps = $$result{"$sync_prefix.3.1"};
	my $pps = $$result{"$sync_prefix.4.1"};
	my $tenmeg = $$result{"$sync_prefix.6.1"};

	print "Synchronization State: ";
	
	my $exit_val=$ERRORS{"OK"};

	if ($gpspps != 0 || $pps != 1 || $tenmeg != 1) {
           print "Not Synchronized: CRITICAL";
           $exit_val=$ERRORS{"CRITICAL"};
	} else {
	   print "OK" 
	}

	if (defined($o_perf)) {
                print " | ";
		print "GPS 1 pps: ".($gpspps == 0?"OK":$gpspps).";";
		print "1 pps: ".($pps == 1?"OK":$pps).";";
		print "10 MHz: ".($tenmeg == 1?"OK":$tenmeg);
		print "\n";
        } else {
                print "\n";
        }

	exit $exit_val;
}

if ($o_check_type eq "gps") {
	my @oidlist = ();
	my @sensors = (2,3,4);
	my $sensor = undef;
	foreach $sensor(@sensors) {
		push(@oidlist, "$gps_prefix.$sensor.1");
	}

#	my $result = (Net::SNMP->VERSION < 4) ? $session->get_request(@oidlist) : $session->get_request(-varbindlist => \@oidlist);
	my $result = $session->get_request(-varbindlist => \@oidlist);
	if (!defined($result)) {
 		printf("ERROR: Description table : %s.\n", $session->error);
		$session->close;
		exit $ERRORS{"UNKNOWN"};
	}
	$session->close;

	my $oid = undef;
	foreach $sensor(@sensors) {
		$oid = "$gps_prefix.$sensor.1";

		if (!defined ($$result{$oid})) {
			print "No information : UNKNOWN\n";
			exit $ERRORS{"UNKNOWN"};
		}
	}

	my $comm = $$result{"$gps_prefix.2.1"};
	my $lock = $$result{"$gps_prefix.3.1"};
	my $snr = $$result{"$gps_prefix.4.1"};

	print "GPS State: ";
	
	my $exit_val=$ERRORS{"OK"};

	if ($lock == 1 || $snr == 1) {
           print "Signal Degraded: WARNING";
           $exit_val=$ERRORS{"WARNING"};
	} 
	if ($comm > 0 || $lock == 2) {
           print "Not Locked: CRITICAL";
           $exit_val=$ERRORS{"CRITICAL"};
	}
	if ($exit_val == $ERRORS{"OK"}) {
	   print "OK" 
	}

	if (defined($o_perf)) {
                print " | ";
		print "Comm: ".($comm == 0?"OK":$comm).";";
		print "Lock: ".($lock == 0?"OK":$lock).";";
		print "SNR: ".($snr == 0?"OK":$snr);
		print "\n";
        } else {
                print "\n";
        }

	exit $exit_val;
}

if ($o_check_type eq "ms_count") {
	my @oidlist = ();
	push(@oidlist, "$ms_count");

#	my $result = (Net::SNMP->VERSION < 4) ? $session->get_request(@oidlist) : $session->get_request(-varbindlist => \@oidlist);
	my $result = $session->get_request(-varbindlist => \@oidlist);
	if (!defined($result)) {
 		printf("ERROR: Description table : %s.\n", $session->error);
		$session->close;
		exit $ERRORS{"UNKNOWN"};
	}
	$session->close;

	if (!defined ($$result{$ms_count})) {
		print "No information : UNKNOWN\n";
		exit $ERRORS{"UNKNOWN"};
	}

	my $count = $$result{"$ms_count"};

	print "MS Count: ";
	
	my $exit_val=$ERRORS{"OK"};

	if ($count < $o_crit) {
           print "$count < $o_crit: CRITICAL";
           $exit_val=$ERRORS{"CRITICAL"};
	} elsif ($count < $o_warn) {
           print "$count < $o_warn: WARNING";
           $exit_val=$ERRORS{"WARNING"};
	} else {
	   print "$count: OK" 
	}

	if (defined($o_perf)) {
                print " | $count;$o_warn;$o_crit\n";
        } else {
                print "\n";
        }

	exit $exit_val;
}

if ($o_check_type eq "noise") {
	my @oidlist = ();
	push(@oidlist, "$noise");

#	my $result = (Net::SNMP->VERSION < 4) ? $session->get_request(@oidlist) : $session->get_request(-varbindlist => \@oidlist);
	my $result = $session->get_request(-varbindlist => \@oidlist);
	if (!defined($result)) {
 		printf("ERROR: Description table : %s.\n", $session->error);
		$session->close;
		exit $ERRORS{"UNKNOWN"};
	}
	$session->close;

	if (!defined ($$result{$noise})) {
		print "No information : UNKNOWN\n";
		exit $ERRORS{"UNKNOWN"};
	}

	my $current_noise = $$result{"$noise"} / 4;
	
	my $crit = $o_crit * -1;
	my $warn = $o_warn * -1;

	print "Current Noise Level: ";
	
	my $exit_val=$ERRORS{"OK"};

	if ($current_noise > $crit) {
           print "$current_noise > $crit: CRITICAL";
           $exit_val=$ERRORS{"CRITICAL"};
	} elsif ($current_noise > $warn) {
           print "$current_noise > $warn: WARNING";
           $exit_val=$ERRORS{"WARNING"};
	} else {
	   print "$current_noise: OK" 
	}

	if (defined($o_perf)) {
                print " | $current_noise;$warn;$crit\n";
        } else {
                print "\n";
        }

	exit $exit_val;
}

if ($o_check_type eq "utilisation") {
	my $warn_up = 100;
	my $warn_down = 100;
	my $crit_up = 100;
	my $crit_down = 100;

	if ($o_warn =~ /(\d*),(\d*)/) {
		$warn_up = $1;
		$warn_down = $2;
	} else {
		print "Warning must be in format: uplink,downlink (numeric)!\n";
                print_usage();
                exit $ERRORS{"UNKNOWN"};
	}
	if ($o_crit =~ /(\d*),(\d*)/) {
		$crit_up = $1;
		$crit_down = $2;
	} else {
		print "Critical must be in format: uplink,downlink (numeric)!\n";
                print_usage();
                exit $ERRORS{"UNKNOWN"};;
	}

	if ($warn_up > $crit_up) {
		print "Uplink Warning <= Uplink Critical!\n";
                print_usage();
                exit $ERRORS{"UNKNOWN"}
	}

	if ($warn_down > $crit_down) {
		print "Downlink Warning <= Downlink Critical!\n";
                print_usage();
                exit $ERRORS{"UNKNOWN"};
	}

	my @oidlist = ();
	my @sensors = (26,27);
	my $sensor = undef;
	foreach $sensor(@sensors) {
		push(@oidlist, "$subframe_prefix.$sensor.1");
	}

#	my $result = (Net::SNMP->VERSION < 4) ? $session->get_request(@oidlist) : $session->get_request(-varbindlist => \@oidlist);
	my $result = $session->get_request(-varbindlist => \@oidlist);
	if (!defined($result)) {
 		printf("ERROR: Description table : %s.\n", $session->error);
		$session->close;
		exit $ERRORS{"UNKNOWN"};
	}
	$session->close;

	my $oid = undef;
	foreach $sensor(@sensors) {
		$oid = "$subframe_prefix.$sensor.1";

		if (!defined ($$result{$oid})) {
			print "No information : UNKNOWN\n";
			exit $ERRORS{"UNKNOWN"};
		}
	}

	my $uplink = $$result{"$subframe_prefix.26.1"};
	my $downlink = $$result{"$subframe_prefix.27.1"};

	print "Subframe Utilisation:";
	
	my $exit_val=$ERRORS{"OK"};

	if ($uplink > $crit_up || $downlink > $crit_down) {
           print " Uplink: $uplink > $crit_up" if ($uplink > $crit_up);
	   print " Downlink: $downlink > $crit_down" if ($downlink > $crit_down);
	   print ": CRITICAL";
           $exit_val=$ERRORS{"CRITICAL"};


	} elsif ($uplink > $warn_up || $downlink > $warn_down) {
           print " Uplink: $uplink > $warn_up" if ($uplink > $warn_up);
	   print " Downlink: $downlink > $warn_down" if ($downlink > $warn_down);
	   print ": WARNING";
           $exit_val=$ERRORS{"WARNING"};
	} else {
	   print " $uplink% / $downlink%: OK" 
	}

	if (defined($o_perf)) {
                print " | ";
		print "Uplink: $uplink;$warn_up;$crit_up - ";
		print "Downlink: $downlink;$warn_down;$crit_down ";
		print "\n";
        } else {
                print "\n";
        }

	exit $exit_val;
}
