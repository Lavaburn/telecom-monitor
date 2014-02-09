#!/usr/bin/perl -w 

# Imports
use strict;
use Net::SNMP;
use Getopt::Long;

# Constants
my %ERRORS=('OK' => 0, 'WARNING' => 1, 'CRITICAL' => 2, 'UNKNOWN' => 3, 'DEPENDENT' => 4);

# OIDs
my $oid_route = "1.3.6.1.2.1.4.21.1.7.";	# IP Route Table
my $oid_forward = "1.3.6.1.2.1.4.24.4.1.4";	# IP Forwarding Table

# Variables
my $o_host 		= undef;    # hostname
my $o_community 	= undef;    # community
my $o_port 		= 161; 	    # port
my $o_help		= undef;    # want some help ?
my $o_type 		= "route";  # Table to use for lookup: route/forward
my $o_net		= "0.0.0.0";# Route
my $o_warn		= undef;    # OK Gateway
my @o_warnL       	= undef;    # OK Gateway List
my $o_crit		= undef;    # WARN Gateway
my @o_critL       	= undef;    # WARN Gateway List
my $o_timeout		= undef;    # Timeout (Default: 30s)
my $o_perf		= undef;    # Output performance data

# Usage
sub print_usage {
    print "Usage: $0 -H <host> -C <snmp_community>  [-p <port>] -T route|forward -n <network> -w <primary GW> -c <redundant GW> [-f] [-t <timeout>]\n";
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
-T, --type=route|forward
   select the SNMP table to lookup
-w, --warn=INTEGER
   Primary Gateways (OK - comma-sep. list)
-c, --crit=INTEGER
   Redundancy Gateways (WARN - comma-sep. list)
-n, --network=IP
   network IP to check gateway for
-f, --perfparse
   Perfparse compatible output
-t, --timeout=INTEGER
   timeout for SNMP in seconds (Default: 30s)
EOT
}

# Options parsing
sub check_options {
    Getopt::Long::Configure ("bundling");
    GetOptions(
      'h'     => \$o_help,    	'help'        	=> \$o_help,
      'H:s'   => \$o_host,	'hostname:s'	=> \$o_host,
      'p:i'   => \$o_port,   	'port:i'	=> \$o_port,
      'C:s'   => \$o_community,	'community:s'	=> \$o_community,	
      't:i'   => \$o_timeout,   'timeout:i'    	=> \$o_timeout,
      'T:s'   => \$o_type,      'type:s'       	=> \$o_type,
      'c:s'   => \$o_crit,      'critical:s'   	=> \$o_crit,
      'w:s'   => \$o_warn,      'warn:s'       	=> \$o_warn,
      'f'     => \$o_perf,      'perfparse'    	=> \$o_perf,
      'n:s'   => \$o_net,	'network:s'	=> \$o_net
    );
        
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

    if (!defined($o_type)) {
	print_usage(); 
    }

    if ($o_type ne "route" && $o_type ne "forward") {
	print_usage(); 
    }


    if (!defined($o_net)) {
	print_usage(); 
	exit $ERRORS{"UNKNOWN"}
    }

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

my $exit_val = undef;

my $gateway;

if ($o_type eq "route") {
	my $oid = $oid_route.$o_net;
	my @oidlists = ($oid);

	my $resultat = $session->get_request(-varbindlist => \@oidlists);

	if (!defined($resultat)) {
		printf("ERROR: Description table : %s.\n", $session->error);
		$session->close;
		exit $ERRORS{"UNKNOWN"};
	}


	if (!defined ($$resultat{$oid})) {
		print "No Route information : UNKNOWN\n";
		exit $ERRORS{"UNKNOWN"};
	}

	$gateway = $$resultat{$oid};
}

if ($o_type eq "forward") {
	my @args = (-varbindlist => [$oid_forward]);

	my $oid;
	while (defined($session->get_next_request(@args))) {
		$oid = ($session->var_bind_names())[0];
	
		if ($oid =~ /$oid_forward.$o_net/) { 
			$gateway = $session->var_bind_list()->{$oid};
			last;
		}
		if (!($oid =~ /$oid_forward/)) { last; }
	
	     	@args = (-varbindlist => [$oid]);
	}

	if (!defined($gateway)) {
		print "No Route information: UNKNOWN\n";
		printf("ERROR: %s.\n", $session->error);
		$session->close;
		exit $ERRORS{"UNKNOWN"};
	}
}

$session->close;

print "Gateway for $o_net: $gateway - ";
$exit_val = $ERRORS{"CRITICAL"};

if ($o_warn =~ /,/) {
	@o_warnL = split(/,/ , $o_warn);
	
	foreach (@o_warnL) {
      		if ($_ eq $gateway) {
			$exit_val = $ERRORS{"OK"};
		}	
	}
} else {
	if ($o_warn eq $gateway) {
		$exit_val = $ERRORS{"OK"};
	}	
}

if ($o_crit =~ /,/) {
      	@o_critL = split(/,/ , $o_crit);
	
	foreach (@o_critL) {
		if ($_ eq $gateway) {
			$exit_val = $ERRORS{"WARNING"};
		}	
	}
} else {
	if ($o_crit eq $gateway) {
		$exit_val = $ERRORS{"WARNING"};
	}	
}
	
print " CRITICAL" if ($exit_val eq $ERRORS{"CRITICAL"});
print " WARNING" if ($exit_val eq $ERRORS{"WARNING"});
print " OK" if ($exit_val eq $ERRORS{"OK"});

if (defined($o_perf)) {
	print " | Correct: $o_warn; Warning: $o_crit; Critical: Others\n";
} else {
	print "\n";
}

exit $exit_val;
