#!/usr/bin/perl

#Imports
use strict;
use Net::SNMP;
use Getopt::Long;

#Constants
my %ERRORS=('OK'=>0,'WARNING'=>1,'CRITICAL'=>2,'UNKNOWN'=>3,'DEPENDENT'=>4);
my @valid_types = ("power", "temperature", "receive", "margin", "esno", "quality", "link", "tx_state", "tx_power");

# OIDs
my $pwr_neg12v	 = "1.3.6.1.4.1.5835.3.1.1.1.21.0.1"; # -12V
my $pwr_12v	 = "1.3.6.1.4.1.5835.3.1.1.1.22.0.1"; # 12V
my $pwr_3v	 = "1.3.6.1.4.1.5835.3.1.1.1.23.0.1"; # 3V
my $pwr_5v	 = "1.3.6.1.4.1.5835.3.1.1.1.24.0.1"; # 5V
my $temp	 = "1.3.6.1.4.1.5835.3.1.1.1.39.0.1"; # Temperature
my $rx		 = "1.3.6.1.4.1.5835.3.1.13.1.15.1.1"; # Receive Signal
my $margin	 = "1.3.6.1.4.1.5835.3.1.13.1.32.1.1"; # Link Margin
my $esno	 = "1.3.6.1.4.1.5835.3.1.13.1.48.1.1"; # Es/No
my $quality	 = "1.3.6.1.4.1.5835.3.1.13.1.66.1.1"; # Signal Quality
my $link	 = "1.3.6.1.4.1.5835.3.1.4.1.97.1.1"; # Ethernet Link Status
my $tx_power	 = "1.3.6.1.4.1.5835.3.1.3.1.75.1.1"; # Signal Quality
my $tx_state	 = "1.3.6.1.4.1.5835.3.1.3.1.37.1.1"; # Ethernet Link Status

#Variables
my $o_host              = undef;        # hostname
my $o_community         = undef;        # community
my $o_port              = 161;  	# port
my $o_help              = undef;        # want some help ?
my $o_check_type        = "power";
my $o_warn              = undef;        # warning level
my $o_crit              = undef;        # critical level
my $o_timeout   	= undef;        # Timeout (Default 5)
my $o_perf              = undef;    	# Output performance data

# Usage
sub print_usage {
    print "Usage: $0 -H <host> -C <snmp_community>  [-p <port>] [-w <warn level>] [-c <crit level>] -T=[power|temperature|receive|margin|esno|quality|link|tx_state|tx_power] [-f] [-t <timeout>]\n";
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
   community name for the host's SNMP agent (implies v1 protocol)
-p, --port=PORT
   SNMP port (Default 161)
-w, --warn=INTEGER
   type: power - not used
   type: temperature - warning level in Celsius
   type: receive - warning level in (negative) dBm
   type: margin - warning level dB
   type: esno - warning level in dB
   type: quality - warning level in dB
   type: link - not used
   type: tx_state - not used
   type: tx_power - warning level in dBm
-c, --crit=INTEGER
   type: power - not used
   type: temperature - critical level in Celsius
   type: receive - critical level in (negative) dBm
   type: margin - critical level dB
   type: esno - critical level in dB
   type: quality - critical level in dB
   type: link - not used
   type: tx_state - not used
   type: tx_power - critical level in dBm
-T, --type=power|temperature|receive|margin|esno|quality|link
       power : Voltage
       temperature : Temperature
       receive : Receive Levels
       margin : Link Margin
       esno : Es/No
       quality : Signal Quality (Eb/No ?)
       link : Ethernet Status
       tx_state: Transmit Status
       tx_power: Transmit Power
-f, --perfparse
   Perfparse compatible output
-t, --timeout=INTEGER
   timeout for SNMP in seconds (Default: 5)
EOT
}

# Options parsing
sub check_options {
    Getopt::Long::Configure ("bundling");
    GetOptions(
      'h'     => \$o_help,	      	'help'          => \$o_help,
      'H:s'   => \$o_host,              'hostname:s'    => \$o_host,
      'p:i'   => \$o_port,              'port:i'        => \$o_port,
      'C:s'   => \$o_community,		'community:s'   => \$o_community,
      't:i'   => \$o_timeout,       	'timeout:i'     => \$o_timeout,
      'c:s'   => \$o_crit,          	'critical:s'    => \$o_crit,
      'w:s'   => \$o_warn,          	'warn:s'        => \$o_warn,
      'f'     => \$o_perf,          	'perfparse'     => \$o_perf,
      'T:s'   => \$o_check_type,    	'type:s'	=> \$o_check_type
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

    if (!($o_check_type eq "power") && !($o_check_type eq "link") && !($o_check_type eq "tx_state")) {
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

	if (($o_check_type eq "temperature") || ($o_check_type eq "receive")) {
		if ($o_warn > $o_crit) {
			print "warning <= critical ! \n";
		        print_usage();
		        exit $ERRORS{"UNKNOWN"}
		}
	} else {
		if ($o_warn < $o_crit) {
			print "warning >= critical ! \n";
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

my $exit_val=undef;

if ($o_check_type eq "power") {
	my @oidlists = ($pwr_12v, $pwr_neg12v, $pwr_5v, $pwr_3v);
	my $resultat = (Net::SNMP->VERSION < 4) ? $session->get_request(@oidlists) : $session->get_request(-varbindlist => \@oidlists);
	if (!defined($resultat)) {
                printf("ERROR: Description table : %s.\n", $session->error);
                $session->close;
                exit $ERRORS{"UNKNOWN"};
        }
	$session->close;

	if (!defined ($$resultat{$pwr_12v})) {
                print "No Power information : UNKNOWN\n";
                exit $ERRORS{"UNKNOWN"};
        }

        my $volt12=$$resultat{$pwr_12v};
	my $voltneg12=$$resultat{$pwr_neg12v};
	my $volt5=$$resultat{$pwr_5v};
	my $volt3=$$resultat{$pwr_3v};

	print "Power: $voltneg12,$volt3,$volt5,$volt12 ; ";

	$exit_val=$ERRORS{"OK"};

	if ($volt12 < 9) {
           print "$volt12 < 9 - ";
           $exit_val=$ERRORS{"CRITICAL"};
        } elsif ($volt12 > 15) {
           print "$volt12 > 15 - ";
           $exit_val=$ERRORS{"CRITICAL"};
        } 

	if ($voltneg12 < -15) {
           print "$voltneg12 < -15 - ";
           $exit_val=$ERRORS{"CRITICAL"};
        } elsif ($voltneg12 > -9) {
           print "$voltneg12 -9 - ";
           $exit_val=$ERRORS{"CRITICAL"};
        }

	if ($volt5 < 3) {
           print "$volt5 < 3 - ";
           $exit_val=$ERRORS{"CRITICAL"};
        } elsif ($volt5 > 7) {
           print "$volt5 > 7 - ";
           $exit_val=$ERRORS{"CRITICAL"};
        }

	if ($volt3 < 2) {
           print "$volt3 < 2 - ";
           $exit_val=$ERRORS{"CRITICAL"};
        } elsif ($volt3 > 5) {
           print "$volt3 > 5 - ";
           $exit_val=$ERRORS{"CRITICAL"};
        }

	if ($exit_val eq $ERRORS{"CRITICAL"}) {
		print " CRITICAL";
	} else {
		if ($volt12 < 10) {
		   print "$volt12 < 10 - ";
		   $exit_val=$ERRORS{"WARNING"};
		} elsif ($volt12 > 14) {
		   print "$volt12 > 14 - ";
		   $exit_val=$ERRORS{"WARNING"};
		} 

		if ($voltneg12 < -14.2) {
		   print "$voltneg12 < -14.2 - ";
		   $exit_val=$ERRORS{"WARNING"};
		} elsif ($voltneg12 > -10) {
		   print "$voltneg12 -10 - ";
		   $exit_val=$ERRORS{"WARNING"};
		}

		if ($volt5 < 4) {
		   print "$volt5 < 4 - ";
		   $exit_val=$ERRORS{"WARNING"};
		} elsif ($volt5 > 6) {
		   print "$volt5 > 6 - ";
		   $exit_val=$ERRORS{"WARNING"};
		}

		if ($volt3 < 2.5) {
		   print "$volt3 < 2.5 - ";
		   $exit_val=$ERRORS{"WARNING"};
		} elsif ($volt3 > 4) {
		   print "$volt3 > 4 - ";
		   $exit_val=$ERRORS{"WARNING"};
		}

		if ($exit_val eq $ERRORS{"WARNING"}) {
			print " WARNING";
		}
	}

        print " OK" if ($exit_val eq $ERRORS{"OK"});

        if (defined($o_perf)) {
                print " | -12V: (10)-(14);(9)-(15), 3.3V: 2.5-4;2-5, 5V: 4-6;3-7, 12V: 10-14;9-15\n";
        } else {
                print "\n";
        }

        exit $exit_val;
}

if ($o_check_type eq "temperature") {
	my @oidlists = ($temp);
	my $resultat = (Net::SNMP->VERSION < 4) ? $session->get_request(@oidlists) : $session->get_request(-varbindlist => \@oidlists);
	if (!defined($resultat)) {
                printf("ERROR: Description table : %s.\n", $session->error);
                $session->close;
                exit $ERRORS{"UNKNOWN"};
        }
	$session->close;

	if (!defined ($$resultat{$temp})) {
                print "No Temperature information : UNKNOWN\n";
                exit $ERRORS{"UNKNOWN"};
        }

        my $temp=$$resultat{$temp};

	print "Temperature: $temp -";

	$exit_val=$ERRORS{"OK"};

	if ($temp > $o_crit) {
           print "$temp > $o_crit : CRITICAL";
           $exit_val=$ERRORS{"CRITICAL"};
        }

        if ($exit_val eq $ERRORS{"OK"} && $temp > $o_warn) {
           print "$temp > $o_warn : WARNING";
           $exit_val=$ERRORS{"WARNING"};
        }

        print " OK" if ($exit_val eq $ERRORS{"OK"});

        if (defined($o_perf)) {
                print " | $o_warn;$o_crit\n";
        } else {
                print "\n";
        }

        exit $exit_val;
}

if ($o_check_type eq "receive") {
	my @oidlists = ($rx);
	my $resultat = (Net::SNMP->VERSION < 4) ? $session->get_request(@oidlists) : $session->get_request(-varbindlist => \@oidlists);
	if (!defined($resultat)) {
                printf("ERROR: Description table : %s.\n", $session->error);
                $session->close;
                exit $ERRORS{"UNKNOWN"};
        }
	$session->close;

	if (!defined ($$resultat{$rx})) {
                print "No Receive Signal information : UNKNOWN\n";
                exit $ERRORS{"UNKNOWN"};
        }

        my $receive=$$resultat{$rx};

	$o_crit = $o_crit * -1;
	$o_warn = $o_warn * -1;

	print "Receive Signal: $receive -";

	$exit_val=$ERRORS{"OK"};

	if ($receive < $o_crit) {
           print "$receive < $o_crit : CRITICAL";
           $exit_val=$ERRORS{"CRITICAL"};
        }

        if ($exit_val eq $ERRORS{"OK"} && $receive < $o_warn) {
           print "$receive < $o_warn : WARNING";
           $exit_val=$ERRORS{"WARNING"};
        }

        print " OK" if ($exit_val eq $ERRORS{"OK"});

        if (defined($o_perf)) {
                print " | $o_warn;$o_crit\n";
        } else {
                print "\n";
        }

        exit $exit_val;
}

if ($o_check_type eq "margin") {
	my @oidlists = ($margin);
	my $resultat = (Net::SNMP->VERSION < 4) ? $session->get_request(@oidlists) : $session->get_request(-varbindlist => \@oidlists);
	if (!defined($resultat)) {
                printf("ERROR: Description table : %s.\n", $session->error);
                $session->close;
                exit $ERRORS{"UNKNOWN"};
        }
	$session->close;

	if (!defined ($$resultat{$margin})) {
                print "No Link Margin information : UNKNOWN\n";
                exit $ERRORS{"UNKNOWN"};
        }

        my $link_margin=$$resultat{$margin};

	print "Link Margin: $link_margin -";
#	$o_crit = $o_crit * -1;
#	$o_warn = $o_warn * -1;

	$exit_val=$ERRORS{"OK"};

	if ($link_margin < $o_crit) {
           print "$link_margin < $o_crit : CRITICAL";
           $exit_val=$ERRORS{"CRITICAL"};
        }

        if ($exit_val eq $ERRORS{"OK"} && $link_margin < $o_warn) {
           print "$link_margin < $o_warn : WARNING";
           $exit_val=$ERRORS{"WARNING"};
        }

        print " OK" if ($exit_val eq $ERRORS{"OK"});

        if (defined($o_perf)) {
                print " | $o_warn;$o_crit\n";
        } else {
                print "\n";
        }

        exit $exit_val;
}

if ($o_check_type eq "esno") {
	my @oidlists = ($esno);
	my $resultat = (Net::SNMP->VERSION < 4) ? $session->get_request(@oidlists) : $session->get_request(-varbindlist => \@oidlists);
	if (!defined($resultat)) {
                printf("ERROR: Description table : %s.\n", $session->error);
                $session->close;
                exit $ERRORS{"UNKNOWN"};
        }
	$session->close;

	if (!defined ($$resultat{$esno})) {
                print "No Es/No information : UNKNOWN\n";
                exit $ERRORS{"UNKNOWN"};
        }

        my $esno_val=$$resultat{$esno};

	print "Es/No: $esno_val -";

	$exit_val=$ERRORS{"OK"};

	if ($esno_val < $o_crit) {
           print "$esno_val < $o_crit : CRITICAL";
           $exit_val=$ERRORS{"CRITICAL"};
        }

        if ($exit_val eq $ERRORS{"OK"} && $esno_val < $o_warn) {
           print "$esno_val < $o_warn : WARNING";
           $exit_val=$ERRORS{"WARNING"};
        }

        print " OK" if ($exit_val eq $ERRORS{"OK"});

        if (defined($o_perf)) {
                print " | $o_warn;$o_crit\n";
        } else {
                print "\n";
        }

        exit $exit_val;
}

if ($o_check_type eq "quality") {
	my @oidlists = ($quality);
	my $resultat = (Net::SNMP->VERSION < 4) ? $session->get_request(@oidlists) : $session->get_request(-varbindlist => \@oidlists);
	if (!defined($resultat)) {
                printf("ERROR: Description table : %s.\n", $session->error);
                $session->close;
                exit $ERRORS{"UNKNOWN"};
        }
	$session->close;

	if (!defined ($$resultat{$quality})) {
                print "No Signal Quality information : UNKNOWN\n";
                exit $ERRORS{"UNKNOWN"};
        }

        my $ebno=$$resultat{$quality};

	print "Signal Quality: $ebno -";

	$exit_val=$ERRORS{"OK"};

	if ($ebno < $o_crit) {
           print "$ebno < $o_crit : CRITICAL";
           $exit_val=$ERRORS{"CRITICAL"};
        }

        if ($exit_val eq $ERRORS{"OK"} && $ebno < $o_warn) {
           print "$ebno < $o_warn : WARNING";
           $exit_val=$ERRORS{"WARNING"};
        }

        print " OK" if ($exit_val eq $ERRORS{"OK"});

        if (defined($o_perf)) {
                print " | $o_warn;$o_crit\n";
        } else {
                print "\n";
        }

        exit $exit_val;
}

if ($o_check_type eq "link") {
	my @oidlists = ($link);
	my $resultat = (Net::SNMP->VERSION < 4) ? $session->get_request(@oidlists) : $session->get_request(-varbindlist => \@oidlists);
	if (!defined($resultat)) {
                printf("ERROR: Description table : %s.\n", $session->error);
                $session->close;
                exit $ERRORS{"UNKNOWN"};
        }
	$session->close;

	if (!defined ($$resultat{$link})) {
                print "No Link Status information : UNKNOWN\n";
                exit $ERRORS{"UNKNOWN"};
        }

        my $link_state=$$resultat{$link};

	print "Link Status: $link_state -";

	$exit_val=$ERRORS{"OK"};

	if (!($link_state eq "Link Up 100 BASE-T  Full Duplex ") && !($link_state eq "Link Up 1000 BASE-T Full Duplex ")) {
           print " CRITICAL";
           $exit_val=$ERRORS{"CRITICAL"};
        }

        print " OK" if ($exit_val eq $ERRORS{"OK"});
        print "\n";

        exit $exit_val;
}

if ($o_check_type eq "tx_state") {
	my @oidlists = ($tx_state);
	my $resultat = (Net::SNMP->VERSION < 4) ? $session->get_request(@oidlists) : $session->get_request(-varbindlist => \@oidlists);
	if (!defined($resultat)) {
                printf("ERROR: Description table : %s.\n", $session->error);
                $session->close;
                exit $ERRORS{"UNKNOWN"};
        }
	$session->close;

	if (!defined ($$resultat{$tx_state})) {
                print "No Transmit Status information : UNKNOWN\n";
                exit $ERRORS{"UNKNOWN"};
        }

        my $transmit_state=$$resultat{$tx_state};

	print "Transmit Status: $transmit_state -";

	$exit_val=$ERRORS{"OK"};

	if (!($transmit_state eq 1)) {
           print " CRITICAL";
           $exit_val=$ERRORS{"CRITICAL"};
        }

        print " OK" if ($exit_val eq $ERRORS{"OK"});
        print "\n";

        exit $exit_val;
}

if ($o_check_type eq "tx_power") {
	my @oidlists = ($tx_power);
	my $resultat = (Net::SNMP->VERSION < 4) ? $session->get_request(@oidlists) : $session->get_request(-varbindlist => \@oidlists);
	if (!defined($resultat)) {
                printf("ERROR: Description table : %s.\n", $session->error);
                $session->close;
                exit $ERRORS{"UNKNOWN"};
        }
	$session->close;

	if (!defined ($$resultat{$tx_power})) {
                print "No Transmit Power information : UNKNOWN\n";
                exit $ERRORS{"UNKNOWN"};
        }

        my $power=$$resultat{$tx_power};
	$o_crit = $o_crit * -1;
	$o_warn = $o_warn * -1;

	print "TX Power: $power -";

	$exit_val=$ERRORS{"OK"};

	if ($power > $o_crit) {
           print "$power > $o_crit : CRITICAL";
           $exit_val=$ERRORS{"CRITICAL"};
        }

        if ($exit_val eq $ERRORS{"OK"} && $power > $o_warn) {
           print "$power > $o_warn : WARNING";
           $exit_val=$ERRORS{"WARNING"};
        }

        print " OK" if ($exit_val eq $ERRORS{"OK"});

        if (defined($o_perf)) {
                print " | $o_warn;$o_crit\n";
        } else {
                print "\n";
        }

        exit $exit_val;
}
