#!/usr/bin/perl -w

# Imports
use strict;
use Net::SNMP;
use Getopt::Long;

# Constants
my %ERRORS = ('OK'=>0, 'WARNING'=>1, 'CRITICAL'=>2, 'UNKNOWN'=>3, 'DEPENDENT'=>4);
my @valid_types = ("tx_power", "hss_sync_state", "hss_ext_pulse", "hbs_state", "hbs_free_slots", "hsu_link_state", "hsu_rss", "hsu_rss_balance", "hsu_bandwidth");

# OIDs
my $oid_winlink1000 = "1.3.6.1.4.1.4458.1000";
my $oid_winlink1000OduAir = $oid_winlink1000.".1.5";
my $oid_winlink1000HbsAir = $oid_winlink1000.".3.1";
my $oid_winlink1000HbsAirLinkEntry = $oid_winlink1000.".3.1.7.2.1";

my $oid_winlink1000OduAirCurrentTxPower = $oid_winlink1000OduAir.".12.0";	# Current TX Power
my $oid_winlink1000OduAirHssSyncStatus = $oid_winlink1000OduAir.".40.3.0";	# HSS State
my $oid_winlink1000OduAirHssExtPulseStatus = $oid_winlink1000OduAir.".40.4.0";	# HSS External Pulse State

my $oid_winlink1000HbsAirState  = $oid_winlink1000HbsAir.".1.0";		# HBS State
my $oid_winlink1000HbsAirAvailTimeSlots = $oid_winlink1000HbsAir.".3.0";	# HBS Free Timeslots

my $oid_winlink1000HbsAirConfHsuName = $oid_winlink1000.".3.1.6.2.1.4";		# Table with HSU Name Config

my $oid_winlink1000HbsAirLinkHsuId = $oid_winlink1000HbsAirLinkEntry.".2";	# HSU Id
my $oid_winlink1000HbsAirLinkState = $oid_winlink1000HbsAirLinkEntry.".3";	# Link State
my $oid_winlink1000HbsAirLinkHbsEstTput = $oid_winlink1000HbsAirLinkEntry.".6";	# Estimated Throughput from HBS (CPE Downlink)
my $oid_winlink1000HbsAirLinkHsuEstTput  = $oid_winlink1000HbsAirLinkEntry.".7";# Estimated Throughput from HSU (CPE Uplink)
my $oid_winlink1000HbsAirLinkHbsRss  = $oid_winlink1000HbsAirLinkEntry.".9";	# Receive Levels on HBS (CPE Uplink)
my $oid_winlink1000HbsAirLinkHbsRssBal  = $oid_winlink1000HbsAirLinkEntry.".10";# RSS Balance on HBS (CPE Uplink)
my $oid_winlink1000HbsAirLinkHsuRss  = $oid_winlink1000HbsAirLinkEntry.".11";	# Receive Levels on HSU (CPE Downlink)
my $oid_winlink1000HbsAirLinkHsuRssBal = $oid_winlink1000HbsAirLinkEntry.".12";	# RSS Balance on HSU (CPE Downlink)

# Variables
my $o_host              = undef;        # hostname
my $o_community         = "netman";     # SNMP community
my $o_port              = 161;          # port
my $o_timeout           = 30;        	# SNMP timeout

my $o_check_type        = "tx_power";
my $o_hsu_name		= undef;

my $o_warn              = undef;        # warning level
my $o_crit              = undef;        # critical level

my $o_perf              = undef;        # Output performance data
my $o_help              = undef;        # want some help ?

# Usage
sub print_usage {
    print "Usage: $0 -H <host> [-C <snmp_community>]  [-p <port>] [-t <timeout>] -T=[tx_power|hss_sync_state|hss_ext_pulse|hbs_state|hbs_free_slots|hsu_link_state|hsu_rss|hsu_rss_balance|hsu_bandwidth] [-n <hsu name>] [-w <warn level>] [-c <crit level>] [-f] \n";
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
   community name for the host's SNMP agent (implies v1 protocol) (Default: netman)
-p, --port=PORT
   SNMP port (Default: 161)
-t, --timeout=INTEGER
   timeout for SNMP in seconds (Default: 30)
-T, --type=tx_power|hss_sync_state|hss_ext_pulse|hbs_state|hbs_free_slots|hsu_link_state|hsu_rss|hsu_rss_balance|hsu_bandwidth
   tx_power:         Current Transmit Power

   hss_sync_state:   HSS Sync Status
   hss_ext_pulse:    HSS External Pulse Detection

   hbs_state:        HBS Status
   hbs_free_slots:   HBS Available Timeslots

   hsu_link_state:   HSU Link Status
   hsu_rss:          HSU Receive Levels
   hsu_rss_balance:  HSU RSS Balance
   hsu_bandwidth:    HSU Estimated Throughput
-n, --name=STRING
   HSU Name 
   (Required for hsu_link_state|hsu_rss|hsu_rss_balance|hsu_bandwidth)
-w, --warn=INTEGER
   tx_power:         Warning Levels for Transmit Power (dBm)

   hbs_free_slots:   Warning Levels for HBS Available Timeslots (0-64)

   hsu_rss:          Warning Levels for HSU Receive Levels (CPE Uplink,CPE Downlink)
   hsu_bandwidth:    Warning Levels for HSU Estimated Throughput (CPE Uplink,CPE Downlink)
-c, --crit=INTEGER
   tx_power:         Critical Levels for Transmit Power (dBm)

   hbs_free_slots:   Critical Levels for HBS Available Timeslots (0-64)

   hsu_rss:          Critical Levels for HSU Receive Levels (CPE Uplink,CPE Downlink)
   hsu_bandwidth:    Critical Levels for HSU Estimated Throughput (CPE Uplink,CPE Downlink)
-f, --perfparse
   Perfparse compatible output
EOT
}

# Is not numeric
sub is_not_num {
  my $num = shift;
  if ( $num =~ /^(\d+\.?\d*)|(^\.\d+)$/ ) { return 0 ;}
  return 1;
}

# Options parsing
sub check_options {
    Getopt::Long::Configure ("bundling");
    GetOptions(
      'h'     => \$o_help,              'help'          => \$o_help,
      'H:s'   => \$o_host,              'hostname:s'    => \$o_host,
      'C:s'   => \$o_community,         'community:s'   => \$o_community,
      'p:i'   => \$o_port,              'port:i'        => \$o_port,
      't:i'   => \$o_timeout,           'timeout:i'     => \$o_timeout,
      'T:s'   => \$o_check_type,        'type:s'        => \$o_check_type,
      'n:s'   => \$o_hsu_name,          'name:s'        => \$o_hsu_name,
      'w:s'   => \$o_warn,              'warn:s'        => \$o_warn,
      'c:s'   => \$o_crit,              'critical:s'    => \$o_crit,
      'f'     => \$o_perf,              'perfparse'     => \$o_perf,
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
         exit $ERRORS{"UNKNOWN"};
    }

    if (defined($o_timeout) && (is_not_num($o_timeout) || ($o_timeout < 2) || ($o_timeout > 60))) {
          print "Timeout must be >1 and <60 !\n";
          print_usage();
          exit $ERRORS{"UNKNOWN"};
    }
    if (!defined($o_timeout)) {
          $o_timeout=30;
    }

    if (defined ($o_help) ) {
          help();
          exit $ERRORS{"UNKNOWN"};
    };

    if (!defined($o_host)) {
	  print "Specify a host !\n";
          print_usage();
          exit $ERRORS{"UNKNOWN"};
    }

    if (!defined($o_community)) {
	  print "Specify a community !\n";
          print_usage();
          exit $ERRORS{"UNKNOWN"};
    }

    if ( $o_check_type eq "hsu_link_state" ||  $o_check_type eq "hsu_rss" ||  $o_check_type eq "hsu_rss_balance" ||  $o_check_type eq "hsu_bandwidth") {
 	if (!defined($o_hsu_name)) {
                print "Specify an HSU Name !\n";
          	print_usage();
         	exit $ERRORS{"UNKNOWN"};
    	}
    }

    if ( $o_check_type eq "tx_power" ||  $o_check_type eq "hbs_free_slots" ||  $o_check_type eq "hsu_rss" ||  $o_check_type eq "hsu_bandwidth") {
 	if (!defined($o_warn) || !defined($o_crit)) {
                print "Specify warning and critical levels !\n";
                print_usage();
                exit $ERRORS{"UNKNOWN"}
    	}
    
	if ($o_check_type eq "tx_power" ||  $o_check_type eq "hbs_free_slots") {
    		if (($o_warn =~ /,/) || ($o_crit =~ /,/)) {
			print "Multiple warning/critical levels are not available for this check !\n";
			print_usage();
			exit $ERRORS{"UNKNOWN"}
		}

		if (is_not_num($o_warn) || is_not_num($o_crit)) {
			print "Specify numeric value for warning and critical levels !\n";
			print_usage();
			exit $ERRORS{"UNKNOWN"}
		}   

		if ($o_check_type eq "tx_power") {
			if ($o_warn > $o_crit) {
				print "Specify warning <= critical ! \n";
				print_usage();
				exit $ERRORS{"UNKNOWN"}
			}
	   	}

		if ($o_check_type eq "hbs_free_slots") {
			if ($o_warn < $o_crit) {
				print "Specify warning >= critical ! \n";
				print_usage();
				exit $ERRORS{"UNKNOWN"}
			}
	   	}
	}
    }
}

sub snmp_get {
	my $OID; my $var;
	foreach $var (@_){ 
		$OID = $var;
	}

	my ($session, $error) = Net::SNMP->session(
    		-hostname  => $o_host,
    		-version   => 1,
    		-community => $o_community,
   		 -port      => $o_port,
    		-timeout   => $o_timeout
	);

	if (!defined($session)) {
   		printf("Error opening session: %s.\n", $error);
   		exit $ERRORS{"UNKNOWN"};
	}

	my @oidlists = ($OID);

        my $result = $session->get_request(-varbindlist => \@oidlists);
        if (!defined($result)) {
                printf("Error: Description table: %s.\n", $session->error);
                $session->close;
                exit $ERRORS{"UNKNOWN"};
        }
        $session->close;

	if (!defined ($$result{$OID})) {
                print "Value could not be retrieved: CRITICAL\n";
                exit $ERRORS{"CRITICAL"};
        }
        return $$result{$OID};
}

sub lookupHsuId {
	my $hsuName; my $var;
	foreach $var (@_){ 
		$hsuName = $var;
	}

	my $i; my $name;
	for ($i = 1; $i <= 32; $i++) {
		$name = snmp_get("$oid_winlink1000HbsAirConfHsuName.$i");
		if ($name eq $hsuName) {
			return $i;
		}
	}

	print "HSU name $hsuName could not be found in configuration !\n";
   	exit $ERRORS{"UNKNOWN"};
}

sub lookupLinkIndex {
	my $hsuId; my $var;
	foreach $var (@_){ 
		$hsuId = $var;
	}

	my $i; my $id;
	for ($i = 1; $i <= 32; $i++) {
		$id = snmp_get("$oid_winlink1000HbsAirLinkHsuId.$i");
		if ($id eq $hsuId) {
			return $i;
		}
	}

	print "HSU Id $hsuId is currently not connected !\n";
   	exit $ERRORS{"UNKNOWN"};
}

# Main Code
check_options();

$SIG{'ALRM'} = sub {
  print "No answer from host !\n";
  exit $ERRORS{"UNKNOWN"};
};

my $exit_val=undef;

if ($o_check_type eq "tx_power") {
	my $value = snmp_get($oid_winlink1000OduAirCurrentTxPower);
	print "Transmit Power: $value dBm - ";

	$exit_val=$ERRORS{"OK"};
	if ($value > $o_crit) {
           	print "CRITICAL";
           	$exit_val=$ERRORS{"CRITICAL"};
        } elsif ($value > $o_warn) {
		print "WARNING";
          	$exit_val=$ERRORS{"WARNING"};
        } else {
		print "OK";
	}

 	if (defined($o_perf)) {
                print " | tx_power=$value;$o_warn;$o_crit\n";
        } else {
                print "\n";
        }

        exit $exit_val;
}

if ($o_check_type eq "hss_sync_state") {
	my $value = snmp_get($oid_winlink1000OduAirHssSyncStatus);
	print "HSS Sync State: $value - ";

	$exit_val=$ERRORS{"OK"};
	if ($value != 3 && $value != 1) {
           	print "CRITICAL";
           	$exit_val=$ERRORS{"CRITICAL"};
        } else {
		print "OK";
	}

	if (defined($o_perf)) {
                print " | state=$value;1=notApplicable,3=synchronized\n";
        } else {
                print "\n";
        }

	exit $exit_val;
}

if ($o_check_type eq "hss_ext_pulse") {
	my $value = snmp_get($oid_winlink1000OduAirHssExtPulseStatus);
	print "HSS External Pulse Status: $value - ";

	$exit_val=$ERRORS{"OK"};
	if ($value == 2 || $value == 5) {
           	print "OK";
	} elsif ($value == 3 || $value == 7) {
           	print "WARNING";
          	$exit_val=$ERRORS{"WARNING"};
        } else {
		print "CRITICAL";
           	$exit_val=$ERRORS{"CRITICAL"};
	}

	if (defined($o_perf)) {
                print " | state=$value;2=generating,5=detected\n";
        } else {
                print "\n";
        }

	exit $exit_val;
}

if ($o_check_type eq "hbs_state") {
	my $value = snmp_get($oid_winlink1000HbsAirState);
	print "HBS Status: $value - ";

	$exit_val=$ERRORS{"OK"};
	if ($value == 7) {
           	print "OK";
        } else {
		print "CRITICAL";
           	$exit_val=$ERRORS{"CRITICAL"};
	}

	if (defined($o_perf)) {
                print " | state=$value;7=transceiving\n";
        } else {
                print "\n";
        }

	exit $exit_val;
}

if ($o_check_type eq "hbs_free_slots") {
	my $value = snmp_get($oid_winlink1000HbsAirAvailTimeSlots);
	print "Available timeslots: $value - ";

	$exit_val=$ERRORS{"OK"};
	if ($value < $o_crit) {
           	print "CRITICAL";
           	$exit_val=$ERRORS{"CRITICAL"};
        } elsif ($value < $o_warn) {
		print "WARNING";
          	$exit_val=$ERRORS{"WARNING"};
        } else {
		print "OK";
	}

	if (defined($o_perf)) {
		my $pct = int($value / 64 * 100);
                print " |available=$value ($pct%);$o_warn;$o_crit\n";
        } else {
                print "\n";
        }

	exit $exit_val;
}

if ($o_check_type eq "hsu_link_state") {
	my $hsuId = lookupHsuId($o_hsu_name);
	my $tableIndex = lookupLinkIndex($hsuId);

	my $value = snmp_get("$oid_winlink1000HbsAirLinkState.$tableIndex");
	print "HSU $o_hsu_name Link State: $value - ";

	$exit_val=$ERRORS{"OK"};
	if ($value == 4) {
           	print "OK";
        } else {
		print "CRITICAL";
           	$exit_val=$ERRORS{"CRITICAL"};
	}

	if (defined($o_perf)) {
                print " | state=$value;4=syncRegistered\n";
        } else {
                print "\n";
        }

	exit $exit_val;
}

if ($o_check_type eq "hsu_rss") {
	my $hsuId = lookupHsuId($o_hsu_name);
	my $tableIndex = lookupLinkIndex($hsuId);

	my $valueUp = snmp_get("$oid_winlink1000HbsAirLinkHbsRss.$tableIndex");
	my $valueDown = snmp_get("$oid_winlink1000HbsAirLinkHsuRss.$tableIndex");
	print "HSU $o_hsu_name Receive Levels (U/D): $valueUp/$valueDown dBm - ";

	$exit_val=$ERRORS{"OK"};

	my($o_warn_u, $o_warn_d) = $o_warn =~ m/(.*),(.*)$/;
	my($o_crit_u, $o_crit_d) = $o_crit =~ m/(.*),(.*)$/;

	$o_warn_u *= -1; $o_warn_d *= -1;
	$o_crit_u *= -1; $o_crit_d *= -1;

	if ($valueUp < $o_crit_u) {
           	print "CRITICAL";
           	$exit_val=$ERRORS{"CRITICAL"};
	} elsif ($valueDown < $o_crit_d) {
		print "CRITICAL";
          	$exit_val=$ERRORS{"CRITICAL"};
	} elsif ($valueUp < $o_warn_u) {
		print "WARNING";
          	$exit_val=$ERRORS{"WARNING"};
        } elsif ($valueDown < $o_warn_d) {
		print "WARNING";
          	$exit_val=$ERRORS{"WARNING"};
        } else {
		print "OK";
	}

	if (defined($o_perf)) {
                print " | rssU/rssD=$valueUp/$valueDown;$o_warn_u/$o_warn_d,$o_crit_u/$o_crit_d\n";
        } else {
                print "\n";
        }

	exit $exit_val;
}

if ($o_check_type eq "hsu_rss_balance") {
	my $hsuId = lookupHsuId($o_hsu_name);
	my $tableIndex = lookupLinkIndex($hsuId);

	my $valueUp = snmp_get("$oid_winlink1000HbsAirLinkHbsRssBal.$tableIndex");
	my $valueDown = snmp_get("$oid_winlink1000HbsAirLinkHsuRssBal.$tableIndex");
	print "HSU $o_hsu_name Receive Balance (U/D): $valueUp/$valueDown - ";

	$exit_val=$ERRORS{"OK"};

	if ($valueUp != 0 || $valueDown != 0) {
           	print "WARNING";
           	$exit_val=$ERRORS{"WARNING"};
        } else {
		print "OK";
	}

	if (defined($o_perf)) {
                print " | rssBalU/rssBalD=$valueUp/$valueDown;0=Equal RSS on both radios\n";
        } else {
                print "\n";
        }

	exit $exit_val;
}

if ($o_check_type eq "hsu_bandwidth") {
	my $hsuId = lookupHsuId($o_hsu_name);
	my $tableIndex = lookupLinkIndex($hsuId);

	my $valueUp = snmp_get("$oid_winlink1000HbsAirLinkHsuEstTput.$tableIndex");
	my $valueDown = snmp_get("$oid_winlink1000HbsAirLinkHbsEstTput.$tableIndex");
	$valueUp = int($valueUp / 1000 / 1000);
	$valueDown = int($valueDown / 1000 / 1000);

	print "HSU $o_hsu_name Estimated Throughput (U/D): $valueUp/$valueDown Mbps - ";

	$exit_val=$ERRORS{"OK"};

	my($o_warn_u, $o_warn_d) = $o_warn =~ m/(.*),(.*)$/;
	my($o_crit_u, $o_crit_d) = $o_crit =~ m/(.*),(.*)$/;

	if ($valueUp < $o_crit_u) {
           	print "CRITICAL";
           	$exit_val=$ERRORS{"CRITICAL"};
	} elsif ($valueDown < $o_crit_d) {
		print "CRITICAL";
          	$exit_val=$ERRORS{"CRITICAL"};
	} elsif ($valueUp < $o_warn_u) {
		print "WARNING";
          	$exit_val=$ERRORS{"WARNING"};
        } elsif ($valueDown < $o_warn_d) {
		print "WARNING";
          	$exit_val=$ERRORS{"WARNING"};
        } else {
		print "OK";
	}

	if (defined($o_perf)) {
                print " | up/down=$valueUp/$valueDown;$o_warn_u/$o_warn_d,$o_crit_u/$o_crit_d\n";
        } else {
                print "\n";
        }

	exit $exit_val;
}
