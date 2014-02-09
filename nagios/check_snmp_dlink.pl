#!/usr/bin/perl -w

#Imports
use strict;
use Net::SNMP;
use Getopt::Long;

#Constants
my %ERRORS=('OK'=>0,'WARNING'=>1,'CRITICAL'=>2,'UNKNOWN'=>3,'DEPENDENT'=>4);
my @valid_types = ("cpu", "power", "fan", "temperature");

# OIDs
my $cpu = "1.3.6.1.4.1.171.10.94.89.89.1.9.0"; # CPU (5 minute)
my $power = "1.3.6.1.4.1.171.10.94.89.89.53.15.1.2.1"; # Power Supply (1 = OK)
my $fan = "1.3.6.1.4.1.171.10.94.89.89.53.15.1.4.1"; # Fan State (1 = OK)
my $temperature = "1.3.6.1.4.1.171.10.94.89.89.53.15.1.9.1"; # Temperature

#Variables
my $o_host              = undef;        # hostname
my $o_community         = undef;        # community
my $o_port              = 161;          # port
my $o_help              = undef;        # want some help ?
my $o_check_type        = "cpu";
my $o_warn              = undef;        # warning level
my $o_crit              = undef;        # critical level
my $o_timeout           = undef;        # Timeout (Default 30)
my $o_perf              = undef;        # Output performance data

# Usage
sub print_usage {
    print "Usage: $0 -H <host> -C <snmp_community>  [-p <port>] [-w <warn level>] [-c <crit level>] -T=[cpu|power|fan|temperature] [-f] [-t <timeout>]\n";
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
   cpu : warning level for CPU Usage
   temperature : warning level for temperature
-c, --crit=INTEGER
   cpu : critical level for CPU Usage
   temperature : critical level for temperature
-T, --type=cpu|power|fan|temperature
   cpu : CPU Usage
   power : State of Power Supply
   fan : State of Fan
   temperature : Temperature
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

    if ($o_check_type eq "cpu" || $o_check_type eq "temperature") {
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

if ($o_check_type eq "power") {
	my @oidlists = ($power);
        my $result = (Net::SNMP->VERSION < 4) ? $session->get_request(@oidlists) : $session->get_request(-varbindlist => \@oidlists);

        if (!defined($result)) {
                printf("ERROR: Description table : %s.\n", $session->error);
                $session->close;
                exit $ERRORS{"UNKNOWN"};
        }

        $session->close;

	if (!defined ($$result{$power})) {
                print "Unknown State of PSU : UNKNOWN\n";
                exit $ERRORS{"UNKNOWN"};
        }

        my $power_state=$$result{$power};
        print "State of PSU: $power_state";

        $exit_val=$ERRORS{"OK"};

        if ($power_state != 1) {
           print "- $power_state != 1: CRITICAL";
           $exit_val=$ERRORS{"CRITICAL"};
        }

        print " OK" if ($exit_val eq $ERRORS{"OK"});

        if (defined($o_perf)) {
                print " | power_state=$power_state [1 = OK]\n";
        } else {
                print "\n";
        }

        exit $exit_val;
}

if ($o_check_type eq "fan") {
	my @oidlists = ($fan);
        my $result = (Net::SNMP->VERSION < 4) ? $session->get_request(@oidlists) : $session->get_request(-varbindlist => \@oidlists);

        if (!defined($result)) {
                printf("ERROR: Description table : %s.\n", $session->error);
                $session->close;
                exit $ERRORS{"UNKNOWN"};
        }

        $session->close;

	if (!defined ($$result{$fan})) {
                print "Unknown State of Fan : UNKNOWN\n";
                exit $ERRORS{"UNKNOWN"};
        }

        my $fan_state=$$result{$fan};
        print "State of Fan: $fan_state";

        $exit_val=$ERRORS{"OK"};

        if ($fan_state != 1) {
           print "- $fan_state != 1: CRITICAL";
           $exit_val=$ERRORS{"CRITICAL"};
        }

        print " OK" if ($exit_val eq $ERRORS{"OK"});

        if (defined($o_perf)) {
                print " | fan_state=$fan_state [1 = OK]\n";
        } else {
                print "\n";
        }

        exit $exit_val;
}

if ($o_check_type eq "cpu") {
	my @oidlists = ($cpu);
        my $result = (Net::SNMP->VERSION < 4) ? $session->get_request(@oidlists) : $session->get_request(-varbindlist => \@oidlists);

        if (!defined($result)) {
                printf("ERROR: Description table : %s.\n", $session->error);
                $session->close;
                exit $ERRORS{"UNKNOWN"};
        }

        $session->close;

	if (!defined ($$result{$cpu})) {
                print "Unknown CPU Usage : UNKNOWN\n";
                exit $ERRORS{"UNKNOWN"};
        }

        my $usage=$$result{$cpu};
        print "CPU Usage: $usage % ";

        $exit_val=$ERRORS{"OK"};

        if ($usage > $o_crit) {
           print "- $usage > $o_crit : CRITICAL";
           $exit_val=$ERRORS{"CRITICAL"};
        }

        if ($exit_val eq $ERRORS{"OK"} && $usage > $o_warn) {
           print "- $usage > $o_warn : WARNING";
           $exit_val=$ERRORS{"WARNING"};
        }

        print " OK" if ($exit_val eq $ERRORS{"OK"});

        if (defined($o_perf)) {
                print " | usage=$usage;$o_warn;$o_crit\n";
        } else {
                print "\n";
        }

        exit $exit_val;
}

if ($o_check_type eq "temperature") {
	my @oidlists = ($temperature);
        my $result = (Net::SNMP->VERSION < 4) ? $session->get_request(@oidlists) : $session->get_request(-varbindlist => \@oidlists);

        if (!defined($result)) {
                printf("ERROR: Description table : %s.\n", $session->error);
                $session->close;
                exit $ERRORS{"UNKNOWN"};
        }

        $session->close;

	if (!defined ($$result{$temperature})) {
                print "Unknown Temperature : UNKNOWN\n";
                exit $ERRORS{"UNKNOWN"};
        }

        my $temp=$$result{$temperature};
        print "Temperature: $temp Celsius ";

        $exit_val=$ERRORS{"OK"};

        if ($temp > $o_crit) {
           print "- $temp > $o_crit : CRITICAL";
           $exit_val=$ERRORS{"CRITICAL"};
        }

        if ($exit_val eq $ERRORS{"OK"} && $temp > $o_warn) {
           print "- $temp > $o_warn : WARNING";
           $exit_val=$ERRORS{"WARNING"};
        }

        print " OK" if ($exit_val eq $ERRORS{"OK"});

        if (defined($o_perf)) {
                print " | temp=$temp;$o_warn;$o_crit\n";
        } else {
                print "\n";
        }

        exit $exit_val;
}

