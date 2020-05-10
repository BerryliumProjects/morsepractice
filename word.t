#! /usr/bin/perl

use Test::Simple tests=>27;
use word;
use Data::Dumper;

$w1 = Word->createfromchar(''); # empty word

ok(defined $w1, 'Empty word created');
ok(! $w1->{complete}, 'Empty word is incomplete');

# print Dumper \$w1;
$w1->append('a'); # real time
$w1->append('b',3.21, 7); # stated time and pcnt

@chdata = $w1->chardata(1);
ok(($chdata[0] eq 'b' and $chdata[1] == 3.21, and $chdata[2] == 7), 'char data ok');
ok(! $w1->{complete}, 'Part built word is incomplete');

$w1->append('b'); # same char as before but not a space
ok($w1->wordtext eq 'abb', 'nonspace is not debounced');

$w1->undo;
ok($w1->wordtext eq 'ab', 'Undo partial word');

$w1->append(' '); # defaulted time
@chdata = $w1->chardata(2);
ok($chdata[1] > 0, 'defaulted date');
ok($w1->{complete}, 'Explicitly terminated word is complete');
# print Dumper \$w1;
ok($w1->wordtext eq 'ab', 'Word text does not include terminator');

ok(Word::debounce(' ') eq '', 'Quickly repeated space debounced');
sleep 1;
ok(Word::debounce(' ') eq ' ', 'Slowly repeated space allowed');

$w1->align('ij');
ok($w1->wordtext eq 'ab', 'Align preserves text if same length');
$w1->align('abxx');
ok($w1->wordtext eq 'ab__', 'Align inserts placeholders at end');
$w1->align('fabxx');
ok($w1->wordtext eq '_ab__', 'Align inserts placeholders at start');
$w1->align('_avbxx');
ok($w1->wordtext eq '_a_b__', 'Align inserts placeholders in middle');


$w2 = Word->createfromchar('x'); # one letter word
ok($w2->{complete}, 'Single letter word is complete');
ok($w2->{starttime} > 0, 'Start time defined');
ok($w2->{endtime} == $w2->{starttime}, 'End time same as start time for single letter word');
# should do nothing as already complete
$w2->append('y');
ok($w2->wordtext eq 'x', 'Word unaltered by appending to complete word');

# print Dumper \$w2;

# create from file with partial word
$tmpfile = '/var/tmp/perlwordtest1';

open(T, ">$tmpfile") or die;
print T "a\t1.23\t5\n";
print T "b\t1.24\t10\n";
print T "c\t1.25\t3\n";
print T "d\t1.26\t4\n";
close(T);
# system("cat $tmpfile");
undef $h;
open($h, $tmpfile);
$w3 = Word->createfromfile($h);
close($h);

($c, $t, $p) = $w3->chardata(3);
ok(($c eq 'd' and $t == 1.26 and $p == 4), 'fields imported from file');

($c2, $t2, $p2) = $w3->chardata(4);
ok(($c2 eq ' ' and $t2 > 0 and $p2 == 4), 'incomplete imported word is terminated automatically');

(@newwords) = $w3->split('efg');
ok(scalar(@newwords) < 2, 'No splitting if only one char too long');
(@newwords) = $w3->split('ef');

ok(($newwords[0]->{complete} and $newwords[1]->{complete}), 'Split words are complete');
ok($newwords[0]->wordtext eq 'ab', 'First split word');
ok($newwords[1]->wordtext eq 'cd', 'Second split word');
@terminator1data = $newwords[0]->chardata(2);
ok($terminator1data[1] == 1.25, 'First split word terminated with correct time');

# print Dumper \$w3;

# create from file with terminator
open(T, ">>$tmpfile") or die;
print T " \t1.27\t4\n";
close(T);
# system("cat $tmpfile");

undef $h;
open($h, $tmpfile);
$w4 = Word->createfromfile($h);
close($h);

ok(($w4->chardata(4))[1] == 1.27, 'terminated word imported from file');

# print Dumper \$w4;

unlink($tmpfile);
