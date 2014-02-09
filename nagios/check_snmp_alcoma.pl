#!/usr/bin/perl -w

#Imports
use strict;
use Switch;
use Net::SNMP;
use Getopt::Long;

#Constants
my %ERRORS=('OK'=>0,'WARNING'=>1,'CRITICAL'=>2,'UNKNOWN'=>3,'DEPENDENT'=>4);
my @valid_types = ("hw_state", "signal_state", "alarm_state", "tx_power", "rx_level", "rx_quality", "snr", "modulation", "ber");

# OIDs
my $hw_state = "1.3.6.1.4.1.12140.2.1.1.0"; #  Hardware Status (0 = OK)
my $signal_state = "1.3.6.1.4.1.12140.2.1.2.0"; #  Radio Signal Status (0 = OK)
my $alarm_state = "1.3.6.1.4.1.12140.2.2.3.0"; #  Station Alarm Status (1 = OK, 2 = WARN, 3 = CRIT)
my $tx_power = "1.3.6.1.4.1.12140.2.3.3.0"; #  TX Power Level (dB)
my $rx_level = "1.3.6.1.4.1.12140.2.3.4.0"; #  Signal RX Level (dB)
my $rx_quality = "1.3.6.1.4.1.12140.2.4.1.0"; #  Signal Quality (%)
my $snr = "1.3.6.1.4.1.12140.2.4.2.0"; #  SNR
my $modulation = "1.3.6.1.4.1.12140.2.4.6.0"; #  Modulation 4FSK (1), QPSK, 4QAM, 8QAM, 16QAM, 4QAM, 16QAM, 32QAM, 64QAM, 128QAM, 256QAM (11)
my $ber6 = "1.3.6.1.4.1.12140.2.7.2.0"; #  BER > 10e-6 => 0 = NO, 1 = YES
my $ber4 = "1.3.6.1.4.1.12140.2.7.3.0"; #  BER > 10e-4 => 0 = NO, 1 = YES

#Variables
my $o_host              = undef;        # hostname
my $o_community         = undef;        # community
my $o_port              = 161;          # port
my $o_help              = undef;        # want some help ?
my $o_check_type        = "hw_state";
my $o_warn              = undef;        # warning level
my $o_crit              = undef;        # critical level
my $o_timeout           = undef;        # Timeout (Default 30)
my $o_perf              = undef;        # Output performance data

# Usage
sub print_usage {
    print "Usage: $0 -H <host> -C <snmp_community>  [-p <port>] [-w <warn level>] [-c <crit level>] -T=[hw_state|signal_state|alarm_state|tx_power|rx_level|rx_quality|snr|modulation|ber] [-f] [-t <timeout>]\n";
}

# Is numeric
sub isnnum {
  my $num = shift;
  if ( $num =~ /^(\d+\.?\d*)|(^\.\d+)$/ ) { return 0 ;}
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
   tx_power: Warning Level for Transmit Power (dB)
   rx_level: Warning Level for Receive Level (dB)
   rx_quality: Warning Level for Receive Quality (%)
   snr: Warning Level for Signal to Noise Ratio (dB)
   modulation: Warning Level for Modulation (1 - 11)
-c, --crit=INTEGER
   tx_power: Critical Level for Transmit Power (dB)
   rx_level: Critical Level for Receive Level (dB)
   rx_quality: Critical Level for Receive Quality (%)
   snr: Critical Level for Signal to Noise Ratio (dB)
   modulation: Critical Level for Modulation (1 - 11)
-T, --type=hw_state|signal_state|alarm_state|tx_power|rx_level|rx_quality|snr|modulation|ber
   hw_state: Hardware Status
   signal_state: Radio Signal Status
   alarm_state: Station Alarm Status
   tx_power: TX Power Level (dB)
   rx_level: Signal RX Level (dB)
   rx_quality: Signal Quality (%)
   snr: Signal to Noise Ratio (dB)
   modulation: Modulation - 4FSK (1), QPSK, 4QAM, 8QAM, 16QAM, 4QAM, 16QAM, 32QAM, 64QAM, 128QAM, 256QAM (11)
   ber: Bit Error Rate
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
      'T:s'   => \$o_check_type,        'type:s'        => \$o_check_type,
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

    if ( $o_check_type eq "tx_power" ||  $o_check_type eq "rx_level" ||  $o_check_type eq "rx_quality" ||  $o_check_type eq "snr" 
		||  $o_check_type eq "modulation") {
 	if (!defined($o_warn) || !defined($o_crit)) {
                print "put warning and critical info!\n";
                print_usage();
                exit $ERRORS{"UNKNOWN"}
    	}

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
    }

    if ( $o_check_type eq "tx_power" || $o_check_type eq "rx_quality" || $o_check_type eq "snr" || $o_check_type eq "modulation") {
	if ($o_warn < $o_crit) {
                print "warning >= critical ! \n";
                print_usage();
                exit $ERRORS{"UNKNOWN"}
        }
    }

    if ($o_check_type eq "rx_level") {	
        if ($o_warn > $o_crit) {
                print "warning <= critical ! \n";
                print_usage();
                exit $ERRORS{"UNKNOWN"}
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
        -version   => 1,
        -community => $o_community,
        -port      => $o_port,
        -timeout   => $o_timeout
);

if (!defined($session)) {
   printf("ERROR opening session: %s.\n", $error);
   exit $ERRORS{"UNKNOWN"};
}

my $exit_val=undef;

if ($o_check_type eq "hw_state") {
	my @oidlists = ($hw_state);
        my $result = (Net::SNMP->VERSION < 4) ? $session->get_request(@oidlists) : $session->get_request(-varbindlist => \@oidlists);

        if (!defined($result)) {
                printf("ERROR: Description table : %s.\n", $session->error);
                $session->close;
                exit $ERRORS{"UNKNOWN"};
        }

        $session->close;

	if (!defined ($$result{$hw_state})) {
                print "Unknown Hardware State: CRITICAL\n";
                exit $ERRORS{"CRITICAL"};
        }

        my $state=$$result{$hw_state};
        print "Hardware State: $state";

        $exit_val=$ERRORS{"OK"};

        if ($state != 0) {
           print "- $state != 0: CRITICAL";
           $exit_val=$ERRORS{"CRITICAL"};
        }

        print " OK" if ($exit_val eq $ERRORS{"OK"});

        if (defined($o_perf)) {
                print " | state=$state [0 = OK]\n";
        } else {
                print "\n";
        }

        exit $exit_val;
}

if ($o_check_type eq "signal_state") {
	my @oidlists = ($signal_state);
        my $result = (Net::SNMP->VERSION < 4) ? $session->get_request(@oidlists) : $session->get_request(-varbindlist => \@oidlists);

        if (!defined($result)) {
                printf("ERROR: Description table : %s.\n", $session->error);
                $session->close;
                exit $ERRORS{"UNKNOWN"};
        }

        $session->close;

	if (!defined ($$result{$signal_state})) {
                print "Unknown Signal State: CRITICAL\n";
                exit $ERRORS{"CRITICAL"};
        }

        my $state=$$result{$signal_state};
        print "Signal State: $state";

        $exit_val=$ERRORS{"OK"};

        if ($state != 0) {
           print "- $state != 0: CRITICAL";
           $exit_val=$ERRORS{"CRITICAL"};
        }

        print " OK" if ($exit_val eq $ERRORS{"OK"});

        if (defined($o_perf)) {
                print " | state=$state [0 = OK]\n";
        } else {
                print "\n";
        }

        exit $exit_val;
}

if ($o_check_type eq "alarm_state") {
	my @oidlists = ($alarm_state);
        my $result = (Net::SNMP->VERSION < 4) ? $session->get_request(@oidlists) : $session->get_request(-varbindlist => \@oidlists);

        if (!defined($result)) {
                printf("ERROR: Description table : %s.\n", $session->error);
                $session->close;
                exit $ERRORS{"UNKNOWN"};
        }

        $session->close;

	if (!defined ($$result{$alarm_state})) {
                print "Unknown Alarm State: UNKNOWN\n";
                exit $ERRORS{"UNKNOWN"};
        }

        my $state=$$result{$alarm_state};
        print "Alarm State: $state";

        $exit_val=$ERRORS{"OK"};

        if ($state == 3) {
           print "- $state = 3: CRITICAL";
           $exit_val=$ERRORS{"CRITICAL"};
        } elsif ($state == 2) {
           print "- $state != 2: WARNING";
           $exit_val=$ERRORS{"WARNING"};
        }

        print " OK" if ($exit_val eq $ERRORS{"OK"});

        if (defined($o_perf)) {
                print " | state=$state [1 = OK, 2 = WARN, 3 = CRIT]\n";
        } else {
                print "\n";
        }

        exit $exit_val;
}

if ($o_check_type eq "tx_power") {
	my @oidlists = ($tx_power);
        my $result = (Net::SNMP->VERSION < 4) ? $session->get_request(@oidlists) : $session->get_request(-varbindlist => \@oidlists);

        if (!defined($result)) {
                printf("ERROR: Description table : %s.\n", $session->error);
                $session->close;
                exit $ERRORS{"UNKNOWN"};
        }

        $session->close;

	if (!defined ($$result{$tx_power})) {
                print "Unknown TX Power: CRITICAL\n";
                exit $ERRORS{"CRITICAL"};
        }

        my $power=$$result{$tx_power};
        print "TX Power: $power dBm ";

        $exit_val=$ERRORS{"OK"};

        if ($power < $o_crit) {
           print "- $power < $o_crit : CRITICAL";
           $exit_val=$ERRORS{"CRITICAL"};
        }

        if ($exit_val eq $ERRORS{"OK"} && $power < $o_warn) {
           print "- $power < $o_warn : WARNING";
           $exit_val=$ERRORS{"WARNING"};
        }

        print " OK" if ($exit_val eq $ERRORS{"OK"});

        if (defined($o_perf)) {
                print " | power=$power;$o_warn;$o_crit\n";
        } else {
                print "\n";
        }

        exit $exit_val;
}

if ($o_check_type eq "rx_level") {
	my @oidlists = ($rx_level);
        my $result = (Net::SNMP->VERSION < 4) ? $session->get_request(@oidlists) : $session->get_request(-varbindlist => \@oidlists);

        if (!defined($result)) {
                printf("ERROR: Description table : %s.\n", $session->error);
                $session->close;
                exit $ERRORS{"UNKNOWN"};
        }

        $session->close;

	if (!defined ($$result{$rx_level})) {
                print "Unknown Receive Level : CRITICAL\n";
                exit $ERRORS{"CRITICAL"};
        }

        my $signal=$$result{$rx_level};
        print "Signal Strength: $signal dB ";

        $exit_val=$ERRORS{"OK"};

	$o_crit = $o_crit * -1;
	$o_warn = $o_warn * -1;

        if ($signal < $o_crit) {
           print "- $signal < $o_crit : CRITICAL";
           $exit_val=$ERRORS{"CRITICAL"};
        }

        if ($exit_val eq $ERRORS{"OK"} && $signal < $o_warn) {
           print "- $signal < $o_warn : WARNING";
           $exit_val=$ERRORS{"WARNING"};
        }

        print " OK" if ($exit_val eq $ERRORS{"OK"});

        if (defined($o_perf)) {
                print " | signal=$signal;$o_warn;$o_crit\n";
        } else {
                print "\n";
        }

        exit $exit_val;
}

if ($o_check_type eq "rx_quality") {
	my @oidlists = ($rx_quality);
        my $result = (Net::SNMP->VERSION < 4) ? $session->get_request(@oidlists) : $session->get_request(-varbindlist => \@oidlists);

        if (!defined($result)) {
                printf("ERROR: Description table : %s.\n", $session->error);
                $session->close;
                exit $ERRORS{"UNKNOWN"};
        }

        $session->close;

	if (!defined ($$result{$rx_quality})) {
                print "Unknown Receive Quality : CRITICAL\n";
                exit $ERRORS{"CRITICAL"};
        }

        my $signal=$$result{$rx_quality};
        print "Signal Quality: $signal % ";

        $exit_val=$ERRORS{"OK"};

        if ($signal < $o_crit) {
           print "- $signal < $o_crit : CRITICAL";
           $exit_val=$ERRORS{"CRITICAL"};
        }

        if ($exit_val eq $ERRORS{"OK"} && $signal < $o_warn) {
           print "- $signal < $o_warn : WARNING";
           $exit_val=$ERRORS{"WARNING"};
        }

        print " OK" if ($exit_val eq $ERRORS{"OK"});

        if (defined($o_perf)) {
                print " | signal=$signal;$o_warn;$o_crit\n";
        } else {
                print "\n";
        }

        exit $exit_val;
}

if ($o_check_type eq "snr") {
	my @oidlists = ($snr);
        my $result = (Net::SNMP->VERSION < 4) ? $session->get_request(@oidlists) : $session->get_request(-varbindlist => \@oidlists);

        if (!defined($result)) {
                printf("ERROR: Description table : %s.\n", $session->error);
                $session->close;
                exit $ERRORS{"UNKNOWN"};
        }

        $session->close;

	if (!defined ($$result{$snr})) {
                print "Unknown SNR : CRITICAL\n";
                exit $ERRORS{"CRITICAL"};
        }

        my $signal=$$result{$snr};
        print "Signal to Noise Ratio: $signal dB ";

        $exit_val=$ERRORS{"OK"};

        if ($signal < $o_crit) {
           print "- $signal < $o_crit : CRITICAL";
           $exit_val=$ERRORS{"CRITICAL"};
        }

        if ($exit_val eq $ERRORS{"OK"} && $signal < $o_warn) {
           print "- $signal < $o_warn : WARNING";
           $exit_val=$ERRORS{"WARNING"};
        }

        print " OK" if ($exit_val eq $ERRORS{"OK"});

        if (defined($o_perf)) {
                print " | signal=$signal;$o_warn;$o_crit\n";
        } else {
                print "\n";
        }

        exit $exit_val;
}

if ($o_check_type eq "modulation") {
	my @oidlists = ($modulation);
        my $result = (Net::SNMP->VERSION < 4) ? $session->get_request(@oidlists) : $session->get_request(-varbindlist => \@oidlists);

        if (!defined($result)) {
                printf("ERROR: Description table : %s.\n", $session->error);
                $session->close;
                exit $ERRORS{"UNKNOWN"};
        }

        $session->close;

	if (!defined ($$result{$modulation})) {
                print "Unknown Modulation : CRITICAL\n";
                exit $ERRORS{"CRITICAL"};
        }

	my $modcod = "INVALID";
        my $index=$$result{$modulation};       
	switch ($index) {
		case 1	{ $modcod = "4FSK"; }
		case 2	{ $modcod = "QPSK"; }
		case 3	{ $modcod = "4QAM"; }
		case 4	{ $modcod = "8QAM"; }
		case 5	{ $modcod = "16QAM"; }
		case 6	{ $modcod = "4QAM"; }
		case 7	{ $modcod = "16QAM"; }
		case 8	{ $modcod = "32QAM"; }
		case 9	{ $modcod = "64QAM"; }
		case 10	{ $modcod = "128QAM"; }
		case 11	{ $modcod = "256QAM"; }
		else	{ $modcod = "INVALID"; }
	}
	print "Modulation: $modcod";

        $exit_val=$ERRORS{"OK"};

        if ($index < $o_crit) {
           print "- $index < $o_crit : CRITICAL";
           $exit_val=$ERRORS{"CRITICAL"};
        }

        if ($exit_val eq $ERRORS{"OK"} && $index < $o_warn) {
           print "- $index < $o_warn : WARNING";
           $exit_val=$ERRORS{"WARNING"};
        }

        print " OK" if ($exit_val eq $ERRORS{"OK"});

        if (defined($o_perf)) {
                print " | modulation=$index ($modcod);$o_warn;$o_crit\n";
        } else {
                print "\n";
        }

        exit $exit_val;
}

if ($o_check_type eq "ber") {
	my @oidlists = ($ber6, $ber4);
        my $result = (Net::SNMP->VERSION < 4) ? $session->get_request(@oidlists) : $session->get_request(-varbindlist => \@oidlists);

        if (!defined($result)) {
                printf("ERROR: Description table : %s.\n", $session->error);
                $session->close;
                exit $ERRORS{"UNKNOWN"};
        }

        $session->close;

	if (!defined ($$result{$ber4})) {
                print "Unknown BER: CRITICAL\n";
                exit $ERRORS{"CRITICAL"};
        }

        my $sw4=$$result{$ber4};
        my $sw6=$$result{$ber6};
        print "BER: 10e-4: $sw4, 10e-6: $sw6";

        $exit_val=$ERRORS{"OK"};

        if ($sw4 == 1) {
           print "- BER < 10e-4: CRITICAL";
           $exit_val=$ERRORS{"CRITICAL"};
        } elsif ($sw6 == 1) {
           print "- BER < 10e-6: WARNING";
           $exit_val=$ERRORS{"WARNING"};
        }

        print " OK" if ($exit_val eq $ERRORS{"OK"});

        if (defined($o_perf)) {
                print " | 10e-4: $sw4, 10e-6: $sw6\n";
        } else {
                print "\n";
        }

        exit $exit_val;
}
