#!/usr/bin/perl -w

#Imports
use strict;
use Net::SNMP;
use Getopt::Long;

#Constants
my %ERRORS=('OK'=>0,'WARNING'=>1,'CRITICAL'=>2,'UNKNOWN'=>3,'DEPENDENT'=>4);
my @valid_types = ("bandwidth", "state", "rss", "rss_balance", "tx_power", "unavailable_time", "severe_error_time", "integrity");

# OIDs
my $bandwidth = "1.3.6.1.4.1.4458.1000.1.3.1.0"; #  Estimated Bandwidth
my $state = "1.3.6.1.4.1.4458.1000.1.5.5.0"; #  Link State (3 = active)
my $rss = "1.3.6.1.4.1.4458.1000.1.5.9.1.0"; #  RSS (dBm)
my $rss_balance = "1.3.6.1.4.1.4458.1000.1.5.49.0"; #  RSS Balance
my $tx_power = "1.3.6.1.4.1.4458.1000.1.5.12.0"; #  Actual Transmit Power
my $time_unavailable = "1.3.6.1.4.1.4458.1000.1.6.1.1.1.101"; #  Unavailable seconds
my $time_error = "1.3.6.1.4.1.4458.1000.1.6.1.1.3.101"; #  Severe Error seconds
my $integrity = "1.3.6.1.4.1.4458.1000.1.6.1.1.5.101"; #  Integrity (1 = OK)

#Variables
my $o_host              = undef;        # hostname
my $o_community         = undef;        # community
my $o_port              = 161;          # port
my $o_help              = undef;        # want some help ?
my $o_check_type        = "bandwidth";
my $o_warn              = undef;        # warning level
my $o_crit              = undef;        # critical level
my $o_timeout           = undef;        # Timeout (Default 30)
my $o_perf              = undef;        # Output performance data

# Usage
sub print_usage {
    print "Usage: $0 -H <host> -C <snmp_community>  [-p <port>] [-w <warn level>] [-c <crit level>] -T=[bandwidth|state|rss|rss_balance|tx_power|unavailable_time|severe_error_time|integrity] [-f] [-t <timeout>]\n";
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
   bandwidth : warning level for estimated bandwidth in Mbps
   rss : warning level for RSS in dBm
   rss_balance : warning level for RSS Balance in dBm
   tx_power : warning level for transmit power in dBm
   unavailable_time : warning level for unavailable time in seconds (last 15 min)
   severe_error_time : warning level for time with severe errors in seconds (last 15 min)
-c, --crit=INTEGER
   bandwidth : critical level for estimated bandwidth in Mbps
   rss : critical level for RSS in dBm
   rss_balance : critical level for RSS Balance in dBm
   tx_power : critical level for transmit power in dBm
   unavailable_time : critical level for unavailable time in seconds (last 15 min)
   severe_error_time : critical level for time with severe errors in seconds (last 15 min)
-T, --type=bandwidth|state|rss|rss_balance|tx_power|unavailable_time|severe_error_time|integrity
   bandwidth : Estimated Link Throughput
   state : Link State
   rss : Receive Level
   rss_balance : Receive Level Difference
   tx_power : Transmit Power
   unavailable_time : Seconds unavailable in 15 min. interval
   severe_error_time : Seconds with severe errors in 15 min. interval
   integrity : Integrity of link in 15 min. interval
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

    if ( $o_check_type eq "bandwidth" ||  $o_check_type eq "rss" ||  $o_check_type eq "rss_balance" ||  $o_check_type eq "tx_power" 
		||  $o_check_type eq "unavailable_time" ||  $o_check_type eq "severe_error_time") {
 	if (!defined($o_warn) || !defined($o_crit)) {
                print "put warning and critical info!\n";
                print_usage();
                exit $ERRORS{"UNKNOWN"}
    	}
    }

    if ( $o_check_type ne "state" &&  $o_check_type ne "integrity") {
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

    if ( $o_check_type eq "bandwidth") {
	if ($o_warn < $o_crit) {
                print "warning >= critical ! \n";
                print_usage();
                exit $ERRORS{"UNKNOWN"}
        }
    }

    if ($o_check_type eq "rss_balance" || $o_check_type eq "tx_power" || $o_check_type eq "unavailable_time" || $o_check_type eq "severe_error_time" ||  $o_check_type eq "rss") {	
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

if ($o_check_type eq "bandwidth") {
	my @oidlists = ($bandwidth);
        my $result = (Net::SNMP->VERSION < 4) ? $session->get_request(@oidlists) : $session->get_request(-varbindlist => \@oidlists);

        if (!defined($result)) {
                printf("ERROR: Description table : %s.\n", $session->error);
                $session->close;
                exit $ERRORS{"UNKNOWN"};
        }

        $session->close;

	if (!defined ($$result{$bandwidth})) {
                print "Estimated Bandwidth Unknown - link down? : CRITICAL\n";
                exit $ERRORS{"CRITICAL"};
        }

        my $est_bw=$$result{$bandwidth};
	$est_bw = $est_bw / 1000 / 1000;
        print "Estimated Throughput: $est_bw Mbps";

        $exit_val=$ERRORS{"OK"};

        if ($est_bw < $o_crit) {
           print "- $est_bw < $o_crit : CRITICAL";
           $exit_val=$ERRORS{"CRITICAL"};
        }

        if ($exit_val eq $ERRORS{"OK"} && $est_bw < $o_warn) {
           print "- $est_bw < $o_warn : WARNING";
           $exit_val=$ERRORS{"WARNING"};
        }

        print " OK" if ($exit_val eq $ERRORS{"OK"});

        if (defined($o_perf)) {
                print " | bandwidth=$est_bw;$o_warn;$o_crit\n";
        } else {
                print "\n";
        }

        exit $exit_val;
}

if ($o_check_type eq "state") {
	my @oidlists = ($state);
        my $result = (Net::SNMP->VERSION < 4) ? $session->get_request(@oidlists) : $session->get_request(-varbindlist => \@oidlists);

        if (!defined($result)) {
                printf("ERROR: Description table : %s.\n", $session->error);
                $session->close;
                exit $ERRORS{"UNKNOWN"};
        }

        $session->close;

	if (!defined ($$result{$state})) {
                print "Unknown Link State - link down? : CRITICAL\n";
                exit $ERRORS{"CRITICAL"};
        }

        my $link_state=$$result{$state};
        print "Link State: $link_state";

        $exit_val=$ERRORS{"OK"};

        if ($link_state != 3) {
           print "- $link_state != 3: CRITICAL";
           $exit_val=$ERRORS{"CRITICAL"};
        }

        print " OK" if ($exit_val eq $ERRORS{"OK"});

        if (defined($o_perf)) {
                print " | link_state=$link_state [3 = OK]\n";
        } else {
                print "\n";
        }

        exit $exit_val;
}

if ($o_check_type eq "rss") {
	my @oidlists = ($rss);
        my $result = (Net::SNMP->VERSION < 4) ? $session->get_request(@oidlists) : $session->get_request(-varbindlist => \@oidlists);

        if (!defined($result)) {
                printf("ERROR: Description table : %s.\n", $session->error);
                $session->close;
                exit $ERRORS{"UNKNOWN"};
        }

        $session->close;

	if (!defined ($$result{$rss})) {
                print "Unknown RSS - link down? : CRITICAL\n";
                exit $ERRORS{"CRITICAL"};
        }

        my $signal=$$result{$rss};
        print "Signal Strength: $signal dBm ";

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

if ($o_check_type eq "rss_balance") {
	my @oidlists = ($rss_balance);
        my $result = (Net::SNMP->VERSION < 4) ? $session->get_request(@oidlists) : $session->get_request(-varbindlist => \@oidlists);

        if (!defined($result)) {
                printf("ERROR: Description table : %s.\n", $session->error);
                $session->close;
                exit $ERRORS{"UNKNOWN"};
        }

        $session->close;

	if (!defined ($$result{$rss_balance})) {
                print "Unknown RSS Balance - link down? : CRITICAL\n";
                exit $ERRORS{"CRITICAL"};
        }

        my $balance=$$result{$rss_balance};
        print "RSS Balance: $balance dBm ";

        $exit_val=$ERRORS{"OK"};

	if ($balance < 0) { $balance = $balance * -1; }

        if ($balance > $o_crit) {
           print "- $balance > $o_crit : CRITICAL";
           $exit_val=$ERRORS{"CRITICAL"};
        }

        if ($exit_val eq $ERRORS{"OK"} && $balance > $o_warn) {
           print "- $balance > $o_warn : WARNING";
           $exit_val=$ERRORS{"WARNING"};
        }

        print " OK" if ($exit_val eq $ERRORS{"OK"});

        if (defined($o_perf)) {
                print " | rss_balance=$balance;$o_warn;$o_crit\n";
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
                print "Unknown TX Power - link down? : CRITICAL\n";
                exit $ERRORS{"CRITICAL"};
        }

        my $power=$$result{$tx_power};
        print "TX Power: $power dBm ";

        $exit_val=$ERRORS{"OK"};

        if ($power > $o_crit) {
           print "- $power > $o_crit : CRITICAL";
           $exit_val=$ERRORS{"CRITICAL"};
        }

        if ($exit_val eq $ERRORS{"OK"} && $power > $o_warn) {
           print "- $power > $o_warn : WARNING";
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

if ($o_check_type eq "unavailable_time") {
	my @oidlists = ($time_unavailable);
        my $result = (Net::SNMP->VERSION < 4) ? $session->get_request(@oidlists) : $session->get_request(-varbindlist => \@oidlists);

        if (!defined($result)) {
                printf("ERROR: Description table : %s.\n", $session->error);
                $session->close;
                exit $ERRORS{"UNKNOWN"};
        }

        $session->close;

	if (!defined ($$result{$time_unavailable})) {
                print "Unknown Unavailable Time - link down? : CRITICAL\n";
                exit $ERRORS{"CRITICAL"};
        }

        my $seconds_unavailable=$$result{$time_unavailable};
        print "Time unavailable in last 15 min: $seconds_unavailable seconds ";

        $exit_val=$ERRORS{"OK"};

        if ($seconds_unavailable > $o_crit) {
           print "- $seconds_unavailable > $o_crit : CRITICAL";
           $exit_val=$ERRORS{"CRITICAL"};
        }

        if ($exit_val eq $ERRORS{"OK"} && $seconds_unavailable > $o_warn) {
           print "- $seconds_unavailable > $o_warn : WARNING";
           $exit_val=$ERRORS{"WARNING"};
        }

        print " OK" if ($exit_val eq $ERRORS{"OK"});

        if (defined($o_perf)) {
                print " | time_unavailable=$seconds_unavailable;$o_warn;$o_crit\n";
        } else {
                print "\n";
        }

        exit $exit_val;
}

if ($o_check_type eq "severe_error_time") {
	my @oidlists = ($time_error);
        my $result = (Net::SNMP->VERSION < 4) ? $session->get_request(@oidlists) : $session->get_request(-varbindlist => \@oidlists);

        if (!defined($result)) {
                printf("ERROR: Description table : %s.\n", $session->error);
                $session->close;
                exit $ERRORS{"UNKNOWN"};
        }

        $session->close;

	if (!defined ($$result{$time_error})) {
                print "Unknown Severe Error Time - link down? : CRITICAL\n";
                exit $ERRORS{"CRITICAL"};
        }

        my $seconds_error=$$result{$time_error};
        print "Time with severe error in last 15 min: $seconds_error seconds ";

        $exit_val=$ERRORS{"OK"};

        if ($seconds_error > $o_crit) {
           print "- $seconds_error > $o_crit : CRITICAL";
           $exit_val=$ERRORS{"CRITICAL"};
        }

        if ($exit_val eq $ERRORS{"OK"} && $seconds_error > $o_warn) {
           print "- $seconds_error > $o_warn : WARNING";
           $exit_val=$ERRORS{"WARNING"};
        }

        print " OK" if ($exit_val eq $ERRORS{"OK"});

        if (defined($o_perf)) {
                print " | time_error=$seconds_error;$o_warn;$o_crit\n";
        } else {
                print "\n";
        }

        exit $exit_val;
}

if ($o_check_type eq "integrity") {
	my @oidlists = ($integrity);
        my $result = (Net::SNMP->VERSION < 4) ? $session->get_request(@oidlists) : $session->get_request(-varbindlist => \@oidlists);

        if (!defined($result)) {
                printf("ERROR: Description table : %s.\n", $session->error);
                $session->close;
                exit $ERRORS{"UNKNOWN"};
        }

        $session->close;

	if (!defined ($$result{$integrity})) {
                print "Unknown Integrity - link down? : CRITICAL\n";
                exit $ERRORS{"CRITICAL"};
        }

        my $link_integrity=$$result{$integrity};
        print "Link Integrity in last 15 min: $link_integrity ";

        $exit_val=$ERRORS{"OK"};

        if ($link_integrity != 1) {
           print "- $link_integrity != 1: CRITICAL";
           $exit_val=$ERRORS{"CRITICAL"};
        }

        print " OK" if ($exit_val eq $ERRORS{"OK"});

        if (defined($o_perf)) {
                print " | integrity=$link_integrity [1 = OK]\n";
        } else {
                print "\n";
        }

        exit $exit_val;
}
