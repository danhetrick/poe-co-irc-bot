#!/usr/bin/perl
#
# poe-co-irc-bot.pl
#
# A bare-bones IRC bot skeleton, using Perl, POE, and
# POE::Component::IRC.
#
# It can load configuration files with Config::Tiny (which is built-in to
# this script); a default config file is included in the DATA section, which
# will be loaded if a config file can't be found.
#
# Most of the hard work is done :-)
# Have fun creating your bot
#
use strict;

use POE qw(Component::IRC);

# Script Settings
my $LWP_SIMPLE_LOADED = undef;
my $DEFAULT_SOCKS_PORT = 1080;
my $VERBOSE = undef;

# Bot settings
my $GET_EXTERNAL_IP_ADDRESS = undef;
my $GET_EXTERNAL_IP_ADDRESS_HOST = "http://myexternalip.com/raw";

# IRC settings
my $NICKNAME				= 'bot';
my $ALTERNATE_NICK			= 'b0t';
my $IRCNAME					= 'poco IRC bot';
my $USERNAME				= 'pocobot';
my $SERVER_ADDRESS   		= 'localhost';
my $SERVER_PORT				= 6667;
my $SERVER_PASSWORD			= undef;
my $EXTERNAL_IP				= undef;
my $DCC_PORTS				= '10000-11000';
my $CHANNELS				= '#foo,#bar,#baz:changeme,#bop';
my $PROXY					= '';
my $SOCKS					= '';
my $SOCKS_ID				= undef;
my $USE_IPV6				= undef;
my $NO_FLOOD_PROTECTION		= undef;
my $USE_SSL					= undef;
my $SSL_KEY					= undef;
my $SSL_CERT				= undef;

load_configuration_file("bot.ini");

# Parse setting inputs

if($GET_EXTERNAL_IP_ADDRESS){
	if  (
		eval {
			require LWP::Simple;
			1;
		}
	) {
		$LWP_SIMPLE_LOADED = 1;
		print "Getting external IP address...";
		my $ip = LWP::Simple::get($GET_EXTERNAL_IP_ADDRESS_HOST);
		$EXTERNAL_IP = $ip;
		print "done!\n";
	} else {
		print "Unable to retrieve external IP. Please install LWP::Simple to use this functionality.\n";
	}
}

my @CHANNELS_TO_JOIN = parse_irc_channel_list($CHANNELS);
my @USE_DCC_PORTS = parse_dcc_port_list($DCC_PORTS);
my ($PROXY_SERVER,$PROXY_PORT) = parse_proxy_entry($PROXY);
my ($SOCKS_SERVER,$SOCKS_PORT) = parse_socks_entry($SOCKS);

if($USE_SSL){
	if  (
		eval {
			require POE::Component::SSLify;
			1;
		}
	) {
		# SSL is available
		if(($SSL_KEY)&&($SSL_CERT)){
			if((-e $SSL_KEY)&&(-f $SSL_KEY)){}else{
				print "SSL Key \"$SSL_KEY\" not found.\n";
				exit 1;
			}
			if((-e $SSL_CERT)&&(-f $SSL_CERT)){}else{
				print "SSL Certificate \"$SSL_CERT\" not found.\n";
				exit 1;
			}
		} else {
			print "SSL Key and Certificate not set.\n";
			exit 1;
		}
	} else {
		print "SSL is not available. Please install POE::Component::SSLify to use this functionality.\n";
		exit 1;
	}
}

# We create a new PoCo-IRC object
my $IRC = POE::Component::IRC->spawn(
	nick => $NICKNAME,
	ircname => $IRCNAME,
	username => $USERNAME,
	server  => $SERVER_ADDRESS,
	port => $SERVER_PORT,
	password => $SERVER_PASSWORD,
	NATAddr => $EXTERNAL_IP,
	DCCPorts => \@USE_DCC_PORTS,
	Proxy => $PROXY_SERVER,
	ProxyPort => $PROXY_PORT,
	socks_proxy => $SOCKS_SERVER,
	socks_port => $SOCKS_PORT,
	socks_id => $SOCKS_ID,
	useipv6 => $USE_IPV6,
	Flood => $NO_FLOOD_PROTECTION,
	UseSSL => $USE_SSL,
	SSLCert => $SSL_CERT,
	SSLKey => $SSL_KEY,
	Raw => 1,
) or die "PoCo-IRC object creation failed!\n$!";

# Register which events we want to receive...
$IRC = POE::Session->create(
	package_states =>
		[ 'main' => [qw(_start irc_001 irc_public irc_msg irc_join
						irc_part irc_433 irc_ctcp_action irc_352 _beat
						irc_registered _default irc_dcc_start irc_dcc_done
						irc_dcc_chat irc_dcc_error irc_dcc_request irc_topic
						irc_mode irc_kick irc_invite irc_nick irc_notice
						irc_raw irc_raw_out irc_dcc_get irc_dcc_send
						)], ],
	heap => { irc => $IRC },
);

# Start up!
$poe_kernel->run();
exit 0;

# EVENTS

sub _default {

	# Uncomment the below code to see every bit of data sent
	# to us from the IRC server

    # my ($event, $args) = @_[ARG0 .. $#_];
    # my @output = ( "$event: " );
 
    # for my $arg (@$args) {
    #     if ( ref $arg eq 'ARRAY' ) {
    #         push( @output, '[' . join(', ', @$arg ) . ']' );
    #     }
    #     else {
    #         push ( @output, "'$arg'" );
    #     }
    # }
    # print join ' ', @output, "\n";

    undef;
}

sub _beat {
	my ( $kernel, $heap, $session ) = @_[ KERNEL, HEAP, SESSION ];

	$kernel->delay( _beat => 1 );

}

sub _start {
	my ( $kernel, $heap, $sender ) = @_[ KERNEL, HEAP, SENDER ];

	verbose("Starting bot...");

	$heap->{irc}->yield( register => 'all' );
	$kernel->delay( _beat => 1 );

}

sub irc_registered {
	my ( $kernel, $heap, $sender, $irc_object ) =
		@_[ KERNEL, HEAP, SENDER, ARG0 ];
	my $alias = $irc_object->session_alias();

	$irc_object->yield( connect => { } );

	verbose("Connecting bot to IRC...");

}

sub irc_001 {
	my ( $kernel, $heap, $sender ) = @_[ KERNEL, HEAP, SENDER ];

	verbose("Connected!");

	foreach my $chan (@CHANNELS_TO_JOIN) {
		my @ce = @{$chan};
		if($ce[1]){
			$heap->{irc}->yield( join => $ce[0] => $ce[1]);
		} else {
			$heap->{irc}->yield( join => $ce[0]);
		}
    	
    }

}

sub irc_join {
	my ( $kernel, $sender, $who, $where ) =
		@_[ KERNEL, SENDER, ARG0, ARG1 ];
	my $nick    = ( split /!/, $who )[0];
	my $hostmask    = ( split /!/, $who )[1];
	my $irc = $sender->get_heap();
	my $server_name = $irc->server_name();

	verbose("$nick($hostmask) joined $where");

}

sub irc_part {
	my ( $kernel, $sender, $who, $where, $msg ) =
		@_[ KERNEL, SENDER, ARG0, ARG1, ARG2 ];
	my $nick    = ( split /!/, $who )[0];
	my $hostmask    = ( split /!/, $who )[1];
	my $irc = $sender->get_heap();
	my $server_name = $irc->server_name();

	if($msg ne ''){
		verbose("$nick($hostmask) left $where ($msg)");
	} else {
		verbose("$nick($hostmask) left $where");
	}
}

sub irc_msg {
	my ( $kernel, $sender, $who, $where, $what ) =
		@_[ KERNEL, SENDER, ARG0, ARG1, ARG2 ];
	my $nick    = ( split /!/, $who )[0];
	my $hostmask    = ( split /!/, $who )[1];
	my $irc = $sender->get_heap();
	my $server_name = $irc->server_name();

	verbose("PRIVATE $nick($hostmask): $what");

}

sub irc_public {
	my ( $kernel, $sender, $who, $where, $what ) =
		@_[ KERNEL, SENDER, ARG0, ARG1, ARG2 ];
	my $nick    = ( split /!/, $who )[0];
	my $hostmask    = ( split /!/, $who )[1];
	my $channel = $where->[0];
	my $irc = $sender->get_heap();
	my $server_name = $irc->server_name();

	verbose("$channel $nick($hostmask): $what");

}

# nick in use
sub irc_433 {
	my ($kernel,$sender) = @_[KERNEL,SENDER];
	$kernel->post( $sender => nick => $ALTERNATE_NICK );

}

sub irc_ctcp_action {
	my ( $kernel, $sender, $who, $where, $what ) = @_[ KERNEL, SENDER, ARG0, ARG1, ARG2 ];
	my $nick     = ( split /!/, $who )[0];
	my $hostmask = ( split /!/, $who )[1];
	my $channel  = $where->[0];
	my $irc = $sender->get_heap();
	my $server_name = $irc->server_name();

	verbose("$where $nick($hostmask) $what");

}

sub irc_topic {
	my ( $kernel, $sender, $who, $where, $what ) =
		@_[ KERNEL, SENDER, ARG0, ARG1, ARG2 ];
	my $nick    = ( split /!/, $who )[0];
	my $hostmask    = ( split /!/, $who )[1];
	my $irc = $sender->get_heap();
	my $server_name = $irc->server_name();

	verbose("$where topic set to \"$what\" by $nick($hostmask)");

}

# who data
sub irc_352 {
	my ( $kernel, $sender, $serv, $data ) = @_[ KERNEL, SENDER, ARG0, ARG1 ];
	my $irc = $sender->get_heap();
	my $chan = ( split / /, $data )[0];
	my $server = $irc->server_name();
	my $nick = ( split / /, $data )[4];
	my $code = ( split / /, $data )[5];

}

sub irc_invite {
	my ( $kernel, $sender, $who, $where ) =
		@_[ KERNEL, SENDER, ARG0, ARG1 ];
	my $nick    = ( split /!/, $who )[0];
	my $hostmask    = ( split /!/, $who )[1];
	my $irc = $sender->get_heap();
	my $server_name = $irc->server_name();

	verbose("$nick($hostmask) invited me to $where");

}

sub irc_kick {
	my ( $kernel, $sender, $who, $where, $target, $why ) =
		@_[ KERNEL, SENDER, ARG0, ARG1, ARG2, ARG3 ];
	my $nick    = ( split /!/, $who )[0];
	my $hostmask    = ( split /!/, $who )[1];
	my $irc = $sender->get_heap();
	my $server_name = $irc->server_name();

	if($why ne ''){
		verbose("$nick($hostmask) kicked $target from $where ($why)");
	} else {
		verbose("$nick($hostmask) kicked $target from $where");
	}

}

sub irc_mode {
	my ( $kernel, $sender, $who, $target, $mode ) =
		@_[ KERNEL, SENDER, ARG0, ARG1, ARG2 ];
	my @ARGS = @_[ ARG3 .. $#_ ];
	my $nick    = ( split /!/, $who )[0];
	my $hostmask    = ( split /!/, $who )[1];
	my $irc = $sender->get_heap();
	my $server_name = $irc->server_name();
	my $arguments = join(' ',@ARGS);

	verbose("$nick($hostmask) set $mode on $target ($arguments)");

}

sub irc_nick {
	my ( $kernel, $sender, $who, $newnick ) =
		@_[ KERNEL, SENDER, ARG0, ARG1 ];
	my $nick    = ( split /!/, $who )[0];
	my $hostmask    = ( split /!/, $who )[1];
	my $irc = $sender->get_heap();
	my $server_name = $irc->server_name();

	verbose("$nick($hostmask) changed their nick to $newnick");

}

sub irc_notice {
	my ( $kernel, $sender, $who, $targets, $what ) =
		@_[ KERNEL, SENDER, ARG0, ARG1, ARG2 ];
	my $nick    = ( split /!/, $who )[0];
	my $hostmask    = ( split /!/, $who )[1];
	my $irc = $sender->get_heap();
	my $server_name = $irc->server_name();
	my $t = join(',',@{$targets});

	verbose("$nick($hostmask) sent a notice to $t: $what");

}

sub irc_raw {
	my ( $kernel, $sender, $raw ) =
		@_[ KERNEL, SENDER, ARG0 ];
	my $irc = $sender->get_heap();
	my $server_name = $irc->server_name();

}

sub irc_raw_out {
	my ( $kernel, $sender, $raw ) =
		@_[ KERNEL, SENDER, ARG0 ];
	my $irc = $sender->get_heap();
	my $server_name = $irc->server_name();

}

# DCC EVENTS

sub irc_dcc_request {
	my ($kernel, $heap, $who, $type, $port, $cookie, $filename, $size, $ip) =
		@_[KERNEL, HEAP, ARG0 .. ARG6];
	my $nick    = ( split /!/, $who )[0];
	my $hostmask    = ( split /!/, $who )[1];

}

sub irc_dcc_start {
	my ($kernel, $heap, $cookie, $nick, $type, $port, $ip) =
		@_[KERNEL, HEAP, ARG0, ARG1, ARG2, ARG3, ARG6];

}

sub irc_dcc_chat {
	my ($kernel, $heap, $cookie, $nick, $port, $line, $ip) =
		@_[KERNEL, HEAP, ARG0, ARG1, ARG2, ARG3, ARG4];

}

sub irc_dcc_done {
	my ($heap, $cookie, $nick, $type, $port, $ip) =
		@_[HEAP, ARG0, ARG1, ARG2, ARG3, ARG7];

}

sub irc_dcc_error {
	my ($heap, $cookie, $err, $nick, $type, $port, $ip) =
		@_[HEAP, ARG0 .. ARG4, ARG8];


}

# receive file
sub irc_dcc_get {
	my ($kernel, $heap, $cookie, $nick, $port, $file, $size, $transferred_size, $ip) =
		@_[KERNEL, HEAP, ARG0 .. ARG6];

}

# send file
sub irc_dcc_send {
	my ($kernel, $heap, $cookie, $nick, $port, $file, $size, $transferred_size, $ip) =
		@_[KERNEL, HEAP, ARG0 .. ARG6];

}

# SUPPORT SUBS

sub verbose {
	if($VERBOSE){
		foreach my $l (@_){
			print "$l\n";
		}
	}
}

# parse_socks_entry()
# Arguments: 1 (string)
# Returns: Array
# Description: Parses a SOCKS server entry. Format consists
#              of <server:<port>. If <port> is ommitted, a
#              default port of 1080 is assumed. Returns an
#              array with values:
#                   value[0] -> server
#                   value[1] -> port
#              Returns an array with two undefined values if
#              passed a malformed entry.
#
# Example Valid Inputs:
# 	socksproxy.com:2345
# 	43.56.78.12
sub parse_socks_entry {
	my $entry = shift;
	
	my($serv,$port) = split(':',$entry);
	if(($serv)&&($port)){
		return ($serv,$port);
	} else {
		# use default port if one isn't passed
		if($serv){
			return ($serv,$DEFAULT_SOCKS_PORT);
		}
		# malformed or no entry
		return (undef,undef);
	}
}

# parse_proxy_entry()
# Arguments: 1 (string)
# Returns: Array
# Description: Parses a proxy server entry. Format consists of
#              <server>:<port>. Returns an array with values:
#                   value[0] -> server
#                   value[1] -> port
#              If the entry is incorrectly formatted, or if
#              the ports is missing in the entry, an array
#              consisting of two undefined values is returned.
#
# Example Valid Inputs:
# 	proxyhost.net:1234
# 	12.34.56.78:54321
sub parse_proxy_entry {
	my $entry = shift;
	
	my($serv,$port) = split(':',$entry);
	if(($serv)&&($port)){
		return ($serv,$port);
	} else {
		# malformed or no entry
		return (undef,undef);
	}
}

# parse_irc_channel_list()
# Arguments: 1 (string)
# Returns: Array of arrays
# Description: Parses channel entries. Each channel consists
#              of an individual string, representing an IRC channel.
#              If a password for the channel is to be set, a
#              colon is entered after the channel name, followed
#              by the password. Returns an array of arrays, with
#              each entry being an arrayref to an array with two
#              values:
#                   value[0] -> channel name
#                   value[1] -> undef |OR| password
#
# Example Valid Inputs:
# 	#foo,#bar
# 	#baz
# 	#fubar:password,#barbaz,#test,#woot:changeme
sub parse_irc_channel_list {
	my $entry = shift;
	my @channels = ();
	
	foreach my $e (split(',',$entry)){
		my @ce = ();
		my($chan,$pass) = split(':',$e);
		if($pass){
			@ce = ($chan,$pass);
		} else {
			@ce = ($chan,undef);
		}
		push(@channels,\@ce);
	}
	return @channels;
}


# parse_dcc_port_list()
# Arguments: 1 (string)
# Returns: Array
# Description: Parses DCC port entries. Entry is a list of
#              numbers seperated by commas. Individial entries
#              can be a single number, or a range of numbers, in
#              the form of "minimum-maximum".
#
# Example Valid Inputs:
# 	10, 20, 30, 40
# 	5
# 	1000-2000,12,6,2100-2101
sub parse_dcc_port_list {
	my $entry = shift;
	my @ports = ();

	foreach my $e (split(',',$entry)){
		if($e=~/\-/){
			my @r = split('-',$e);
			if(scalar @r != 2){
				# malformed entry
			} else {
				if ($r[0] eq int($r[0]) && $r[0] > 0) {}else{
					# $r[0] is not a valid number
				}
				if ($r[1] eq int($r[1]) && $r[1] > 0) {}else{
					# $r[1] is not a valid number
				}
				foreach my $pe ($r[0]..$r[1]){
					push(@ports,$pe);
				}
			}
		} else {
			if ($e eq int($e) && $e > 0) {}else{
				# $e is not a valid number
			}
			push(@ports,$e);
		}
	}

	return @ports;
}

sub load_configuration_file {
	my $file = shift;

	my $c = undef;
	my @missing = ();

	if((-e $file)&&(-f $file)){
		$c = Config::Tiny->read($file);
	} else {
		$c = Config::Tiny->read_string(join('',<DATA>));
	}

	if($c){}else{
		print Config::Tiny->errstr."\n";
		exit 1;
	}

	# Mandatory settings

	if($c->{irc}->{nick}){
		$NICKNAME = $c->{irc}->{nick};
	} else {
		push(@missing,"No nickname set");
	}

	if($c->{irc}->{alternate}){
		$ALTERNATE_NICK = $c->{irc}->{alternate};
	} else {
		push(@missing,"No alternate nickname set");
	}

	if($c->{irc}->{server}){
		$SERVER_ADDRESS = $c->{irc}->{server};
	} else {
		push(@missing,"No IRC server set");
	}

	if($c->{irc}->{channels}){
		$CHANNELS = $c->{irc}->{channels};
	} else {
		push(@missing,"No IRC channels set");
	}

	# Optional settings

	if($c->{dcc}->{'get-external-ip'}){
		$GET_EXTERNAL_IP_ADDRESS = $c->{dcc}->{'get-external-ip'};
	}

	if($c->{dcc}->{'get-external-ip-host'}){
		$GET_EXTERNAL_IP_ADDRESS_HOST = $c->{dcc}->{'get-external-ip-host'};
	}

	if($c->{dcc}->{'external-ip'}){
		$EXTERNAL_IP = $c->{dcc}->{'external-ip'};
	}

	if($c->{options}->{verbose}){
		$VERBOSE = $c->{options}->{verbose};
	}

	if($c->{options}->{ipv6}){
		$USE_IPV6 = $c->{options}->{ipv6};
	}

	if($c->{options}->{proxy}){
		$PROXY = $c->{options}->{proxy};
	}

	if($c->{options}->{socks}){
		$SOCKS = $c->{options}->{socks};
	}

	if($c->{options}->{'socks-id'}){
		$SOCKS = $c->{options}->{'socks-id'};
	}

	if($c->{options}->{ssl}){
		$USE_SSL = $c->{options}->{ssl};
	}

	if($c->{options}->{noflood}){
		$NO_FLOOD_PROTECTION = $c->{options}->{noflood};
	}

	if($c->{ssl}->{key}){
		$SSL_KEY = $c->{ssl}->{key};
	}

	if($c->{ssl}->{certificate}){
		$SSL_CERT = $c->{ssl}->{certificate};
	}

	if($c->{irc}->{port}){
		$SERVER_PORT = $c->{irc}->{port};
	}

	if($c->{irc}->{ircname}){
		$IRCNAME = $c->{irc}->{ircname};
	}

	if($c->{irc}->{username}){
		$USERNAME = $c->{irc}->{username};
	}

	if($c->{dcc}->{'ports'}){
		$DCC_PORTS = $c->{dcc}->{'ports'};
	}

	# Check for missing options
	if(scalar @missing >=1){
		print join("\n",@missing)."\n";
		print "Please edit your configuration file.\n";
		exit 1;
	}

}

# ===============
# |CONFIG::TINY |
# ===============

package Config::Tiny;
 
# If you thought Config::Simple was small...
 
use strict;
 
# Warning: There is another version line, in t/02.main.t.
 
our $VERSION = '2.23';
 
BEGIN {
        require 5.008001;
        $Config::Tiny::errstr  = '';
}
 
# Create an empty object.
 
sub new { return bless {}, shift }
 
# Create an object from a file.
 
sub read
{
        my($class)           = ref $_[0] ? ref shift : shift;
        my($file, $encoding) = @_;
 
        return $class -> _error('No file name provided') if (! defined $file || ($file eq '') );
 
        # Slurp in the file.
 
        $encoding = $encoding ? "<:$encoding" : '<';
        local $/  = undef;
 
        open( CFG, $encoding, $file ) or return $class -> _error( "Failed to open file '$file' for reading: $!" );
        my $contents = <CFG>;
        close( CFG );
 
        return $class -> _error("Reading from '$file' returned undef") if (! defined $contents);
 
        return $class -> read_string( $contents );
 
} # End of read.
 
# Create an object from a string.
 
sub read_string
{
        my($class) = ref $_[0] ? ref shift : shift;
        my($self)  = bless {}, $class;
 
        return undef unless defined $_[0];
 
        # Parse the file.
 
        my $ns      = '_';
        my $counter = 0;
 
        foreach ( split /(?:\015{1,2}\012|\015|\012)/, shift )
        {
                $counter++;
 
                # Skip comments and empty lines.
 
                next if /^\s*(?:\#|\;|$)/;
 
                # Remove inline comments.
 
                s/\s\;\s.+$//g;
 
                # Handle section headers.
 
                if ( /^\s*\[\s*(.+?)\s*\]\s*$/ )
                {
                        # Create the sub-hash if it doesn't exist.
                        # Without this sections without keys will not
                        # appear at all in the completed struct.
 
                        $self->{$ns = $1} ||= {};
 
                        next;
                }
 
                # Handle properties.
 
                if ( /^\s*([^=]+?)\s*=\s*(.*?)\s*$/ )
                {
                        $self->{$ns}->{$1} = $2;
 
                        next;
                }
 
                return $self -> _error( "Syntax error at line $counter: '$_'" );
        }
 
        return $self;
}
 
# Save an object to a file.
 
sub write
{
        my($self)            = shift;
        my($file, $encoding) = @_;
 
        return $self -> _error('No file name provided') if (! defined $file or ($file eq '') );
 
        $encoding = $encoding ? ">:$encoding" : '>';
 
        # Write it to the file.
 
        my($string) = $self->write_string;
 
        return undef unless defined $string;
 
        open( CFG, $encoding, $file ) or return $self->_error("Failed to open file '$file' for writing: $!");
        print CFG $string;
        close CFG;
 
        return 1;
 
} # End of write.
 
# Save an object to a string.
 
sub write_string
{
        my($self)     = shift;
        my($contents) = '';
 
        for my $section ( sort { (($b eq '_') <=> ($a eq '_')) || ($a cmp $b) } keys %$self )
        {
                # Check for several known-bad situations with the section
                # 1. Leading whitespace
                # 2. Trailing whitespace
                # 3. Newlines in section name.
 
                return $self->_error("Illegal whitespace in section name '$section'") if $section =~ /(?:^\s|\n|\s$)/s;
 
                my $block = $self->{$section};
                $contents .= "\n" if length $contents;
                $contents .= "[$section]\n" unless $section eq '_';
 
                for my $property ( sort keys %$block )
                {
                        return $self->_error("Illegal newlines in property '$section.$property'") if $block->{$property} =~ /(?:\012|\015)/s;
 
                        $contents .= "$property=$block->{$property}\n";
                }
        }
 
        return $contents;
 
} # End of write_string.
 
# Error handling.
 
sub errstr { $Config::Tiny::errstr }
sub _error { $Config::Tiny::errstr = $_[1]; undef }

__DATA__
;
; pocoirc-bot.ini
;

[irc]

; Set the bot's nick
nick=bot

; Set the bot's alternate nick
alternate=b0t

; Set the bot's IRCname and username
ircname=poco the irc bot
username=bot

; Set the server and port the bot is to connect to
server=localhost
port=6667

; Set the channels you want the bot to join on connect
; Channels can be separated with commas; if a channel
; requires a password to join, attach a colon to the
; end of the channel name and enter the password, like
; so: #channel:password
channels=#foo,#bar:baz,#beep

[options]

; Set to 1 to turn on verbose more
verbose=1

; Set to 1 to use SSL to connect to IRC
ssl=0

; Set to 1 to use IPv6 for connections
ipv6=0

; Set to 1 to turn off flood protection
noflood=0

; Uncomment and edit to use a proxy server
;proxy=server:port

; Uncomment and edit to use a SOCKS/SOCKS4a server
;socks=server:port
;socks-id=none

[dcc]

; Set which ports to use with DCC
; Multiple ports can be set if separated by commas,
; or ranges can be set with "minimum-maximum"
ports=10000-11000

; Set the IP reported to other IRC users
external-ip=127.0.0.1

; Set this to 1 to fetch your external IP from an outside source
get-external-ip=0
get-external-ip-host=http://myexternalip.com/raw


[ssl]
key=file.key
certificate=file.cert
