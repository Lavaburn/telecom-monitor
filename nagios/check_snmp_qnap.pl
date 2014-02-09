#!/usr/bin/perl -w

#Imports
use strict;
use Net::SNMP;
use Getopt::Long;

#Constants
my %ERRORS=('OK' => 0, 'WARNING' => 1, 'CRITICAL' => 2, 'UNKNOWN' => 3, 'DEPENDENT' => 4);

# OIDs
my $qnap = "1.3.6.1.4.1.24681";
my $state_index = "$qnap.1.2.11.1.4"; # Disk State .X

#Variables
my $o_host              = undef;        # hostname
my $o_community         = undef;        # community
my $o_port              = 161;          # port
my $o_help              = undef;        # want some help ?
my $o_index	        = 1;		# Disk number
my $o_timeout           = 30;  		# Timeout (Default 30)
my $o_perf              = undef;        # Output performance data

# Usage
sub print_usage {
    print "Usage: $0 -H <host> -C <snmp_community>  [-p <port>] -i=[1|2|3|4] [-f] [-t <timeout>]\n";
}

# Is not numeric
sub isnnum {
  my $num = shift;
  if ($num =~ /^(\d+\.?\d*)|(^\.\d+)$/) { 
	return 0 ;
  }
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
   community name for the host's SNMP agent (implies v2 protocol)
-p, --port=PORT
   SNMP port (Default 161)
-i, --index=1|2|3|4
   Index of Disk
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
      'f'     => \$o_perf,              'perfparse'     => \$o_perf,
      'i:i'   => \$o_index,	        'index:i'        => \$o_index,
    );

    if (defined($o_index) && (isnnum($o_index) || ($o_index < 1) || ($o_index > 4))) {
                print "Index must be between 1 and 4 !\n";
                print_usage();
                exit $ERRORS{"UNKNOWN"}
    }

    if (defined($o_timeout) && (isnnum($o_timeout) || ($o_timeout < 2) || ($o_timeout > 60))) {
                print "Timeout must be >1 and <60 !\n";
                print_usage();
                exit $ERRORS{"UNKNOWN"}
    }

    if (!defined($o_timeout)) {
                $o_timeout=30;
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

my $oid = "$state_index.$o_index";
my @oidlists = ($oid);
my $result = (Net::SNMP->VERSION < 4) ? $session->get_request(@oidlists) : $session->get_request(-varbindlist => \@oidlists);

if (!defined($result)) {
	printf("ERROR: Description table : %s.\n", $session->error);
        $session->close;
        exit $ERRORS{"UNKNOWN"};
}
$session->close;

if (!defined ($$result{$oid})) {
	print "Unknown State of Disk #$o_index : UNKNOWN\n";
        exit $ERRORS{"UNKNOWN"};
}

my $state = $$result{$oid};
print "State of Disk #$o_index: ";

$exit_val = $ERRORS{"OK"};
if ($state != 0) {
        print " CRITICAL";
	$exit_val = $ERRORS{"CRITICAL"};
}
print " OK" if ($exit_val eq $ERRORS{"OK"});

if (defined($o_perf)) {
	print " | state=$state [0 = OK]\n";
} else {
	print "\n";
}

exit $exit_val;
