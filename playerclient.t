#! /usr/bin/perl

use lib '.';
use Test::Simple tests=>8;
use playerclient;
use Data::Dumper;

my $e = {wpm=>25, effwpm=>15, pitch=>600, attenuation=>10, pitchshift=>0, dashweight=>5, extrawordspaces=>2};
print Dumper $e;

my $pc = PlayerClient->init;
ok(defined($pc),'client created');

$pc->openPlayer($e); # not text mode
ok(defined($pc->{MP}), 'player opened');
ok(1, 'play cq cq dx');
$pc->writePlayer('cq cq');
$pc->syncflush;
$pc->writePlayer('dx');
$pc->closePlayer;
ok(!(defined $pc->{MP}), 'player closed');

ok(1, 'play codex at standard settings of 440Hz and 20wpm');
PlayerClient->playText($e, 'codex');

$e->{pitchshift} = 1;
ok(1, 'play calibration test with pitch shift 1 semitone');
PlayerClient->calibrate($e);

$e->{playratefactor} = 1.5;
ok(1, 'play calibration test with 1.5 play rate adjustment');
PlayerClient->calibrate($e);

ok(1, 'play calibration test with default standard settings');
PlayerClient->calibrate();

