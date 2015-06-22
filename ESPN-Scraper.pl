#!/usr/bin/perl

#----------------------------------------------------------------------------------------
# Author:   Mark Hanna 
# Purpose:  --- Obtain pitching stat information from go.espn.com
#    		--- Parse the html code looking for the table which displays the info
#			--- Load the data into the MySQL database
#           --- Includes Games Played, Games Started, Innings Pitched, Hits, Runs,
#           --- Earned Runs, Walks, Strikeouts, Wins, Losses, Saves, Holds, Blown Saves,
#           --- Walks and Hits Per Innings Pitched, Earned Run Average
#----------------------------------------------------------------------------------------

# use lib "/Users/mark/perl5/perlbrew/perls/perl-5.14.4/lib/site_perl/5.14.4/darwin-2level" ;
# use lib "/Users/mark/perl5/perlbrew/perls/perl-5.14.4/lib/site_perl/5.14.4" ;
# use lib "/Users/mark/perl5/perlbrew/perls/perl-5.14.4/lib/5.14.4/darwin-2level" ;
# use lib "/Users/mark/perl5/perlbrew/perls/perl-5.14.4/lib/5.14.4" ;
# use lib "/Users/mark/Perl_Tests" ;

use HTML::TableExtract;
use Data::Dumper;
use WWW::Mechanize;
use WWW::Mechanize::Link;
use DBI;
use IO::Socket;
use Net::MySQL;
use feature qw(say state);
use strict;

#----------------------------------------------------------------------------------------
# in order to find some of these packages I has to
# perlbrew lib create base ; perlbrew switch perl-5.14.4
#----------------------------------------------------------------------------------------

#----------------------------------------------------------------------------------------
# The Moose classes might be moved into packages later
# use BaseballPackages::BaseballPlayer;
# use BaseballPackages::BaseballTeam;
# use BaseballPackages::BaseballPitchingStats;
#----------------------------------------------------------------------------------------

#----------------------------------------------------------------------------------------
#                               initialize_globals
#----------------------------------------------------------------------------------------

our $dbg = 0;    # global debugging
state $row_run_i   = 0;
state $rank_number = 1;
state $era_level   = 0.00;

#----------------------------------------------------------------------------------------
# These are the Headers shown on the pitching stats page on ESPN.com
#  this variable controls the columns returned by HTML::Extractor
#----------------------------------------------------------------------------------------

our @column__headers = ();

#foreach my $x ( @column__headers ) { print " [" . ${x} . "] " ; }; print "\n";
our @column__headers =
  qw( RK PLAYER TEAM GP GS IP H R ER BB SO W L SV HLD BLSV WHIP ERA );

#foreach my $x ( @column__headers ) { print " [" . ${x} . "] " ; }; print "\n";
# our @column__headers = qw( RK PLAYER TEAM GP GS IP H ER BB SO W L SV HLD BLSV WHIP ERA );
#foreach my $x ( @column__headers ) { print " [" . ${x} . "] " ; }; print "\n";

#----------------------------------------------------------------------------------------
# This is the starting page to grab for pitching stats
#----------------------------------------------------------------------------------------
our @espn_urls = qw(
  http://espn.go.com/mlb/stats/pitching/_/count/1/qualified/false/order/false
  http://espn.go.com/mlb/stats/pitching/_/count/41/qualified/true/order/false
  http://espn.go.com/mlb/stats/pitching/_/count/81/qualified/false/order/false
  http://espn.go.com/mlb/stats/pitching/_/count/101/qualified/false/order/false
  http://espn.go.com/mlb/stats/pitching/_/count/121/qualified/false/order/false
  http://espn.go.com/mlb/stats/pitching/_/count/141/qualified/false/order/false);

#----------------------------------------------------------------------------------------
# This is the url to get next and is set in get_next_page_link
# initialize the url to the beginning page.
#----------------------------------------------------------------------------------------
our $next_espn_url = $espn_urls[0];

#----------------------------------------------------------------------------------------
# create a new page object using WWW::Mechanize
#----------------------------------------------------------------------------------------
our $espnpage = WWW::Mechanize->new( autocheck => 1 );

#----------------------------------------------------------------------------------------
# use HTML::TableExtract->new to create and populate a table record of rows and columns
# which match the search critera if the column headers
# NOTE: setting keep_html=>0 removes the hrefs and other code from within the tables
#       setting keep_html=>1 retains the hrefs and other code from within the tables
#----------------------------------------------------------------------------------------
#  old method below almost worked but if I set R for runs in Column headers then it would
# returned as an undefined error  no R would work but the R (runs) column would be ommitted
# our $te = HTML::TableExtract->new(keep_html=>0, headers => \@column__headers );
# our $te = HTML::TableExtract->new(keep_html=>0, headers => \@column__headers , slice_columns => 0);
our $te = HTML::TableExtract->new( keep_html => 0, slice_columns => 0 );

#----------------------------------------------------------------------------------------
# global used to store the raw html code returned by WWW:Mechanize parse
#----------------------------------------------------------------------------------------
our $page_raw_html;

#----------------------------------------------------------------------------------------
# global used to store the processed player records obtained from ESPN
#----------------------------------------------------------------------------------------
our @player_records = ();

#----------------------------------------------------------------------------------------
# global used for a database handle
#----------------------------------------------------------------------------------------
our $dbh = "";

#----------------------------------------------------------------------------------------
#							end initialization of the globals
#----------------------------------------------------------------------------------------

package Player;

use Moose;

has 'idPlayer' => (
    is  => 'rw',
    isa => 'Int',
);

has 'idTeam' => (
    is  => 'rw',
    isa => 'Str',
);

has 'name_last' => (
    is  => 'rw',
    isa => 'Str'
);

has 'name_first' => (
    is  => 'rw',
    isa => 'Str'
);

has 'games_pitched' => (
    is  => 'rw',
    isa => 'Int'
);

has 'games_started' => (
    is  => 'rw',
    isa => 'Int'
);

has 'innings_pitched' => (
    is  => 'rw',
    isa => 'Num'
);

has 'hits' => (
    is  => 'rw',
    isa => 'Int'
);

has 'runs' => (
    is  => 'rw',
    isa => 'Int'
);

has 'earned_runs' => (
    is  => 'rw',
    isa => 'Int'
);

has 'walks' => (
    is  => 'rw',
    isa => 'Int'
);

has 'strike_outs' => (
    is  => 'rw',
    isa => 'Int'
);

has 'wins' => (
    is  => 'rw',
    isa => 'Int'
);

has 'losses' => (
    is  => 'rw',
    isa => 'Int'
);

has 'saves' => (
    is  => 'rw',
    isa => 'Int'
);

has 'holds' => (
    is  => 'rw',
    isa => 'Int'
);

has 'blown_saves' => (
    is  => 'rw',
    isa => 'Int'
);

has 'whip' => (
    is  => 'rw',
    isa => 'Num'
);

has 'era' => (
    is  => 'rw',
    isa => 'Num'
);

=for comment	
    $self->{idTeam}  = @$row[2];
    $self->{GP}      = @$row[3];
    $self->{GS}      = @$row[4];
    $self->{IP}      = @$row[5];
    $self->{H}       = @$row[6];
    $self->{R}       = @$row[7];
    $self->{ER}      = @$row[8];
    $self->{BB}      = @$row[9];
    $self->{SO}      = @$row[10];
    $self->{W}       = @$row[11];
    $self->{L}       = @$row[12];
    $self->{SV}      = @$row[13];
    $self->{HLD}     = @$row[14];
    $self->{BLSV}    = @$row[15];
    $self->{WHIP}    = @$row[16];
    $self->{ERA}     = @$row[17];	
=cut

sub load_player_name {

#-------------------------------------------------------------------------------------
# set to value to do local developmental debugging
#-------------------------------------------------------------------------------------
    my $dbg = 0;

#-------------------------------------------------------------------------------------
# peel off the self reference ... not used here
#-------------------------------------------------------------------------------------
    my $self = shift;

#-------------------------------------------------------------------------------------
# grab the name field and place it in an array of words and shift to the next argument
#-------------------------------------------------------------------------------------
    my ($row) = shift;

#-------------------------------------------------------------------------------------
# pass in 1 if you expect the last name first   pass in 0 if not
#-------------------------------------------------------------------------------------
    my $order_is_last_then_first = shift;

#-------------------------------------------------------------------------------------
# the field holding the name in it case we need to process it for order
#-------------------------------------------------------------------------------------
    my $name_str = @$row[1];

    print "\$name_str = \[${name_str}\]  \n" if ( $dbg > 0 );

#-------------------------------------------------------------------------------------
# verify that a string was passed for the name
#-------------------------------------------------------------------------------------
    if ( $name_str eq "" ) {
        print "Warning NO NAME WAS passed in ... \n";
        return 0;
    }

#-------------------------------------------------------------------------------------
# Put the name string into an array for processing
#-------------------------------------------------------------------------------------
    my @name = split( ' ', $name_str );

#-------------------------------------------------------------------------------------
# Get the number of words in the name in case something wield like Billie Von Hemslinger
#-------------------------------------------------------------------------------------
    my $num_words = @name;

    if ( $dbg > 1 ) {
        print "\@name contains ...\n";
        foreach my $tmp_str (@name) {
            print "\t[" . $tmp_str . "]\n";
        }
        print "\$order_is_last_then_first ["
          . $order_is_last_then_first . "]\n";
    }    # if ($dbg > 0)   # development debug

#-------------------------------------------------------------------------------------
# If $order_is_last_then_first is true then reverse the words
#-------------------------------------------------------------------------------------
    if ( $name[0] ne "" && $order_is_last_then_first == 1 ) {
        if ( $num_words == 2 ) {
            @name = reverse(@name);
            print "name in load_player_name ["
              . $name[0] . "] ["
              . $name[1] . "]\n"
              if ( $dbg > 0 );
            $self->{name_last}  = $name[1];
            $self->{name_first} = $name[0];
        }
        elsif ( $num_words == 3 ) {

  #-----------------------------------------------------------------------------
  # assume Van Helsing Tom  ... to  Tom Van Helsing
  #-----------------------------------------------------------------------------
            my @tmp_name = @name;
            $name[1]            = $tmp_name[0];
            $name[2]            = $tmp_name[1];
            $name[0]            = $tmp_name[2];
            $self->{name_last}  = $name[1] . " " . $name[2];
            $self->{name_first} = $name[0];
        }
        elsif ( $num_words == 4 ) {

  #-----------------------------------------------------------------------------
  # assume De La Rosa Rubby ... to
  #-----------------------------------------------------------------------------
            my @tmp_name = @name;
            $name[1]            = $tmp_name[0];
            $name[2]            = $tmp_name[1];
            $name[3]            = $tmp_name[2];
            $name[0]            = $tmp_name[3];
            $self->{name_last}  = $name[1] . " " . $name[2] . " " . $name[3];
            $self->{name_first} = $name[0];

        }    # elsif
    }
    elsif ( $name[0] ne "" && $order_is_last_then_first == 0 ) {
        $self->{name_first} = $name[0];
        $self->{name_last}  = $name[1];
        for ( my $i = 2 ; $i < $num_words ; $i++ ) {
            $self->{name_last} .= " " . $name[$i];
        }
    }    # elsif

    $self->{idTeam} = @$row[2];

#   print "name in load_player_name [" . $name[0] . "] [" . $name[1] . "]\n" if ( $dbg > 0 );

    print "Number of Words in the @{name} [${num_words}]\n" if ( $dbg > 0 );

    return 1;

}    # load_player_name

#---------------------------------------------------------------------------------------------------
#          sub load_player_pitchingstats {
# taken from http://espn.go.com/mlb/stats/pitching/_/year/2015/seasontype/2
#
# RK	PLAYER		TEAM	GP	GS	IP		H	R	ER	BB	SO	W	L	SV	HLD	BLSV	WHIP	ERA
# 1		David Price	DET		2	2	14.1	9	3	0	3	11	1	0	0	0	0		0.84	0.00
#---------------------------------------------------------------------------------------------------

sub load_player_pitchingstats {

#-------------------------------------------------------------------------------------
# set to value to do local developmental debugging
#-------------------------------------------------------------------------------------
    my $dbg = 0;

#-------------------------------------------------------------------------------------
# peel off the self reference ... not used here
#-------------------------------------------------------------------------------------
    my $self = shift;

#-------------------------------------------------------------------------------------
# grab the name field and place it in an array of words and shift to the next argument
#-------------------------------------------------------------------------------------
    my ($row) = shift;

#-------------------------------------------------------------------------------------
# verify that a row array was passed for the name
#-------------------------------------------------------------------------------------
    if ( $dbg > 0 ) {
        print "========== ";
        my $i = 0;
        for ( $i = 0 ; $i < @$row && $i < 20 ; $i++ ) {
            print "\@\$row[" . $i . "] = [", @$row[$i] . "]\n";
        }    #for
        print "\n";
    }

    $self->{idTeam}          = @$row[2];
    $self->{games_pitched}   = @$row[3];
    $self->{games_started}   = @$row[4];
    $self->{innings_pitched} = @$row[5];
    $self->{hits}            = @$row[6];
    $self->{runs}            = @$row[7];
    $self->{earned_runs}     = @$row[8];
    $self->{walks}           = @$row[9];
    $self->{strike_outs}     = @$row[10];
    $self->{wins}            = @$row[11];
    $self->{losses}          = @$row[12];
    $self->{saves}           = @$row[13];
    $self->{holds}           = @$row[14];
    $self->{blown_saves}     = @$row[15];
    $self->{whip}            = @$row[16];
    $self->{era}             = @$row[17];

=for comment
    # I can process the loop several ways    
    print "========== ";
    foreach my $cell (@$row) {
        print $cell . "|";
    } #foreach
    print "\n";
    print "========== ";
    my $i = 0;
    for ($i = 0 ; $i < @$row && $i < 20 ; $i++) {
        print "\@\$row[" . $i ."] = [", @$row[$i] . "]\n";
    } #for
    print "\n";
=cut

    return 1;

}

__PACKAGE__->meta->make_immutable;

1;

#----------------------------------------------------------------------------------------
#	Add a player to the Player Table MySql database  in the Baseball record
#----------------------------------------------------------------------------------------
sub add_a_new_player {
    my $idTeam_arg     = shift;
    my $name_last_arg  = shift;
    my $name_first_arg = shift;

#-----------------------------------------------------------------------------------------
# Names like O'Day need the ' or ` if a typo changed to \' for the $sql mySQL query string
#-----------------------------------------------------------------------------------------
    $name_last_arg =~ s/[\`\']/\\\'/g;
    $name_first_arg =~ s/[\`\']/\\\'/g;

    my $idPlayer   = "";
    my $idTeam     = "";
    my $name_last  = "";
    my $name_first = "";

    print "\n\n\n  add_a_new_player \n\n\n";
    my $sql =
qq"INSERT IGNORE INTO `Baseball`.`Player` (`idTeam`, `name_last`, `name_first`) VALUES ('$idTeam_arg', '$name_last_arg', '$name_first_arg')";
    my $sth = $dbh->prepare($sql) or warn "Cannot prepare: " . $dbh->errstr();
    $sth->execute() or die "Cannot execute: " . $sth->errstr();

    $sql =
qq"SELECT * FROM Player WHERE idTeam LIKE '$idTeam_arg' AND name_last LIKE '$name_last_arg' AND name_first LIKE '$name_first_arg'";
    $sth = $dbh->prepare($sql) or warn "Cannot prepare: " . $dbh->errstr();
    $sth->execute() or die "Cannot execute: " . $sth->errstr();
    $sth->bind_columns( \$idPlayer, \$idTeam, \$name_last, \$name_first );
    if ( $sth->fetch() ) {
        print
"\tadd_a_new_player ->bind_columns fetch results:\n===============================\n"
          if ( $dbg > 0 );
        print
"\t                   idPlayer is ${idPlayer}, the team is ${idTeam}, the name is ${name_first} ${name_last}\n"
          if ( $dbg > 0 );
    }
    else {
#	($idPlayer,$idTeam,$name_last,$name_first) = add_a_new_player() if $add_if_not_found ;
        print
"\ta N O T FOUND !!!!!!!!!   add_a_new_player ->bind_columns fetch results:\n===============================\n"
          if ( $dbg > 0 );
        print
"\t                   idPlayer is ${idPlayer}, the team is ${idTeam}, the name is ${name_first} ${name_last}\n"
          if ( $dbg > 0 );

    }

    return ( $idPlayer, $idTeam, $name_last, $name_first );
}    # add_a_new_player

#----------------------------------------------------------------------------------------
#	Check to see if a Player is in the database if not the player can be added
#   if the argument to add if it is passed in
#----------------------------------------------------------------------------------------
sub check_db_for_a_player_by_name {
    my $idPlayer_arg;
    my $idTeam_arg     = shift;
    my $name_last_arg  = shift;
    my $name_first_arg = shift;

#-----------------------------------------------------------------------------------------
# Names like O'Day need the ' or ` if a typo changed to \' for the $sql mySQL query string
#-----------------------------------------------------------------------------------------
    $name_last_arg =~ s/[\`\']/\\\'/g;
    $name_first_arg =~ s/[\`\']/\\\'/g;
    my $add_if_not_found = shift;

    my $idPlayer   = "";
    my $idTeam     = "";
    my $name_last  = "";
    my $name_first = "";
    my $sth;
    my $dbg = 1;

#-----------------------------------------------------------------------------------------
# $sql holds the mySQL query string
#-----------------------------------------------------------------------------------------
    my $sql =
qq"SELECT * FROM Player WHERE idTeam LIKE '$idTeam_arg' AND name_last LIKE '$name_last_arg' AND name_first LIKE '$name_first_arg'";

    print "\$sql = [" . $sql . "]\n" if ( $dbg > 0 );

#-----------------------------------------------------------------------------------------
# The prepare() function returns a statement handle (commonly called $sth).
#           the mySQL query prepared by $dbh->prepare
#-----------------------------------------------------------------------------------------
    $sth = $dbh->prepare($sql) or warn "Cannot prepare: " . $dbh->errstr();
    $sth->execute() or die "Cannot execute: " . $sth->errstr();

    $sth->bind_columns( \$idPlayer, \$idTeam, \$name_last, \$name_first );
    if ( $sth->fetch() ) {
        print
"\tcheck_db_for_a_player_by_name  bind_columns then fetch results: ===============================\n"
          if ( $dbg > 0 );
        print
"\t                             idPlayer is ${idPlayer}, the team is ${idTeam}, the name is ${name_first} ${name_last}\n"
          if ( $dbg > 0 );
        return ( $idPlayer, $idTeam, $name_last, $name_first );
    }
    else {
#	($idPlayer,$idTeam,$name_last,$name_first, 1) = add_a_new_player() if $add_if_not_found ;
        return ( "", "", "", "" );
    }
    $sth->finish();
}    # check_db_for_a_player_by_name

#-----------------------------------------------------------------------------------------
# This method works as an example  it is not used in the final version
#-----------------------------------------------------------------------------------------
sub test_get_a_record_from_Player {
    my ( $idPlayer, $idTeam, $name_last, $name_first );

#-----------------------------------------------------------------------------------------
# $sql holds the mySQL query string
#-----------------------------------------------------------------------------------------
#  my $sql = qq`SELECT idPlayer, idTeam, name_last, name_first FROM Baseball.Player WHERE idTeam LIKE "CIN"` ;

    my $sql = qq`SELECT * FROM Baseball.Player`;

#-----------------------------------------------------------------------------------------
# The prepare() function returns a statement handle (commonly called $sth).
#           the mySQL query prepared by $dbh->prepare
#-----------------------------------------------------------------------------------------
    my $sth = $dbh->prepare($sql) or warn "Cannot prepare: " . $dbh->errstr();

#-----------------------------------------------------------------------------------------
#      another way  columns need to be in order ... on the fetchrow_array call
#-----------------------------------------------------------------------------------------
    $sth = $dbh->prepare($sql) or warn "Cannot prepare: " . $dbh->errstr();
    $sth->execute() or die "Cannot execute: " . $sth->errstr();
    my $rows = $sth->rows();
    for ( my $i = 0 ; $i < $rows ; $i++ ) {
        ( $idPlayer, $idTeam, $name_last, $name_first ) =
          $sth->fetchrow_array();
        print
"fetchrow_array  idPlayer is ${idPlayer}, the team is ${idTeam}, the name is ${name_first} ${name_last}\n";
    }
    $sth->finish();
}

sub set_pitching_stats {

#-------------------------------------------------------------------------------------
# set to value to do local developmental debugging
#-------------------------------------------------------------------------------------
    my $dbg    = 0;
    my $row    = shift;
    my $count  = 0;
    my $player = Player->new();

    $player->load_player_name( $row, 0 );

    $player->load_player_pitchingstats($row);

# print "END UP first  array elements = ${count} [" . $player->name_first . "] last  [" . $player->name_last . "] . [" . $player->idTeam . "]\n";

#------------------------------------------------------------------------------------
# store the newly populated $player into an array to be used for database updating
# of the player record
#------------------------------------------------------------------------------------
    push @player_records, $player;
    $count = @player_records;

}    # set_pitching_stats

#----------------------------------------------------------------------------------------
# Get the url of the next page from the ESPN pitching stats page
# The procedure keys off the href text on the page used by ESPN i.e. NEXT
#
# This procedure process the text of the web page and looks for this code
# <div class="mod-footer">
#				<div class="foot-content"><ul style="float:right;margin:0px;"><li style="padding:0px;">
# <a href="http://espn.go.com/mlb/stats/pitching/_/qualified/false/order/false" style="padding: 0;">TOP</a> |
# <a href="http://espn.go.com/mlb/stats/pitching/_/count/41/qualified/false/order/false" style="padding: 0;">NEXT</a> |
# <a href="http://espn.go.com/mlb/stats/pitching/_/count/339/qualified/false/order/false" style="padding: 0;">BOT</a>
#    </li></ul>
# </div>
# we want to extract the next page from the site for processing next
#----------------------------------------------------------------------------------------
sub get_next_page_link {
    my $result = shift;
    $next_espn_url = "";
    my $dbg = 0;    # localized debugging var

    no warnings;   # prevent use of uninitialized variable in if statement below
    foreach my $link ( $result->find_all_links() ) {
        my $t = $link->text;
        if ( $t eq "NEXT" ) {
            $next_espn_url = $link->url_abs();
            chomp($next_espn_url);
        }
        use warnings;    # set warnings again ... easier

        print(  "\n\n\n\***********\n\n\nFound next url\n["
              . $next_espn_url
              . "]\n\n\n" )
          if ( ( $next_espn_url ne "" ) && $dbg >= 2 );

        if ( $dbg == 1 ) {
            print "======\n";
            say $link->url();
            say $link->text();
            say $link->name();
            say $link->tag();
            say $link->base();
            say $link->attrs();
            say $link->URI();
            say $link->url_abs();
        }    # if ($dbg > 1)

        last
          if ( $next_espn_url ne "" )
          ;    # exit foreach loop as immediately after setting the NEXT url

    }    # foreach
}

#----------------------------------------------------------------------------------------
# fetch the page off the web
# Use the get method on local scope $result and return $result to set $espnpage global
#----------------------------------------------------------------------------------------
sub get_web_page {
    my $url = shift;
    my $result = WWW::Mechanize->new( autocheck => 1 );
    $result->get($url);
    return $result;
}    # sub get_web_page

#----------------------------------------------------------------------------------------
# use HTML::TableExtract->parse method $espnpage->content to populate a table record
# with the rows and columns which match the search criteria of the column headers
#----------------------------------------------------------------------------------------
sub extract_the_table_object_from_the_webpage {

    my $dbg = 0;

    $page_raw_html = $espnpage->content;
    print $page_raw_html . "\n\n\n"
      if ( $dbg > 0 );    # debugging during development

   # $te = HTML::TableExtract->new(keep_html=>0, headers => \@column__headers );
    $te = HTML::TableExtract->new( keep_html => 0, slice_columns => 0 );

    $te->parse($page_raw_html);

}    # extract_the_table_object_from_the_webpage

#----------------------------------------------------------------------------------------
# Debugging    To see the entire html text obtained uncomment below
#----------------------------------------------------------------------------------------
sub debug_html_text {
    say $page_raw_html;
}    # sub debug_html_text

#----------------------------------------------------------------------------------------
# The foreach loop below may need to be replaced with direct assignment to a MySQL call
#----------------------------------------------------------------------------------------
sub process_pitcher_records {
    state $i = 0;
    my $k = 0;

    my $ts = $te->first_table_found();

    foreach my $row ( $ts->rows ) {

#--------------------------------------------------------------------------------
# ESPN adds a new header as a row every ten listings ... this skips that row away
#--------------------------------------------------------------------------------
        next if ( @$row[0] eq "RK" );

#--------------------------------------------------------------------------------
# ESPN data is put into a global array for processing
#--------------------------------------------------------------------------------
        set_pitching_stats($row);

#--------------------------------------------------------------------------------
# ESPN rank is unreliable so I will zero it out
#--------------------------------------------------------------------------------
        @$row[0] = "";

#--------------------------------------------------------------------------------
# process a row from left to right using a foreach loop
#--------------------------------------------------------------------------------
        print( "process_pitcher_records --- " . ++$i . "  " );
        foreach my $cell (@$row) {
            print $cell . "|";
        }    #foreach
        print "\n\n";
    }    # foreach row

}    # process_pitcher_records

#----------------------------------------------------------------------------------------
# The add_player_stats function uses a global @player_records which is an array of
# which is part of a Moose enabled package Player
#----------------------------------------------------------------------------------------
sub add_player_stats {
    my $i = 1;
    state $j = 0;
    my @found;
    my $idPlayer_result   = "";
    my $idTeam_result     = "";
    my $name_last_result  = "";
    my $name_first_result = "";

    $dbg = 0;
    no warnings;
    if ( $dbg > 1 ) {
        print "********************** add_player_stats  ******************";
        print "********************** add_player_stats  ******************";
        print "********************** add_player_stats  ******************";
        print "********************** add_player_stats  ******************";
    }

    foreach my $rec (@player_records) {
        $i++;
        if ( $dbg > 0 ) {
            print "\n\nadd_player_stats ===============================\n\n";
            print "${i} ≈ |"
              . $rec->{idPlayer} . "|"
              . $rec->{name_first} . "|"
              . $rec->{name_last} . "|"
              . $rec->{idTeam} . "|"
              . $rec->{games_pitched} . "|"
              . $rec->{games_started} . "|"
              . $rec->{innings_pitched} . "|"
              . $rec->{hits} . "|"
              . $rec->{runs} . "|"
              . $rec->{earned_runs} . "|"
              . $rec->{walks} . "|"
              . $rec->{strike_outs} . "|"
              . $rec->{wins} . "|"
              . $rec->{losses} . "|"
              . $rec->{saves} . "|"
              . $rec->{holds} . "|"
              . $rec->{blown_saves} . "|"
              . $rec->{whip} . "|"
              . $rec->{era} . "|\n";
        }

        $idPlayer_result   = $rec->idPlayer;
        $idTeam_result     = $rec->idTeam;
        $name_last_result  = $rec->name_last;
        $name_first_result = $rec->name_first;

        $dbg = 0;
        print "**** show_player_records p["
          . $idPlayer_result . "]  t["
          . $idTeam_result . "]  l["
          . $name_last_result . "]  f["
          . $name_first_result . "]\n"
          if ( $dbg > 0 );

#---------------------------------------------------------------------------------
#  add_player_stats  check for player in Baseball.Player TABELE
#---------------------------------------------------------------------------------
        @found =
          check_db_for_a_player_by_name( $idTeam_result, $name_last_result,
            $name_first_result, 0 );

        if ( $found[0] ) {
 #------------------------------------------------------------------------------
 #    Set the idPlayer which is in Baseball.Player to use as a idPlayer field
 #    in the Baseball.PitchingStats
 #------------------------------------------------------------------------------
            $rec->{idPlayer} = $found[0];
            $j++;
            print "add_player_stats " . $j . " calling add_a_new_player\n"
              if ( $dbg > 0 );
            my $sql = qq"INSERT INTO Baseball.PitchingStats  
			(
			`idPlayer`,
			`games_pitched`,
			`games_started`,
			`innings_pitched`,
			
			`hits`,
			`runs`,
			`earned_runs`,
			`walks`,
			
			`strike_outs`,
			`wins`,
			`losses`,
			`saves`,
			
			`holds`,
			`blown_saves`,
			`whip`,
			`era`
			) VALUES 
			(
			'$rec->{idPlayer}',
			'$rec->{games_pitched}',
			'$rec->{games_started}',
			'$rec->{innings_pitched}',
			
			'$rec->{hits}',
			'$rec->{runs}',
			'$rec->{earned_runs}',
			'$rec->{walks}',
			
			'$rec->{strike_outs}',
			'$rec->{wins}',
			'$rec->{losses}',
			'$rec->{saves}',
			
			'$rec->{holds}',
			'$rec->{blown_saves}',
			'$rec->{whip}',
			'$rec->{era}'
			)";
            print "\n\n${sql}\n\n\n" if ( $dbg > 0 );
            my $sth = $dbh->prepare($sql)
              or warn "Cannot prepare: " . $dbh->errstr();
            $sth->execute() or warn "Cannot execute: " . $sth->errstr();
        }

    }    #foreach
    use warnings;
}    #add_player_stats

#----------------------------------------------------------------------------------------
# The add_player_records function uses a global @player_records which is an array of
# which is part of a Moose enabled package Player
#----------------------------------------------------------------------------------------
sub add_player_records {
    my $i = 1;
    state $j = 0;
    my @found;
    my $idTeam_result     = "";
    my $name_last_result  = "";
    my $name_first_result = "";

    $dbg = 1;
    no warnings;
    foreach my $rec (@player_records) {
        print $i++;
        print "|"
          . $rec->idPlayer . "|"
          . $rec->name_first . "|"
          . $rec->name_last . "|"
          . $rec->idTeam . "\n";

        $idTeam_result     = $rec->idTeam;
        $name_last_result  = $rec->name_last;
        $name_first_result = $rec->name_first;

        print "**** show_player_records team["
          . $idTeam_result . "]  l["
          . $name_last_result . "]  f["
          . $name_first_result . "]\n"
          if ( $dbg > 0 );

        # test_get_a_record_from_Player ;
        @found =
          check_db_for_a_player_by_name( $idTeam_result, $name_last_result,
            $name_first_result, 0 );

        # 5th argument of 0 means look only and 1 means if not found add

		if ( $found[0] eq "" ) {
			# add an existing_player to  Baseball.Player 
			$j++;
 			print "show_player_records ${j}  calling add_a_new_player\n";
			add_a_new_player ( $rec->idTeam , $rec->name_last , $rec->name_first );
		}
    }    #foreach
    use warnings;
}    # add_player_records

#----------------------------------------------------------------------------------------
#	CONNECT the program to the MySql database   Baseball
#----------------------------------------------------------------------------------------
sub process_connect_db {
    my $driver   = "mysql";
    my $database = "Baseball";
    my $dsn      = "DBI:$driver:database=$database";
    my $userid   = "th787dg45nkoi8";
    my $password = "xxxxxxxxxxxxxx";
    $dbh = DBI->connect( $dsn, $userid, $password ) or die $DBI::errstr;
}	 # process_connect_db

#-----------------------------------------------------------------------------------------
# Disconnect the link to the database
#-----------------------------------------------------------------------------------------
sub process_disconnect_db {
    $dbh->disconnect();
}	 # process_disconnect_db

sub slurp_up_the_espn_content {
    while ( $next_espn_url ne "" ) {

        $espnpage = get_web_page($next_espn_url);

        get_next_page_link($espnpage);

        $dbg = 0;
        debug_html_text if ( $dbg > 0 );

        extract_the_table_object_from_the_webpage;

        process_pitcher_records;
    }    # while   used to process an undetermined number of pages
}

#----------------------------------------------------------------------------------------
#				M A I N    P R O G R A M
#----------------------------------------------------------------------------------------

process_connect_db;


slurp_up_the_espn_content;

#-----------------------------------------------------------------------------------------
#  add_player_records
#                 adds Baseball.Player records to the database from global @player_records
#-----------------------------------------------------------------------------------------
add_player_records;

#-----------------------------------------------------------------------------------------
#  add_player_stats
#          adds Baseball.PitchingStats records to the database from global @player_records
#-----------------------------------------------------------------------------------------
add_player_stats;


process_disconnect_db;

