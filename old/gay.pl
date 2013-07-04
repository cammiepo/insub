#!/usr/bin/perl -w
#
# a suite of text filters to annoy people :D
#
# author: cj_ <cjones@gmail.com>
#
# "If used sparingly, and in good taste, ASCII art generally
# is very well-received !"
#                             -- Some Sucker
#
# credits:
#    ben for banner leetness
#    Pi for the popeye filter
#    j0no for entirety of 8.7 release features and bugfixes
#    zb for adding ansi color support and putting this in ports :D
#    sisko for the original color script
#    various ideas from: tosat, jej, twid, cappy, rob
#    uke for the inspiration for the checker
#    hlprmnky for the jigs and for debugging
#    various stolen things: emacs spook file, jwz's scrambler script
#
# (this whole thing needs to be rewritten)
#
##############################################################################
# Copyright (c) 2003-2012, Chris Jones                                       #
# All rights reserved.                                                       #
#                                                                            #
# Redistribution and use in source and binary forms, with or without         #
# modification, are permitted provided that the following conditions are     #
# met:                                                                       #
#                                                                            #
#  1. Redistributions of source code must retain the above copyright         #
#     notice, this list of conditions and the following disclaimer.          #
#                                                                            #
#  2. Redistributions in binary form must reproduce the above copyright      #
#     notice, this list of conditions and the following disclaimer in        #
#     the documentation and/or other materials provided with the             #
#     distribution.                                                          #
#                                                                            #
# THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS    #
# IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO,  #
# THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR     #
# PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT HOLDER OR          #
# CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL,      #
# EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO,        #
# PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR         #
# PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF     #
# LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING       #
# NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS         #
# SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.               #
##############################################################################

use strict;
use Encode;
use Unicode::Normalize;
use Text::Wrap;
use IPC::Open3;
use vars qw/$VERSION %IRSSI $SPLASH $NAME $CONTEXT $OUTPUT/;
use vars qw/$BASH_PROMPT $ANSI/;

$| = 1;

$NAME = 'gay';
$VERSION = '16.0';

%IRSSI = (
	name		=> $NAME,
	version		=> $VERSION,
	author		=> 'cj_',
	contact		=> 'cjones@gmail.com',
	download	=> 'https://github.com/cjones/insub',
	description	=> 'a lot of annoying ascii color/art text filters',
	license		=> 'BSD',
);

##########################################
# Figure out where we are being run from #
# and set up the environment properly    #
##########################################

if ($ENV{'REQUEST_METHOD'}) {
	# cgi.. color routine should use
	# markup instead of ansi or mirc
	$CONTEXT = 'cgi';
	$OUTPUT = 'html';
} else {
	$OUTPUT = 'irc';
	eval { Irssi::Core::is_static() };
	if ($@) {
		# this indicates that there is no irssi.. HENCE
		# we are being run from somewhere else.  do not use
		# Irssi extensions
		$CONTEXT = 'terminal';
	} else {
		# no problems?  great.  preload Irssi functions
		$CONTEXT = 'irssi';
		eval 'use Irssi;';
	}
}

# being run from the command line, oh my.. use ANSI
# for color sequences instead of mirc
if ($CONTEXT eq 'terminal') {
	eval 'use Term::ANSIColor';
	$ANSI = $@ ? 0 : 1;
	$OUTPUT = 'ansi' if $ANSI;
}

# a place to cache stdin data
my $stdin;

# some command names based on our root name
my $EXEC = $NAME . "exec";
my $CAT  = $NAME . "cat";

# Time::HiRes only works on some systems that support
# gettimeofday system calls.  safely test for this
my $can_throttle = 0;
eval "use Time::HiRes"; 
unless ($@) { $can_throttle = 1 }

### console printing functions

sub cprint_lines {
	my $text = shift;
	foreach my $line (split(/\n/, $text)) {
		cprint("$line\n");
	}
}

sub cprint {
	my $text = shift;
	$text =~ s/\n//g;
	if ($CONTEXT eq "irssi") {
		Irssi::print($text);
	} else {
		print $text, "\n";
	}
}



# defaults
my $settings = {
	cowfile			=> "default",
	cowpath			=> undef,
	figfont			=> "standard",
	linewrap		=> 70,
	rainbow_offset		=> 0,
	rainbow_keepstate	=> 1,
	keepstate_file		=> $ENV{HOME} . "/.$NAME-state",
	default_style		=> 1,
	check_size		=> 3,
	check_text		=> 0,
	check_colors		=> "4,2",
	matrix_size		=> 6,
	matrix_spacing		=> 2,
	colcat_max		=> 2048,
	jive_cmd		=> "jive",
	spook_words		=> 6,
	hug_size		=> 5,
	sine_height		=> 5,
	sine_frequency		=> "0.3",
	sine_background		=> " ",
	banner_style		=> "phrase",
};

# wrap settings routines.. irssi cares about type
# perl doesn't.. go figure

sub settings_get_str {
	my $key = shift;
	if ($CONTEXT eq 'irssi') {
		return Irssi::settings_get_str($key);
	} else {
		return $settings->{$key};
	}
}

sub settings_get_int {
	my $key = shift;
	if ($CONTEXT eq 'irssi') {
		return Irssi::settings_get_int($key);
	} else {
		return $settings->{$key};
	}
}

sub settings_get_bool {
	my $key = shift;
	if ($CONTEXT eq 'irssi') {
		return Irssi::settings_get_bool($key);
	} else {
		return $settings->{$key};
	}
}

sub settings_set_int {
	my $key = shift;
	my $val = shift;
	if ($CONTEXT eq 'irssi') {
		Irssi::settings_set_int($key, $val);
	} else {
		$settings->{$key} = $val;
	}
}



#######################
# define some globals #
#######################

# type of cow variable
my $thoughts;

# usage/contact info
$SPLASH = "$IRSSI{name} $IRSSI{version} by $IRSSI{author} <$IRSSI{contact}>";

my $USAGE;
if ($CONTEXT eq 'irssi' or $OUTPUT eq 'irc') {
	$USAGE = "/$NAME";
} elsif ($CONTEXT eq 'terminal' or $OUTPUT eq 'ansi') {
	$USAGE = $0;
}

$USAGE .= <<EOU;
 [-usage|-help|-version|-colors] [filters ...] [text ...]

 FILTERS:
     [-YES] [-blink] [-jive] [-exec] [-cow] [-cowfile <cow>] [-capchk] [-think]
     [-fig] [-font <font>] [-box] [-3d] [-arrow] [-diag] [-banner]
     [-banstyle <phrase|line|letter|char:?>] [-check] [-matrix] [-strip]
     [-spook] [-scramble] [-mirror] [-rotate] [-rev] [-leet] [-hug] [-flip]
     [-fake] [-ircii] [-jigs] [-tree] [-popeye] [-sine] [-chalk]
     [-throttle <ms>] [-repeat <#>] [-rainbow <map>] [-skew <#>] [-msg <nick>]
     [-pre <str>] [-cmd <cmd>]
EOU


my $blink = "\x1b[5m";

my $ansi_map = {
	0 => 'white',
	1 => 'black',
	2 => 'blue',
	3 => 'green',
	4 => 'bold red',
	5 => 'red',
	6 => 'magenta',
	7 => 'yellow',
	8 => 'bold yellow',
	9 => 'bold green',
	10 => 'cyan',
	11 => 'bold cyan',
	12 => 'bold blue',
	13 => 'bold magenta',
	14 => 'bold black',
	15 => 'bold white',
};

# This would probably be better as actual font attributes
# because we might want to use 'bold' or something.
# then we can just close with </font>
my $html_map = {
	0 => '#ffffff',
	1 => '#000000',
	2 => '#000088', # blue
	3 => '#00ff00',
	4 => '#880000',
	5 => '#ff5555',  # yellow?
	6 => '#ff00ff',
	7 => '#ff0000',
	8 => '#ff9999',  #bold yello?
	9 => '#008800',
	10 => '#004400', #cyan?
	11 => '#008800', #bold cyan?
	12 => '#0000ff', #bold blue',
	13 => '#ff00ff', #bold magenta',
	14 => '#333333', #bold black',
	15 => '#ffffff', #bold white',
};

# This could be better, if orkut's formatting worked as advertised.
my $orkut_map = {
	0 => 'white',
	1 => 'black',
	2 => 'navy', # blue
	3 => 'lime',
	4 => 'maroon',
	5 => 'gold',  # yellow?
	6 => 'purple',
	7 => 'red',
	8 => 'yellow',  #bold yello?
	9 => 'green',
	10 => 'teal',   #cyan?
	11 => 'aqua',   #bold cyan?
	12 => 'blue',   #bold blue
	13 => 'violet', #bold magenta
	14 => 'b',      #bold black
	15 => 'white',  #bold white
};

my $colorCodeMap = {
	r => 5,
	o => 4,
	y => 7,
	Y => 8,
	g => 3,
	G => 9,
	c => 10,
	C => 11,
	b => 2,
	B => 12,
	m => 6,
	M => 13,
	0 => 1,
	1 => 14,
	2 => 15,
	w => 0,
};

my $has_color = 0;
my $prev_fg_color;
my $prev_bg_color;
sub do_color {
	my $text = shift;
	my $fg_col = shift;
	my $bg_col = shift;
	my $format = shift || 'mirc';

	if ($format eq 'code') {
		$fg_col = $colorCodeMap->{$fg_col} if defined $fg_col;
		$bg_col = $colorCodeMap->{$bg_col} if defined $bg_col;
	}

	$has_color = 1;

	my $ret;
	if ($OUTPUT eq 'irc') {
		$ret = "\003$fg_col";

		if (defined $bg_col) {
			$ret .= ",$bg_col";
		}
		
		# if first char is a , or number,
		# we need some esc char's so the color thingy
		# doesn't get confused
		my $ord = ord(substr($text, 0, 1));
		if (($ord >= 48 and $ord <= 57) or $ord == 44) {
			$ret .= "\26\26";
		}

		# mIRC remove formatting character
		return ($ret . $text . "\x0F");
	} elsif ($OUTPUT eq 'ansi') {
		$ret = Term::ANSIColor::color($ansi_map->{$fg_col});

		$ret = '\[' . $ret if ($BASH_PROMPT);

		# hack  :(
		if (defined $bg_col) {
			my $bg = $ansi_map->{$bg_col};
			$bg =~ s/bold //;
			$bg = "on_$bg";
			$ret .= Term::ANSIColor::color($bg);
		}

		
		$ret .= '\]' if ($BASH_PROMPT);
		$ret .= $text;
		$ret .= '\[' if ($BASH_PROMPT);
		$ret .= Term::ANSIColor::color("reset");
		$ret .= '\]' if ($BASH_PROMPT);

		return $ret;
	} elsif ($OUTPUT eq 'html') {
		$bg_col ||= 1; # default to black

		# this is the best place to do this, probably
		$text =~ s/&/&amp;/g;
		$text =~ s/</&lt;/g;
		$text =~ s/>/&gt;/g;

		if ((defined($prev_bg_color) && $bg_col != $prev_bg_color) ||
		    (defined($prev_fg_color) && $fg_col != $prev_fg_color)) {
			$ret .= qq(</span>);
		}

		if ((defined($prev_bg_color) && $bg_col == $prev_bg_color) &&
		    (defined($prev_fg_color) && $fg_col == $prev_fg_color)) {
			$ret .= $text;
		} elsif ($bg_col == 1) {
			# black is assumed because of a div taggy
			$ret .= sprintf(
				qq(<span style="color:%s;">%s),
				$html_map->{$fg_col},
				$text,
			);
		} else {
			$ret .= sprintf(
				qq(<span style="color:%s;background-color:%s;">%s),
				$html_map->{$fg_col},
				$html_map->{$bg_col},
				$text,
			);
		}
		$prev_bg_color = $bg_col;
		$prev_fg_color = $fg_col;
		return $ret;
	} elsif ($OUTPUT eq 'bbcode') {
		$ret = sprintf(
			qq([color=%s]%s[/color]),
			$html_map->{$fg_col},
			$text,
		);

		return $ret;
	} elsif ($OUTPUT eq 'orkut') {
		# Orkut has not seen fit to make a colour white,
		# even though the forums don't have a white background.
		if ($orkut_map->{$fg_col} eq 'white') {
			$ret = ' ';
		} elsif ($orkut_map->{$fg_col} eq 'black') {
			$ret = $text;
		} else {
			$ret = sprintf(
				qq([%s]%s[/%s]),
				$orkut_map->{$fg_col},
				$text,
				$orkut_map->{$fg_col},
			);
		}

		return $ret;
	} elsif ($OUTPUT eq 'aim') {
		# In AIM, you better set the background and font on your own
		# AIM uses <body> tags and a custom <font> attribute to set
		# colour. There's really no way to paste it in, and have it
		# look good.

		# this is the best place to do this, probably
		$text =~ s/&/&amp;/g;
		$text =~ s/</&lt;/g;
		$text =~ s/>/&gt;/g;

		$ret = sprintf(
			qq(<font color="%s">%s</font>),
			$html_map->{$fg_col},
			$text,
		);

		return $ret;
	}


	return ($text);
}

sub show_colmap {
	foreach my $color (sort { $a <=> $b } keys %$ansi_map) {
		my $color_name = $ansi_map->{$color};
		my $msg = sprintf("%2d: %s\n", $color, $color_name);
		my $bg = ($color == 1) ? 0 : undef; # use white background for black
		cprint(do_color($msg, $color, $bg));
	}
}


# OH HAI THERE NSA
my @spook_lines = (
	# emacs
	"\$400 million in gold bullion",
	"[Hello to all my fans in domestic surveillance]", "AK-47", "ammunition",
	"arrangements", "assassination", "BATF", "bomb", "Cheney", "CIA",
	"class struggle", "Clinton", "Cocaine", "colonel", "counter-intelligence",
	"cracking", "Croatian", "cryptographic", "Delta Force", "DES",
	"domestic disruption", "explosion", "FBI", "fissionable", "FSF",
	"Ft. Bragg", "Ft. Meade", "genetic", "Honduras", "jihad", "Kennedy",
	"KGB", "Khaddafi", "kibo", "Legion of Doom", "Liberals", "Marxist",
	"Mossad", "munitions", "Nazi", "NORAD", "Noriega", "North Korea", "NSA",
	"nuclear", "Ortega", "Panama", "Peking", "PLO", "plutonium", "Qaddafi",
	"quiche", "radar", "Rule Psix", "Saddam Hussein", "SDI", "SEAL Team 6",
	"security", "Semtex", "Serbian", "smuggle", "South Africa", "Soviet",
	"spy", "strategic", "supercomputer", "terrorist", "Treasury", "Uzi",
	"Waco, Texas", "World Trade Center",
	
	# hugs
	"9-11", "Al Jazeera", "Al Qaeda", "Arabs", "Arafat", "Ashcroft", "Bush",
	"Chemical Ali", "conspiracy", "Diebold", "Eggs", "Embedded Journalism",
	"Fallujah", "Free Masons", "GOP", "Grass Roots", "Hamas", "IndyMedia",
	"Israel", "Kerry", "Kill the president", "Libya", "Lockheed-Martin",
	"Muslim", "Palestine", "Patriot Act", "Punch-cards", "Republican",
	"Rocket Propelled Grenades", "Shiite", "Skull and Bones", "Terrorism",
	"Voter Fraud", "war profiteering",
	
	# blog
	"2.3 Oz. cocaine", "20755-6000", "Al Amn al-Askari", "anarchy", "ASPIC",
	"assasinate", "assassinate", "Bletchley Park", "Clandestine",
	"Compsec 97", "Computer Terrorism", "Counter Terrorism Security",
	"Counterterrorism", "DefCon V", "Defense Information Warfare",
	"Defensive Information", "eavesdropping", "echelon",
	"Electronic Surveillance", "Encryption", "Enemy of the State",
	"Espionage", "Europol", "Glock 26", "HALO", "HERF pipe-bomb",
	"Information Security", "Information Terrorism", "Information Warfare",
	"InfoSec", "Lebed", "MI6", "Military Intelligence", "nailbomb",
	"National Information Infrastructure", "Offensive Information",
	"Offensive Information Warfare", "Ortega Waco", "Privacy", "Rewson",
	"Roswell", "SAFE", "Satellite imagery", "Sayeret Mat\'Kal", "Soros",
	"Spetznaz", "Steak Knife", "subversives", "Ufologico Nazionale",
	"Undercover", "Verisign", "Waco", "Waihopai", "White House", "Whitewater",
	"wire transfer", "World Domination",
	
	# prism
	"1071", "1080H", "15kg", "1911", "1984", "1997", "22nd SAS",
	"2600 Magazine", "312", "3848", "3B2", "414", "50BMG", "707", "737",
	"747,777", "757", "767", "8182", "868", "888", "ABC", "ACC", "Active X",
	"ADIU", "advise", "advisors", "afsatcom", "AFSPC", "AHPCRC", "AIEWS",
	"AIMSX", "Aladdin", "Alica", "Alouette,executive", "AMEMB", "Amherst",
	"AMW", "ANC", "Anonymous", "AOL", "AOL TOS", "ARC", "Archives", "Area51",
	"argus", "Armani", "ARPA", "Artichoke", "ASIO", "ASIS", "ASLET", "Asset",
	"AT&T", "Atlas", "Audiotel", "Austin", "AVN", "B.D.M.,Sphinx", "Badger",
	"bank", "basement", "BBE", "BECCA", "Becker", "beef", "Bess", "bet",
	"Beyond Hope", "BfV", "BITNET", "black-bag", "Black-Ops", "Blackbird",
	"Blacklisted 411", "Blackmednet", "Blacknet", "Blowfish", "Blowpipe",
	"BMDO", "BND", "Bob", "BOP", "BOSS", "botux", "BRLO", "Broadside",
	"Bubba", "Bubba the Love Sponge", "bullion", "BVD", "Cable & Wireless",
	"CANSLO", "Cap-Stun", "Capricorn", "CATO", "CBM", "CBNRC", "CBOT", "CCC",
	"CCS", "CDA", "CDC", "cdi", "CESID", "CFC", "chaining", "chameleon man",
	"Chan", "Chelsea", "Chicago Posse", "Chobetsu", "chosen", "CID", "CIDA",
	"CIM", "CIO", "CIS", "CISE", "clone", "COCOT", "Coderpunks", "codes",
	"Cohiba", "Comirex", "Competitor", "Compsec", "Consul", "CONUS",
	"Cornflower", "Corporate Security", "COS", "COSMOS", "Covert Video",
	"Cowboy", "CQB", "CRA", "credit card", "cryptanalysis", "crypto-anarchy",
	"CSE", "csystems", "CTP", "CTU", "CUD", "cybercash", "Cypherpunks",
	"D-11", "Daisy", "data havens", "data-haven", "DATTA", "DCJFTF", "Dead",
	"DEADBEEF", "debugging", "Defcon", "defence Information Warfare", "Delta",
	"DERA", "DEVGRP", "DIA", "Dictionary", "Digicash", "DITSA", "DJC", "DOE",
	"Dolch", "DRA", "DREC", "DREO", "DSD", "DSS", "Duress", "DynCorp",
	"e-cash", "E.T.", "E911", "EADA", "EDI", "EG&G", "Egret", "Elvis",
	"Embassy", "enigma", "EOD", "ESN", "ETA", "eternity server", "EUB",
	"Event Security", "Exon Shell", "explicit", "Face", "fangs", "Fax",
	"Fax encryption", "FBIS", "FCIC", "FDM", "Fetish", "FINCEN", "finks",
	"Firewalls", "FIS", "fish", "FKS", "Flame", "Flashbangs", "FLETC",
	"Flintlock", "FLiR", "Flu", "FMS", "force", "Fort Meade", "Forte",
	"fraud", "freedom", "Freeh", "froglegs", "FSB", "FXR", "Gamma", "garbage",
	"Gatt", "GCHQ", "GEO", "GEODSS", "GEOS", "Geraldton", "GGL", "GIGN",
	"Gist", "Global", "Glock", "GOE", "Goodwin", "Gorelick", "gorilla",
	"Gorizont", "government", "GPMG", "grey Data", "grom", "GRU", "GSA",
	"GSG-9", "GSS", "Guppy", "H&K", "H.N.P.", "Hackers", "HAHO", "Halcon",
	"Halibut", "Harvard", "hate", "HIC", "High Security", "Hillal", "HoHoCon",
	"Hollyhock", "HPCC", "HRT", "HTCIA", "humint", "Hutsul", "IACIS", "ICE",
	"IDEA", "IDF", "IDP", "illuminati", "IMF", "Indigo",
	"industrial espionage", "industrial intelligence", "Infowar",
	"Ingram Mac-10", "INR", "INS", "interception", "Internet Underground",
	"Intiso", "Investigation", "Ionosphere", "IRIDF", "Iris", "IRS", "ISA",
	"ISACA", "ISI", "ISN", "ISS", "jack", "JANET", "Jasmine", "JAVA", "JICC",
	"JITEM", "Juile", "Juiliett Class Submarine", "Keyhole", "Kh-11",
	"Kilderkin", "Kilo Class", "Kiwi", "KLM", "l0ck", "LABLINK", "Lacrosse",
	"LEETAC", "Leitrim", "Lexis-Nexis", "LLC", "loch", "lock picking",
	"Locks", "Loin", "LRTS", "LUK", "Lynch", "M-14", "M.P.R.I.", "M72750",
	"Mace", "Macintosh Firewalls", "Macintosh Internet Security",
	"Macintosh Security", "mailbomb", "Mantis", "market", "Masuda",
	"Mavricks", "Mayfly", "MCI", "MD2", "MD4", "MD5", "MDA", "Medco", "mega",
	"Menwith", "Merlin", "Meta-hackers", "MI-17", "MI5", "Middleman",
	"Military", "Minox", "MIT", "MITM", "MOD", "MOIS", "mol", "Mole",
	"Morwenstow", "Mossberg", "MP5k", "MP5K-SD", "MSCJ", "MSEE", "MSNBC",
	"MSW", "MYK", "NACSI", "NATIA", "NATOA", "NAVWAN", "NAVWCWPNS", "NCCS",
	"NCSA", "Nerd", "niche", "NIJ", "Nike", "NIMA", "ninja", "nitrate",
	"nkvd", "NOCS", "NRC", "NRL", "NRO", "NSCT", "NSG", "NSP", "NSWC", "NTIS",
	"NTT", "NVD", "OAU", "Oratory", "orthodox", "Oscor", "OSS", "OTP",
	"package", "passwd", "Passwords", "Patel", "PBX", "PCS", "Peering", "PEM",
	"penrep", "Perl-RSA", "PFS", "PGP", "PGP 2.6.2.", "PGP 5.0i", "PGP 5.1",
	"PGP 5.53", "Phon-e", "Pine Gap", "pink noise", "Pixar", "PLA",
	"Planet-1", "Platform", "Playboy", "POCSAG", "Police", "Porno",
	"Pornstars", "PPP", "PPS", "president", "press-release", "Pretoria",
	"Priavacy", "primacord", "PRIME", "Propaganda", "PSAC", "Pseudonyms",
	"Psyops", "PTT", "r00t", "racal", "RAID", "rail gun", "Rand Corporation",
	"Rapid Reaction", "RCMP", "rebels", "Recce", "Red Cell", "redheads",
	"Reflection", "remailers", "ReMOB", "Reno", "replay", "Retinal Fetish",
	"RFI", "rhost", "rhosts", "RIT", "rogue", "Rolm", "Ronco", "RSA", "RSP",
	"RUOP", "RX-7", "S.A.I.C.", "S.E.T. Team", "S/Key", "SABC", "SACLANT",
	"SADF", "SADMS", "Salsa", "SAP", "SAR", "sardine", "SAS", "SASP", "SASR",
	"Satellite phones", "SBI", "SBIRS", "SBS", "SCIF", "screws", "Scully",
	"SEAL", "Sears Tower", "Secert Service", "Secure",
	"Secure Internet Connections", "secure shell", "Security Consulting",
	"Security Evaluation", "SEL", "SERT", "SETA", "Sex", "SGC", "SGDN", "SGI",
	"SHA", "SHAPE", "Shayet-13", "SHF", "SIG", "SIGDASYS", "SIGDEV",
	"sigvoice", "siliconpimp", "SIN", "SIRC", "SISDE", "SISMI", "Skytel",
	"SL-1", "SLI", "SLIP", "sneakers", "sniper", "snuffle", "SONANGOL",
	"SORO", "SORT", "Speakeasy", "speedbump", "spies", "Spoke",
	"spook keywords", "spook words", "Spyderco", "squib", "SRI", "ssa",
	"SSCI", "SSL", "stakeout", "Standford", "STARLAN", "Stego", "STEP",
	"Stephanie", "Steve Case", "Sugar Grove", "SUN", "Sundevil", "SURVIAC",
	"SUSLO", "SVR", "SWAT", "sweep", "sweeping", "SWS", "Talent",
	"TDM. SUKLO", "TDR", "TDYC", "Telex", "TELINT", "Templeton", "TEMPSET",
	"Terrorism Defensive Information", "Texas", "TEXTA. ELF", "THAAD", "the",
	"TIE", "Tie-fighter", "Time", "toad", "Tools", "top secret", "TRD",
	"Trump", "TRW", "TSCI", "TSCM", "TUSA", "TWA", "UDT", "UHF", "UKUSA",
	"unclassified", "UNCPCJ", "unix", "Unix Security", "UOP", "USACIL",
	"USAFA", "USCG", "USCODE", "USCOI", "USDOJ", "USP", "USSS", "UT/RUS",
	"utopia", "UTU", "UXO", "veggie", "VHF", "Vinnell", "VIP",
	"VIP Protection", "Virii", "virtual", "virus", "VLSI", "VNET",
	"Wackendude", "Wackenhutt", "WANK", "Weekly World News", "white noise",
	"William Gates", "WINGS", "WORM", "XS4ALL", "Yakima", "Yobie", "York",
	"Yukon", "Zen", "zip", "zone"
);

# leet mapping
my $leet_map = {
	a => [ "4", "/\\", "@", "a", "A" ],
	b => [ "|o", "b", "B" ],
	c => [ "C", "c", "<" ],
	d => [ "d", "D", "|)" ],
	e => [ "e", "E", "3" ],
	f => [ "f", "F", "/=" ],
	g => [ "g", "G", "6" ],
	h => [ "h", "H", "|-|" ],
	i => [ "i", "I", "|", "1" ],
	j => [ "j", "J" ],
	k => [ "keke", "x", "X", "k", "K", "|<" ],
	l => [ "l", "L", "7", "|_" ],
	m => [ "|V|", "|\\/|", "m", "M" ],
	n => [ "n", "N", "|\\|" ],
	o => [ "0", "o", "O", "()", "[]", "<>" ],
	p => [ "p", "P", "9" ],
	q => [ "q", "Q" ],
	r => [ "r", "R" ],
	s => [ "s", "S", "5" ],
	t => [ "t", "T", "7" ],
	u => [ "|_|", "u", "U", "\\/" ],
	v => [ "v", "V", "\\/" ],
	w => [ "w", "W", "uu", "UU", "uU", "Uu", "\\/\\/" ],
	x => [ "x", "X", "><" ],
	y => [ "y", "Y" ],
	z => [ "z", "Z", "5" ],
};

# 'jigs' mapping
my $jigs_map = {
	7	=> "8",
	8	=> "9",
	9	=> "0",
	0	=> "-",
	'-'	=> "=",
	'='	=> "7",
	y	=> "u",
	h	=> "j",
	n	=> "m",
	u	=> "i",
	j	=> "k",
	m	=> ".",
	i	=> "o",
	k	=> "l",
	","	=> ".",
	o	=> "p",
	l	=> ";",
	"."	=> "/",
	p	=> "[",
	";"	=> "'",
	"/"	=> "n",
	"["	=> "]",
	"]"	=> '\\',
	'"'	=> "h",
	'\\'	=> "u",
};

my @bash_map = (
	"a",
	"d",
	"D{[^{]*}",
	"e",
	"h",
	"H",
	"j",
	"l",
	"n",
	"r",
	"s",
	"t",
	"T",
	"@",
	"A",
	"u",
	"v",
	"V",
	"w",
	"W",
	"!",
	"#",
	"\\\$",
	"\\d{1,3}",
	"\\\\",
	"\\[",
	"\\]",
);


# random text for text substitution
# needless to say if someone has this string
# in their text, it'll get clobbered.
my $rnd = "rAnDoM";

# markup stuff
my $COWCUT = "---COWCUT---";

###############################
# these are the main commands #
###############################

sub insub {
	my $text = shift;

	if    ($text =~ /^(?:-YES )?-help/i  ) { show_help()               }
	elsif ($text =~ /^(?:-YES )?-vers/i  ) { cprint($SPLASH)           }
	elsif ($text =~ /^(?:-YES )?-update/i) { update()                  }
	elsif ($text =~ /^(?:-YES )?-usage/i ) { cprint_lines($USAGE)      }
	elsif ($text =~ /^(?:-YES )?-colors/i   ) { show_colmap()             }
	else                                  { process(undef, $text, @_) }
}

# these are aliases that use a predefined set of filters
sub insubexec { process("e",   @_) }    # execute
sub insubcat  { process("x",   @_) }	# byte restriction
sub gv        { process("v",   @_) }	# display version info

###############################
# this handles the processing #
###############################

sub process {
	my ($flags, $text, $server, $dest) = @_;

	$flags ||= ""; # silence undef warnings on cmd line

	
	if ($CONTEXT eq 'irssi') {
		if (!$server || !$server->{connected}) {
			cprint("Not connected to server");
			return;
		}

		return unless $dest;
	}

	# set up defaults
	my @text;
	my $prefix;
	my $cmd;
	my $style   = settings_get_int("default_style");
	my $cowfile = settings_get_str("cowfile");
	my $figfont = settings_get_str("figfont");
	my $banstyle = settings_get_str("banner_style");

	my $sendto = $dest->{name} if $dest;

	# allows commands to figure out target from context
	my $target;
	if ($dest && ($dest->{type} eq "CHANNEL" || $dest->{type} eq "QUERY")) {
		$target = $dest;
	} else {
		$target = $server;
	}

	# parse args
	my @args;
	my $error_returned = 0;
	if (defined $text) {
		(@args, $error_returned) = shellwords($text);
		return if $error_returned;
	}
	if ($CONTEXT eq 'irssi') {
        my $term_type = 'term_type';
        if (Irssi::version() > 20040819) { # when did the setting name change?
			$term_type = 'term_charset';
        }
		if (Irssi::settings_get_str($term_type) =~ /utf/i) {
			push @args, '-utf8';
		}
	}


	my $throttle = 0;
	my $force = 0;
	my $repeat;
	my $map;
	my $skew;
	while(1) {
		my $arg = shift(@args); last if (!defined $arg);
		if ($arg =~ /^-msg/)      { $sendto = shift(@args); next }
		if ($arg =~ /^-pre/)      { $prefix = shift(@args); next }
		if ($arg =~ /^-cmd/)      { $cmd    = shift(@args); next }
		if ($arg =~ /^-blink/)    { $flags .= "b"; next }
		if ($arg =~ /^-jive/)     { $flags .= "j"; next }
		if ($arg =~ /^-exec/)     { $flags .= "e"; next }
		if ($arg =~ /^-cowfile/)  { $cowfile = shift(@args); next }
		if ($arg =~ /^-cow/)      { $flags .= "c"; next }
		if ($arg =~ /^-fig/)      { $flags .= "f"; next }
		if ($arg =~ /^-font/)     { $figfont = shift(@args); next }
		if ($arg =~ /^-banstyle/) { $banstyle = shift(@args); next }
		if ($arg =~ /^-utf8/)     { $flags .= "8"; next }
		if ($arg =~ /^-box/)      { $flags .= "o"; next }
		if ($arg =~ /^-3d/)       { $flags .= "3"; next }
		if ($arg =~ /^-arrow/)    { $flags .= "a"; next }
		if ($arg =~ /^-diag/)     { $flags .= "D"; next }
		if ($arg =~ /^-banner/)   { $flags .= "B"; next }
		if ($arg =~ /^-check/)    { $flags .= "C"; next }
		if ($arg =~ /^-capchk/)   { $flags .= "h"; next }
		if ($arg =~ /^-matrix/)   { $flags .= "m"; next }
		if ($arg =~ /^-strip/)    { $flags .= "n"; next }
		if ($arg =~ /^-spook/)    { $flags .= "s"; next }
		if ($arg =~ /^-scramble/) { $flags .= "S"; next }
		if ($arg =~ /^-mirror/)   { $flags .= "M"; next }
		if ($arg =~ /^-rotate/)   { $flags .= "4"; next }
		if ($arg =~ /^-rev/)      { $flags .= "R"; next }
		if ($arg =~ /^-leet/)     { $flags .= "l"; next }
		if ($arg =~ /^-hug/)      { $flags .= "H"; next }
		if ($arg =~ /^-flip/)     { $flags .= "F"; next }
		if ($arg =~ /^-fake/)     { $flags .= "I"; next }
		if ($arg =~ /^-ircii/)    { $flags .= "d"; next }
		if ($arg =~ /^-jigs/)     { $flags .= "J"; next }
		if ($arg =~ /^-tree/)     { $flags .= "t"; next }
		if ($arg =~ /^-think/)    { $flags .= "T"; next }
		if ($arg =~ /^-unused/)   { $flags .= "u"; next }
		if ($arg =~ /^-popeye/)   { $flags .= "p"; next }
		if ($arg =~ /^-sine/)     { $flags .= "w"; next }
		if ($arg =~ /^-wave/)     { $flags .= "w"; next } # bck compat
		if ($arg =~ /^-YES/i)     { $force = 1; next    }
		if ($arg =~ /^-chalk/i)   { $flags .= "P"; next }
		if ($arg =~ /^-thro/)     { $throttle = shift(@args); next }
		if ($arg =~ /^-repeat/)   { $repeat   = shift(@args); next }
		if ($arg =~ /^-rain/)     { $map = shift(@args); $flags .= 'r'; next }
		if ($arg =~ /^-skew/)	  { $skew = shift(@args); next }

		# this is getting trickier
		if ($arg =~ /^-(\d+)$/) {
			$flags .= "r";
			if    ($1 == 1) { $style = 'rainbow' }
			elsif ($1 == 2) { $style = 'usa' }
			elsif ($1 == 3) { $map = random_colmap()}
			elsif ($1 == 4) { $style = 'randcol' }
			elsif ($1 == 5) { $style = 'grey' }
			elsif ($1 == 6) { $style = 'scale' }
			elsif ($1 == 7) { $style = 'xmas' }
			elsif ($1 == 8) { $style = 'canada' }
			next;
		} elsif ($arg =~ /^-4(\w+)$/) {
			$flags .= "r";
			$style = $1;
			next;
		}

		# doesn't match arguments, must be text!
		push(@text, $arg);
	}
	$text = join(" ", @text);
	$text =~ s/\\n/\n/sg;
	Encode::_utf8_on($text) if $flags =~ /8/;

	########################################
	# sanity check before applying filters #
	########################################
	
	if ($flags =~ /c/ and $flags =~ /T/) {
		cprint("This cow cannot THINK and SPEAK at the same time.");
		return;
	}

	if ($flags =~ /c/) { $thoughts = "\\" }
	if ($flags =~ /T/) { $thoughts = "o"  }
	
	# this stuff tries to protect you from yourself
	# .. using -YES will skip this
	unless ($force) {
		if ($flags =~ /h/ and $flags =~ /M/) {
			cprint("Combining -capchk and -mirror is bad, mkay (try -YES)");
			return;
		}

		if ($flags =~ /s/ and $flags =~ /f/) {
			cprint("Spook and figlet is probably a bad idea (see: -YES)");
			return;
		}
	}

	# for outlining, precedence must be set
	# 3dbox > arrow > box
	$flags =~ s/(o|a)//g if $flags =~ /3/;
	$flags =~ s/o//g     if $flags =~ /a/;

	# check should override rainbow for now
	$flags =~ s/r//g if $flags =~ /C/;

	# ... so should capchk, unless it's a cow, in which case
	# we invoke cowcut-fu
	my $cowcut = 0;
	if ($flags =~ /h/) {
		# yes, capchk was specified
		if ($flags =~ /c/ and $flags =~ /r/) {
			$cowcut = 1;
		} else {
			$flags =~ s/r//g;
		}
	}

	# capchk takes precedence over check
	$flags =~ s/C//g if $flags =~ /h/;

	# the TREE cannot be colored
	$flags =~ s/r//g if $flags =~ /t/;

	if ($throttle) {
		unless ($can_throttle) {
			cprint("Sorry, your system does not allow high resolution sleeps");
			return;
		}

		if ($throttle < 5 or $throttle > 10_000) {
			cprint("Please use a throttle between 10ms and 10,000ms");
			return;
		}

		$throttle = $throttle / 1000;
	}

	if (defined $repeat) {
		$repeat =~ s/[^0-9]//g;
		if ($repeat > 1) {
			$text = $text x $repeat;
		}
	}


	##############################
	# filter text based on flags #
	##############################
	
	my $flag_list = "348BCDFHIJMRSTabcdefhjlmnoprstuvwxP";

	# flag sanity check.  because there are a lot of flags,
	# require master list to contain all viable flags
	if ($flag_list =~ /(.).*\1/) {
		cprint("There was an internal error with flag processing: duplicate ($1)");
		return;
	}

	foreach my $f (split(//, $flags)) {
		if ($flag_list !~ /$f/) {
			cprint("There was an internal error with flag processing: missing ($f)");
			return;
		}
	}

	# validate utf8 support, only works in 5.8+
	my $utf8 = ($flags =~ /8/ && $] >= 5.008);

	# most useful command yet
	if ($flags =~ /u/) {
		cprint("Sorry, the -unused flag is unsupported.");
		return;
	}
	
	# where to get text
	$text = "$IRSSI{name} $IRSSI{version} - $IRSSI{download}" if $flags =~ /v/;
	$text = $stdin                   if defined($stdin);
	$text = NFD($text);
	$text = execute($text)           if $flags =~ /e/;
	$text = slurp($text, $utf8)      if $flags =~ /x/;
	$text = spookify($text)          if $flags =~ /s/;

	# change the text contents itself
	$text = jive($text)              if $flags =~ /j/;
	$text = scramble($text)          if $flags =~ /S/;
	$text = leet($text)              if $flags =~ /l/;
	$text = reverse_ascii($text)     if $flags =~ /R/;
	$text = jigs($text)              if $flags =~ /J/;

	# change the text appearance
	$text = sine($text)              if $flags =~ /w/;
	$text = diagonal($text)          if $flags =~ /D/;
	$text = popeye($text)            if $flags =~ /p/;
	$text = matrix($text)            if $flags =~ /m/;
	$text = figlet($text, $figfont)  if $flags =~ /f/;
	$text = banner($text, $banstyle) if $flags =~ /B/;
	$text = hug($text)               if $flags =~ /H/;
	$text = rotate($text)            if $flags =~ /4/;
	$text = gwrap($text)             if $flags !~ /[f4]/;
	$text = chalkboard($text)        if $flags =~ /P/;

	# change the text presentation
	$text = checker($text)                    if $flags =~ /h/;
	$text = reverse_ascii($text)              if $flags =~ /M/;
	$text = cowsay($text, $cowfile, $cowcut)  if $flags =~ /(c|T)/;
	$text = reverse_ascii($text)              if $flags =~ /M/ and $flags =~ /(c|T)/;
	$text = upside_down($text)                if $flags =~ /F/;
	$text = checker($text)                    if $flags =~ /C/;

	# draw a box, pass a style flag
	$text = outline($text, 0)                 if $flags =~ /o/;
	$text = outline($text, 1)                 if $flags =~ /3/;
	$text = outline($text, 2)                 if $flags =~ /a/;

	# change the final products visual appearance
	$text = rainbow($text, $style, $map, $skew)   if $flags =~ /r/;
	$text = tree($text)              if $flags =~ /t/;
	$text = blink($text)             if $flags =~ /b/;

	# stuff to bust ircii :D
	$text = ircii_fake($text) if $flags =~ /I/;
	$text = ircii_drop($text) if $flags =~ /d/;

	$text = prefix($text, $prefix) if $prefix;
	$text = strip($text) if $flags =~ /n/;
	$text = NFC($text);

	########################
	# output final product #
	########################

	# don't go the final mile if a filter returned an error
	return unless (defined $text && (length($text) >= 1));

	# html needs to be handled with kids gloves
	if ($OUTPUT eq 'html') {
		print qq(<div style="background-color:black;color:white;"><pre>);
		
		# not colorized, we should look for
		# unescaped brackets ourselves,
		# since we can't reply on do_color() to handle
		# it.. this is ok since there won't be any html unless
		# it's from do_color
		unless ($has_color) {
			$text =~ s/&/&amp;/g;
			$text =~ s/</&lt;/g;
			$text =~ s/>/&gt;/g;
		}
	} elsif ($OUTPUT eq 'aim') {
		unless ($has_color) {
			$text =~ s/&/&amp;/g;
			$text =~ s/</&lt;/g;
			$text =~ s/>/&gt;/g;
		}
	}


	foreach my $line (split(/\n/, $text)) {
		if ($CONTEXT eq 'irssi') {
			$line = " " if $line eq ""; # hack
			my @cmd = ();
			push(@cmd, "msg");
			push(@cmd, "-channel") if ($server->{chat_type} =~ /^silc/i);
			push(@cmd, $sendto);
			$cmd = join(" ", @cmd) unless $cmd;
			$target->command("$cmd $line");
		} elsif ($CONTEXT eq 'terminal' or $CONTEXT eq 'cgi') {
			print $line, "\n";
		}

		if ($throttle) {
			Time::HiRes::sleep($throttle);
		}
	}

	if ($OUTPUT eq 'html') {
		print qq(</pre></div>\n);
	}
}

###########
# FILTERS #
###########

sub prefix {
	my ($text, $prefix) = @_;
	return if (!defined $text || !defined $prefix);

	my @new;
	foreach my $line (split(/\n/, $text)) {
		$line = "$prefix $line";
		push(@new, $line);
	}
	$text = join("\n", @new);

	return $text;
}

my $COWPATH;
sub find_cowpath {
	$COWPATH = $ENV{COWPATH} || "";
	return if -d $COWPATH;

	$COWPATH = settings_get_str("cowpath") || "";
	return if -d $COWPATH;

	my $cowsay_cmd = whereis("cowsay");
	if ($cowsay_cmd) {
		if (open(IN, "< $cowsay_cmd")) {
			while (my $line = <IN>) {
				if ($line =~ m!^\$cowpath = \$ENV\{'COWPATH'\} \|\| '(.*?)';!) {
					$COWPATH = $1;
					last;
				}
			}
			close IN;
		}
	}

	$COWPATH ||= "";

	return if -d $COWPATH;

	$COWPATH = undef;
	cprint("I could not figure out your COWPATH!!");
}

sub cowsay {
	# my cowsay implementation.. because normal cowsay
	# messes up bubble-size if you have imbedded
	# color codes.. this works pretty much the same,
	# except it doesn't have support for stuff like
	# tongue and eyes.

	my $text = shift;
	return if (!defined $text);

	my $cowfile = shift || "default";
	my $cowcut = shift;

	# my mother tried to find my cowpath once.. once.
	unless ($COWPATH) { find_cowpath() }

	unless ($COWPATH) {
		cprint("I cannot continue with cowsay, for there is no COWPATH!");
		return $text;
	}

	my @output;

	# this is the whole point of doing my own cowsay
	my $length = 0;
	my @text = split(/\n/, $text);
	foreach my $line (@text) {
		my $l = clean_length($line);
		$length = $l if $l > $length;
	}

	# add filler to the end
	foreach my $line (@text) {
		$line .= (" " x ($length - clean_length($line)));
	}

	my $div = " " . ("-" x ($length+2));
	push(@output, $div);
	push(@output, $COWCUT) if $cowcut;
	my $count = 0;
	my $total = scalar(@text) - 1;
	foreach my $line (@text) {
		if ($total == 0) {
			push(@output, "< $line >");
		} elsif ($count == 0) {
			push(@output, "/ $line \\");
		} elsif ($count == $total) {
			push(@output, "\\ $line /");
		} else {
			push(@output, "| $line |");
		}
		$count++;
	}
	
	# this is rainbow() markup for toggling colorize
	push(@output, $COWCUT) if $cowcut;
	push(@output, $div);

	if ($cowfile =~ /^<rand(om)?>$/i) {
		my @cowfiles;
		foreach my $dir (split(/:/, $COWPATH)) {
			unless (opendir(COWDIR, $dir)) {
				cprint("failed to open: $dir");
				return;
			}

			push(@cowfiles, grep(/\.cow$/, readdir(COWDIR)));
			close COWDIR;
		}

		$cowfile = $cowfiles[rand(@cowfiles)];
	}

	my $full;
	$cowfile .= ".cow" unless ($cowfile =~ /\.cow$/);
	if ($cowfile =~ m!/!) {
		$full = $cowfile;
	} else {
		foreach my $path (split(/:/, $COWPATH)) {
			if (-f "$path/$cowfile") {
				$full = "$path/$cowfile";
				last;
			}
		}
	}

	unless (-f $full) {
		cprint("could not find cowfile: $cowfile");
		return;
	}

	my $the_cow = "";
	my $eyes = "oo";
	my $tongue = "  ";

	# very odd.. unless $thoughts is addressed in some
	# fasion in this scope, eval doesn't notice it
	# i say this is a perl bug
	$thoughts = $thoughts;


	unless (open(IN, "<$full")) {
		cprint("couldn't read $full: $!");
		return;
	}
	my $cow_code = join('', <IN>);
	close IN;

	eval $cow_code;

	push(@output, split(/\n/, $the_cow));
	return join("\n", @output);
}

sub figlet {
	# pass text through figlet
	my $text = shift;
	return if (!defined $text);

	my $figlet_font = shift || 'standard';
	my $figlet_wrap = settings_get_int('linewrap');

	if ($figlet_font =~ /random/i) {
		chomp(my $fontdir = run(command => "figlet", args => "-I2"));

		if (opendir(FONTDIR, $fontdir)) {
			my @fonts = grep(s/\.flf$//, readdir(FONTDIR));
			close FONTDIR;

			$figlet_font = $fonts[rand(@fonts)];
		} else {
			cprint("could not open $fontdir");
			$figlet_font = "standard";
		}
	}

	my $output = run(
		command	=> "figlet",
		args	=> "-f $figlet_font -w $figlet_wrap",
		stdin	=> $text,
	) || return $text;

	$output =~ s/^\s+\n//g;     # sometimes it leaves leading blanks too!
	$output =~ s/\n\s+\n$//s;   # figlet leaves a trailing blank line.. sometimes

	return $output;
}

sub jive {
	# pass text through jive filter
	my $text = shift;
	return if (!defined $text);

	# see if we can find the program
	my $jive_cmd = settings_get_str('jive_cmd');
	$jive_cmd = -x $jive_cmd ? $jive_cmd : whereis("jive");
	unless (-x $jive_cmd) {
		cprint("$jive_cmd not found or not executable!");
		return;
	}

	my $pid = open3(
		\*WRITE, \*READ, \*ERR,
		$jive_cmd
	);

	print WRITE $text;
	close WRITE;

	$text = join('', <READ>);
	close READ;

	# check for errors
	cprint_lines(join('', <ERR>));
	close ERR;

	waitpid($pid, 0);

	return $text;
}

sub checker {
	# checker filter.  thanks to uke
	my $text = shift;
	return if (!defined $text);
	
	my $checksize = settings_get_int('check_size');
	my $checktext  = settings_get_int('check_text');

	my @colors = split(/\s*,\s*/, settings_get_str("check_colors"));

	my $rownum = 0;
	my $offset = 0;
	my @text = split(/\n/, $text);

	# what is the longest line?
	my $length = 0;
	foreach my $line (@text) {
		$length = length($line) if length($line) > $length;
	}

	foreach my $line (@text) {
		# pad line with whitespace
		$line .= (" " x ($length - length($line)));

		my $newline;
		my $state = 0;
		for (my $i = 0; $i < length($line); $i = $i + $checksize) {
			my $chunk = substr($line, $i, $checksize);
			my $index = ($state + $offset); $index -= scalar(@colors) if $index >= scalar(@colors);

			# add color
			$newline .= do_color($chunk, $checktext, $colors[$index]);
			$state++; $state = 0 if $state >= scalar(@colors);
		}

		$line = $newline;

		# increment rowcount/swap offset
		$rownum++;
		if ($rownum == $checksize) {
			$rownum = 0;
			$offset++; $offset = 0 if $offset >= scalar(@colors);
		}
	}
	return join("\n", @text);
}

sub get_state {
	my $state;
	if ($CONTEXT eq 'irssi') {
		$state = settings_get_int("rainbow_offset");
	} else {
		my $file = settings_get_str("keepstate_file");
		if (open(STATE, "< $file")) {
			$state = <STATE>;
			close STATE;
			chomp $state;
			$state =~ s/[^0-9]//g;
		}
	}

	$state ||= 0;
	return $state;
}

sub set_state {
	my $state = shift;
	if ($CONTEXT eq 'irssi') {
		settings_set_int("rainbow_offset", $state);
	} else {
		my $file = settings_get_str("keepstate_file");
		unlink($file);
		if (open(STATE, "> $file")) {
			print STATE "$state\n";
			close STATE;
		}
	}
}

# New way of doing it
my $rainbowMap = {
	rainbow	=> 'rrooyyYYGGggccCCBBbbmmMM',	# -1
	usa	=> 'oowwBB',			# -2
	blue	=> 'bB',			# -4blue
	green	=> 'gG',			# -4green
	purple	=> 'mM',			# -4purple
	grey	=> '12',			# -4grey (-5)
	yellow	=> 'yY',			# -4yellow
	red	=> 'or',			# -4red
	scale	=> 'ww22CC11CC22',		# -6
	xmas	=> 'og',			# -7
	canada	=> 'ooww',			# -8
};

sub random_colmap {
    my @map = keys %$colorCodeMap;
    fisher_yates_shuffle(\@map);
    return join('', @map);
}

sub rainbow {
	my $text = shift;
	my $style = shift || 'rainbow';
	my $map = shift;
	my $skew = shift || 1;

	return if !defined $text;

	my $offset = settings_get_bool('rainbow_keepstate') ? get_state() : 0;
	$map = $rainbowMap->{$style} if (!defined $map && exists $rainbowMap->{$style});

	return $text if !defined $map;

	my $colorize = 1;
	my $output = '';
	foreach my $line (split(/\r?\n/, $text)) {
		if ($line =~ /$COWCUT/) { $colorize++; next }
		if (!$colorize % 2) { $output .= "$line\n"; next }

		my $i = 0;
		foreach my $char ($line =~ /(\X)/g) {
			my $color = substr($map, ($offset + $i) % length($map), 1);
			$output .= do_color($char, $color, undef, 'code');
			$i++;
		}

		$offset += $skew;
		$output .= "\n";
	}

	set_state($offset) if settings_get_bool('rainbow_keepstate');
	return $output
}

sub blink {
	# make the text blink
	my $text = shift;
	return if (!defined $text);

	my @newtext;
	foreach my $line (split(/\n/, $text)) {
		if ($OUTPUT eq 'html') {
			push(@newtext, "<blink>$line</blink>");
		} else {
			push(@newtext, $blink . $line);
		}
	}
	return join("\n", @newtext);
}

sub clean_length {
	my $text = shift;
	return if (!defined $text);

	# generic mIRC color syntax
	$text =~ s/\x03\d{0,2}(,\d{0,2})?//g;

	# bold ^b, inverse ^v, underline ^_, clear ^O
	$text =~ s/\x02|\x16|\x1F|\x0F//g;

	# ansi
	$text =~ s/\x1b\[\d+(?:,\d+)?m//g;

	#html
	$text =~ s/<span[^>]+>//g;
	$text =~ s/<\/span>//g;

	if ($OUTPUT eq 'bbcode') {
		$text =~ s/\[color=(#[0-9a-f]{6}|[a-z]+)\]//ig;
		$text =~ s/\[\/color\]//ig;
	} elsif ($OUTPUT eq 'aim') {
		$text =~ s/<font[^>]+>//ig;
		$text =~ s/<\/font>//ig;
	} elsif ($OUTPUT eq 'orkut') {
		$text =~ 
		s/\[\/?(aqua|blue|fuchsia|gold|gray|green|lime|maroon|navy|olive|orange|pink|purple|red|silver|teal|violet|yellow|b|i|u)\]//ig;
	}

	return length($text);
}


sub matrix {
	# 0-day greetz to EnCapSulaTE1!11!one
	my $text = shift;
	return if (!defined $text);

	my $size = settings_get_int("matrix_size");
	my $spacing = settings_get_int("matrix_spacing");

	$size = 1 if ($size < 1);

	# first, let's dispense with the newlinesa
	# because they have no meaning up/down
	$text =~ s/\n/ /sg;

	my @text;
	my @matrix = $text =~ /(\X)/g;
	for (my $i = 0; $i < @matrix; $i += $size) {
		my @chunk = @matrix[$i..$i+$size-1];
		for (my $j = 0; $j < @chunk; $j++) {
			$text[$j] .= $chunk[$j] . (" " x $spacing);
		}
	}
	return join("\n", @text);
}

sub outline {
	# draw a box around text.. thanks 2 twid
	# for the idea
	my $text = shift;
	return if (!defined $text);
	
	my $style = shift;
	my ($_3d, $_arrow);

	if ($style == 1) {
		$_3d = 1;
	} elsif ($style == 2) {
		# arrow-style, thanks to rob
		$_arrow = 1;
	}
	
	my @text = split(/\n/, $text);

	# what is the longest line
	my $length = 0;
	
	foreach my $line (@text) {
		$length = clean_length($line) if clean_length($line) > $length;
	}

	# add box around each line
	my $lc = "|"; my $rc = "|";
	if ($_arrow) { $lc = ">"; $rc = "<" }
	foreach my $line (@text) {
		$line = "$lc $line" . (" " x ($length - clean_length($line) + 1)) . "$rc";
		$line .= " |" if ($_3d);
	}

	# top/bottom frame
	my ($top_frame, $bottom_frame);
	if ($_arrow) {
		$top_frame = "\\" . ("^" x ($length + 2)) . "/";
		$bottom_frame = "/" . ("^" x ($length + 2)) . "\\";
	} else {
		$top_frame = "+" . ("-" x ($length + 2)) . "+";
		$bottom_frame = $top_frame;
	}


	if ($_3d) {
		push(@text, $bottom_frame . "/");
		unshift(@text, $top_frame . " |");
	} else {
		push(@text, $bottom_frame);
		unshift(@text, $top_frame);
	}

	if ($_3d) {
		unshift(@text, " /" . (" " x ($length + 2)) . "/|");
		unshift(@text, "  " . ("_" x ($length + 3)));
	}


	return join("\n", @text);
}

sub whereis {
	# evaluate $PATH, since this doesn't seem to be inherited
	# in sh subproccess in irssi.. odd
	my $cmd = shift;
	my $path;
	
	# generate a lot of possible locations for cowsay path
	$path .= $ENV{PATH};
	$path .= ":/bin:/sbin:/usr/bin:/usr/sbin:/usr/local/bin:/usr/local/sbin";
	$path .= ":/usr/local/cowsay/bin:/opt/cowsay/bin";

	foreach my $path (split(/:/, $path)) {
		next unless $path;
		if (-x "$path/$cmd") {
			return "$path/$cmd";
		}
	}
}

sub slurp {
	# read in a file with max setting (useful for catting /dev/urandom :D )
	# maybe make this read in chunks, not by line, or something.. seems clumsy
	my $file = shift || return;
	my $utf8 = shift;

	# expand ~
	$file =~ s!^~([^/]*)!$1 ? (getpwnam($1))[7] : ($ENV{HOME} || $ENV{LOGDIR} || (getpwuid($>))[7])!ex;

	{
		my $result;
		if ($utf8) { eval '$result = open(IN, "<:utf8", "$file");' }
		else { $result = open(IN, "<$file"); }
		unless ($result) {
			cprint("could not open $file: $!");
			return;
		}
	}

	my $max = settings_get_int("colcat_max");
	my $text;
	while (my $line = <IN>) {
		$text .= $line;
		last if length($text) >= $max;
	}
	close IN;

	return $text;
}

sub execute {
	# execute command and return output
	my $text = shift;
	return if (!defined $text);

	my $pid = open3(
		\*WRITE, \*READ, \*ERR,
		$text
	);

	close WRITE;

	$text = join('', <READ>);
	close READ;
	
	# check for errors
	cprint_lines(join('', <ERR>));
	close ERR;

	waitpid($pid, 0);

	return $text;
}



sub show_help {
	my $help = <<EOH;
$USAGE

STYLES:
-1     rainbow
-2     red white and blue
-3     random colors
-4     random alternating colors
-5     alternating gray
-6     greyscale
-7     festive
-8     o'canada

IRC ONLY:
/$NAME          just like /say, but takes args
/$EXEC      like /exec
/$CAT       pipe a file
/gv           say version outloud

SETTINGS:
   cowfile
   cowpath
   figfont
   linewrap
   rainbow_offset
   rainbow_keepstate
   default_style
   check_size
   check_text
   check_colors
   matrix_size
   matrix_spacing
   colcat_max
   jive_cmd
   spook_words
   hug_size
   sine_height
   sine_frequency
   sine_background
EOH
	cprint_lines(draw_box($SPLASH, $help, undef, 1));
}

sub draw_box {
	# taken from a busted script distributed with irssi
	# just a simple ascii line-art around help text
	my ($title, $text, $footer, $color) = @_;

	$color = 0 unless $CONTEXT eq 'irssi';

	$footer = $title unless($footer);
	my $box;
	$box .= '%R,--[%n%9%U' . $title . '%U%9%R]%n' . "\n";
	foreach my $line (split(/\n/, $text)) {
		$box .= '%R|%n ' . $line . "\n";
	}
	$box .= '%R`--<%n' . $footer . '%R>->%n';
	$box =~ s/%.//g unless $color;
	return $box;
}

sub update {
	unless ($CONTEXT eq 'irssi') {
		warn "let's not do that outside irssi ok?\n";
		return;
	}

	# automatically check for updates
	my $updateURL = "https://raw.github.com/cjones/insub/master/old/" . $IRSSI{name} . ".pl";
	
	# do we have useragent?
	eval "use LWP::UserAgent";
	if ($@) {
		cprint("LWP::UserAgent failed to load: $!");
		return;
	}

	# first see what the latest version is
	my $ua = LWP::UserAgent->new();

	my $req = HTTP::Request->new(GET => $updateURL);
	my $script_dir = Irssi::get_irssi_dir() . "/scripts";

	my $saveTo = "$script_dir/downloaded-$IRSSI{name}.pl";
	my $res = $ua->request($req, $saveTo);
	if (!$res->is_success()) {
		cprint("Problem contacting the mothership: " . $res->status_line());
		return;
	}

        my $newVersion;
        if (open(IN, "< $saveTo")) {
                while (my $line = <IN>) {
                    if ($line =~ /^\$VERSION\s+=\s+'(.*?)';$/) {
                        $newVersion = $1;
                        last;
                    }
                }
                close IN;
        } else {
            cprint("that didn't go well :(");
            return;
        }
        cprint("your version: $VERSION");
        cprint("latest version: $newVersion");
        if ($newVersion > $VERSION) {
            rename($saveTo, "$script_dir/$IRSSI{name}.pl");
            cprint("Updated successfully! '/run $IRSSI{name}' to load");
        } else {
            cprint("nothing to see here");
            unlink($saveTo);
        }
}


sub spookify {
	# add emacs spook text.  if there is previously existing text, it appends
	my $text = shift;
	my $count = settings_get_int('spook_words') || return $text;
	my @spook_words;
	for (my $i = 0; $i < $count; $i++) {
		my $word = $spook_lines[int(rand(0) * scalar(@spook_lines))];
		push(@spook_words, $word);
	}
	$text = join(" ", @spook_words) . " $text";
	return $text;
}

sub gwrap {
	# fix that shit
	my $text = shift;
	return if (!defined $text);

	my $wrap = settings_get_int("linewrap") || return $text;
	$Text::Wrap::columns = $wrap;
	my @output;
	foreach my $line (split(/\n/, $text)) {
		local $^W = undef; # silence spurious warnings
		if (length($line) > $wrap) {
			($line) = Text::Wrap::wrap(undef, undef, $line);
		}
		$line =~ s/\t/     /g;
		push(@output, $line);
	}

	$text = join("\n", @output);
	return $text;
}

sub leet {
	# leet speak :(
	my $text = shift;
	return if (!defined $text);

	my @output;
	foreach my $line (split(/\n/, $text)) {
		my $newline;
		for (my $i = 0; $i < length($line); $i++) {
			my $char = lc(substr($line, $i, 1));
			if ($leet_map->{$char}) {
				my @possibles = @{$leet_map->{$char}};
				$char = $possibles[int(rand(0) * scalar(@possibles))];
			}
			$newline .= $char;
		}
		push(@output, $newline);
	}
	return join("\n", @output);
}

sub hug {
	my $text = shift;
	return if (!defined $text);

	my @text = split(/\n/, $text);
	my $size = settings_get_int("hug_size");

	# what is the longest line
	my $length = 0;
	foreach my $line (@text) {
		$length = clean_length($line) if clean_length($line) > $length;
	}


	my @output;
	foreach my $line (@text) {
		$line = ("{" x $size) . ' ' . $line . (' ' x ($length - length($line))) . ' ' . ("}" x $size);
		push(@output, $line);
	}

	return join("\n", @output);
}

sub reverse_ascii {
	#####################
	# reverse ascii art #
	#####################
	
	my $text = shift;
	return if (!defined $text);

	my @lines = split(/\n/, $text);

	# how big is the longest line
	my $length = 0;
	foreach my $line (@lines) {
		my $line_length = clean_length($line);
		$length = $line_length if ($line_length > $length);
	}

	my @output;
	foreach my $line (@lines) {
		if ($line =~ /$COWCUT/) {
			push(@output, $line);
		} else {
			$line =~ s!/!$rnd!g;  $line =~ s!\\!/!g; $line =~ s!$rnd!\\!g;
			$line =~ s!{!$rnd!g;  $line =~ s!}!{!g;  $line =~ s!$rnd!}!g;
			$line =~ s!\(!$rnd!g; $line =~ s!\)!(!g; $line =~ s!$rnd!)!g;
			$line =~ s!\[!$rnd!g; $line =~ s!\]![!g; $line =~ s!$rnd!]!g;
			$line =~ s!<!$rnd!g;  $line =~ s!>!<!g;  $line =~ s!$rnd!>!g;
			push(@output, sprintf("%" . $length . "s", scalar(reverse($line))));
		}
	}

	return join("\n", @output);
}

sub upside_down {
	# kind of like reverse_ascii, only on a different axis
	my $text = shift;
	return if (!defined $text);

	my @output;
	foreach my $line (split(/\n/, $text)) {
		$line =~ s!/!$rnd!g;  $line =~ s!\\!/!g; $line =~ s!$rnd!\\!g;
		$line =~ s!v!$rnd!g;  $line =~ s!\^!v!g; $line =~ s!$rnd!^!g;
		$line =~ s!w!$rnd!g;  $line =~ s!m!w!g;  $line =~ s!$rnd!m!g;
		$line =~ s!_!-!g;
		unshift(@output, $line);
	}

	return join("\n", @output);
}

# irssi is not friendly to require semantic
# so just use perl's shellwords.pl here
sub shellwords {
	my $text = join('', @_);
	return if (!defined $text);

	my (@words, $snippet, $field);

	$text =~ s/^\s+//;

	# fix deep recursion case (can't escape newline :P)
	# found by hlprmnky
	if ($text =~ /(?:[^\\]|^)\x5c$/) {
		cprint("Unmatched escape");
		return;
	}

	while ($text ne '') {
		$field = '';
		for (;;) {
			if ($text =~ s/^"(([^"\\]|\\.)*)"//) {
				($snippet = $1) =~ s#\\(.)#$1#g;
			} elsif ($text =~ /^"/) {
				cprint("Unmatched double quote");
				return;
			} elsif ($text =~ s/^'(([^'\\]|\\.)*)'//) {
				($snippet = $1) =~ s#\\(.)#$1#g;
			} elsif ($text =~ /^'/) {
				cprint("Unmatched single quote");
				return;
			} elsif ($text =~ s/^\\(.)//) {
				$snippet = $1;
			} elsif ($text =~ s/^([^\s\\'"]+)//) {
				$snippet = $1;
			} else {
				$text =~ s/^\s+//;
				last;
			}

			$field .= $snippet;
		}
		push(@words, $field);
	}
	return @words;
}

sub scramble {
	# stupid blog meme about mixing up
	# the inside letters
	my $text = shift;
	return if (!defined $text);

	my @newtext;
	foreach my $line (split(/\n/, $text)) {
		my @newline;
		foreach my $word (split(/\s+/, $line)) {
			my @letters = $word =~ /(\X)/g;
			my $first = shift(@letters);
			my $last = pop(@letters);
			fisher_yates_shuffle(\@letters) if scalar(@letters) > 0;
			my $newline = $first . join('', @letters) . $last;
			push(@newline, $newline);
		}
		push(@newtext, join(" ", @newline));
	}

	$text = join("\n", @newtext);
	return $text;
}

sub fisher_yates_shuffle {
	# safe randomizing
	my $array = shift;
	my $i;
	for ($i = @$array; --$i; ) {
		my $j = int rand ($i+1);
		next if $i == $j;
		@$array[$i,$j] = @$array[$j,$i];
	}
}

sub ircii_fake {
	# some ansi stuff to obscure the <nick>
	my $text = shift;
	return if (!defined $text);

	my @new;

	foreach my $line (split(/\n/, $text)) {
		$line = "\x85\x8d$line";
		push(@new, $line);
	}

	$text = join("\n", @new);

	return $text;
}

sub ircii_drop {
	# this is just evil.  move the cursor somewhere
	# inconvenient
	
	my $text = shift;
	return if (!defined $text);

	$text .= ("\x84" x 23);

	return $text;
}

# shift ascii homerow, code by hlprmnky
# hella copped from leet, above
sub jigs {
	my $text = shift;
	return if (!defined $text);

	my @output;
	foreach my $line (split(/\n/, $text)) {
		my $newline;
		for (my $i = 0; $i < length($line); $i++) {
			my $char = lc(substr($line, $i, 1));
			if ($jigs_map->{$char}) {
				$char = $jigs_map->{$char};
			}
			$newline .= $char;
		}
		push(@output, $newline);
	}
	return join("\n", @output);
}

#######################
### christmas stuff ###
#######################

sub tree {
	# this is the hardest filter i've ever written :(
	# there must be a more graceful, or at least ideomatic,
	# way of doing this, but i can't think of it.
	
        my $text = shift;
	return if (!defined $text);

	# bulbs.. only bright primary colors
        my @bulbs = (2,4,6,8,12);

	# don't do this in the loop or you don't get
	# random numbers
	srand(time());

	# cache green
	my $green = 3;

	my @output;
        foreach my $line (split(/\n/, $text)) {
		# it's gotta be at least 3 chars long to work
		unless (length($line) > 2) {
			push(@output, $line);
			next;
		}

		# the inside can't be all whitespace
		if ($line =~ /^.\s+.$/) {
			push(@output, $line);
			next;
		}

		# split line into an array of characters
		my @row = $line =~ /(\X)/g;

		# determine which points can be changed
		my @map;
		for (my $i = 0; $i < scalar(@row); $i++) {
			my $char = $row[$i];

			if ($i == 0 or $i == $#row) {
				push(@map, 0);
			} elsif ($char =~ /\s/) {
				push(@map, 0);
			} else {
				push(@map, 1);
			}
		}

		# (int(rand(0) * (max - min + 1))) + min
		my $max = grep(($_ == 1), @map);
		my $min = 1;
		my $map_pos = (int(rand(0) * ($max - $min + 1))) + $min;


		# god this is such a hack...
		# figure out which part of @map we mean
		my $count = 0;
		my $actual;
		for (my $i = 0; $i < scalar(@map); $i++) {
			my $map = $map[$i];

			if ($map == 1) {
				$count++;
			}

			if ($count == $map_pos) {
				$actual = $i;
				last;
			}
		}


		my ($head, $bulb, $foot);
		my $switch = 0;
		for (my $i = 0; $i < scalar(@row); $i++) {
			if ($i == $actual) {
				my $color = $bulbs[rand(@bulbs)];
				$bulb = do_color("*", $color);
				$switch++;
			} elsif ($switch == 0) {
				$head .= $row[$i];
			} elsif ($switch == 1) {
				$foot .= $row[$i];
			}
		}

		my $newline = do_color($head, $green) . $bulb . do_color($foot, $green);
		push(@output, $newline);
        }

	$text = join("\n", @output);
        return $text;
}

sub rotate {
	my $text = shift;
	return if (!defined $text);

	my @lines = split(/\r?\n/, $text);
	my @new;
	foreach my $line (reverse @lines) {
		my @cols = reverse ($line =~ /(\X)/g);
		for (my $i = 0; $i < @cols; $i++) {
			$new[$i] .= $cols[$i];
		}
	}
	$text = join("\n", reverse @new);
	return $text;
}

sub diagonal {
	my $text = shift;
	return if (!defined $text);

	my $new;
	for (my $i = 0; $i < length($text); $i++) {
		$new .= sprintf "%s%s\n", (" " x $i), substr($text, $i, 1);
	}

	return $new;
}

sub popeye {
	my $text = shift;
	return if (!defined $text);

	my $spacer = 0;
	my $new;
	foreach my $word (split(/\s+/, $text)) {
		$new    .= (" " x $spacer) . $word . "\n";
		$spacer += length($word);
	}

	return $new;
}

sub sine {
	my $text = shift;
	return if (!defined $text);

	my $freq   = settings_get_str("sine_frequency");
	my $height = settings_get_int("sine_height");
	my $bg     = settings_get_str("sine_background");

	$bg ||= " ";

	return unless ($freq > 0);

	my @output;
	my $lineNO = 0;
	foreach my $line (split(/\n/, $text)) {
		my @chrs = $line =~ /(\X)/g;
		my $width  = @chrs * $freq;

		my $plot = {};
		my $x = 0;
		foreach my $chr (@chrs) {
			my $y = int($height * sin($x)) + $height;
			$plot->{$x}->{$y} = $chr;
			$x += $freq;
		}

		for (my $y = 0; $y <= $height * 2; $y++) {
			for (my $x = 0; $x <= $width; $x += $freq) {
				if (exists $plot->{$x}->{$y}) {
					$output[$lineNO] .= $plot->{$x}->{$y};
				} else {
					$output[$lineNO] .= $bg;
				}
			}

			$lineNO++;
		}
	}

	my @cleaned;
	foreach my $line (@output) {
		next if $line =~ /^[$bg]+$/;
		$line =~ s/[$bg]+$//;
		push(@cleaned, $line);
	}

	$text = join("\n", @cleaned);

	return $text;
}

sub banner {
	my $text  = shift;
	return if (!defined $text);

	my $style = shift;

	my @chrs = $text =~ /(\X)/g;
	my $iter = 0;

	my $output;
	foreach my $chr (@chrs) {
		$chr =~ s/[\r\n]/ /;
		my $banner = perlBanner($chr);
		next if (!defined $banner); # remove if you don't want to die for unknowns 

		if ($style eq "phrase") {
			foreach my $bchr (split(//, $banner)) {
				if ($bchr =~ s/#/$chr/) {
					$iter = 0 if ++$iter >= @chrs;
				}
				$output .= $bchr;
			}
		}

		elsif ($style eq "line") {
			foreach my $line (split(/\n/, $banner)) {
				if ($line =~ s/#/$chr/g) {
					$iter = 0 if ++$iter > (@chrs - 1);
				}
				$output .= "$line\n";
			}
		}

		elsif ($style eq "letter") {
			$banner =~ s/#/$chr/g;
			$output .= $banner;
		}

		elsif ($style =~ /char:(.)/) {
			my $chr = $1;
			$banner =~ s/#/$chr/g;
			$output .= $banner;
		}
	}

	return $output;
}

####################################
# port of c banner utility to perl #
####################################

# defaults/constants
my $MAXMSG = 1024;
my $DWIDTH = 132;
my $NCHARS = 128;
my $NBYTES = 9470; # This really ought to be generated from the array

# Pointers into data_table for each ASCII char
my @asc_ptr = (
 #   0       1       2       3       4       5       6       7   Octal :(
     0,      0,      0,      0,      0,      0,      0,      0,  #  ^@ 000
     0,      0,      0,      0,      0,      0,      0,      0,  #  ^H 010
     0,      0,      0,      0,      0,      0,      0,      0,  #  ^P 020
     0,      0,      0,      0,      0,      0,      0,      0,  #  ^X 030
     1,      3,     50,     81,    104,    281,    483,    590,  #     040
   621,    685,    749,    851,    862,    893,    898,    921,  #   ( 050
  1019,   1150,   1200,   1419,   1599,   1744,   1934,   2111,  #   0 060
  2235,   2445,   2622,   2659,   9271,   2708,   9371,   2715,  #   8 070
  2857,   3072,   3273,   3403,   3560,   3662,   3730,   3785,  #   @ 100
  3965,   4000,   4015,   4115,   4281,   4314,   4432,   4548,  #   H 110
  4709,   4790,   4999,   5188,   5397,   5448,   5576,   5710,  #   P 120
  5892,   6106,   6257,      0,      0,      0,      0,      0,  #   X 130
    50,   6503,   6642,   6733,   6837,   6930,   7073,   7157,  #   ` 140
  7380,   7452,   7499,   7584,   7689,   7702,   7797,   7869,  #   h 150
  7978,   8069,   8160,   8222,   8381,   8442,   8508,   8605,  #   p 160
  8732,   8888,   9016,      0,      0,      0,      0,      0   #   x 170
);

# Table of stuff to print. Format:
# 128+n -> print current line n times.
# 64+n  -> this is last byte of char.
# else, put m chars at position n (where m
# is the next elt in array) and goto second
# next element in array.

# If you add new data, please be sane and add it to the end :<

my @data_table = (
  #    0     1     2     3     4     5     6     7     8     9 
     129,  227,  130,   34,    6,   90,   19,  129,   32,   10,  #     0 
      74,   40,  129,   31,   12,   64,   53,  129,   30,   14,  #    10 
      54,   65,  129,   30,   14,   53,   67,  129,   30,   14,  #    20 
      54,   65,  129,   31,   12,   64,   53,  129,   32,   10,  #    30 
      74,   40,  129,   34,    6,   90,   19,  129,  194,  130,  #    40 
      99,    9,  129,   97,   14,  129,   96,   18,  129,   95,  #    50 
      22,  129,   95,   16,  117,    2,  129,   95,   14,  129,  #    60 
      96,   11,  129,   97,    9,  129,   99,    6,  129,  194,  #    70 
     129,   87,    4,  101,    4,  131,   82,   28,  131,   87,  #    80 
       4,  101,    4,  133,   82,   28,  131,   87,    4,  101,  #    90 
       4,  131,  193,  129,   39,    1,   84,   27,  129,   38,  #   100 
       3,   81,   32,  129,   37,    5,   79,   35,  129,   36,  #   110 
       5,   77,   38,  129,   35,    5,   76,   40,  129,   34,  #   120 
       5,   75,   21,  103,   14,  129,   33,    5,   74,   19,  #   130 
     107,   11,  129,   32,    5,   73,   17,  110,    9,  129,  #   140 
      32,    4,   73,   16,  112,    7,  129,   31,    4,   72,  #   150 
      15,  114,    6,  129,   31,    4,   72,   14,  115,    5,  #   160 
     129,   30,    4,   71,   15,  116,    5,  129,   27,   97,  #   170 
     131,   30,    4,   69,   14,  117,    4,  129,   30,    4,  #   180 
      68,   15,  117,    4,  132,   30,    4,   68,   14,  117,  #   190 
       4,  129,   27,   97,  131,   30,    5,   65,   15,  116,  #   200 
       5,  129,   31,    4,   65,   14,  116,    4,  129,   31,  #   210 
       6,   64,   15,  116,    4,  129,   32,    7,   62,   16,  #   220 
     115,    4,  129,   32,    9,   61,   17,  114,    5,  129,  #   230 
      33,   11,   58,   19,  113,    5,  129,   34,   14,   55,  #   240 
      21,  112,    5,  129,   35,   40,  111,    5,  129,   36,  #   250 
      38,  110,    5,  129,   37,   35,  109,    5,  129,   38,  #   260 
      32,  110,    3,  129,   40,   27,  111,    1,  129,  193,  #   270 
     129,   30,    4,  103,    9,  129,   30,    7,  100,   15,  #   280 
     129,   30,   10,   99,   17,  129,   33,   10,   97,    6,  #   290 
     112,    6,  129,   36,   10,   96,    5,  114,    5,  129,  #   300 
      39,   10,   96,    4,  115,    4,  129,   42,   10,   95,  #   310 
       4,  116,    4,  129,   45,   10,   95,    3,  117,    3,  #   320 
     129,   48,   10,   95,    3,  117,    3,  129,   51,   10,  #   330 
      95,    4,  116,    4,  129,   54,   10,   96,    4,  115,  #   340 
       4,  129,   57,   10,   96,    5,  114,    5,  129,   60,  #   350 
      10,   97,    6,  112,    6,  129,   63,   10,   99,   17,  #   360 
     129,   66,   10,  100,   15,  129,   69,   10,  103,    9,  #   370 
     129,   39,    9,   72,   10,  129,   36,   15,   75,   10,  #   380 
     129,   35,   17,   78,   10,  129,   33,    6,   48,    6,  #   390 
      81,   10,  129,   32,    5,   50,    5,   84,   10,  129,  #   400 
      32,    4,   51,    4,   87,   10,  129,   31,    4,   52,  #   410 
       4,   90,   10,  129,   31,    3,   53,    3,   93,   10,  #   420 
     129,   31,    3,   53,    3,   96,   10,  129,   31,    4,  #   430 
      52,    4,   99,   10,  129,   32,    4,   51,    4,  102,  #   440 
      10,  129,   32,    5,   50,    5,  105,   10,  129,   33,  #   450 
       6,   48,    6,  108,   10,  129,   35,   17,  111,   10,  #   460 
     129,   36,   15,  114,    7,  129,   40,    9,  118,    4,  #   470 
     129,  193,  129,   48,   18,  129,   43,   28,  129,   41,  #   480 
      32,  129,   39,   36,  129,   37,   40,  129,   35,   44,  #   490 
     129,   34,   46,  129,   33,   13,   68,   13,  129,   32,  #   500 
       9,   73,    9,  129,   32,    7,   75,    7,  129,   31,  #   510 
       6,   77,    6,  129,   31,    5,   78,    5,  129,   30,  #   520 
       5,   79,    5,  129,   20,   74,  132,   30,    4,   80,  #   530 
       4,  129,   31,    3,   79,    4,  129,   31,    4,   79,  #   540 
       4,  129,   32,    3,   78,    4,  129,   32,    4,   76,  #   550 
       6,  129,   33,    4,   74,    7,  129,   34,    4,   72,  #   560 
       8,  129,   35,    5,   72,    7,  129,   37,    5,   73,  #   570 
       4,  129,   39,    4,   74,    1,  129,  129,  193,  130,  #   580 
     111,    6,  129,  109,   10,  129,  108,   12,  129,  107,  #   590 
      14,  129,   97,    2,  105,   16,  129,   99,   22,  129,  #   600 
     102,   18,  129,  105,   14,  129,  108,    9,  129,  194,  #   610 
     130,   63,   25,  129,   57,   37,  129,   52,   47,  129,  #   620 
      48,   55,  129,   44,   63,  129,   41,   69,  129,   38,  #   630 
      75,  129,   36,   79,  129,   34,   83,  129,   33,   28,  #   640 
      90,   28,  129,   32,   23,   96,   23,  129,   32,   17,  #   650 
     102,   17,  129,   31,   13,  107,   13,  129,   30,    9,  #   660 
     112,    9,  129,   30,    5,  116,    5,  129,   30,    1,  #   670 
     120,    1,  129,  194,  130,   30,    1,  120,    1,  129,  #   680 
      30,    5,  116,    5,  129,   30,    9,  112,    9,  129,  #   690 
      31,   13,  107,   13,  129,   32,   17,  102,   17,  129,  #   700 
      32,   23,   96,   23,  129,   33,   28,   90,   28,  129,  #   710 
      34,   83,  129,   36,   79,  129,   38,   75,  129,   41,  #   720 
      69,  129,   44,   63,  129,   48,   55,  129,   52,   47,  #   730 
     129,   57,   37,  129,   63,   25,  129,  194,  129,   80,  #   740 
       4,  130,   80,    4,  129,   68,    2,   80,    4,   94,  #   750 
       2,  129,   66,    6,   80,    4,   92,    6,  129,   67,  #   760 
       7,   80,    4,   90,    7,  129,   69,    7,   80,    4,  #   770 
      88,    7,  129,   71,    6,   80,    4,   87,    6,  129,  #   780 
      72,   20,  129,   74,   16,  129,   76,   12,  129,   62,  #   790 
      40,  131,   76,   12,  129,   74,   16,  129,   72,   20,  #   800 
     129,   71,    6,   80,    4,   87,    6,  129,   69,    7,  #   810 
      80,    4,   88,    7,  129,   67,    7,   80,    4,   90,  #   820 
       7,  129,   66,    6,   80,    4,   92,    6,  129,   68,  #   830 
       2,   80,    4,   94,    2,  129,   80,    4,  130,  193,  #   840 
     129,   60,    4,  139,   41,   42,  131,   60,    4,  139,  #   850 
     193,  130,   34,    6,  129,   32,   10,  129,   31,   12,  #   860 
     129,   30,   14,  129,   20,    2,   28,   16,  129,   22,  #   870 
      22,  129,   24,   19,  129,   27,   15,  129,   31,    9,  #   880 
     129,  194,  129,   60,    4,  152,  193,  130,   34,    6,  #   890 
     129,   32,   10,  129,   31,   12,  129,   30,   14,  131,  #   900 
      31,   12,  129,   32,   10,  129,   34,    6,  129,  194,  #   910 
     129,   30,    4,  129,   30,    7,  129,   30,   10,  129,  #   920 
      33,   10,  129,   36,   10,  129,   39,   10,  129,   42,  #   930 
      10,  129,   45,   10,  129,   48,   10,  129,   51,   10,  #   940 
     129,   54,   10,  129,   57,   10,  129,   60,   10,  129,  #   950 
      63,   10,  129,   66,   10,  129,   69,   10,  129,   72,  #   960 
      10,  129,   75,   10,  129,   78,   10,  129,   81,   10,  #   970 
     129,   84,   10,  129,   87,   10,  129,   90,   10,  129,  #   980 
      93,   10,  129,   96,   10,  129,   99,   10,  129,  102,  #   990 
      10,  129,  105,   10,  129,  108,   10,  129,  111,   10,  #  1000 
     129,  114,    7,  129,  117,    4,  129,  193,  129,   60,  #  1010 
      31,  129,   53,   45,  129,   49,   53,  129,   46,   59,  #  1020 
     129,   43,   65,  129,   41,   69,  129,   39,   73,  129,  #  1030 
      37,   77,  129,   36,   79,  129,   35,   15,  101,   15,  #  1040 
     129,   34,   11,  106,   11,  129,   33,    9,  109,    9,  #  1050 
     129,   32,    7,  112,    7,  129,   31,    6,  114,    6,  #  1060 
     129,   31,    5,  115,    5,  129,   30,    5,  116,    5,  #  1070 
     129,   30,    4,  117,    4,  132,   30,    5,  116,    5,  #  1080 
     129,   31,    5,  115,    5,  129,   31,    6,  114,    6,  #  1090 
     129,   32,    7,  112,    7,  129,   33,    9,  109,    9,  #  1100 
     129,   34,   11,  106,   11,  129,   35,   15,  101,   15,  #  1110 
     129,   36,   79,  129,   37,   77,  129,   39,   73,  129,  #  1120 
      41,   69,  129,   43,   65,  129,   46,   59,  129,   49,  #  1130 
      53,  129,   53,   45,  129,   60,   31,  129,  193,  129,  #  1140 
      30,    4,  129,   30,    4,  100,    1,  129,   30,    4,  #  1150 
     100,    3,  129,   30,    4,  100,    5,  129,   30,   76,  #  1160 
     129,   30,   78,  129,   30,   80,  129,   30,   82,  129,  #  1170 
      30,   83,  129,   30,   85,  129,   30,   87,  129,   30,  #  1180 
      89,  129,   30,   91,  129,   30,    4,  132,  193,  129,  #  1190 
      30,    3,  129,   30,    7,  129,   30,   10,  112,    1,  #  1200 
     129,   30,   13,  112,    2,  129,   30,   16,  112,    3,  #  1210 
     129,   30,   18,  111,    5,  129,   30,   21,  111,    6,  #  1220 
     129,   30,   23,  112,    6,  129,   30,   14,   47,    8,  #  1230 
     113,    6,  129,   30,   14,   49,    8,  114,    5,  129,  #  1240 
      30,   14,   51,    8,  115,    5,  129,   30,   14,   53,  #  1250 
       8,  116,    4,  129,   30,   14,   55,    8,  116,    5,  #  1260 
     129,   30,   14,   56,    9,  117,    4,  129,   30,   14,  #  1270 
      57,    9,  117,    4,  129,   30,   14,   58,   10,  117,  #  1280 
       4,  129,   30,   14,   59,   10,  117,    4,  129,   30,  #  1290 
      14,   60,   11,  117,    4,  129,   30,   14,   61,   11,  #  1300 
     116,    5,  129,   30,   14,   62,   11,  116,    5,  129,  #  1310 
      30,   14,   63,   12,  115,    6,  129,   30,   14,   64,  #  1320 
      13,  114,    7,  129,   30,   14,   65,   13,  113,    8,  #  1330 
     129,   30,   14,   65,   15,  111,    9,  129,   30,   14,  #  1340 
      66,   16,  109,   11,  129,   30,   14,   67,   17,  107,  #  1350 
      12,  129,   30,   14,   68,   20,  103,   16,  129,   30,  #  1360 
      14,   69,   49,  129,   30,   14,   70,   47,  129,   30,  #  1370 
      14,   71,   45,  129,   30,   14,   73,   42,  129,   30,  #  1380 
      15,   75,   38,  129,   33,   12,   77,   34,  129,   36,  #  1390 
      10,   79,   30,  129,   40,    6,   82,   23,  129,   44,  #  1400 
       3,   86,   15,  129,   47,    1,  129,  193,  129,  129,  #  1410 
      38,    3,  129,   37,    5,  111,    1,  129,   36,    7,  #  1420 
     111,    2,  129,   35,    9,  110,    5,  129,   34,    8,  #  1430 
     110,    6,  129,   33,    7,  109,    8,  129,   32,    7,  #  1440 
     110,    8,  129,   32,    6,  112,    7,  129,   31,    6,  #  1450 
     113,    6,  129,   31,    5,  114,    6,  129,   30,    5,  #  1460 
     115,    5,  129,   30,    5,  116,    4,  129,   30,    4,  #  1470 
     117,    4,  131,   30,    4,  117,    4,  129,   30,    4,  #  1480 
      79,    2,  117,    4,  129,   30,    5,   78,    4,  117,  #  1490 
       4,  129,   30,    5,   77,    6,  116,    5,  129,   30,  #  1500 
       6,   76,    8,  115,    6,  129,   30,    7,   75,   11,  #  1510 
     114,    6,  129,   30,    8,   73,   15,  112,    8,  129,  #  1520 
      31,    9,   71,   19,  110,    9,  129,   31,   11,   68,  #  1530 
      26,  107,   12,  129,   32,   13,   65,   14,   82,   36,  #  1540 
     129,   32,   16,   61,   17,   83,   34,  129,   33,   44,  #  1550 
      84,   32,  129,   34,   42,   85,   30,  129,   35,   40,  #  1560 
      87,   27,  129,   36,   38,   89,   23,  129,   38,   34,  #  1570 
      92,   17,  129,   40,   30,   95,   11,  129,   42,   26,  #  1580 
     129,   45,   20,  129,   49,   11,  129,  193,  129,   49,  #  1590 
       1,  129,   49,    4,  129,   49,    6,  129,   49,    8,  #  1600 
     129,   49,   10,  129,   49,   12,  129,   49,   14,  129,  #  1610 
      49,   17,  129,   49,   19,  129,   49,   21,  129,   49,  #  1620 
      23,  129,   49,   14,   65,    9,  129,   49,   14,   67,  #  1630 
       9,  129,   49,   14,   69,    9,  129,   49,   14,   71,  #  1640 
      10,  129,   49,   14,   74,    9,  129,   49,   14,   76,  #  1650 
       9,  129,   49,   14,   78,    9,  129,   49,   14,   80,  #  1660 
       9,  129,   49,   14,   82,    9,  129,   49,   14,   84,  #  1670 
       9,  129,   30,    4,   49,   14,   86,   10,  129,   30,  #  1680 
       4,   49,   14,   89,    9,  129,   30,    4,   49,   14,  #  1690 
      91,    9,  129,   30,    4,   49,   14,   93,    9,  129,  #  1700 
      30,   74,  129,   30,   76,  129,   30,   78,  129,   30,  #  1710 
      81,  129,   30,   83,  129,   30,   85,  129,   30,   87,  #  1720 
     129,   30,   89,  129,   30,   91,  129,   30,    4,   49,  #  1730 
      14,  132,  193,  129,   37,    1,  129,   36,    3,   77,  #  1740 
       3,  129,   35,    5,   78,   11,  129,   34,    7,   78,  #  1750 
      21,  129,   33,    7,   79,   29,  129,   32,    7,   79,  #  1760 
      38,  129,   32,    6,   80,    4,   92,   29,  129,   31,  #  1770 
       6,   80,    5,  102,   19,  129,   31,    5,   80,    6,  #  1780 
     107,   14,  129,   31,    4,   81,    5,  107,   14,  129,  #  1790 
      30,    5,   81,    6,  107,   14,  129,   30,    4,   81,  #  1800 
       6,  107,   14,  130,   30,    4,   81,    7,  107,   14,  #  1810 
     129,   30,    4,   80,    8,  107,   14,  130,   30,    5,  #  1820 
      80,    8,  107,   14,  129,   30,    5,   79,    9,  107,  #  1830 
      14,  129,   31,    5,   79,    9,  107,   14,  129,   31,  #  1840 
       6,   78,   10,  107,   14,  129,   32,    6,   76,   11,  #  1850 
     107,   14,  129,   32,    8,   74,   13,  107,   14,  129,  #  1860 
      33,   10,   71,   16,  107,   14,  129,   33,   15,   67,  #  1870 
      19,  107,   14,  129,   34,   51,  107,   14,  129,   35,  #  1880 
      49,  107,   14,  129,   36,   47,  107,   14,  129,   37,  #  1890 
      45,  107,   14,  129,   39,   41,  107,   14,  129,   41,  #  1900 
      37,  107,   14,  129,   44,   32,  107,   14,  129,   47,  #  1910 
      25,  111,   10,  129,   51,   16,  115,    6,  129,  119,  #  1920 
       2,  129,  193,  129,   56,   39,  129,   51,   49,  129,  #  1930 
      47,   57,  129,   44,   63,  129,   42,   67,  129,   40,  #  1940 
      71,  129,   38,   75,  129,   37,   77,  129,   35,   81,  #  1950 
     129,   34,   16,   74,    5,  101,   16,  129,   33,   11,  #  1960 
      76,    5,  107,   11,  129,   32,    9,   77,    5,  110,  #  1970 
       9,  129,   32,    7,   79,    4,  112,    7,  129,   31,  #  1980 
       6,   80,    4,  114,    6,  129,   31,    5,   81,    4,  #  1990 
     115,    5,  129,   30,    5,   82,    4,  116,    5,  129,  #  2000 
      30,    4,   82,    4,  116,    5,  129,   30,    4,   82,  #  2010 
       5,  117,    4,  131,   30,    5,   82,    5,  117,    4,  #  2020 
     129,   31,    5,   81,    6,  117,    4,  129,   31,    6,  #  2030 
      80,    7,  117,    4,  129,   32,    7,   79,    8,  117,  #  2040 
       4,  129,   32,    9,   77,    9,  116,    5,  129,   33,  #  2050 
      11,   75,   11,  116,    4,  129,   34,   16,   69,   16,  #  2060 
     115,    5,  129,   35,   49,  114,    5,  129,   37,   46,  #  2070 
     113,    5,  129,   38,   44,  112,    6,  129,   40,   41,  #  2080 
     112,    5,  129,   42,   37,  113,    3,  129,   44,   33,  #  2090 
     114,    1,  129,   47,   27,  129,   51,   17,  129,  193,  #  2100 
     129,  103,    2,  129,  103,    6,  129,  104,    9,  129,  #  2110 
     105,   12,  129,  106,   15,  129,  107,   14,  135,   30,  #  2120 
      10,  107,   14,  129,   30,   17,  107,   14,  129,   30,  #  2130 
      25,  107,   14,  129,   30,   31,  107,   14,  129,   30,  #  2140 
      37,  107,   14,  129,   30,   42,  107,   14,  129,   30,  #  2150 
      46,  107,   14,  129,   30,   50,  107,   14,  129,   30,  #  2160 
      54,  107,   14,  129,   30,   58,  107,   14,  129,   59,  #  2170 
      32,  107,   14,  129,   64,   30,  107,   14,  129,   74,  #  2180 
      23,  107,   14,  129,   81,   18,  107,   14,  129,   86,  #  2190 
      16,  107,   14,  129,   91,   14,  107,   14,  129,   96,  #  2200 
      25,  129,  100,   21,  129,  104,   17,  129,  107,   14,  #  2210 
     129,  111,   10,  129,  114,    7,  129,  117,    4,  129,  #  2220 
     120,    1,  129,  193,  129,   48,   13,  129,   44,   21,  #  2230 
     129,   42,   26,  129,   40,   30,   92,   12,  129,   38,  #  2240 
      34,   88,   20,  129,   36,   37,   86,   25,  129,   35,  #  2250 
      39,   84,   29,  129,   34,   13,   63,   12,   82,   33,  #  2260 
     129,   33,   11,   67,    9,   80,   36,  129,   32,    9,  #  2270 
      70,    7,   79,   38,  129,   31,    8,   72,   46,  129,  #  2280 
      30,    7,   74,   22,  108,   11,  129,   30,    6,   75,  #  2290 
      19,  111,    9,  129,   30,    5,   75,   17,  113,    7,  #  2300 
     129,   30,    5,   74,   16,  114,    6,  129,   30,    4,  #  2310 
      73,   16,  115,    6,  129,   30,    4,   72,   16,  116,  #  2320 
       5,  129,   30,    4,   72,   15,  117,    4,  129,   30,  #  2330 
       4,   71,   16,  117,    4,  129,   30,    5,   70,   16,  #  2340 
     117,    4,  129,   30,    5,   70,   15,  117,    4,  129,  #  2350 
      30,    6,   69,   15,  116,    5,  129,   30,    7,   68,  #  2360 
      17,  115,    5,  129,   30,    9,   67,   19,  114,    6,  #  2370 
     129,   30,   10,   65,   22,  113,    6,  129,   31,   12,  #  2380 
      63,   27,  110,    9,  129,   32,   14,   60,   21,   84,  #  2390 
       9,  106,   12,  129,   33,   47,   85,   32,  129,   34,  #  2400 
      45,   86,   30,  129,   35,   43,   88,   26,  129,   36,  #  2410 
      40,   90,   22,  129,   38,   36,   93,   17,  129,   40,  #  2420 
      32,   96,   10,  129,   42,   28,  129,   44,   23,  129,  #  2430 
      48,   15,  129,  193,  129,   83,   17,  129,   77,   27,  #  2440 
     129,   36,    1,   74,   33,  129,   35,    3,   72,   37,  #  2450 
     129,   34,    5,   70,   41,  129,   33,    6,   69,   44,  #  2460 
     129,   33,    5,   68,   46,  129,   32,    5,   67,   49,  #  2470 
     129,   31,    5,   66,   17,  101,   16,  129,   31,    5,  #  2480 
      66,   11,  108,   10,  129,   30,    4,   65,    9,  110,  #  2490 
       9,  129,   30,    4,   64,    8,  112,    7,  129,   30,  #  2500 
       4,   64,    7,  114,    6,  129,   30,    4,   64,    6,  #  2510 
     115,    5,  129,   30,    4,   64,    5,  116,    5,  129,  #  2520 
      30,    4,   64,    5,  117,    4,  131,   30,    4,   65,  #  2530 
       4,  117,    4,  129,   30,    5,   65,    4,  116,    5,  #  2540 
     129,   31,    5,   66,    4,  115,    5,  129,   31,    6,  #  2550 
      67,    4,  114,    6,  129,   32,    7,   68,    4,  112,  #  2560 
       7,  129,   32,    9,   69,    5,  110,    9,  129,   33,  #  2570 
      11,   70,    5,  107,   11,  129,   34,   16,   72,    5,  #  2580 
     101,   16,  129,   35,   81,  129,   37,   77,  129,   38,  #  2590 
      75,  129,   40,   71,  129,   42,   67,  129,   44,   63,  #  2600 
     129,   47,   57,  129,   51,   49,  129,   56,   39,  129,  #  2610 
     193,  130,   34,    6,   74,    6,  129,   32,   10,   72,  #  2620 
      10,  129,   31,   12,   71,   12,  129,   30,   14,   70,  #  2630 
      14,  131,   31,   12,   71,   12,  129,   32,   10,   72,  #  2640 
      10,  129,   34,    6,   74,    6,  129,  194,  130,   34,  #  2650 
       6,   74,    6,  129,   32,   10,   72,   10,  129,   31,  #  2660 
      12,   71,   12,  129,   30,   14,   70,   14,  129,   20,  #  2670 
       2,   28,   16,   70,   14,  129,   22,   22,   70,   14,  #  2680 
     129,   24,   19,   71,   12,  129,   27,   15,   72,   10,  #  2690 
     129,   31,    9,   74,    6,  129,  194,  129,   53,    4,  #  2700 
      63,    4,  152,  193,  130,   99,    7,  129,   97,   13,  #  2710 
     129,   96,   16,  129,   96,   18,  129,   96,   19,  129,  #  2720 
      97,   19,  129,   99,    6,  110,    7,  129,  112,    6,  #  2730 
     129,  114,    5,  129,   34,    6,   57,    5,  115,    4,  #  2740 
     129,   32,   10,   54,   12,  116,    4,  129,   31,   12,  #  2750 
      53,   16,  117,    3,  129,   30,   14,   52,   20,  117,  #  2760 
       4,  129,   30,   14,   52,   23,  117,    4,  129,   30,  #  2770 
      14,   52,   25,  117,    4,  129,   31,   12,   52,   27,  #  2780 
     117,    4,  129,   32,   10,   53,   10,   70,   11,  116,  #  2790 
       5,  129,   34,    6,   55,    5,   73,   10,  115,    6,  #  2800 
     129,   74,   11,  114,    7,  129,   75,   12,  112,    9,  #  2810 
     129,   76,   13,  110,   10,  129,   77,   16,  106,   14,  #  2820 
     129,   78,   41,  129,   80,   38,  129,   81,   36,  129,  #  2830 
      82,   34,  129,   84,   30,  129,   86,   26,  129,   88,  #  2840 
      22,  129,   92,   14,  129,  194,  129,   55,   15,  129,  #  2850 
      50,   25,  129,   47,   32,  129,   45,   13,   70,   12,  #  2860 
     129,   43,    9,   76,   10,  129,   42,    6,   79,    8,  #  2870 
     129,   41,    5,   81,    7,  129,   40,    4,   84,    6,  #  2880 
     129,   39,    4,   59,   12,   85,    6,  129,   38,    4,  #  2890 
      55,   19,   87,    5,  129,   37,    4,   53,   23,   88,  #  2900 
       4,  129,   36,    4,   51,    8,   71,    6,   89,    4,  #  2910 
     129,   36,    4,   51,    6,   73,    4,   89,    4,  129,  #  2920 
      36,    4,   50,    6,   74,    4,   90,    3,  129,   35,  #  2930 
       4,   50,    5,   75,    3,   90,    4,  129,   35,    4,  #  2940 
      50,    4,   75,    4,   90,    4,  131,   35,    4,   50,  #  2950 
       5,   75,    4,   90,    4,  129,   36,    4,   51,    5,  #  2960 
      75,    4,   90,    4,  129,   36,    4,   51,    6,   75,  #  2970 
       4,   90,    4,  129,   36,    4,   53,   26,   90,    4,  #  2980 
     129,   37,    4,   54,   25,   90,    4,  129,   37,    4,  #  2990 
      52,   27,   90,    3,  129,   38,    4,   52,    4,   89,  #  3000 
       4,  129,   39,    4,   51,    4,   88,    4,  129,   40,  #  3010 
       4,   50,    4,   87,    5,  129,   41,    4,   50,    4,  #  3020 
      86,    5,  129,   42,    4,   50,    4,   85,    5,  129,  #  3030 
      43,    3,   50,    4,   83,    6,  129,   44,    2,   51,  #  3040 
       5,   80,    7,  129,   46,    1,   52,    6,   76,    9,  #  3050 
     129,   54,   28,  129,   56,   23,  129,   60,   16,  129,  #  3060 
     193,  129,   30,    4,  132,   30,    5,  129,   30,    8,  #  3070 
     129,   30,   12,  129,   30,   16,  129,   30,    4,   37,  #  3080 
      12,  129,   30,    4,   41,   12,  129,   30,    4,   44,  #  3090 
      13,  129,   30,    4,   48,   13,  129,   52,   13,  129,  #  3100 
      56,   12,  129,   58,   14,  129,   58,    4,   64,   12,  #  3110 
     129,   58,    4,   68,   12,  129,   58,    4,   72,   12,  #  3120 
     129,   58,    4,   75,   13,  129,   58,    4,   79,   13,  #  3130 
     129,   58,    4,   83,   13,  129,   58,    4,   87,   13,  #  3140 
     129,   58,    4,   91,   12,  129,   58,    4,   95,   12,  #  3150 
     129,   58,    4,   96,   15,  129,   58,    4,   93,   22,  #  3160 
     129,   58,    4,   89,   30,  129,   58,    4,   85,   36,  #  3170 
     129,   58,    4,   81,   38,  129,   58,    4,   77,   38,  #  3180 
     129,   58,    4,   73,   38,  129,   58,    4,   70,   37,  #  3190 
     129,   58,    4,   66,   37,  129,   58,   41,  129,   58,  #  3200 
      37,  129,   54,   38,  129,   30,    4,   50,   38,  129,  #  3210 
      30,    4,   46,   38,  129,   30,    4,   42,   38,  129,  #  3220 
      30,    4,   38,   39,  129,   30,   43,  129,   30,   39,  #  3230 
     129,   30,   35,  129,   30,   31,  129,   30,   27,  129,  #  3240 
      30,   24,  129,   30,   20,  129,   30,   16,  129,   30,  #  3250 
      12,  129,   30,    8,  129,   30,    5,  129,   30,    4,  #  3260 
     132,  193,  129,   30,    4,  117,    4,  132,   30,   91,  #  3270 
     137,   30,    4,   80,    4,  117,    4,  138,   30,    4,  #  3280 
      80,    5,  116,    5,  129,   30,    5,   79,    6,  116,  #  3290 
       5,  130,   30,    6,   78,    8,  115,    6,  129,   31,  #  3300 
       6,   77,    9,  115,    6,  129,   31,    7,   76,   11,  #  3310 
     114,    6,  129,   31,    8,   75,   14,  112,    8,  129,  #  3320 
      32,    8,   74,   16,  111,    9,  129,   32,    9,   73,  #  3330 
      19,  109,   10,  129,   33,   10,   71,   24,  106,   13,  #  3340 
     129,   33,   13,   68,   12,   83,   35,  129,   34,   16,  #  3350 
      64,   15,   84,   33,  129,   35,   43,   85,   31,  129,  #  3360 
      36,   41,   86,   29,  129,   37,   39,   88,   25,  129,  #  3370 
      38,   37,   90,   21,  129,   40,   33,   93,   15,  129,  #  3380 
      42,   29,   96,    9,  129,   45,   24,  129,   49,   16,  #  3390 
     129,  193,  129,   63,   25,  129,   57,   37,  129,   53,  #  3400 
      45,  129,   50,   51,  129,   47,   57,  129,   45,   61,  #  3410 
     129,   43,   65,  129,   41,   69,  129,   39,   73,  129,  #  3420 
      38,   25,   92,   21,  129,   36,   21,   97,   18,  129,  #  3430 
      35,   18,  102,   14,  129,   34,   16,  106,   11,  129,  #  3440 
      33,   14,  108,   10,  129,   32,   12,  111,    8,  129,  #  3450 
      32,   10,  113,    6,  129,   31,   10,  114,    6,  129,  #  3460 
      31,    8,  115,    5,  129,   30,    8,  116,    5,  129,  #  3470 
      30,    7,  116,    5,  129,   30,    6,  117,    4,  130,  #  3480 
      30,    5,  117,    4,  131,   31,    4,  116,    5,  129,  #  3490 
      32,    4,  116,    4,  129,   32,    5,  115,    5,  129,  #  3500 
      33,    4,  114,    5,  129,   34,    4,  112,    6,  129,  #  3510 
      35,    4,  110,    7,  129,   37,    4,  107,    9,  129,  #  3520 
      39,    4,  103,   12,  129,   41,    4,  103,   18,  129,  #  3530 
      43,    4,  103,   18,  129,   45,    5,  103,   18,  129,  #  3540 
      48,    5,  103,   18,  129,   51,    1,  129,  193,  129,  #  3550 
      30,    4,  117,    4,  132,   30,   91,  137,   30,    4,  #  3560 
     117,    4,  135,   30,    5,  116,    5,  130,   30,    6,  #  3570 
     115,    6,  130,   31,    6,  114,    6,  129,   31,    7,  #  3580 
     113,    7,  129,   32,    7,  112,    7,  129,   32,    8,  #  3590 
     111,    8,  129,   33,    9,  109,    9,  129,   33,   12,  #  3600 
     106,   12,  129,   34,   13,  104,   13,  129,   35,   15,  #  3610 
     101,   15,  129,   36,   19,   96,   19,  129,   37,   24,  #  3620 
      90,   24,  129,   39,   73,  129,   40,   71,  129,   42,  #  3630 
      67,  129,   44,   63,  129,   46,   59,  129,   49,   53,  #  3640 
     129,   52,   47,  129,   56,   39,  129,   61,   29,  129,  #  3650 
     193,  129,   30,    4,  117,    4,  132,   30,   91,  137,  #  3660 
      30,    4,   80,    4,  117,    4,  140,   30,    4,   79,  #  3670 
       6,  117,    4,  129,   30,    4,   77,   10,  117,    4,  #  3680 
     129,   30,    4,   73,   18,  117,    4,  132,   30,    4,  #  3690 
     117,    4,  130,   30,    5,  116,    5,  130,   30,    7,  #  3700 
     114,    7,  129,   30,    8,  113,    8,  129,   30,   11,  #  3710 
     110,   11,  129,   30,   18,  103,   18,  132,  193,  129,  #  3720 
      30,    4,  117,    4,  132,   30,   91,  137,   30,    4,  #  3730 
      80,    4,  117,    4,  132,   80,    4,  117,    4,  136,  #  3740 
      79,    6,  117,    4,  129,   77,   10,  117,    4,  129,  #  3750 
      73,   18,  117,    4,  132,  117,    4,  130,  116,    5,  #  3760 
     130,  114,    7,  129,  113,    8,  129,  110,   11,  129,  #  3770 
     103,   18,  132,  193,  129,   63,   25,  129,   57,   37,  #  3780 
     129,   53,   45,  129,   50,   51,  129,   47,   57,  129,  #  3790 
      45,   61,  129,   43,   65,  129,   41,   69,  129,   39,  #  3800 
      73,  129,   38,   25,   92,   21,  129,   36,   21,   97,  #  3810 
      18,  129,   35,   18,  102,   14,  129,   34,   16,  106,  #  3820 
      11,  129,   33,   14,  108,   10,  129,   32,   12,  111,  #  3830 
       8,  129,   32,   10,  113,    6,  129,   31,   10,  114,  #  3840 
       6,  129,   31,    8,  115,    5,  129,   30,    8,  116,  #  3850 
       5,  129,   30,    7,  116,    5,  129,   30,    6,  117,  #  3860 
       4,  130,   30,    5,  117,    4,  131,   30,    5,   75,  #  3870 
       4,  116,    5,  129,   31,    5,   75,    4,  116,    4,  #  3880 
     129,   31,    6,   75,    4,  115,    5,  129,   32,    7,  #  3890 
      75,    4,  114,    5,  129,   32,    9,   75,    4,  112,  #  3900 
       6,  129,   33,   11,   75,    4,  110,    7,  129,   34,  #  3910 
      15,   75,    4,  107,    9,  129,   35,   44,  103,   12,  #  3920 
     129,   36,   43,  103,   18,  129,   38,   41,  103,   18,  #  3930 
     129,   39,   40,  103,   18,  129,   41,   38,  103,   18,  #  3940 
     129,   44,   35,  129,   48,   31,  129,   52,   27,  129,  #  3950 
      61,   18,  129,  193,  129,   30,    4,  117,    4,  132,  #  3960 
      30,   91,  137,   30,    4,   80,    4,  117,    4,  132,  #  3970 
      80,    4,  140,   30,    4,   80,    4,  117,    4,  132,  #  3980 
      30,   91,  137,   30,    4,  117,    4,  132,  193,  129,  #  3990 
      30,    4,  117,    4,  132,   30,   91,  137,   30,    4,  #  4000 
     117,    4,  132,  193,  129,   44,    7,  129,   40,   13,  #  4010 
     129,   37,   17,  129,   35,   20,  129,   34,   22,  129,  #  4020 
      33,   23,  129,   32,   24,  129,   32,   23,  129,   31,  #  4030 
       6,   41,   13,  129,   31,    5,   42,   11,  129,   30,  #  4040 
       5,   44,    7,  129,   30,    4,  132,   30,    5,  130,  #  4050 
      31,    5,  129,   31,    6,  117,    4,  129,   31,    8,  #  4060 
     117,    4,  129,   32,    9,  117,    4,  129,   33,   11,  #  4070 
     117,    4,  129,   34,   87,  129,   35,   86,  129,   36,  #  4080 
      85,  129,   37,   84,  129,   38,   83,  129,   40,   81,  #  4090 
     129,   42,   79,  129,   45,   76,  129,   50,   71,  129,  #  4100 
     117,    4,  132,  193,  129,   30,    4,  117,    4,  132,  #  4110 
      30,   91,  137,   30,    4,   76,    8,  117,    4,  129,  #  4120 
      30,    4,   73,   13,  117,    4,  129,   30,    4,   70,  #  4130 
      18,  117,    4,  129,   30,    4,   67,   23,  117,    4,  #  4140 
     129,   65,   26,  129,   62,   31,  129,   59,   35,  129,  #  4150 
      56,   29,   89,    7,  129,   53,   29,   91,    7,  129,  #  4160 
      50,   29,   93,    7,  129,   47,   29,   95,    6,  129,  #  4170 
      30,    4,   45,   29,   96,    7,  129,   30,    4,   42,  #  4180 
      29,   98,    7,  129,   30,    4,   39,   30,  100,    6,  #  4190 
     129,   30,    4,   36,   30,  101,    7,  129,   30,   33,  #  4200 
     103,    7,  117,    4,  129,   30,   30,  105,    6,  117,  #  4210 
       4,  129,   30,   27,  106,    7,  117,    4,  129,   30,  #  4220 
      25,  108,    7,  117,    4,  129,   30,   22,  110,   11,  #  4230 
     129,   30,   19,  111,   10,  129,   30,   16,  113,    8,  #  4240 
     129,   30,   13,  115,    6,  129,   30,   11,  116,    5,  #  4250 
     129,   30,    8,  117,    4,  129,   30,    5,  117,    4,  #  4260 
     129,   30,    4,  117,    4,  130,   30,    4,  130,  193,  #  4270 
     129,   30,    4,  117,    4,  132,   30,   91,  137,   30,  #  4280 
       4,  117,    4,  132,   30,    4,  144,   30,    5,  130,  #  4290 
      30,    7,  129,   30,    8,  129,   30,   11,  129,   30,  #  4300 
      18,  132,  193,  129,   30,    4,  117,    4,  132,   30,  #  4310 
      91,  132,   30,    4,  103,   18,  129,   30,    4,   97,  #  4320 
      24,  129,   30,    4,   92,   29,  129,   30,    4,   87,  #  4330 
      34,  129,   81,   40,  129,   76,   45,  129,   70,   49,  #  4340 
     129,   65,   49,  129,   60,   49,  129,   55,   49,  129,  #  4350 
      50,   48,  129,   44,   49,  129,   39,   48,  129,   33,  #  4360 
      49,  129,   30,   47,  129,   34,   37,  129,   40,   26,  #  4370 
     129,   46,   19,  129,   52,   19,  129,   58,   19,  129,  #  4380 
      64,   19,  129,   70,   19,  129,   76,   19,  129,   82,  #  4390 
      19,  129,   30,    4,   88,   18,  129,   30,    4,   94,  #  4400 
      18,  129,   30,    4,  100,   18,  129,   30,    4,  106,  #  4410 
      15,  129,   30,   91,  137,   30,    4,  117,    4,  132,  #  4420 
     193,  129,   30,    4,  117,    4,  132,   30,   91,  132,  #  4430 
      30,    4,  107,   14,  129,   30,    4,  104,   17,  129,  #  4440 
      30,    4,  101,   20,  129,   30,    4,   99,   22,  129,  #  4450 
      96,   25,  129,   93,   28,  129,   91,   28,  129,   88,  #  4460 
      29,  129,   85,   29,  129,   82,   29,  129,   79,   29,  #  4470 
     129,   76,   29,  129,   74,   29,  129,   71,   29,  129,  #  4480 
      68,   29,  129,   65,   29,  129,   62,   29,  129,   60,  #  4490 
      29,  129,   57,   29,  129,   54,   29,  129,   51,   29,  #  4500 
     129,   49,   28,  129,   46,   29,  129,   43,   29,  129,  #  4510 
      40,   29,  117,    4,  129,   37,   29,  117,    4,  129,  #  4520 
      35,   29,  117,    4,  129,   32,   29,  117,    4,  129,  #  4530 
      30,   91,  132,  117,    4,  132,  193,  129,   63,   25,  #  4540 
     129,   57,   37,  129,   53,   45,  129,   50,   51,  129,  #  4550 
      47,   57,  129,   45,   61,  129,   43,   65,  129,   41,  #  4560 
      69,  129,   39,   73,  129,   38,   21,   92,   21,  129,  #  4570 
      36,   18,   97,   18,  129,   35,   14,  102,   14,  129,  #  4580 
      34,   11,  106,   11,  129,   33,   10,  108,   10,  129,  #  4590 
      32,    8,  111,    8,  129,   32,    6,  113,    6,  129,  #  4600 
      31,    6,  114,    6,  129,   31,    5,  115,    5,  129,  #  4610 
      30,    5,  116,    5,  130,   30,    4,  117,    4,  132,  #  4620 
      30,    5,  116,    5,  130,   31,    5,  115,    5,  129,  #  4630 
      31,    6,  114,    6,  129,   32,    6,  113,    6,  129,  #  4640 
      32,    8,  111,    8,  129,   33,   10,  108,   10,  129,  #  4650 
      34,   11,  106,   11,  129,   35,   14,  102,   14,  129,  #  4660 
      36,   18,   97,   18,  129,   38,   21,   92,   21,  129,  #  4670 
      39,   73,  129,   41,   69,  129,   43,   65,  129,   45,  #  4680 
      61,  129,   47,   57,  129,   50,   51,  129,   53,   45,  #  4690 
     129,   57,   37,  129,   63,   25,  129,  193,  129,   30,  #  4700 
       4,  117,    4,  132,   30,   91,  137,   30,    4,   80,  #  4710 
       4,  117,    4,  132,   80,    4,  117,    4,  134,   80,  #  4720 
       5,  116,    5,  131,   80,    6,  115,    6,  130,   81,  #  4730 
       6,  114,    6,  129,   81,    8,  112,    8,  129,   81,  #  4740 
       9,  111,    9,  129,   82,   10,  109,   10,  129,   82,  #  4750 
      13,  106,   13,  129,   83,   35,  129,   84,   33,  129,  #  4760 
      85,   31,  129,   86,   29,  129,   88,   25,  129,   90,  #  4770 
      21,  129,   93,   15,  129,   96,    9,  129,  193,  129,  #  4780 
      63,   25,  129,   57,   37,  129,   53,   45,  129,   50,  #  4790 
      51,  129,   47,   57,  129,   45,   61,  129,   43,   65,  #  4800 
     129,   41,   69,  129,   39,   73,  129,   38,   21,   92,  #  4810 
      21,  129,   36,   18,   97,   18,  129,   35,   14,  102,  #  4820 
      14,  129,   34,   11,  106,   11,  129,   33,   10,  108,  #  4830 
      10,  129,   32,    8,  111,    8,  129,   32,    6,  113,  #  4840 
       6,  129,   31,    6,  114,    6,  129,   31,    5,  115,  #  4850 
       5,  129,   30,    5,  116,    5,  130,   30,    4,   39,  #  4860 
       2,  117,    4,  129,   30,    4,   40,    4,  117,    4,  #  4870 
     129,   30,    4,   41,    5,  117,    4,  129,   30,    4,  #  4880 
      41,    6,  117,    4,  129,   30,    5,   40,    8,  116,  #  4890 
       5,  129,   30,    5,   39,   10,  116,    5,  129,   31,  #  4900 
       5,   38,   11,  115,    5,  129,   31,   18,  114,    6,  #  4910 
     129,   32,   17,  113,    6,  129,   32,   16,  111,    8,  #  4920 
     129,   33,   15,  108,   10,  129,   33,   14,  106,   11,  #  4930 
     129,   32,   17,  102,   14,  129,   31,   23,   97,   18,  #  4940 
     129,   31,   28,   92,   21,  129,   30,   82,  129,   30,  #  4950 
      80,  129,   30,   11,   43,   65,  129,   30,   10,   45,  #  4960 
      61,  129,   31,    8,   47,   57,  129,   32,    6,   50,  #  4970 
      51,  129,   33,    5,   53,   45,  129,   35,    4,   57,  #  4980 
      37,  129,   38,    2,   63,   25,  129,  193,  129,   30,  #  4990 
       4,  117,    4,  132,   30,   91,  137,   30,    4,   76,  #  5000 
       8,  117,    4,  129,   30,    4,   73,   11,  117,    4,  #  5010 
     129,   30,    4,   70,   14,  117,    4,  129,   30,    4,  #  5020 
      67,   17,  117,    4,  129,   65,   19,  117,    4,  129,  #  5030 
      62,   22,  117,    4,  129,   59,   25,  117,    4,  129,  #  5040 
      56,   28,  117,    4,  129,   53,   31,  117,    4,  129,  #  5050 
      50,   34,  117,    4,  129,   47,   29,   80,    5,  116,  #  5060 
       5,  129,   30,    4,   45,   29,   80,    5,  116,    5,  #  5070 
     129,   30,    4,   42,   29,   80,    5,  116,    5,  129,  #  5080 
      30,    4,   39,   30,   80,    6,  115,    6,  129,   30,  #  5090 
       4,   36,   30,   80,    6,  115,    6,  129,   30,   33,  #  5100 
      81,    6,  114,    6,  129,   30,   30,   81,    8,  112,  #  5110 
       8,  129,   30,   27,   81,    9,  111,    9,  129,   30,  #  5120 
      25,   82,   10,  109,   10,  129,   30,   22,   82,   13,  #  5130 
     106,   13,  129,   30,   19,   83,   35,  129,   30,   16,  #  5140 
      84,   33,  129,   30,   13,   85,   31,  129,   30,   11,  #  5150 
      86,   29,  129,   30,    8,   88,   25,  129,   30,    5,  #  5160 
      90,   21,  129,   30,    4,   93,   15,  129,   30,    4,  #  5170 
      96,    9,  129,   30,    4,  130,  193,  129,   30,   18,  #  5180 
     130,   30,   18,   89,   15,  129,   30,   18,   85,   23,  #  5190 
     129,   34,   11,   83,   27,  129,   34,    9,   81,   31,  #  5200 
     129,   33,    8,   79,   35,  129,   33,    6,   78,   16,  #  5210 
     106,    9,  129,   32,    6,   77,   15,  109,    7,  129,  #  5220 
      32,    5,   76,   14,  111,    6,  129,   31,    5,   75,  #  5230 
      14,  113,    5,  129,   31,    4,   74,   15,  114,    5,  #  5240 
     129,   31,    4,   74,   14,  115,    4,  129,   30,    4,  #  5250 
      73,   15,  116,    4,  129,   30,    4,   73,   14,  116,  #  5260 
       4,  129,   30,    4,   73,   14,  117,    4,  129,   30,  #  5270 
       4,   72,   15,  117,    4,  130,   30,    4,   71,   15,  #  5280 
     117,    4,  130,   30,    4,   70,   15,  117,    4,  129,  #  5290 
      30,    5,   70,   15,  117,    4,  129,   30,    5,   69,  #  5300 
      15,  116,    5,  129,   30,    6,   68,   16,  115,    5,  #  5310 
     129,   31,    6,   67,   16,  114,    6,  129,   31,    7,  #  5320 
      66,   17,  113,    6,  129,   32,    7,   64,   18,  111,  #  5330 
       8,  129,   32,    8,   62,   19,  109,    9,  129,   33,  #  5340 
       9,   60,   20,  107,   10,  129,   34,   11,   57,   22,  #  5350 
     103,   13,  129,   35,   43,  103,   18,  129,   36,   41,  #  5360 
     103,   18,  129,   38,   38,  103,   18,  129,   39,   35,  #  5370 
     103,   18,  129,   41,   31,  129,   43,   27,  129,   46,  #  5380 
      22,  129,   49,   14,  129,  193,  129,  103,   18,  132,  #  5390 
     110,   11,  129,  113,    8,  129,  114,    7,  129,  116,  #  5400 
       5,  130,  117,    4,  132,   30,    4,  117,    4,  132,  #  5410 
      30,   91,  137,   30,    4,  117,    4,  132,  117,    4,  #  5420 
     132,  116,    5,  130,  114,    7,  129,  113,    8,  129,  #  5430 
     110,   11,  129,  103,   18,  132,  193,  129,  117,    4,  #  5440 
     132,   56,   65,  129,   50,   71,  129,   46,   75,  129,  #  5450 
      44,   77,  129,   42,   79,  129,   40,   81,  129,   38,  #  5460 
      83,  129,   36,   85,  129,   35,   86,  129,   34,   20,  #  5470 
     117,    4,  129,   33,   17,  117,    4,  129,   32,   15,  #  5480 
     117,    4,  129,   32,   13,  117,    4,  129,   31,   12,  #  5490 
     129,   31,   10,  129,   31,    9,  129,   30,    9,  129,  #  5500 
      30,    8,  130,   30,    7,  132,   31,    6,  130,   31,  #  5510 
       7,  129,   32,    6,  129,   32,    7,  129,   33,    7,  #  5520 
     129,   34,    7,  129,   35,    8,  129,   36,    9,  117,  #  5530 
       4,  129,   38,    9,  117,    4,  129,   40,   10,  117,  #  5540 
       4,  129,   42,   12,  117,    4,  129,   44,   77,  129,  #  5550 
      46,   75,  129,   50,   71,  129,   56,   43,  100,   21,  #  5560 
     129,  117,    4,  132,  193,  129,  117,    4,  132,  115,  #  5570 
       6,  129,  110,   11,  129,  105,   16,  129,  101,   20,  #  5580 
     129,   96,   25,  129,   92,   29,  129,   87,   34,  129,  #  5590 
      83,   38,  129,   78,   43,  129,   74,   47,  129,   70,  #  5600 
      42,  117,    4,  129,   65,   42,  117,    4,  129,   60,  #  5610 
      43,  117,    4,  129,   56,   42,  129,   51,   42,  129,  #  5620 
      46,   43,  129,   42,   43,  129,   37,   44,  129,   33,  #  5630 
      43,  129,   30,   42,  129,   33,   34,  129,   38,   25,  #  5640 
     129,   42,   16,  129,   47,   15,  129,   52,   15,  129,  #  5650 
      57,   15,  129,   61,   16,  129,   66,   16,  129,   71,  #  5660 
      16,  129,   76,   16,  129,   80,   16,  129,   85,   16,  #  5670 
     117,    4,  129,   90,   16,  117,    4,  129,   95,   16,  #  5680 
     117,    4,  129,  100,   21,  129,  105,   16,  129,  110,  #  5690 
      11,  129,  114,    7,  129,  117,    4,  132,  193,  129,  #  5700 
     117,    4,  132,  115,    6,  129,  110,   11,  129,  105,  #  5710 
      16,  129,  101,   20,  129,   96,   25,  129,   92,   29,  #  5720 
     129,   87,   34,  129,   83,   38,  129,   78,   43,  129,  #  5730 
      74,   47,  129,   70,   42,  117,    4,  129,   65,   42,  #  5740 
     117,    4,  129,   60,   43,  117,    4,  129,   56,   42,  #  5750 
     129,   51,   42,  129,   46,   43,  129,   42,   43,  129,  #  5760 
      37,   44,  129,   33,   43,  129,   30,   42,  129,   33,  #  5770 
      34,  129,   38,   25,  129,   42,   16,  129,   47,   15,  #  5780 
     129,   52,   15,  129,   57,   15,  129,   61,   16,  129,  #  5790 
      65,   17,  129,   60,   27,  129,   56,   36,  129,   51,  #  5800 
      42,  129,   46,   43,  129,   42,   43,  129,   37,   44,  #  5810 
     129,   33,   43,  129,   30,   42,  129,   33,   34,  129,  #  5820 
      38,   25,  129,   42,   16,  129,   47,   15,  129,   52,  #  5830 
      15,  129,   57,   15,  129,   61,   16,  129,   66,   16,  #  5840 
     129,   71,   16,  129,   76,   16,  129,   80,   16,  129,  #  5850 
      85,   16,  117,    4,  129,   90,   16,  117,    4,  129,  #  5860 
      95,   16,  117,    4,  129,  100,   21,  129,  105,   16,  #  5870 
     129,  110,   11,  129,  114,    7,  129,  117,    4,  132,  #  5880 
     193,  129,   30,    4,  117,    4,  132,   30,    4,  115,  #  5890 
       6,  129,   30,    4,  112,    9,  129,   30,    6,  109,  #  5900 
      12,  129,   30,    9,  106,   15,  129,   30,   11,  103,  #  5910 
      18,  129,   30,   14,  100,   21,  129,   30,    4,   38,  #  5920 
       9,   98,   23,  129,   30,    4,   40,   10,   95,   26,  #  5930 
     129,   30,    4,   43,    9,   92,   29,  129,   46,    9,  #  5940 
      89,   32,  129,   49,    8,   86,   28,  117,    4,  129,  #  5950 
      51,    9,   83,   28,  117,    4,  129,   54,    9,   80,  #  5960 
      28,  117,    4,  129,   57,    8,   77,   28,  117,    4,  #  5970 
     129,   59,    9,   74,   28,  129,   62,   37,  129,   64,  #  5980 
      33,  129,   66,   28,  129,   63,   28,  129,   60,   28,  #  5990 
     129,   57,   28,  129,   54,   33,  129,   51,   39,  129,  #  6000 
      48,   29,   83,    9,  129,   30,    4,   45,   29,   86,  #  6010 
       9,  129,   30,    4,   42,   29,   89,    9,  129,   30,  #  6020 
       4,   39,   29,   92,    8,  129,   30,    4,   36,   29,  #  6030 
      94,    9,  129,   30,   32,   97,    9,  129,   30,   29,  #  6040 
     100,    8,  117,    4,  129,   30,   26,  103,    8,  117,  #  6050 
       4,  129,   30,   23,  105,    9,  117,    4,  129,   30,  #  6060 
      20,  108,   13,  129,   30,   18,  111,   10,  129,   30,  #  6070 
      15,  113,    8,  129,   30,   12,  116,    5,  129,   30,  #  6080 
       9,  117,    4,  129,   30,    6,  117,    4,  129,   30,  #  6090 
       4,  117,    4,  132,  193,  129,  117,    4,  132,  114,  #  6100 
       7,  129,  111,   10,  129,  108,   13,  129,  105,   16,  #  6110 
     129,  102,   19,  129,  100,   21,  129,   96,   25,  129,  #  6120 
      93,   28,  129,   90,   31,  129,   87,   34,  129,   84,  #  6130 
      30,  117,    4,  129,   30,    4,   81,   30,  117,    4,  #  6140 
     129,   30,    4,   78,   30,  117,    4,  129,   30,    4,  #  6150 
      75,   30,  117,    4,  129,   30,    4,   72,   30,  129,  #  6160 
      30,   69,  129,   30,   66,  129,   30,   63,  129,   30,  #  6170 
      60,  129,   30,   57,  129,   30,   54,  129,   30,   51,  #  6180 
     129,   30,   48,  129,   30,   51,  129,   30,    4,   73,  #  6190 
      12,  129,   30,    4,   76,   12,  129,   30,    4,   80,  #  6200 
      12,  129,   30,    4,   83,   12,  129,   87,   12,  129,  #  6210 
      90,   12,  117,    4,  129,   94,   11,  117,    4,  129,  #  6220 
      97,   12,  117,    4,  129,  101,   12,  117,    4,  129,  #  6230 
     104,   17,  129,  108,   13,  129,  111,   10,  129,  115,  #  6240 
       6,  129,  117,    4,  134,  193,  129,   30,    1,  103,  #  6250 
      18,  129,   30,    4,  103,   18,  129,   30,    7,  103,  #  6260 
      18,  129,   30,    9,  103,   18,  129,   30,   12,  110,  #  6270 
      11,  129,   30,   15,  113,    8,  129,   30,   18,  114,  #  6280 
       7,  129,   30,   21,  116,    5,  129,   30,   24,  116,  #  6290 
       5,  129,   30,   27,  117,    4,  129,   30,   30,  117,  #  6300 
       4,  129,   30,   33,  117,    4,  129,   30,    4,   37,  #  6310 
      28,  117,    4,  129,   30,    4,   40,   28,  117,    4,  #  6320 
     129,   30,    4,   42,   29,  117,    4,  129,   30,    4,  #  6330 
      45,   29,  117,    4,  129,   30,    4,   48,   29,  117,  #  6340 
       4,  129,   30,    4,   51,   29,  117,    4,  129,   30,  #  6350 
       4,   54,   29,  117,    4,  129,   30,    4,   57,   29,  #  6360 
     117,    4,  129,   30,    4,   59,   30,  117,    4,  129,  #  6370 
      30,    4,   62,   30,  117,    4,  129,   30,    4,   65,  #  6380 
      30,  117,    4,  129,   30,    4,   68,   30,  117,    4,  #  6390 
     129,   30,    4,   71,   30,  117,    4,  129,   30,    4,  #  6400 
      74,   30,  117,    4,  129,   30,    4,   77,   30,  117,  #  6410 
       4,  129,   30,    4,   80,   30,  117,    4,  129,   30,  #  6420 
       4,   83,   30,  117,    4,  129,   30,    4,   86,   35,  #  6430 
     129,   30,    4,   89,   32,  129,   30,    4,   91,   30,  #  6440 
     129,   30,    4,   94,   27,  129,   30,    5,   97,   24,  #  6450 
     129,   30,    5,  100,   21,  129,   30,    7,  103,   18,  #  6460 
     129,   30,    8,  106,   15,  129,   30,   11,  109,   12,  #  6470 
     129,   30,   18,  112,    9,  129,   30,   18,  115,    6,  #  6480 
     129,   30,   18,  117,    4,  129,   30,   18,  120,    1,  #  6490 
     129,  193,  129,   42,    8,  129,   38,   16,  129,   36,  #  6500 
      20,  129,   34,   24,   71,    5,  129,   33,   26,   69,  #  6510 
      10,  129,   32,   28,   68,   13,  129,   31,   30,   68,  #  6520 
      14,  129,   31,    9,   52,    9,   68,   15,  129,   30,  #  6530 
       8,   54,    8,   69,   14,  129,   30,    7,   55,    7,  #  6540 
      71,    4,   78,    6,  129,   30,    6,   56,    6,   79,  #  6550 
       5,  129,   30,    6,   56,    6,   80,    4,  130,   31,  #  6560 
       5,   56,    5,   80,    4,  129,   31,    5,   56,    5,  #  6570 
      79,    5,  129,   32,    5,   55,    5,   78,    6,  129,  #  6580 
      33,    5,   54,    5,   77,    7,  129,   34,    6,   52,  #  6590 
       6,   74,    9,  129,   35,   48,  129,   33,   49,  129,  #  6600 
      32,   49,  129,   31,   49,  129,   30,   49,  129,   30,  #  6610 
      47,  129,   30,   45,  129,   30,   41,  129,   30,    6,  #  6620 
     129,   30,    4,  129,   30,    3,  129,   30,    2,  129,  #  6630 
     193,  129,   30,    4,  117,    4,  130,   31,   90,  136,  #  6640 
      37,    5,   72,    5,  129,   35,    5,   74,    5,  129,  #  6650 
      33,    5,   76,    5,  129,   32,    5,   77,    5,  129,  #  6660 
      31,    5,   78,    5,  129,   31,    4,   79,    4,  129,  #  6670 
      30,    5,   79,    5,  131,   30,    6,   78,    6,  129,  #  6680 
      30,    7,   77,    7,  129,   31,    8,   75,    8,  129,  #  6690 
      31,   11,   72,   11,  129,   32,   15,   67,   15,  129,  #  6700 
      33,   48,  129,   34,   46,  129,   35,   44,  129,   37,  #  6710 
      40,  129,   39,   36,  129,   42,   30,  129,   46,   22,  #  6720 
     129,  193,  129,   48,   18,  129,   43,   28,  129,   41,  #  6730 
      32,  129,   39,   36,  129,   37,   40,  129,   35,   44,  #  6740 
     129,   34,   46,  129,   33,   13,   68,   13,  129,   32,  #  6750 
       9,   73,    9,  129,   32,    7,   75,    7,  129,   31,  #  6760 
       6,   77,    6,  129,   31,    5,   78,    5,  129,   30,  #  6770 
       5,   79,    5,  129,   30,    4,   80,    4,  133,   31,  #  6780 
       3,   79,    4,  129,   31,    4,   79,    4,  129,   32,  #  6790 
       3,   78,    4,  129,   32,    4,   76,    6,  129,   33,  #  6800 
       4,   74,    7,  129,   34,    4,   72,    8,  129,   35,  #  6810 
       5,   72,    7,  129,   37,    5,   73,    4,  129,   39,  #  6820 
       4,   74,    1,  129,  129,  193,  129,   46,   22,  129,  #  6830 
      42,   30,  129,   39,   36,  129,   37,   40,  129,   35,  #  6840 
      44,  129,   34,   46,  129,   33,   48,  129,   32,   15,  #  6850 
      67,   15,  129,   31,   11,   72,   11,  129,   31,    8,  #  6860 
      75,    8,  129,   30,    7,   77,    7,  129,   30,    6,  #  6870 
      78,    6,  129,   30,    5,   79,    5,  131,   31,    4,  #  6880 
      79,    4,  129,   31,    5,   78,    5,  129,   32,    5,  #  6890 
      77,    5,  129,   33,    5,   76,    5,  129,   35,    5,  #  6900 
      74,    5,  117,    4,  129,   37,    5,   72,    5,  117,  #  6910 
       4,  129,   30,   91,  136,   30,    4,  130,  193,  129,  #  6920 
      48,   18,  129,   43,   28,  129,   41,   32,  129,   39,  #  6930 
      36,  129,   37,   40,  129,   35,   44,  129,   34,   46,  #  6940 
     129,   33,   13,   55,    4,   68,   13,  129,   32,    9,  #  6950 
      55,    4,   73,    9,  129,   32,    7,   55,    4,   75,  #  6960 
       7,  129,   31,    6,   55,    4,   77,    6,  129,   31,  #  6970 
       5,   55,    4,   78,    5,  129,   30,    5,   55,    4,  #  6980 
      79,    5,  129,   30,    4,   55,    4,   80,    4,  132,  #  6990 
      30,    4,   55,    4,   79,    5,  129,   31,    3,   55,  #  7000 
       4,   78,    5,  129,   31,    4,   55,    4,   77,    6,  #  7010 
     129,   32,    3,   55,    4,   75,    7,  129,   32,    4,  #  7020 
      55,    4,   73,    9,  129,   33,    4,   55,    4,   68,  #  7030 
      13,  129,   34,    4,   55,   25,  129,   35,    5,   55,  #  7040 
      24,  129,   37,    5,   55,   22,  129,   39,    4,   55,  #  7050 
      20,  129,   55,   18,  129,   55,   16,  129,   55,   11,  #  7060 
     129,  193,  129,   80,    4,  129,   30,    4,   80,    4,  #  7070 
     130,   30,   78,  129,   30,   82,  129,   30,   85,  129,  #  7080 
      30,   87,  129,   30,   88,  129,   30,   89,  129,   30,  #  7090 
      90,  130,   30,    4,   80,    4,  115,    6,  129,   30,  #  7100 
       4,   80,    4,  117,    4,  129,   80,    4,  105,    6,  #  7110 
     117,    4,  129,   80,    4,  103,   10,  116,    5,  129,  #  7120 
      80,    4,  102,   19,  129,   80,    4,  101,   19,  129,  #  7130 
     101,   19,  129,  101,   18,  129,  102,   16,  129,  103,  #  7140 
      12,  129,  105,    6,  129,  193,  129,   12,   10,   59,  #  7150 
      11,  129,    9,   16,   55,   19,  129,    7,   20,   53,  #  7160 
      23,  129,    6,    7,   23,    5,   32,    6,   51,   27,  #  7170 
     129,    4,    7,   25,   16,   50,   29,  129,    3,    6,  #  7180 
      27,   16,   49,   31,  129,    2,    6,   28,   16,   48,  #  7190 
      33,  129,    1,    6,   27,   18,   47,   35,  129,    1,  #  7200 
       6,   27,   31,   71,   12,  129,    1,    5,   26,   15,  #  7210 
      44,   10,   75,    8,  129,    1,    5,   25,   14,   45,  #  7220 
       7,   77,    7,  129,    1,    5,   25,   13,   45,    5,  #  7230 
      79,    5,  129,    1,    5,   24,   14,   45,    4,   80,  #  7240 
       4,  129,    1,    5,   24,   13,   45,    4,   80,    4,  #  7250 
     129,    1,    5,   23,   14,   45,    4,   80,    4,  129,  #  7260 
       1,    5,   23,   13,   45,    4,   80,    4,  129,    1,  #  7270 
       6,   22,   13,   45,    5,   79,    5,  129,    1,    6,  #  7280 
      21,   14,   45,    7,   77,    7,  129,    1,    7,   21,  #  7290 
      13,   46,    8,   75,    8,  129,    1,    8,   20,   13,  #  7300 
      46,   12,   71,   12,  129,    1,   10,   18,   15,   47,  #  7310 
      35,  129,    2,   30,   48,   33,  129,    3,   29,   49,  #  7320 
      32,  129,    4,   27,   50,   31,  129,    5,   25,   51,  #  7330 
      27,   80,    2,   86,    4,  129,    7,   21,   53,   23,  #  7340 
      80,    3,   85,    6,  129,    9,   17,   55,   19,   80,  #  7350 
      12,  129,   12,   12,   59,   11,   81,   11,  129,   82,  #  7360 
      10,  129,   84,    7,  129,   86,    4,  129,  193,  129,  #  7370 
      30,    4,  117,    4,  130,   30,   91,  136,   30,    4,  #  7380 
      72,    5,  129,   30,    4,   74,    5,  129,   75,    5,  #  7390 
     129,   76,    5,  129,   76,    6,  129,   77,    6,  130,  #  7400 
      77,    7,  130,   76,    8,  129,   30,    4,   75,    9,  #  7410 
     129,   30,    4,   72,   12,  129,   30,   54,  129,   30,  #  7420 
      53,  130,   30,   52,  129,   30,   51,  129,   30,   49,  #  7430 
     129,   30,   46,  129,   30,   42,  129,   30,    4,  130,  #  7440 
     193,  129,   30,    4,   80,    4,  129,   30,    4,   80,  #  7450 
       4,  100,    6,  129,   30,   54,   98,   10,  129,   30,  #  7460 
      54,   97,   12,  129,   30,   54,   96,   14,  131,   30,  #  7470 
      54,   97,   12,  129,   30,   54,   98,   10,  129,   30,  #  7480 
      54,  100,    6,  129,   30,    4,  130,  193,  129,    7,  #  7490 
       6,  129,    4,   11,  129,    3,   13,  129,    2,   14,  #  7500 
     129,    1,   15,  130,    1,    3,    6,    9,  129,    1,  #  7510 
       3,    7,    6,  129,    1,    3,  130,    1,    4,  129,  #  7520 
       1,    5,   80,    4,  129,    1,    7,   80,    4,  100,  #  7530 
       6,  129,    2,   82,   98,   10,  129,    3,   81,   97,  #  7540 
      12,  129,    4,   80,   96,   14,  129,    5,   79,   96,  #  7550 
      14,  129,    7,   77,   96,   14,  129,   10,   74,   97,  #  7560 
      12,  129,   14,   70,   98,   10,  129,   19,   65,  100,  #  7570 
       6,  129,  193,  129,   30,    4,  117,    4,  130,   30,  #  7580 
      91,  136,   30,    4,   57,    9,  129,   30,    4,   55,  #  7590 
      12,  129,   52,   17,  129,   50,   20,  129,   48,   24,  #  7600 
     129,   46,   27,  129,   44,   21,   69,    6,  129,   41,  #  7610 
      22,   70,    6,   80,    4,  129,   30,    4,   39,   21,  #  7620 
      72,    6,   80,    4,  129,   30,    4,   36,   22,   73,  #  7630 
      11,  129,   30,   26,   75,    9,  129,   30,   23,   76,  #  7640 
       8,  129,   30,   21,   78,    6,  129,   30,   19,   79,  #  7650 
       5,  129,   30,   16,   80,    4,  129,   30,   14,   80,  #  7660 
       4,  129,   30,   12,  129,   30,   10,  129,   30,    7,  #  7670 
     129,   30,    5,  129,   30,    4,  130,  193,  129,   30,  #  7680 
       4,  117,    4,  130,   30,   91,  136,   30,    4,  130,  #  7690 
     193,  129,   30,    4,   80,    4,  130,   30,   54,  136,  #  7700 
      30,    4,   72,    5,  129,   30,    4,   74,    5,  129,  #  7710 
      75,    5,  129,   76,    5,  129,   30,    4,   75,    7,  #  7720 
     129,   30,    4,   74,    9,  129,   30,   54,  132,   30,  #  7730 
      53,  129,   30,   52,  129,   30,   51,  129,   30,   48,  #  7740 
     129,   30,    4,   72,    5,  129,   30,    4,   74,    5,  #  7750 
     129,   75,    5,  129,   76,    5,  129,   30,    4,   75,  #  7760 
       7,  129,   30,    4,   74,    9,  129,   30,   54,  132,  #  7770 
      30,   53,  129,   30,   52,  129,   30,   51,  129,   30,  #  7780 
      48,  129,   30,    4,  130,  193,  129,   30,    4,   80,  #  7790 
       4,  130,   30,   54,  136,   30,    4,   72,    5,  129,  #  7800 
      30,    4,   74,    5,  129,   75,    5,  129,   76,    5,  #  7810 
     129,   76,    6,  129,   77,    6,  130,   77,    7,  130,  #  7820 
      76,    8,  129,   30,    4,   75,    9,  129,   30,    4,  #  7830 
      72,   12,  129,   30,   54,  129,   30,   53,  130,   30,  #  7840 
      52,  129,   30,   51,  129,   30,   49,  129,   30,   46,  #  7850 
     129,   30,   42,  129,   30,    4,  130,  193,  129,   48,  #  7860 
      18,  129,   43,   28,  129,   41,   32,  129,   39,   36,  #  7870 
     129,   37,   40,  129,   35,   44,  129,   34,   46,  129,  #  7880 
      33,   13,   68,   13,  129,   32,    9,   73,    9,  129,  #  7890 
      32,    7,   75,    7,  129,   31,    6,   77,    6,  129,  #  7900 
      31,    5,   78,    5,  129,   30,    5,   79,    5,  129,  #  7910 
      30,    4,   80,    4,  132,   30,    5,   79,    5,  130,  #  7920 
      31,    5,   78,    5,  129,   31,    6,   77,    6,  129,  #  7930 
      32,    7,   75,    7,  129,   32,    9,   73,    9,  129,  #  7940 
      33,   13,   68,   13,  129,   34,   46,  129,   35,   44,  #  7950 
     129,   37,   40,  129,   39,   36,  129,   41,   32,  129,  #  7960 
      43,   28,  129,   48,   18,  129,  193,  129,    1,    3,  #  7970 
      80,    4,  130,    1,   83,  137,   37,    5,   72,    5,  #  7980 
     129,   35,    5,   74,    5,  129,   33,    5,   76,    5,  #  7990 
     129,   32,    5,   77,    5,  129,   31,    5,   78,    5,  #  8000 
     129,   31,    4,   79,    4,  129,   30,    5,   79,    5,  #  8010 
     131,   30,    6,   78,    6,  129,   30,    7,   77,    7,  #  8020 
     129,   31,    8,   75,    8,  129,   31,   11,   72,   11,  #  8030 
     129,   32,   15,   67,   15,  129,   33,   48,  129,   34,  #  8040 
      46,  129,   35,   44,  129,   37,   40,  129,   39,   36,  #  8050 
     129,   42,   30,  129,   46,   22,  129,  193,  129,   46,  #  8060 
      22,  129,   42,   30,  129,   39,   36,  129,   37,   40,  #  8070 
     129,   35,   44,  129,   34,   46,  129,   33,   48,  129,  #  8080 
      32,   15,   67,   15,  129,   31,   11,   72,   11,  129,  #  8090 
      31,    8,   75,    8,  129,   30,    7,   77,    7,  129,  #  8100 
      30,    6,   78,    6,  129,   30,    5,   79,    5,  131,  #  8110 
      31,    4,   79,    4,  129,   31,    5,   78,    5,  129,  #  8120 
      32,    5,   77,    5,  129,   33,    5,   76,    5,  129,  #  8130 
      35,    5,   74,    5,  129,   37,    5,   72,    5,  129,  #  8140 
       1,   83,  136,    1,    3,   80,    4,  130,  193,  129,  #  8150 
      30,    4,   80,    4,  130,   30,   54,  136,   30,    4,  #  8160 
      68,    6,  129,   30,    4,   70,    6,  129,   71,    7,  #  8170 
     129,   72,    7,  129,   73,    7,  129,   74,    7,  129,  #  8180 
      74,    8,  129,   75,    8,  130,   69,   15,  129,   67,  #  8190 
      17,  129,   66,   18,  129,   65,   19,  130,   65,   18,  #  8200 
     130,   66,   16,  129,   67,   13,  129,   69,    8,  129,  #  8210 
     193,  129,   30,   13,   64,    8,  129,   30,   13,   61,  #  8220 
      14,  129,   30,   13,   59,   18,  129,   30,   13,   57,  #  8230 
      22,  129,   33,    8,   56,   24,  129,   32,    7,   55,  #  8240 
      26,  129,   32,    6,   54,   28,  129,   31,    6,   53,  #  8250 
      16,   77,    6,  129,   31,    5,   53,   14,   79,    4,  #  8260 
     129,   30,    5,   52,   14,   80,    4,  129,   30,    5,  #  8270 
      52,   13,   80,    4,  129,   30,    4,   52,   13,   80,  #  8280 
       4,  129,   30,    4,   52,   12,   80,    4,  129,   30,  #  8290 
       4,   51,   13,   80,    4,  130,   30,    4,   50,   13,  #  8300 
      79,    5,  129,   30,    4,   50,   13,   78,    5,  129,  #  8310 
      30,    5,   49,   14,   77,    6,  129,   31,    4,   49,  #  8320 
      13,   76,    6,  129,   31,    5,   48,   14,   75,    7,  #  8330 
     129,   32,    5,   47,   14,   73,    8,  129,   32,    6,  #  8340 
      45,   16,   71,   13,  129,   33,   27,   71,   13,  129,  #  8350 
      34,   26,   71,   13,  129,   35,   24,   71,   13,  129,  #  8360 
      37,   20,  129,   39,   16,  129,   43,    9,  129,  193,  #  8370 
     129,   80,    4,  131,   41,   56,  129,   37,   60,  129,  #  8380 
      35,   62,  129,   33,   64,  129,   32,   65,  129,   31,  #  8390 
      66,  129,   30,   67,  130,   30,   11,   80,    4,  129,  #  8400 
      30,    9,   80,    4,  129,   30,    8,   80,    4,  129,  #  8410 
      31,    7,   80,    4,  129,   31,    6,  129,   32,    5,  #  8420 
     129,   33,    5,  129,   35,    4,  129,   38,    3,  129,  #  8430 
     193,  129,   80,    4,  130,   42,   42,  129,   38,   46,  #  8440 
     129,   35,   49,  129,   33,   51,  129,   32,   52,  129,  #  8450 
      31,   53,  130,   30,   54,  129,   30,   12,  129,   30,  #  8460 
       9,  129,   30,    8,  129,   30,    7,  130,   31,    6,  #  8470 
     130,   32,    6,  129,   33,    5,  129,   34,    5,  129,  #  8480 
      35,    5,   80,    4,  129,   37,    5,   80,    4,  129,  #  8490 
      30,   54,  136,   30,    4,  130,  193,  129,   80,    4,  #  8500 
     130,   77,    7,  129,   74,   10,  129,   70,   14,  129,  #  8510 
      66,   18,  129,   62,   22,  129,   59,   25,  129,   55,  #  8520 
      29,  129,   51,   33,  129,   47,   37,  129,   44,   32,  #  8530 
      80,    4,  129,   40,   32,   80,    4,  129,   36,   32,  #  8540 
     129,   32,   33,  129,   30,   31,  129,   33,   24,  129,  #  8550 
      36,   17,  129,   40,   12,  129,   44,   12,  129,   48,  #  8560 
      12,  129,   51,   13,  129,   55,   13,  129,   59,   13,  #  8570 
      80,    4,  129,   63,   13,   80,    4,  129,   67,   17,  #  8580 
     129,   71,   13,  129,   74,   10,  129,   78,    6,  129,  #  8590 
      80,    4,  131,  193,  129,   80,    4,  130,   77,    7,  #  8600 
     129,   74,   10,  129,   70,   14,  129,   66,   18,  129,  #  8610 
      62,   22,  129,   59,   25,  129,   55,   29,  129,   51,  #  8620 
      33,  129,   47,   37,  129,   44,   32,   80,    4,  129,  #  8630 
      40,   32,   80,    4,  129,   36,   32,  129,   32,   33,  #  8640 
     129,   30,   31,  129,   33,   24,  129,   36,   17,  129,  #  8650 
      40,   12,  129,   44,   12,  129,   47,   13,  129,   44,  #  8660 
      20,  129,   40,   28,  129,   36,   31,  129,   32,   32,  #  8670 
     129,   30,   30,  129,   33,   24,  129,   36,   17,  129,  #  8680 
      40,   12,  129,   44,   12,  129,   48,   12,  129,   51,  #  8690 
      13,  129,   55,   13,  129,   59,   13,   80,    4,  129,  #  8700 
      63,   13,   80,    4,  129,   67,   17,  129,   71,   13,  #  8710 
     129,   74,   10,  129,   78,    6,  129,   80,    4,  131,  #  8720 
     193,  129,   30,    4,   80,    4,  130,   30,    4,   79,  #  8730 
       5,  129,   30,    5,   77,    7,  129,   30,    6,   74,  #  8740 
      10,  129,   30,    8,   72,   12,  129,   30,   11,   69,  #  8750 
      15,  129,   30,   13,   67,   17,  129,   30,    4,   37,  #  8760 
       8,   64,   20,  129,   30,    4,   39,    8,   62,   22,  #  8770 
     129,   41,    8,   59,   25,  129,   43,    8,   57,   27,  #  8780 
     129,   45,    8,   55,   22,   80,    4,  129,   47,   27,  #  8790 
      80,    4,  129,   49,   23,  129,   47,   22,  129,   44,  #  8800 
      23,  129,   42,   22,  129,   30,    4,   39,   27,  129,  #  8810 
      30,    4,   37,   31,  129,   30,   27,   62,    8,  129,  #  8820 
      30,   25,   64,    8,  129,   30,   22,   66,    8,   80,  #  8830 
       4,  129,   30,   20,   68,    8,   80,    4,  129,   30,  #  8840 
      17,   70,    8,   80,    4,  129,   30,   15,   73,   11,  #  8850 
     129,   30,   12,   75,    9,  129,   30,   10,   77,    7,  #  8860 
     129,   30,    7,   79,    5,  129,   30,    5,   80,    4,  #  8870 
     129,   30,    4,   80,    4,  130,  193,  129,    4,    5,  #  8880 
      80,    4,  129,    2,    9,   80,    4,  129,    1,   11,  #  8890 
      77,    7,  129,    1,   12,   74,   10,  129,    1,   12,  #  8900 
      70,   14,  129,    1,   12,   66,   18,  129,    1,   11,  #  8910 
      62,   22,  129,    2,    9,   59,   25,  129,    4,   11,  #  8920 
      55,   29,  129,    7,   12,   51,   33,  129,   10,   12,  #  8930 
      47,   37,  129,   14,   12,   44,   32,   80,    4,  129,  #  8940 
      17,   13,   40,   32,   80,    4,  129,   21,   13,   36,  #  8950 
      32,  129,   25,   40,  129,   29,   32,  129,   33,   24,  #  8960 
     129,   36,   17,  129,   40,   12,  129,   44,   12,  129,  #  8970 
      48,   12,  129,   51,   13,  129,   55,   13,  129,   59,  #  8980 
      13,   80,    4,  129,   63,   13,   80,    4,  129,   67,  #  8990 
      17,  129,   71,   13,  129,   74,   10,  129,   78,    6,  #  9000 
     129,   80,    4,  131,  193,  129,   30,    1,   71,   13,  #  9010 
     129,   30,    3,   71,   13,  129,   30,    6,   71,   13,  #  9020 
     129,   30,    9,   75,    9,  129,   30,   11,   77,    7,  #  9030 
     129,   30,   14,   79,    5,  129,   30,   17,   79,    5,  #  9040 
     129,   30,   19,   80,    4,  129,   30,   22,   80,    4,  #  9050 
     129,   30,   25,   80,    4,  129,   30,   27,   80,    4,  #  9060 
     129,   30,    4,   36,   24,   80,    4,  129,   30,    4,  #  9070 
      38,   25,   80,    4,  129,   30,    4,   41,   24,   80,  #  9080 
       4,  129,   30,    4,   44,   24,   80,    4,  129,   30,  #  9090 
       4,   46,   25,   80,    4,  129,   30,    4,   49,   25,  #  9100 
      80,    4,  129,   30,    4,   52,   24,   80,    4,  129,  #  9110 
      30,    4,   54,   30,  129,   30,    4,   57,   27,  129,  #  9120 
      30,    4,   59,   25,  129,   30,    4,   62,   22,  129,  #  9130 
      30,    4,   65,   19,  129,   30,    5,   67,   17,  129,  #  9140 
      30,    5,   70,   14,  129,   30,    7,   73,   11,  129,  #  9150 
      30,    9,   76,    8,  129,   30,   13,   78,    6,  129,  #  9160 
      30,   13,   81,    3,  129,   30,   13,  129,  193,    2,  #  9170 
       9,   59,   25,  129,    4,   11,   55,   29,  129,    7,  #  9180 
      12,   51,   33,  129,   10,   12,   47,   37,  129,   14,  #  9190 
      12,   44,   32,   80,    4,  129,   17,   13,   40,   32,  #  9200 
      80,    4,  129,   21,   13,   36,   32,  129,   25,   40,  #  9210 
     129,   29,   32,  129,   33,   24,  129,   36,   17,  129,  #  9220 
      40,   12,  129,   44,   12,  129,   48,   12,  129,   51,  #  9230 
      13,  129,   55,   13,  129,   59,   13,   80,    4,  129,  #  9240 
      63,   13,   80,    4,  129,   67,   17,  129,   71,   13,  #  9250 
     129,   74,   10,  129,   78,    6,  129,   80,    4,  131,  #  9260 
     193,  129,   65,   21,  129,   64,   23,  129,   63,   25,  #  9270 
     129,   62,   27,  129,   61,   29,  129,   60,   31,  129,  #  9280 
      59,   16,   76,   16,  129,   58,   16,   77,   16,  129,  #  9290 
      57,   16,   78,   16,  129,   56,   16,   78,   16,  129,  #  9300 
      55,   16,   79,   16,  129,   54,   16,   80,   16,  129,  #  9310 
      53,   16,   81,   16,  129,   52,   16,   82,   16,  129,  #  9320 
      51,   16,   83,   16,  129,   50,   16,   84,   16,  129,  #  9330 
      49,   16,   85,   16,  129,   48,   16,   86,   16,  129,  #  9340 
      47,   16,   87,   16,  129,   46,   16,   88,   16,  129,  #  9350 
      45,   16,   89,   16,  129,   46,   14,   90,   14,  129,  #  9360 
     193,   129,  46,   14,   90,   14,  129,   45,   16,   89,  #  9370
      16,   129,  46,   16,   88,   16,  129,   47,   16,   87,  #  9380
      16,   129,  48,   16,   86,   16,  129,   49,   16,   85,  #  9390
      16,   129,  50,   16,   84,   16,  129,   51,   16,   83,  #  9400
      16,   129,  52,   16,   82,   16,  129,   53,   16,   81,  #  9410
      16,   129,  54,   16,   80,   16,  129,   55,   16,   79,  #  9420
      16,   129,  56,   16,   78,   16,  129,   57,   16,   78,  #  9430
      16,   129,  58,   16,   77,   16,  129,   59,   16,   76,  #  9440
      16,   129,  60,   31,  129,   61,   29,  129,   62,   27,  #  9450
     129,    63,  25,  129,   64,   23,  129,   65,   21,  129,  #  9460
     193                                                         #  9470
);

sub perlBanner {
	my $message = shift;
	return if (!defined $message);

	my $width = 50;

	my $output;

	my @print;
	for (my $i = 0; $i < $width; $i++) {
		my $j = $i * 132 / $width;
		$print[$j] = 1;
	}

	# Have now read in the data. Next get the message to be printed.
	my @message;
	{
		$message =~ s/\n//g;
		@message = split(//, $message);
	}

	# check message to make sure it's legal
	for (my $i = 0; $i < @message; $i++) {
		my $chr = $message[$i];
		my $asc = ord($chr);
		if ($asc >= $NCHARS || $asc_ptr[$asc] == 0) {
			cprint("the character '$chr' is not in my character set");
			return undef;
		}
	}

	# Now have message. Print it one character at a time.
	my @line;
	for (my $i = 0; $i < @message; $i++) {
		for (my $j = 0; $j < $DWIDTH; $j++) {
			$line[$j] = ' ';
		}

		my $chr = $message[$i];
		my $asc = ord($chr);

		my $pc = $asc_ptr[$asc];
		my $term = 0;
		my $max = 0;
		my $linen = 0;

		while (!$term) {
			if ($pc < 0 || $pc > $NBYTES) {
				cprint("I'm somewhere where I don't know where I am! banner array position: $pc (lol)");
				return undef;
			}

			my $x = $data_table[$pc] & 0377;
			if ($x >= 128) {
				if ($x > 192) {
					$term++;
				}

				$x = $x & 63;
				while ($x--) {
					if ($print[$linen++]) {
						for (my $j = 0; $j <= $max; $j++) {
							if ($print[$j])  {
								$output .= $line[$j];
							}
						}

						$output .= "\n";
					}
				}

				for (my $j = 0; $j < $DWIDTH; $j++) {
					$line[$j] = ' ';
				}

				$pc++;
			} else {
				my $y = $data_table[$pc + 1];
				$max = $x + $y;
				while ($x < $max) {
					$line[$x++] = '#';
				}
				$pc += 2;
			}
		}
	}

	return $output;
}

sub chalkboard {
	my $message = shift;

	my $boardTemplate = <<CHALKBOARD;
 _____________________________________________________________ 
| \$text1    ^^^^^^^^\\ |
| \$text2    |       | |
| \$text3    |_ __   | |
| \$text4    (.(. )  | |
| \$partial _       (_      ) |
|                                           \\\\      /___/' /  |
|                                           _\\\\_      \\    |  |
|                                          ((   )     /====|  |
|                                           \\  <.__._-      \\ |
|___________________________________________ <//___.         ||
CHALKBOARD

	my @message;
	for (my $i = 1; $i <= (int(225 / (length($message) + 1)) + 1); $i++) {
		push(@message, uc($message));
	}
	$message = substr(join(' ', @message), 0, 225);
	my $text = {};
	for (my $i = 1; $i <= 5; $i++) {
		$text->{$i} = substr($message, (($i - 1) * 46), 46);
	}


	my $output = $boardTemplate;
	$message = uc($message) . (' ' x (46 - length($message)));
	my $partial = substr($message, 0, 41);
	$partial = uc($partial) . (' ' x (41 - length($partial)));
	$output =~ s/\$text([1-4])/$text->{$1}/g;
	$output =~ s/\$partial/$partial/g;

	return $output;
}


# run a command and return output
sub run {
	my %params = @_;

	my $command = $params{command};
	my $args    = $params{args};
	my $stdin   = $params{stdin};

	# see if we can find the program
	$command = whereis($command);

	if (!-x $command) {
		cprint("$command not found or not executable!");
		return;
	}

	my $pid = open3(\*WRITE, \*READ, \*ERR, "$command $args");

	if ($stdin) { print WRITE $stdin }
	close WRITE;

	my $output = join('', <READ>);
	close READ;

	# check for errors
	while (my $line = <ERR>) {
		next if $line eq "Message: "; # hack for banner :(
		cprint_lines($line);
	}
	close ERR;

	waitpid($pid, 0);

	return $output;
}

sub strip {
	my $text = shift;
	return if (!defined $text);

	my $output;
	foreach my $line (split(/\r?\n/, $text)) {
		$output .= "$line\n" unless ($line =~ /^\s*$/);
	}

	return $output;
}

if ($CONTEXT eq 'terminal') {
	my $callback = \&insub;

	my @args;
	foreach my $arg (@ARGV) {
		if    ($arg =~ /^-html/o)   { $OUTPUT = 'html'           }
		elsif ($arg =~ /^-ansi/o)   { $OUTPUT = 'ansi' if $ANSI  }
		elsif ($arg =~ /^-bash/o)   { $BASH_PROMPT = 1           }
		elsif ($arg =~ /^-cat/o)    { $callback = \&insubcat     }
		elsif ($arg =~ /^-stdin/o)  { $stdin = join('', <STDIN>) }
		elsif ($arg =~ /^-aim/o)    { $OUTPUT = 'aim'            }
		elsif ($arg =~ /^-bbcode/o) { $OUTPUT = 'bbcode'         }
		elsif ($arg =~ /^-orkut/o)  { $OUTPUT = 'orkut'          }
		elsif ($arg =~ /^-mirc/o)   { $OUTPUT = 'irc'            }
		else { push(@args, $arg) }
	}

	if (@args) {
		$callback->(join(' ', @args));
	} else {
		printf "%s\n", $USAGE;
	}

	exit(0);
} elsif ($CONTEXT eq 'irssi') {
	# command bindings.. basically there
	# is only one "real" command, the rest
	# are aliases for preset filters. so,
	# only do this if we are in Irssi
	Irssi::command_bind($NAME, \&insub);
	Irssi::command_bind($EXEC, \&insubexec);
	Irssi::command_bind($CAT, \&insubcat);
	Irssi::command_bind("gv", \&gv);


	# if run in Irssi, establish settings and
	# provide default values

	# cowsay
	Irssi::settings_add_str($IRSSI{name}, 'cowfile', $settings->{cowfile});
	Irssi::settings_add_str($IRSSI{name}, 'cowpath', $settings->{cowpath});

	# figlet
	Irssi::settings_add_str($IRSSI{name}, 'figfont', $settings->{figfont});
	Irssi::settings_add_int($IRSSI{name}, 'linewrap', $settings->{linewrap});

	# rainbow
	Irssi::settings_add_int($IRSSI{name}, 'rainbow_offset', $settings->{rainbow_offset});
	Irssi::settings_add_bool($IRSSI{name}, 'rainbow_keepstate', $settings->{rainbowkeepstate});
	Irssi::settings_add_int($IRSSI{name}, 'default_style', $settings->{default_style});

	# checkers
	Irssi::settings_add_int($IRSSI{name}, 'check_size', $settings->{check_size});
	Irssi::settings_add_int($IRSSI{name}, 'check_text', $settings->{check_text});
	Irssi::settings_add_str($IRSSI{name}, 'check_colors', $settings->{check_colors});

	# the matrix
	Irssi::settings_add_int($IRSSI{name}, 'matrix_size', $settings->{matrix_size});
	Irssi::settings_add_int($IRSSI{name}, 'matrix_spacing', $settings->{matrix_spacing});

	# sine wave settings
	Irssi::settings_add_int($IRSSI{name}, 'sine_height', $settings->{sine_height});
	Irssi::settings_add_str($IRSSI{name}, 'sine_frequency', $settings->{sine_frequency});
	Irssi::settings_add_str($IRSSI{name}, 'sine_background', $settings->{sine_background});

	# misc
	Irssi::settings_add_int($IRSSI{name}, 'colcat_max', $settings->{colcat_max});
	Irssi::settings_add_str($IRSSI{name}, 'jive_cmd', $settings->{jive_cmd});
	Irssi::settings_add_int($IRSSI{name}, 'spook_words', $settings->{spook_words});
	Irssi::settings_add_int($IRSSI{name}, 'hug_size', $settings->{hug_size});
	Irssi::settings_add_str($IRSSI{name}, 'banner_style', $settings->{banner_style});

	cprint("$SPLASH.  '/$NAME help' for usage");
}

# note, do not add an __END__ here, because irssi does not like it.  thx plz



=head1 NAME

insub

=head1 SYNOPSIS

a bunch of annoying text filters, generally used to add color to ascii
art.

=head1 DESCRIPTION

=over 4

=item * Using insub inside PS1 bash prompt

In your .bashrc, or wherever you like to set your prompt, add code such as 
the following:

export PROMPT_COMMAND="PS1=\$(echo 'prompt> ' | <script> -bash -1 -stdin)"

You may use Bash PS1 escaped characters directly in your prompt, such as 
this:

export PROMPT_COMMAND="PS1=\$(echo '\u@\h: \w\$ ' | <script> -bash -1 -stdin)"

The problem with this however, is that the escaped characters are expanded 
after script. If you want per-character colouring, you will need to be 
more sneaky. This will use per-character colouring for the same prompt as 
above:

export PROMPT_COMMAND="PS1=\$(echo \"\$USER@\$(hostname -s): \$(pwd|sed \
\"s?^\$HOME?\~?\")\\\\\$ \" | <script> -bash -1 -stdin)"

On my system it takes about a second and a half for the whole thing to
process. This may be a few milliseconds faster, but won't adapt if your
$USER, hostname, or $HOME should change during your session.

export PROMPT_COMMAND="PS1=\$(echo \"$USER@$(hostname -s): \$(pwd|sed \
\"s?^$HOME?\~?\")\\\\\$ \" | <script> -bash -1 -stdin)"

Hopefully, this documentation has been useful. D:

=back

=cut
