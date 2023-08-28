#! /usr/bin/perl

use lib '.';
use Test::Simple tests=>8;
use charcodes;
use Data::Dumper;

my $c = CharCodes->getChars();
ok (defined $c and length($c gt 3), 'getChars returned list');
ok (substr($c, -1) eq 'z', 'char list is alphanumeric ordered');

my $c2 = CharCodes->getCharsKochOrder(0);
ok (defined $c2 and length($c gt 3), 'getCharsKochOrder returned list');
ok ($c2 eq $c, 'KochOrder for length 0 is full and alphanumeric ordered');

my $ck2 = CharCodes->getCharsKochOrder(2);
ok ($ck2 eq 'km', "$ck2: KochOrder for length 2 is equally weighted");

my $ck3 = CharCodes->getCharsKochOrder(3);
ok ($ck3 eq 'kmrr', "$ck3: KochOrder for length 3 is weighted");

my $ck5 = CharCodes->getCharsKochOrder(5);
ok ($ck5 eq 'kmrsusu', "$ck5: KochOrder for length 5 is double weighted");

my $cc = CharCodes->getCharCodes();
ok ($cc->{'k'} = '-.- ', 'getCharCodes returned expected hash');

