#! /usr/bin/perl

use Test::Simple tests=>7;
use testwordgenerator;
use Data::Dumper;

$w = TestWordGenerator->new(4,8);

ok (defined($w), '$w defined');

$w->addRandom ('abcd', 3);
ok ($w->{size} == 3, '3 random added');

$w->addDictionary('qsolist.txt',0,5);

print Dumper $w;
ok ($w->{size} == 8, '5 added from qsolist');

$w = TestWordGenerator->new(4,8);
$w->addPseudo (10000);

ok ($w->{size} == 10000, '10000 pseudo added');
$pw = join('',@{$w->{testwords}});

%h = ();
$tot = 0;
foreach (split('', $pw)) {
   ($h{$_})++;
   $tot++;
}

foreach (sort keys %h) {
   $f = int(100.0 * $h{$_} / $tot + 0.5);
   print "$_\t$f\n";
}

$w = TestWordGenerator->new(4,10);

ok (defined($w), '$w defined');

$w->addCallsign(0, 3);
ok ($w->{size} == 3, '3 standard callsigns added');

$w->addCallsign(1, 3);
ok ($w->{size} == 6, '3 international callsigns added');

print Dumper $w;

