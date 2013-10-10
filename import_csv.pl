#!/usr/local/bin/perl
use strict;
use warnings;
use Data::Dumper;

use DBI;

$|++;
my $user = 'root';
my $pass = 'password';

my $dbh = DBI->connect( 'dbi:mysql:IPsniffer', $user, $pass ) || die "Can't connect to database\n";

my $file = 'IP-COUNTRY-REGION-CITY-LATITUDE-LONGITUDE-ISP-DOMAIN-MOBILE.CSV';
open my $fh, '<', $file || die "Can't open file: $file\n";

my $sql = qq/insert into ip_data ( ip_from, ip_to, country_code, country_name, region, city, isp_name, domain_name, mcc, mnc, mobile_brand ) values ( ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ? )/;
my $sth = $dbh->prepare( $sql );


while ( my $row = <$fh> ) {
  $row =~ s/\r\n//g;
  #chomp( $row );
  my @cols = split /,/, $row;

  foreach ( @cols ){
    s/"//g;
    s/^\s+//;
    s/\s+$//;
  }

  $sth->execute( $cols[0], $cols[1], $cols[2], $cols[3], $cols[4], $cols[5], $cols[8], $cols[9], $cols[10], $cols[11], $cols[12] );
}
print "Done\n";
