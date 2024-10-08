#! /usr/bin/perl

use lib '.';
use Test::Simple tests=>18;
use testwordgenerator;
use Data::Dumper;

$w = TestWordGenerator->new(1,6,1);
$w->addWord(' ab ab ');
ok ($w->chooseWord eq 'ab', 'leading/trailing whitespace ignored in word');
$w->addWord(undef);
$w->addWord(' ');
ok ($w->{size} == 1, 'empty words not added');

$w = TestWordGenerator->new(3,6,1);

ok (defined($w), '$w defined');

$w->addRandom ('abcd', 3);
ok ($w->{size} == 3, '3 random added');

$word = '';
@words = ();

for (1..3) {
  $word = $w->chooseWord;
  push @words, $word;
  print "Repeated word test: $word\n";
}

ok ($words[0] eq $words[1], 'Word repeated ok');
ok ($words[0] ne $words[2], 'Word was not duplicated');
$word = $w->chooseWord(1); # extra repeat requested
$word = $w->chooseWord;

ok ($word eq $words[2], 'Extra repeat granted');
$word = $w->chooseWord(1); # extra repeat requested when already granted once
ok ($word ne $words[2], 'Second extra repeat denied');

$w->addDictionary('qsowordlist.txt',0,5);

ok ($w->{size} == 8, '8 added from qsowordlist');

$w->addSpecified(0.5, 'ypp', 'ypq', 'ypr', 'yps');
ok ($w->{size} == 16, 'specified words weighted to 50% of total');

print Dumper $w;

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

$w->addCallsign(1, 0, 3);
ok ($w->{size} == 3, '3 euro simple callsigns added');

$w->addCallsign(1, 1, 3);
ok ($w->{size} == 6, '3 euro callsigns with possible suffixes added');

$w->addCallsign(0, 2, 3);
ok ($w->{size} == 9, '3 random complex callsigns added');

ok ($w->chooseWord ne '', 'first word chosen');
ok ($w->chooseWord ne '', 'second word chosen');

print Dumper $w;

$w = TestWordGenerator->new(2,3);

$w->addPhonemes();
ok ($w->{size} > 5, '>5 phonemes added');

print Dumper $w;
