#! /usr/bin/perl

use lib '.';
use Test::Simple tests=>10;
use charcodes;
use Data::Dumper;

my $c = CharCodes->getChars();
ok ((defined $c and length($c) gt 3), 'getChars returned list');
ok (substr($c, -1) eq 'z', 'char list is alphanumeric ordered');

my $c2 = CharCodes->getCharsKochOrder(0);
ok ((defined $c2 and length($c) gt 3), 'getCharsKochOrder returned list');
ok ($c2 eq $c, 'KochOrder for length 0 is full and alphanumeric ordered');

my $kw = CharCodes->getKochWeights(0);
ok ($kw eq '', 'No Koch weights for level 0');

my $ck2 = CharCodes->getCharsKochOrder(2);
ok ($ck2 eq 'km', "KochOrder for length 2");

$kw = CharCodes->getKochWeights(2);
ok ($kw eq '', 'No Koch weights for level 2');

$kw = CharCodes->getKochWeights(3);
ok ($kw eq 'r', 'Single Koch weight for level 3');

$kw = CharCodes->getKochWeights(5);
ok ($kw eq 'su', 'Double Koch weight for level 5');

my $cc = CharCodes->getCharCodes();
ok ($cc->{'k'} = '-.- ', 'getCharCodes returned expected hash');

