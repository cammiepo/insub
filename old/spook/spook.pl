#!/usr/bin/env perl

use strict;
use warnings;

sub main
{
    my @emacs = (
        "\$400 million in gold bullion",
        "[Hello to all my fans in domestic surveillance]", "AK-47",
        "ammunition", "arrangements", "assassination", "BATF", "bomb", "CIA",
        "class struggle", "Clinton", "Cocaine", "colonel",
        "counter-intelligence", "cracking", "Croatian", "cryptographic",
        "Delta Force", "DES", "domestic disruption", "explosion", "FBI", "FSF",
        "fissionable", "Ft. Bragg", "Ft. Meade", "genetic", "Honduras",
        "jihad", "Kennedy", "KGB", "Khaddafi", "kibo", "Legion of Doom",
        "Marxist", "Mossad", "munitions", "Nazi", "Noriega", "North Korea",
        "NORAD", "NSA", "nuclear", "Ortega", "Panama", "Peking", "PLO",
        "plutonium", "Qaddafi", "quiche", "radar", "Rule Psix",
        "Saddam Hussein", "SDI", "SEAL Team 6", "security", "Semtex",
        "Serbian", "smuggle", "South Africa", "Soviet ", "spy", "strategic",
        "supercomputer", "terrorist", "Treasury", "Uzi", "Waco, Texas",
        "World Trade Center", "Liberals", "Cheney"
    );

    my @hugs = (
        "Eggs", "Libya", "Bush", "Kill the president", "GOP", "Republican",
        "Shiite", "Muslim", "Chemical Ali", "Ashcroft", "Terrorism",
        "Al Qaeda", "Al Jazeera", "Hamas", "Israel", "Palestine", "Arabs",
        "Arafat", "Patriot Act", "Voter Fraud", "Punch-cards", "Diebold",
        "conspiracy", "Fallujah", "IndyMedia", "Skull and Bones", "Free Masons",
        "Kerry", "Grass Roots", "9-11", "Rocket Propelled Grenades",
        "Embedded Journalism", "Lockheed-Martin", "war profiteering",
    );

    my @blog = (
        "Kill the President", "anarchy", "echelon", "nuclear",
        "assassinate", "Roswell", "Waco", "World Trade Center", "Soros",
        "Whitewater", "Lebed", "HALO", "Spetznaz", "Al Amn al-Askari",
        "Glock 26", "Steak Knife", "Rewson", "SAFE", "Waihopai", "ASPIC",
        "MI6", "Information Security", "Information Warfare", "Privacy",
        "Information Terrorism", "Terrorism", "Defensive Information",
        "Defense Information Warfare", "Offensive Information",
        "Offensive Information Warfare", "Ortega Waco", "assasinate",
        "National Information Infrastructure", "InfoSec",
        "Computer Terrorism", "DefCon V", "Encryption", "Espionage", "NSA",
        "CIA", "FBI", "White House", "Undercover", "Compsec 97", "Europol",
        "Military Intelligence", "Verisign", "Echelon",
        "Ufologico Nazionale", "smuggle", "Bletchley Park", "Clandestine",
        "Counter Terrorism Security", "Enemy of the State", "20755-6000",
        "Electronic Surveillance", "Counterterrorism", "eavesdropping",
        "nailbomb", "Satellite imagery", "subversives", "World Domination",
        "wire transfer", "jihad", "fissionable", "Sayeret Mat'Kal",
        "HERF pipe-bomb", "2.3 Oz.  cocaine"
    );

    my @refs=(\@emacs, \@hugs, \@blog);
    my @keys=("emacs", "hugs", "blog");
    for (my $i=0; $i < @refs; $i++) {
        my $ref = $refs[$i];
        my $key = $keys[$i];
        open(OUT, "> spook-$key.txt") || die $!;
        printf OUT "%s\n", join("\n", @$ref);
        close(OUT);
    }

    #foreach my $ref (\@emacs, \@hugs, \@blog) {
    #    printf("%s\n", join("\n", @$ref));
    #}
}

exit(main());
