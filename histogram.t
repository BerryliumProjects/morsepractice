#! /usr/bin/perl

use Test::Simple tests=>7;
use histogram;
use Data::Dumper;

$h = Histogram->new;

ok (defined($h), '$h defined');

$h->add('key2', 3);
$h->add('key1', 20);
$h->add('key1', 5);

ok ($h->grandtotal == 28, 'Grand total');
ok ($h->grandcount == 3, 'Grand count');
ok ($h->keytotal('key1') == 25, 'Key total');
ok ($h->keycount('key1')  == 2, 'Key count');
ok ($h->averages->{'key1'} == 12.5, 'Key Average');
ok ($h->keys->[1] eq 'key2', 'keys');
print Dumper $h;


