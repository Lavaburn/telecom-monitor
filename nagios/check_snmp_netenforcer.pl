#!/usr/bin/perl -w

#Imports
use strict;
use Net::SNMP;
use Getopt::Long;

#Constants
my %ERRORS=('OK'=>0,'WARNING'=>1,'CRITICAL'=>2,'UNKNOWN'=>3,'DEPENDENT'=>4);
my @valid_types = ("mem", "disk", "cpu");

# OIDs
my $memory = "1.3.6.1.4.1.2603.5.5.4.0"; # Memory Usage (%)
my $disk = "1.3.6.1.4.1.2603.5.5.5.0"; # Disk Usage (%)
my $cpu = "1.3.6.1.4.1.2603.5.5.15.0"; # CPU Usage (%)

#Variables
my $o_host              = undef;        # hostname
my $o_community         = undef;        # community
my $o_port              = 161;          # port
my $o_help              = undef;        # want some help ?
my $o_check_type        = undef;
my $o_warn              = undef;        # warning level
my $o_crit              = undef;        # critical level
my $o_timeout           = 30;           # Timeout (Default 30)
my $o_perf              = undef;        # Output performance data

# Usage
sub print_usage {
    print "Usage: $0 -H <host> -C <snmp_community>  [-p <port>] -w <warn level> -c <crit level> -T=[mem|disk|cpu] [-f] [-t <timeout>]\n";
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
	memory: Warning Level for Memory Usage (%)
	disk: Warning Level for Disk Usage (%)
	cpu: Warning Level for CPU Usage (%)
-c, --crit=INTEGER
	memory: Critical Level for Memory Usage (%)
	disk: Critical Level for Disk Usage (%)
	cpu: Critical Level for CPU Usage (%)
-T, --type=mem|disk|cpu
	memory: Memory Usage (%)
	disk: Disk Usage (%)
	cpu: CPU Usage (%)
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

if ($o_check_type eq "mem") {
        my @oidlists = ($memory);

        my $resultat = (Net::SNMP->VERSION < 4) ? $session->get_request(@oidlists) : $session->get_request(-varbindlist => \@oidlists);

        if (!defined($resultat)) {
                printf("ERROR: Description table : %s.\n", $session->error);
                $session->close;
                exit $ERRORS{"UNKNOWN"};
        }

        $session->close;

        if (!defined ($$resultat{$memory})) {
                print "No Memory Information found : UNKNOWN\n";
                exit $ERRORS{"UNKNOWN"};
        }

        my $mempct=$$resultat{$memory};


        print "Memory Usage: $mempct % ";

        $exit_val=$ERRORS{"OK"};

        if ($mempct > $o_crit) {
           print "| $mempct > $o_crit : CRITICAL";
           $exit_val=$ERRORS{"CRITICAL"};
        }

        if ($exit_val eq $ERRORS{"OK"} && $mempct > $o_warn) {
           print "| $mempct > $o_warn : WARNING";
           $exit_val=$ERRORS{"WARNING"};
        }

        print ": OK" if ($exit_val eq $ERRORS{"OK"});

        if (defined($o_perf)) {
                print " | memory=$mempct;$o_warn;$o_crit\n";
        } else {
                print "\n";
        }

        exit $exit_val;
}

if ($o_check_type eq "disk") {
        my @oidlists = ($disk);

        my $resultat = (Net::SNMP->VERSION < 4) ? $session->get_request(@oidlists) : $session->get_request(-varbindlist => \@oidlists);

        if (!defined($resultat)) {
                printf("ERROR: Description table : %s.\n", $session->error);
                $session->close;
                exit $ERRORS{"UNKNOWN"};
        }

        $session->close;

        if (!defined ($$resultat{$disk})) {
                print "No Disk Information found : UNKNOWN\n";
                exit $ERRORS{"UNKNOWN"};
        }

        my $diskpct=$$resultat{$disk};


        print "Disk Usage: $diskpct % ";

        $exit_val=$ERRORS{"OK"};

        if ($diskpct > $o_crit) {
           print "| $diskpct > $o_crit : CRITICAL";
           $exit_val=$ERRORS{"CRITICAL"};
        }

        if ($exit_val eq $ERRORS{"OK"} && $diskpct > $o_warn) {
           print "| $diskpct > $o_warn : WARNING";
           $exit_val=$ERRORS{"WARNING"};
        }

        print ": OK" if ($exit_val eq $ERRORS{"OK"});

        if (defined($o_perf)) {
                print " | disk=$diskpct;$o_warn;$o_crit\n";
        } else {
                print "\n";
        }

        exit $exit_val;
}

if ($o_check_type eq "cpu") {
        my @oidlists = ($cpu);

        my $resultat = (Net::SNMP->VERSION < 4) ? $session->get_request(@oidlists) : $session->get_request(-varbindlist => \@oidlists);

        if (!defined($resultat)) {
                printf("ERROR: Description table : %s.\n", $session->error);
                $session->close;
                exit $ERRORS{"UNKNOWN"};
        }

        $session->close;

        if (!defined ($$resultat{$cpu})) {
                print "No CPU Information found : UNKNOWN\n";
                exit $ERRORS{"UNKNOWN"};
        }

        my $cpupct=$$resultat{$cpu};


        print "CPU Usage: $cpupct % ";

        $exit_val=$ERRORS{"OK"};

        if ($cpupct > $o_crit) {
           print "| $cpupct > $o_crit : CRITICAL";
           $exit_val=$ERRORS{"CRITICAL"};
        }

        if ($exit_val eq $ERRORS{"OK"} && $cpupct > $o_warn) {
           print "| $cpupct > $o_warn : WARNING";
           $exit_val=$ERRORS{"WARNING"};
        }

        print ": OK" if ($exit_val eq $ERRORS{"OK"});

        if (defined($o_perf)) {
                print " | cpu=$cpupct;$o_warn;$o_crit\n";
        } else {
                print "\n";
        }

        exit $exit_val;
}
