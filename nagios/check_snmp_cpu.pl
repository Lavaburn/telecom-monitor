#!/usr/bin/perl -w

# Imports
use strict;
use Net::SNMP;
use Getopt::Long;

# Constants
my %ERRORS=('OK' => 0, 'WARNING' => 1, 'CRITICAL' => 2, 'UNKNOWN' => 3, 'DEPENDENT' => 4);
my @valid_types = ("extreme", "mikrotik", "qnap");

# OIDs
my $extreme = "1.3.6.1.4.1.1916";
my $extreme_cpu = "$extreme.1.32.1.4.1";
my $extreme_cpu_5m = "$extreme_cpu.9.1"; 	# Extreme CPU load (5 min avg)
my $extreme_cpu_1m = "$extreme_cpu.8.1"; 	# Extreme CPU load (1 min avg)
my $extreme_cpu_5s = "$extreme_cpu.5.1"; 	# Extreme CPU load (5 sec avg)
my $mikrotik_cpu = "1.3.6.1.2.1.25.3.3.1.2.1"; 	# Mikrotik CPU load
my $qnap_cpu = "1.3.6.1.4.1.24681.1.2.1.0"; 	# QNAP CPU load

# Variables
my $o_host              = undef;        # hostname
my $o_community         = undef;        # community
my $o_port              = 161;  	# port
my $o_help              = undef;        # want some help ?
my $o_check_type        = "extreme";
my $o_warn              = undef;        # warning level
my @o_warnL             = undef;        # warning levels on Extreme
my $o_crit              = undef;        # critical level
my @o_critL             = undef;        # critical levels on Extreme
my $o_timeout   	= undef;        # Timeout (Default: 30 sec)
my $o_perf              = undef;   	# Output performance data

# Usage
sub print_usage {
    print "Usage: $0 -H <host> -C <snmp_community>  [-p <port>] -w <warn level> -c <crit level> -T=[extreme|mikrotik|qnap] [-f] [-t <timeout>]\n";
}

# Is not numeric
sub isnnum {
  my $num = shift;
  if ($num =~ /^(\d+\.?\d*)|(^\.\d+)$/) { 
	return 0 ;
  }
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
   community name for the host's SNMP agent (implies v2 protocol)
-p, --port=PORT
   SNMP port (Default 161)
-w, --warn=INTEGER | INT,INT,INT
   1 value check : warning level for cpu in percent
   3 value check : comma separated warning level for cpu (%) on Extreme: 1min, 5min, 15min
-c, --crit=INTEGER | INT,INT,INT   
   1 value check : critical level for cpu in percent
   3 value check : comma separated critical level for cpu (%) on Extreme: 1min, 5min, 15min
-T, --type=extreme
        extreme : Extreme Networks Switches CPU Utilization (1,5 & 15 minutes values)
        mikrotik : Mikrotik Routers CPU Utilisation (1 value)
	qnap : QNAP Storage CPU Utilisation (1 value) 
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
      'h'     => \$o_help,          'help'          => \$o_help,
      'H:s'   => \$o_host,          'hostname:s'    => \$o_host,
      'p:i'   => \$o_port,          'port:i'        => \$o_port,
      'C:s'   => \$o_community,     'community:s'   => \$o_community,
      't:i'   => \$o_timeout,       'timeout:i'     => \$o_timeout,
      'c:s'   => \$o_crit,          'critical:s'    => \$o_crit,
      'w:s'   => \$o_warn,          'warn:s'        => \$o_warn,
      'f'     => \$o_perf,          'perfparse'     => \$o_perf,
      'T:s'   => \$o_check_type,    'type:s'        => \$o_check_type
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
                $o_timeout = 30;
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

    $o_warn =~ s/\%//g;
    $o_crit =~ s/\%//g;

        if (($o_check_type eq "extreme")) {
                @o_warnL=split(/,/ , $o_warn);
                @o_critL=split(/,/ , $o_crit);
                if (($#o_warnL != 2) || ($#o_critL != 2)) {
                        print "3 warnings and critical !\n";
                        print_usage();
                        exit $ERRORS{"UNKNOWN"}
                }

                for (my $i=0;$i<3;$i++) {
                        if ( isnnum($o_warnL[$i]) || isnnum($o_critL[$i])) {
                                print "Numeric value for warning or critical !\n";
                                print_usage();
                                exit $ERRORS{"UNKNOWN"}
                        }
                        if ($o_warnL[$i] > $o_critL[$i]) {
                                print "warning <= critical ! \n";
                                print_usage();
                                exit $ERRORS{"UNKNOWN"}
                        }
                }
        } else {
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

if ($o_check_type eq "extreme") {
        my @oidlists = ($extreme_cpu_5m, $extreme_cpu_1m, $extreme_cpu_5s);

        my $result = $session->get_request(-varbindlist => \@oidlists);

        if (!defined($result)) {
                printf("ERROR: Description table : %s.\n", $session->error);
                $session->close;
                exit $ERRORS{"UNKNOWN"};
        }

        $session->close;

        if (!defined ($$result{$extreme_cpu_5s})) {
                print "No CPU information : UNKNOWN\n";
                exit $ERRORS{"UNKNOWN"};
        }

        my @load = undef;

        $load[0]=$$result{$extreme_cpu_5s};
        $load[1]=$$result{$extreme_cpu_1m};
        $load[2]=$$result{$extreme_cpu_5m};

        print "CPU : $load[0] $load[1] $load[2] :";

        $exit_val = $ERRORS{"OK"};
        for (my $i = 0; $i < 3; $i++) {
          if ($load[$i] > $o_critL[$i]) {
           print " $load[$i] > $o_critL[$i] : CRITICAL";
           $exit_val=$ERRORS{"CRITICAL"};
          }

          if ($load[$i] > $o_warnL[$i]) {
                if ($exit_val eq $ERRORS{"OK"}) {
               	print " $load[$i] > $o_warnL[$i] : WARNING";
         	$exit_val = $ERRORS{"WARNING"};
             }
          }
        }

        print " OK" if ($exit_val eq $ERRORS{"OK"});

        if (defined($o_perf)) {
                print " | load_5_sec=$load[0]%;$o_warnL[0];$o_critL[0] ";
                print "load_1_min=$load[1]%;$o_warnL[1];$o_critL[1] ";
                print "load_5_min=$load[2]%;$o_warnL[2];$o_critL[2]\n";
        } else {
                print "\n";
        }

        exit $exit_val;
}

if ($o_check_type eq "mikrotik") {
	my @oidlists = ($mikrotik_cpu);

        my $result = $session->get_request(-varbindlist => \@oidlists);

        if (!defined($result)) {
                printf("ERROR: Description table : %s.\n", $session->error);
                $session->close;
                exit $ERRORS{"UNKNOWN"};
        }

        $session->close;

        if (!defined ($$result{$mikrotik_cpu})) {
                print "No CPU information : UNKNOWN\n";
                exit $ERRORS{"UNKNOWN"};
        }

        my $load = $$result{$mikrotik_cpu};

        print "CPU $load% : ";

        $exit_val = $ERRORS{"OK"};
       
	if ($load > $o_crit) {
           print " $load > $o_crit : CRITICAL";
           $exit_val = $ERRORS{"CRITICAL"};
        }

        if ($load > $o_warn) {
        	if ($exit_val eq $ERRORS{"OK"}) {
               		print " $load > $o_warn : WARNING";
         		$exit_val = $ERRORS{"WARNING"};
             	}
        }

        print " OK" if ($exit_val eq $ERRORS{"OK"});

        if (defined($o_perf)) {
                print " | load=$load%;$o_warn;$o_crit\n";
        } else {
                print "\n";
        }

        exit $exit_val;
}

if ($o_check_type eq "qnap") {
	my @oidlists = ($qnap_cpu);

        my $result = $session->get_request(-varbindlist => \@oidlists);

        if (!defined($result)) {
                printf("ERROR: Description table : %s.\n", $session->error);
                $session->close;
                exit $ERRORS{"UNKNOWN"};
        }

        $session->close;

	if (!defined ($$result{$qnap_cpu})) {
                print "No CPU information : UNKNOWN\n";
                exit $ERRORS{"UNKNOWN"};
        }

	my $load = $$result{$qnap_cpu};
	$load =~ s/ \%//g;

	print "CPU $load% : ";

	$exit_val = $ERRORS{"OK"};
       
	if ($load > $o_crit) {
           print " $load > $o_crit : CRITICAL";
           $exit_val = $ERRORS{"CRITICAL"};
        }

	if ($load > $o_warn) {
        	if ($exit_val eq $ERRORS{"OK"}) {
               		print " $load > $o_warn : WARNING";
         		$exit_val = $ERRORS{"WARNING"};
             	}
        }
 
        print " OK" if ($exit_val eq $ERRORS{"OK"});

        if (defined($o_perf)) {
                print " | load=$load%;$o_warn;$o_crit\n";
        } else {
                print "\n";
        }

        exit $exit_val;
}
