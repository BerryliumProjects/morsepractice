#! /usr/bin/perl

use Test::Simple tests=>14;
use testwordgenerator;
use Data::Dumper;

$w = TestWordGenerator->new(1,6,1);
$w->addWord(" a\tb\rc\nd ");
ok ($w->chooseWord eq 'abcd', 'whitespace ignored in word');
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
  $word = $w->chooseWord($word);
  push @words, $word;
  print "Repeated word test: $word\n";
}

ok ($words[0] eq $words[1], 'Word repeated ok');
ok ($words[1] ne $words[2], 'Word was not duplicated');

$w->addDictionary('qsowordlist.txt',0,5);

print Dumper $w;
ok ($w->{size} == 8, '5 added from qsowordlist');

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

$w->addCallsign(0, 1, 3);
ok ($w->{size} == 6, '3 random complex callsigns added');

ok ($w->chooseWord ne '', 'first word chosen');
ok ($w->chooseWord ne '', 'second word chosen');

print Dumper $w;

$w = TestWordGenerator->new(2,3);

$w->addPhonemes();
ok ($w->{size} > 5, '>5 phonemes added');

print Dumper $w;
