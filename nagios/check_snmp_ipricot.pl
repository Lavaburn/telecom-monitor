#!/usr/bin/perl

#Imports
use strict;
use Net::SNMP;
use Getopt::Long;

#Constants
my %ERRORS=('OK'=>0,'WARNING'=>1,'CRITICAL'=>2,'UNKNOWN'=>3,'DEPENDENT'=>4);
my @valid_types = ("ebno", "status", "temperature");

# OIDs
my $ipricot_ebno = "1.3.6.1.4.1.6697.1.1.1.1.18.0"; # Eb/No
my $ipricot_status = "1.3.6.1.4.1.6697.1.1.1.1.21.0"; # Status
my $ipricot_temperature = "1.3.6.1.4.1.6697.1.1.1.2.1.0"; # Temperature

#Variables
my $o_host              = undef;        # hostname
my $o_community         = undef;        # community
my $o_port              = 161;          # port
my $o_help              = undef;        # want some help ?
my $o_check_type        = "ebno";
my $o_warn              = undef;        # warning level
my $o_crit              = undef;        # critical level
my $o_timeout           = undef;        # Timeout (Default 5)
my $o_perf              = undef;        # Output performance data

# Usage
sub print_usage {
    print "Usage: $0 -H <host> -C <snmp_community>  [-p <port>] [-w <warn level>] [-c <crit level>] -T=[ebno|status|temperature] [-f] [-t <timeout>]\n";
}

# Is numeric
sub isnnum {
  my $num = shift;
  if ( $num =~ /^(\d+\.?\d*)|(^\.\d+)$/ ) { return 0 ;}
  return 1;
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
   type: ebno - warning level in dB
   type: status - not used
   type: temperature - warning level in Celsius
-c, --crit=INTEGER
   type: ebno - critical level in dB
   type: status - not used
   type: temperature - critical level in Celsius
-T, --type=status|esno|ebno|power
        ebno : Eb/No
        status : Locked?
        temperature : Temperature
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

    if (!($o_check_type eq "status")) {
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

	if (($o_check_type eq "ebno")) {
        	if ($o_warn < $o_crit) {
                	print "warning >= critical ! \n";
               		print_usage();
                	exit $ERRORS{"UNKNOWN"}
        	}
	}

	if (($o_check_type eq "temperature")) {
        	if ($o_warn > $o_crit) {
                	print "warning <= critical ! \n";
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

if ($o_check_type eq "ebno") {
        my @oidlists = ($ipricot_ebno);
        my $resultat = (Net::SNMP->VERSION < 4) ? $session->get_request(@oidlists) : $session->get_request(-varbindlist => \@oidlists);
        if (!defined($resultat)) {
                printf("ERROR: Description table : %s.\n", $session->error);
                $session->close;
                exit $ERRORS{"UNKNOWN"};
        }
        $session->close;

        if (!defined ($$resultat{$ipricot_ebno})) {
                print "No Eb/No information : UNKNOWN\n";
                exit $ERRORS{"UNKNOWN"};
        }

        my $ebno=$$resultat{$ipricot_ebno};
	$ebno = $ebno / 10;

        print "Eb/No: $ebno - ";

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

if ($o_check_type eq "status") {
        my @oidlists = ($ipricot_status);
        my $resultat = (Net::SNMP->VERSION < 4) ? $session->get_request(@oidlists) : $session->get_request(-varbindlist => \@oidlists);
        if (!defined($resultat)) {
                printf("ERROR: Description table : %s.\n", $session->error);
                $session->close;
                exit $ERRORS{"UNKNOWN"};
        }
        $session->close;

        if (!defined ($$resultat{$ipricot_status})) {
                print "No status information : UNKNOWN\n";
                exit $ERRORS{"UNKNOWN"};
        }

        my $status=$$resultat{$ipricot_status};

        print "Status: $status -";

        $exit_val=$ERRORS{"OK"};

        if (!($status eq 1)) {
           print " CRITICAL";
           $exit_val=$ERRORS{"CRITICAL"};
        }

        print " OK" if ($exit_val eq $ERRORS{"OK"});
        print "\n";

        exit $exit_val;
}

if ($o_check_type eq "temperature") {
        my @oidlists = ($ipricot_temperature);
        my $resultat = (Net::SNMP->VERSION < 4) ? $session->get_request(@oidlists) : $session->get_request(-varbindlist => \@oidlists);
        if (!defined($resultat)) {
                printf("ERROR: Description table : %s.\n", $session->error);
                $session->close;
                exit $ERRORS{"UNKNOWN"};
        }
        $session->close;

        if (!defined ($$resultat{$ipricot_temperature})) {
                print "No temperature information : UNKNOWN\n";
                exit $ERRORS{"UNKNOWN"};
        }

        my $temp=$$resultat{$ipricot_temperature};
	$temp = $temp / 100;

        print "Temperature: $temp - ";

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

