#! /usr/bin/perl

use Test::Simple tests=>4;
use testwordgenerator;
use Data::Dumper;

$w = TestWordGenerator->new(4,8);

ok (defined($w), '$w defined');

$w->addRandom ('abcd', 3);

ok ($w->{size} == 3, '3 random added');

$w->addPseudo (10);

ok ($w->{size} == 13, '10 pseudo added');

$w->addDictionary('qsolist.txt',0,5);

ok ($w->{size} == 18, '5 added from qsolist');
print Dumper $w;

